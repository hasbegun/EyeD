#include "nats_client.h"

#include <iostream>

#include <nats.h>

struct CNatsClient::Impl {
    natsConnection* conn = nullptr;
    natsOptions* opts = nullptr;
    std::string url;
};

CNatsClient::CNatsClient() : impl_(std::make_unique<Impl>()) {}

CNatsClient::~CNatsClient() {
    disconnect();
}

bool CNatsClient::connect(const std::string& url) {
    if (impl_->conn) {
        disconnect();
    }

    impl_->url = url;

    natsStatus s = natsOptions_Create(&impl_->opts);
    if (s != NATS_OK) {
        std::cerr << "[nats] Failed to create options: " << natsStatus_GetText(s) << std::endl;
        return false;
    }

    natsOptions_SetURL(impl_->opts, url.c_str());
    natsOptions_SetTimeout(impl_->opts, 5000);          // 5s connect timeout
    natsOptions_SetMaxReconnect(impl_->opts, 10);
    natsOptions_SetReconnectWait(impl_->opts, 1000);     // 1s between reconnects

    s = natsConnection_Connect(&impl_->conn, impl_->opts);
    if (s != NATS_OK) {
        std::cerr << "[nats] Failed to connect to " << url << ": "
                  << natsStatus_GetText(s) << std::endl;
        natsOptions_Destroy(impl_->opts);
        impl_->opts = nullptr;
        return false;
    }

    std::cout << "[nats] Connected to " << url << std::endl;
    return true;
}

bool CNatsClient::connect(const std::string& url, const NatsTLSConfig& tls) {
    if (impl_->conn) {
        disconnect();
    }

    impl_->url = url;

    natsStatus s = natsOptions_Create(&impl_->opts);
    if (s != NATS_OK) {
        std::cerr << "[nats] Failed to create options: " << natsStatus_GetText(s) << std::endl;
        return false;
    }

    natsOptions_SetURL(impl_->opts, url.c_str());
    natsOptions_SetTimeout(impl_->opts, 5000);
    natsOptions_SetMaxReconnect(impl_->opts, 10);
    natsOptions_SetReconnectWait(impl_->opts, 1000);

    // Enable TLS
    s = natsOptions_SetSecure(impl_->opts, true);
    if (s != NATS_OK) {
        std::cerr << "[nats] Failed to enable TLS: " << natsStatus_GetText(s) << std::endl;
        natsOptions_Destroy(impl_->opts);
        impl_->opts = nullptr;
        return false;
    }

    // Set CA certificate for server verification
    if (!tls.ca_cert_path.empty()) {
        s = natsOptions_SetCATrustedCertificates(impl_->opts, tls.ca_cert_path.c_str());
        if (s != NATS_OK) {
            std::cerr << "[nats] Failed to set CA cert (" << tls.ca_cert_path << "): "
                      << natsStatus_GetText(s) << std::endl;
            natsOptions_Destroy(impl_->opts);
            impl_->opts = nullptr;
            return false;
        }
    }

    // Set client certificate + key for mTLS
    if (!tls.cert_path.empty() && !tls.key_path.empty()) {
        s = natsOptions_SetCertificatesChain(impl_->opts,
                                              tls.cert_path.c_str(),
                                              tls.key_path.c_str());
        if (s != NATS_OK) {
            std::cerr << "[nats] Failed to set client cert (" << tls.cert_path << "): "
                      << natsStatus_GetText(s) << std::endl;
            natsOptions_Destroy(impl_->opts);
            impl_->opts = nullptr;
            return false;
        }
    }

    s = natsConnection_Connect(&impl_->conn, impl_->opts);
    if (s != NATS_OK) {
        std::cerr << "[nats] Failed to connect (TLS) to " << url << ": "
                  << natsStatus_GetText(s) << std::endl;
        natsOptions_Destroy(impl_->opts);
        impl_->opts = nullptr;
        return false;
    }

    std::cout << "[nats] Connected (mTLS) to " << url << std::endl;
    return true;
}

void CNatsClient::disconnect() {
    if (impl_->conn) {
        natsConnection_Close(impl_->conn);
        natsConnection_Destroy(impl_->conn);
        impl_->conn = nullptr;
    }
    if (impl_->opts) {
        natsOptions_Destroy(impl_->opts);
        impl_->opts = nullptr;
    }
}

bool CNatsClient::is_connected() const noexcept {
    return impl_->conn != nullptr &&
           natsConnection_Status(impl_->conn) == NATS_CONN_STATUS_CONNECTED;
}

iris::Result<void> CNatsClient::publish(
    const std::string& subject,
    const std::vector<uint8_t>& payload) {
    if (!impl_->conn) {
        return iris::make_error(iris::ErrorCode::IoFailed, "NATS client not connected");
    }

    natsStatus s = natsConnection_Publish(
        impl_->conn,
        subject.c_str(),
        payload.data(),
        static_cast<int>(payload.size()));

    if (s != NATS_OK) {
        return iris::make_error(
            iris::ErrorCode::IoFailed,
            std::string("NATS publish failed: ") + natsStatus_GetText(s));
    }

    return {};
}

iris::Result<std::vector<uint8_t>> CNatsClient::request(
    const std::string& subject,
    const std::vector<uint8_t>& payload) {
    if (!impl_->conn) {
        return iris::make_error(iris::ErrorCode::IoFailed, "NATS client not connected");
    }

    natsMsg* reply = nullptr;
    natsStatus s = natsConnection_Request(
        &reply,
        impl_->conn,
        subject.c_str(),
        payload.data(),
        static_cast<int>(payload.size()),
        10000);  // 10s request timeout

    if (s != NATS_OK) {
        return iris::make_error(
            iris::ErrorCode::IoFailed,
            std::string("NATS request failed: ") + natsStatus_GetText(s));
    }

    const auto* data = reinterpret_cast<const uint8_t*>(natsMsg_GetData(reply));
    const int len = natsMsg_GetDataLength(reply);
    std::vector<uint8_t> result(data, data + len);

    natsMsg_Destroy(reply);
    return result;
}
