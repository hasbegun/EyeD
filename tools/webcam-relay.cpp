/**
 * MJPEG webcam relay for macOS/Windows Docker development.
 *
 * Captures from the host webcam and serves an MJPEG stream over HTTP.
 * The Docker capture-device container reads this stream via:
 *   cv::VideoCapture("http://host.docker.internal:8090/video")
 *
 * Build:
 *   cmake -B build tools && cmake --build build
 *
 * Usage:
 *   ./build/webcam-relay [--port 8090] [--device 0]
 */

#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include <opencv2/opencv.hpp>

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#pragma comment(lib, "ws2_32.lib")
using socket_t = SOCKET;
#define CLOSE_SOCKET closesocket
#else
#include <arpa/inet.h>
#include <csignal>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
using socket_t = int;
#define CLOSE_SOCKET close
#define INVALID_SOCKET (-1)
#endif

static std::atomic<bool> g_running{true};

struct Camera {
    cv::VideoCapture cap;
    std::mutex mtx;
};

static void serve_client(socket_t client_fd, Camera &cam) {
    // Read the HTTP request line (we only care about GET /video)
    char buf[1024];
    int n = recv(client_fd, buf, sizeof(buf) - 1, 0);
    if (n <= 0) {
        CLOSE_SOCKET(client_fd);
        return;
    }
    buf[n] = '\0';

    // Check for GET /video
    if (std::strstr(buf, "GET /video") == nullptr) {
        const char *resp = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n";
        send(client_fd, resp, (int)std::strlen(resp), 0);
        CLOSE_SOCKET(client_fd);
        return;
    }

    // Send MJPEG header
    const char *header =
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: multipart/x-mixed-replace; boundary=frame\r\n"
        "Cache-Control: no-cache\r\n"
        "Connection: close\r\n"
        "\r\n";
    if (send(client_fd, header, (int)std::strlen(header), 0) < 0) {
        CLOSE_SOCKET(client_fd);
        return;
    }

    std::vector<uchar> jpeg_buf;
    std::vector<int> encode_params = {cv::IMWRITE_JPEG_QUALITY, 80};

    while (g_running) {
        cv::Mat frame;
        {
            std::lock_guard<std::mutex> lk(cam.mtx);
            cam.cap.read(frame);
        }
        if (frame.empty()) break;

        cv::imencode(".jpg", frame, jpeg_buf, encode_params);

        // Write MJPEG boundary + JPEG data
        char part_header[128];
        int hlen = std::snprintf(part_header, sizeof(part_header),
            "--frame\r\nContent-Type: image/jpeg\r\nContent-Length: %zu\r\n\r\n",
            jpeg_buf.size());

        if (send(client_fd, part_header, hlen, 0) < 0) break;
        if (send(client_fd, reinterpret_cast<const char *>(jpeg_buf.data()),
                 (int)jpeg_buf.size(), 0) < 0)
            break;
        if (send(client_fd, "\r\n", 2, 0) < 0) break;
    }

    CLOSE_SOCKET(client_fd);
}

static void print_usage(const char *prog) {
    std::fprintf(stderr, "Usage: %s [--port PORT] [--device INDEX]\n", prog);
}

int main(int argc, char **argv) {
    int port = 8090;
    int device = 0;

    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--port") == 0 && i + 1 < argc) {
            port = std::atoi(argv[++i]);
        } else if (std::strcmp(argv[i], "--device") == 0 && i + 1 < argc) {
            device = std::atoi(argv[++i]);
        } else if (std::strcmp(argv[i], "--help") == 0 ||
                   std::strcmp(argv[i], "-h") == 0) {
            print_usage(argv[0]);
            return 0;
        } else {
            print_usage(argv[0]);
            return 1;
        }
    }

#ifdef _WIN32
    WSADATA wsa;
    WSAStartup(MAKEWORD(2, 2), &wsa);
#else
    std::signal(SIGPIPE, SIG_IGN);
    std::signal(SIGINT, [](int) { g_running = false; });
    std::signal(SIGTERM, [](int) { g_running = false; });
#endif

    // Open camera
    Camera cam;
    cam.cap.open(device);
    if (!cam.cap.isOpened()) {
        std::fprintf(stderr, "ERROR: Cannot open camera device %d\n", device);
        return 1;
    }

    int w = static_cast<int>(cam.cap.get(cv::CAP_PROP_FRAME_WIDTH));
    int h = static_cast<int>(cam.cap.get(cv::CAP_PROP_FRAME_HEIGHT));
    std::printf("Webcam opened: %dx%d\n", w, h);
    std::printf("Serving MJPEG on http://0.0.0.0:%d/video\n", port);
    std::printf("Docker URL: http://host.docker.internal:%d/video\n", port);
    std::printf("Press Ctrl+C to stop\n");

    // Create server socket
    socket_t server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd == INVALID_SOCKET) {
        std::perror("socket");
        return 1;
    }

    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR,
               reinterpret_cast<const char *>(&opt), sizeof(opt));

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(static_cast<uint16_t>(port));

    if (bind(server_fd, reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) < 0) {
        std::perror("bind");
        CLOSE_SOCKET(server_fd);
        return 1;
    }

    if (listen(server_fd, 4) < 0) {
        std::perror("listen");
        CLOSE_SOCKET(server_fd);
        return 1;
    }

    // Accept loop
    while (g_running) {
        sockaddr_in client_addr{};
        socklen_t client_len = sizeof(client_addr);
        socket_t client_fd =
            accept(server_fd, reinterpret_cast<sockaddr *>(&client_addr), &client_len);
        if (client_fd == INVALID_SOCKET) {
            if (!g_running) break;
            continue;
        }
        // Handle each client in a detached thread
        std::thread(serve_client, client_fd, std::ref(cam)).detach();
    }

    std::printf("\nStopping...\n");
    CLOSE_SOCKET(server_fd);
    cam.cap.release();

#ifdef _WIN32
    WSACleanup();
#endif
    return 0;
}
