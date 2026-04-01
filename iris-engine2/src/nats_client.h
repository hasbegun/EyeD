#pragma once

#include <memory>
#include <string>

#include <iris/crypto/smpc_queue.hpp>

/// TLS configuration for NATS connections.
/// All paths must point to PEM-encoded files.
struct NatsTLSConfig {
    std::string ca_cert_path;   // CA certificate (for verifying server)
    std::string cert_path;      // Client certificate (for mTLS)
    std::string key_path;       // Client private key
};

/// Concrete INatsClient implementation using the nats.c C library.
/// Provides publish/request semantics over a NATS connection.
class CNatsClient : public iris::INatsClient {
  public:
    CNatsClient();
    ~CNatsClient() override;

    CNatsClient(const CNatsClient&) = delete;
    CNatsClient& operator=(const CNatsClient&) = delete;

    /// Connect to the NATS server at the given URL (e.g. "nats://nats:4222").
    bool connect(const std::string& url);

    /// Connect to the NATS server with mTLS.
    bool connect(const std::string& url, const NatsTLSConfig& tls);

    /// Disconnect from the NATS server.
    void disconnect();

    /// Whether the client is currently connected.
    [[nodiscard]] bool is_connected() const noexcept;

    iris::Result<void> publish(
        const std::string& subject,
        const std::vector<uint8_t>& payload) override;

    iris::Result<std::vector<uint8_t>> request(
        const std::string& subject,
        const std::vector<uint8_t>& payload) override;

  private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};
