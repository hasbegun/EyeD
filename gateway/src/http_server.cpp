#include "http_server.h"
#include <iostream>

namespace eyed {

// ── BeastWsSession ────────────────────────────────────────────────────────────

BeastWsSession::BeastWsSession(tcp::socket socket)
    : ws_(std::move(socket)) {}

void BeastWsSession::send(const std::string& message) {
    if (!open_) throw std::runtime_error("WebSocket session closed");
    std::lock_guard<std::mutex> lock(write_mutex_);
    ws_.text(true);
    ws_.write(net::buffer(message));
}

bool BeastWsSession::is_open() const {
    return open_;
}

void BeastWsSession::run_read_loop(std::function<void(std::string)> on_message) {
    beast::flat_buffer buffer;
    while (open_) {
        beast::error_code ec;
        ws_.read(buffer, ec);
        if (ec) break;
        if (on_message) {
            on_message(beast::buffers_to_string(buffer.data()));
        }
        buffer.consume(buffer.size());
    }
    open_ = false;
}

// ── HttpServer ────────────────────────────────────────────────────────────────

HttpServer::HttpServer(const std::string& address, unsigned short port,
                       NatsClient* nats, Breaker* breaker,
                       WsHub* ws_hub, SignalingHub* signaling_hub)
    : address_(address), port_(port), nats_(nats), breaker_(breaker),
      ws_hub_(ws_hub), signaling_hub_(signaling_hub) {}

HttpServer::~HttpServer() {
    stop();
}

void HttpServer::run() {
    if (running_.exchange(true)) {
        return; // Already running
    }

    try {
        auto const addr = net::ip::make_address(address_);
        acceptor_ = std::make_unique<tcp::acceptor>(ioc_, tcp::endpoint{addr, port_});

        thread_ = std::make_unique<std::thread>([this]() {
            do_accept();
            ioc_.run();
        });

    } catch (const std::exception& e) {
        std::cerr << "HTTP server error: " << e.what() << std::endl;
        running_ = false;
    }
}

void HttpServer::stop() {
    if (!running_.exchange(false)) {
        return; // Not running
    }

    if (acceptor_) {
        acceptor_->close();
    }

    ioc_.stop();

    if (thread_ && thread_->joinable()) {
        thread_->join();
    }
}

void HttpServer::do_accept() {
    acceptor_->async_accept(
        [this](beast::error_code ec, tcp::socket socket) {
            if (!ec) {
                std::thread([this, s = std::move(socket)]() mutable {
                    handle_request(std::move(s));
                }).detach();
            }

            if (running_) {
                do_accept();
            }
        });
}

void HttpServer::handle_request(tcp::socket socket) {
    try {
        beast::flat_buffer buffer;
        http::request<http::string_body> req;
        http::read(socket, buffer, req);

        std::string target = std::string(req.target());

        // WebSocket upgrade detection
        if (websocket::is_upgrade(req)) {
            auto session = std::make_shared<BeastWsSession>(std::move(socket));
            session->accept(std::move(req));

            if (target.rfind("/ws/results", 0) == 0) {
                handle_ws_results(session);
            } else if (target.rfind("/ws/signaling", 0) == 0) {
                std::string device_id = parse_query_param(target, "device_id");
                std::string role      = parse_query_param(target, "role");
                if (device_id.empty() || (role != "device" && role != "viewer")) {
                    // Reject invalid params — close immediately
                    return;
                }
                handle_ws_signaling(session, device_id, role);
            }
            return;
        }

        http::response<http::string_body> res;

        // Route HTTP requests
        if (target == "/health/alive") {
            res = handle_health_alive();
        } else if (target == "/health/ready") {
            res = handle_health_ready();
        } else if (req.method() == http::verb::options) {
            res.result(http::status::no_content);
            res.version(req.version());
            add_cors_headers(res);
        } else {
            res = handle_not_found();
        }

        res.version(req.version());
        res.keep_alive(req.keep_alive());
        add_cors_headers(res);

        http::write(socket, res);
        socket.shutdown(tcp::socket::shutdown_send);

    } catch (const std::exception&) {
        // Connection error, ignore
    }
}

void HttpServer::handle_ws_results(std::shared_ptr<BeastWsSession> session) {
    if (ws_hub_) ws_hub_->add_client(session);
    // Read loop — discard incoming messages, detect disconnect
    session->run_read_loop(nullptr);
    if (ws_hub_) ws_hub_->remove_client(session);
}

void HttpServer::handle_ws_signaling(std::shared_ptr<BeastWsSession> session,
                                     const std::string& device_id,
                                     const std::string& role) {
    if (!signaling_hub_) return;

    if (role == "device") {
        signaling_hub_->register_device(device_id, session);
    } else {
        signaling_hub_->register_viewer(device_id, session);
    }

    // Read loop — relay every incoming message through the signaling hub
    session->run_read_loop([this, session](const std::string& msg) {
        signaling_hub_->relay(session, msg);
    });

    signaling_hub_->unregister(session);
}

std::string HttpServer::parse_query_param(const std::string& target, const std::string& key) {
    auto qpos = target.find('?');
    if (qpos == std::string::npos) return "";
    std::string query = target.substr(qpos + 1);
    std::string search = key + "=";
    auto pos = query.find(search);
    if (pos == std::string::npos) return "";
    pos += search.size();
    auto end = query.find('&', pos);
    return query.substr(pos, end == std::string::npos ? std::string::npos : end - pos);
}

http::response<http::string_body> HttpServer::handle_health_alive() {
    http::response<http::string_body> res{http::status::ok, 11};
    res.set(http::field::content_type, "application/json");

    nlohmann::json j;
    j["alive"] = true;
    res.body() = j.dump();
    res.prepare_payload();

    return res;
}

http::response<http::string_body> HttpServer::handle_health_ready() {
    http::response<http::string_body> res{http::status::ok, 11};
    res.set(http::field::content_type, "application/json");

    nlohmann::json j;
    j["alive"] = true;
    j["ready"] = nats_->is_connected() && breaker_->state() == State::Closed;
    j["nats_connected"] = nats_->is_connected();
    j["circuit_breaker"] = breaker_->state_string();
    j["version"] = "0.1.0";
    res.body() = j.dump();
    res.prepare_payload();

    return res;
}

http::response<http::string_body> HttpServer::handle_not_found() {
    http::response<http::string_body> res{http::status::not_found, 11};
    res.set(http::field::content_type, "text/plain");
    res.body() = "Not Found";
    res.prepare_payload();
    return res;
}

void HttpServer::add_cors_headers(http::response<http::string_body>& res) {
    res.set(http::field::access_control_allow_origin, "*");
    res.set(http::field::access_control_allow_methods, "GET, POST, PUT, DELETE, OPTIONS");
    res.set(http::field::access_control_allow_headers, "Content-Type, Authorization");
}

} // namespace eyed
