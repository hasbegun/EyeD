// WebSocket test: connects to /ws/results, waits for one message, prints it and exits.
// Usage: ws_test [gateway_host] [http_port]
//   Defaults: localhost 8080

#include <iostream>
#include <string>
#include <boost/asio.hpp>
#include <boost/beast.hpp>
#include <boost/beast/websocket.hpp>

namespace beast     = boost::beast;
namespace websocket = beast::websocket;
namespace net       = boost::asio;
using tcp           = net::ip::tcp;

int main(int argc, char* argv[]) {
    std::string host = (argc > 1) ? argv[1] : "localhost";
    std::string port = (argc > 2) ? argv[2] : "8080";

    std::cout << "{\"level\":\"info\",\"msg\":\"Connecting to WebSocket\","
              << "\"host\":\"" << host << "\",\"port\":\"" << port << "\"}" << std::endl;

    try {
        net::io_context ioc;
        tcp::resolver resolver{ioc};
        websocket::stream<tcp::socket> ws{ioc};

        auto const results = resolver.resolve(host, port);
        auto ep = net::connect(ws.next_layer(), results);

        std::string host_port = host + ":" + std::to_string(ep.port());
        ws.handshake(host_port, "/ws/results");

        std::cout << "{\"level\":\"info\",\"msg\":\"WebSocket connected, waiting for message\"}" << std::endl;

        beast::flat_buffer buffer;
        ws.read(buffer);

        std::string msg = beast::buffers_to_string(buffer.data());
        std::cout << "{\"level\":\"info\",\"msg\":\"Received WebSocket message\",\"data\":"
                  << msg << "}" << std::endl;

        ws.close(websocket::close_code::normal);

        std::cout << "{\"level\":\"info\",\"msg\":\"ws-test PASSED\"}" << std::endl;
        return 0;

    } catch (const std::exception& e) {
        std::cerr << "{\"level\":\"error\",\"msg\":\"ws-test failed\",\"error\":\""
                  << e.what() << "\"}" << std::endl;
        return 1;
    }
}
