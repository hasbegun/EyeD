#pragma once

#include <memory>
#include <string>
#include <thread>
#include <atomic>
#include <mutex>
#include <functional>
#include <boost/asio.hpp>
#include <boost/beast.hpp>
#include <boost/beast/websocket.hpp>
#include <nlohmann/json.hpp>
#include "nats_client.h"
#include "breaker.h"
#include "ws_hub.h"
#include "signaling_hub.h"

namespace beast = boost::beast;
namespace http = beast::http;
namespace websocket = beast::websocket;
namespace net = boost::asio;
using tcp = net::ip::tcp;

namespace eyed {

// Concrete WebSocket session backed by Boost.Beast
class BeastWsSession : public WsSession,
                       public std::enable_shared_from_this<BeastWsSession> {
public:
    explicit BeastWsSession(tcp::socket socket);

    void send(const std::string& message) override;
    bool is_open() const override;

    // Accept the WebSocket upgrade from an already-read HTTP request
    template<typename Body, typename Allocator>
    void accept(http::request<Body, http::basic_fields<Allocator>> req) {
        ws_.accept(req);
    }

    // Read loop: calls on_message for each incoming frame; blocks until disconnect
    void run_read_loop(std::function<void(std::string)> on_message = nullptr);

private:
    websocket::stream<tcp::socket> ws_;
    std::atomic<bool> open_{true};
    std::mutex write_mutex_;
};

class HttpServer {
public:
    HttpServer(const std::string& address, unsigned short port,
               NatsClient* nats, Breaker* breaker,
               WsHub* ws_hub = nullptr, SignalingHub* signaling_hub = nullptr);
    ~HttpServer();

    void run();
    void stop();

private:
    std::string address_;
    unsigned short port_;
    NatsClient* nats_;
    Breaker* breaker_;
    WsHub* ws_hub_;
    SignalingHub* signaling_hub_;

    net::io_context ioc_;
    std::unique_ptr<tcp::acceptor> acceptor_;
    std::unique_ptr<std::thread> thread_;
    std::atomic<bool> running_{false};

    void do_accept();
    void handle_request(tcp::socket socket);
    void handle_ws_results(std::shared_ptr<BeastWsSession> session);
    void handle_ws_signaling(std::shared_ptr<BeastWsSession> session,
                             const std::string& device_id,
                             const std::string& role);
    static std::string parse_query_param(const std::string& target, const std::string& key);

    // HTTP handlers
    http::response<http::string_body> handle_health_alive();
    http::response<http::string_body> handle_health_ready();
    http::response<http::string_body> handle_not_found();

    // CORS helper
    void add_cors_headers(http::response<http::string_body>& res);
};

} // namespace eyed
