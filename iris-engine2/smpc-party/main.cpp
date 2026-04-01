#include <iostream>
#include <memory>
#include <csignal>
#include <atomic>
#include <thread>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <functional>

#include <nats.h>

#include <iris/crypto/smpc_participant_service.hpp>
#include <iris/crypto/smpc_sharded_gallery.hpp>
#include <iris/crypto/smpc_queue.hpp>
#include <iris/crypto/smpc_queue_codec.hpp>

namespace {

std::atomic<bool> g_shutdown{false};

void signal_handler(int signal) {
    if (signal == SIGINT || signal == SIGTERM) {
        std::cerr << "Received shutdown signal, exiting gracefully...\n";
        g_shutdown.store(true);
    }
}

std::string get_env_or_default(const char* name, const std::string& default_val) {
    const char* val = std::getenv(name);
    return val ? std::string(val) : default_val;
}

int get_env_int_or_default(const char* name, int default_val) {
    const char* val = std::getenv(name);
    return val ? std::atoi(val) : default_val;
}

struct ParticipantContext {
    std::shared_ptr<iris::ISMPCParticipantConsumer> service;
    std::function<size_t()> size_fn;
};

// --- NATS message handlers ---

void on_share_sync(natsConnection* /*conn*/, natsSubscription* /*sub*/,
                   natsMsg* msg, void* closure) {
    auto* ctx = static_cast<ParticipantContext*>(closure);

    const auto* data = reinterpret_cast<const uint8_t*>(natsMsg_GetData(msg));
    const int len = natsMsg_GetDataLength(msg);
    std::vector<uint8_t> payload(data, data + len);

    auto job_r = iris::decode_share_sync_job(payload);
    if (!job_r.has_value()) {
        std::cerr << "[party] Failed to decode share_sync: "
                  << job_r.error().message << "\n";
        natsMsg_Destroy(msg);
        return;
    }

    auto result = ctx->service->handle_share_sync(*job_r);
    if (!result.has_value()) {
        std::cerr << "[party] handle_share_sync failed: "
                  << result.error().message << "\n";
    }

    natsMsg_Destroy(msg);
}

void on_match(natsConnection* conn, natsSubscription* /*sub*/,
              natsMsg* msg, void* closure) {
    auto* ctx = static_cast<ParticipantContext*>(closure);

    const auto* data = reinterpret_cast<const uint8_t*>(natsMsg_GetData(msg));
    const int len = natsMsg_GetDataLength(msg);
    std::vector<uint8_t> payload(data, data + len);

    const char* reply_to = natsMsg_GetReply(msg);

    auto job_r = iris::decode_match_job(payload);
    if (!job_r.has_value()) {
        std::cerr << "[party] Failed to decode match job: "
                  << job_r.error().message << "\n";
        natsMsg_Destroy(msg);
        return;
    }

    auto response_r = ctx->service->handle_match(*job_r);
    if (!response_r.has_value()) {
        std::cerr << "[party] handle_match failed: "
                  << response_r.error().message << "\n";
        natsMsg_Destroy(msg);
        return;
    }

    auto encoded_r = iris::encode_participant_match_response(*response_r);
    if (!encoded_r.has_value()) {
        std::cerr << "[party] Failed to encode match response: "
                  << encoded_r.error().message << "\n";
        natsMsg_Destroy(msg);
        return;
    }

    if (reply_to && reply_to[0] != '\0') {
        natsConnection_Publish(conn, reply_to,
                               encoded_r->data(),
                               static_cast<int>(encoded_r->size()));
    }

    natsMsg_Destroy(msg);
}

void on_batch_match(natsConnection* conn, natsSubscription* /*sub*/,
                    natsMsg* msg, void* closure) {
    auto* ctx = static_cast<ParticipantContext*>(closure);

    const auto* data = reinterpret_cast<const uint8_t*>(natsMsg_GetData(msg));
    const int len = natsMsg_GetDataLength(msg);
    std::vector<uint8_t> payload(data, data + len);

    const char* reply_to = natsMsg_GetReply(msg);

    auto job_r = iris::decode_batch_match_job(payload);
    if (!job_r.has_value()) {
        std::cerr << "[party] Failed to decode batch match job: "
                  << job_r.error().message << "\n";
        natsMsg_Destroy(msg);
        return;
    }

    auto response_r = ctx->service->handle_batch_match(*job_r);
    if (!response_r.has_value()) {
        std::cerr << "[party] handle_batch_match failed: "
                  << response_r.error().message << "\n";
        natsMsg_Destroy(msg);
        return;
    }

    auto encoded_r = iris::encode_batch_participant_match_response(*response_r);
    if (!encoded_r.has_value()) {
        std::cerr << "[party] Failed to encode batch match response: "
                  << encoded_r.error().message << "\n";
        natsMsg_Destroy(msg);
        return;
    }

    if (reply_to && reply_to[0] != '\0') {
        natsConnection_Publish(conn, reply_to,
                               encoded_r->data(),
                               static_cast<int>(encoded_r->size()));
    }

    natsMsg_Destroy(msg);
}

}  // namespace

int main(int argc, char** argv) {
    (void)argc;
    (void)argv;

    std::signal(SIGINT, signal_handler);
    std::signal(SIGTERM, signal_handler);

    // Read configuration from environment
    const int party_id = get_env_int_or_default("PARTY_ID", 1);
    const std::string nats_url = get_env_or_default("NATS_URL", "nats://localhost:4222");
    const std::string subject_prefix = get_env_or_default("NATS_SUBJECT_PREFIX", "smpc");
    const int shard_id = get_env_int_or_default("SHARD_ID", 0);
    const int total_shards = get_env_int_or_default("TOTAL_SHARDS", 0);
    const std::string tls_cert_dir = get_env_or_default("TLS_CERT_DIR", "");

    std::cout << "Starting SMPC Participant Service\n";
    std::cout << "  Party ID: " << party_id << "\n";
    std::cout << "  NATS URL: " << nats_url << "\n";
    std::cout << "  Subject Prefix: " << subject_prefix << "\n";

    // Create participant service (sharded or plain)
    ParticipantContext ctx;
    if (total_shards > 0) {
        auto svc = std::make_shared<iris::SMPCShardedParticipantService>(
            static_cast<uint8_t>(party_id),
            static_cast<uint8_t>(shard_id),
            static_cast<size_t>(total_shards));
        ctx.size_fn = [svc]() { return svc->size(); };
        ctx.service = svc;
        std::cout << "  Mode: sharded (shard " << shard_id
                  << "/" << total_shards << ")\n";
    } else {
        auto svc = std::make_shared<iris::SMPCParticipantService>(
            static_cast<uint8_t>(party_id));
        ctx.size_fn = [svc]() { return svc->size(); };
        ctx.service = svc;
        std::cout << "  Mode: standard\n";
    }

    // Connect to NATS
    natsOptions* opts = nullptr;
    natsConnection* conn = nullptr;

    natsStatus s = natsOptions_Create(&opts);
    if (s != NATS_OK) {
        std::cerr << "Failed to create NATS options: " << natsStatus_GetText(s) << "\n";
        return 1;
    }

    natsOptions_SetURL(opts, nats_url.c_str());
    natsOptions_SetTimeout(opts, 10000);
    natsOptions_SetMaxReconnect(opts, -1);       // Infinite reconnects
    natsOptions_SetReconnectWait(opts, 2000);

    // Configure mTLS if cert dir is set
    if (!tls_cert_dir.empty()) {
        const std::string ca_path   = tls_cert_dir + "/ca.crt";
        const std::string cert_path = tls_cert_dir + "/party-" + std::to_string(party_id) + ".crt";
        const std::string key_path  = tls_cert_dir + "/party-" + std::to_string(party_id) + ".key";

        s = natsOptions_SetSecure(opts, true);
        if (s != NATS_OK) {
            std::cerr << "Failed to enable TLS: " << natsStatus_GetText(s) << "\n";
            natsOptions_Destroy(opts);
            return 1;
        }
        s = natsOptions_SetCATrustedCertificates(opts, ca_path.c_str());
        if (s != NATS_OK) {
            std::cerr << "Failed to set CA cert: " << natsStatus_GetText(s) << "\n";
            natsOptions_Destroy(opts);
            return 1;
        }
        s = natsOptions_SetCertificatesChain(opts, cert_path.c_str(), key_path.c_str());
        if (s != NATS_OK) {
            std::cerr << "Failed to set client cert: " << natsStatus_GetText(s) << "\n";
            natsOptions_Destroy(opts);
            return 1;
        }
        std::cout << "  TLS: enabled (certs: " << tls_cert_dir << ")\n";
    }

    s = natsConnection_Connect(&conn, opts);
    if (s != NATS_OK) {
        std::cerr << "Failed to connect to NATS at " << nats_url << ": "
                  << natsStatus_GetText(s) << "\n";
        natsOptions_Destroy(opts);
        return 1;
    }

    std::cout << "Connected to NATS at " << nats_url
              << (tls_cert_dir.empty() ? "" : " (mTLS)") << "\n";

    // Subscribe to NATS subjects
    const std::string pid = std::to_string(party_id);
    const std::string share_sync_subj = subject_prefix + ".participant." + pid + ".share_sync";
    const std::string match_subj      = subject_prefix + ".participant." + pid + ".match";
    const std::string batch_subj      = subject_prefix + ".participant." + pid + ".batch_match";

    natsSubscription* sub_share_sync = nullptr;
    natsSubscription* sub_match = nullptr;
    natsSubscription* sub_batch = nullptr;

    s = natsConnection_Subscribe(&sub_share_sync, conn, share_sync_subj.c_str(),
                                  on_share_sync, &ctx);
    if (s != NATS_OK) {
        std::cerr << "Failed to subscribe to " << share_sync_subj << ": "
                  << natsStatus_GetText(s) << "\n";
        natsConnection_Destroy(conn);
        natsOptions_Destroy(opts);
        return 1;
    }

    s = natsConnection_Subscribe(&sub_match, conn, match_subj.c_str(),
                                  on_match, &ctx);
    if (s != NATS_OK) {
        std::cerr << "Failed to subscribe to " << match_subj << ": "
                  << natsStatus_GetText(s) << "\n";
        natsSubscription_Destroy(sub_share_sync);
        natsConnection_Destroy(conn);
        natsOptions_Destroy(opts);
        return 1;
    }

    s = natsConnection_Subscribe(&sub_batch, conn, batch_subj.c_str(),
                                  on_batch_match, &ctx);
    if (s != NATS_OK) {
        std::cerr << "Failed to subscribe to " << batch_subj << ": "
                  << natsStatus_GetText(s) << "\n";
        natsSubscription_Destroy(sub_match);
        natsSubscription_Destroy(sub_share_sync);
        natsConnection_Destroy(conn);
        natsOptions_Destroy(opts);
        return 1;
    }

    std::cout << "Subscribed to:\n";
    std::cout << "  " << share_sync_subj << "\n";
    std::cout << "  " << match_subj << "\n";
    std::cout << "  " << batch_subj << "\n";
    std::cout << "Participant service ready. Waiting for messages...\n";

    // Main event loop — NATS callbacks run on separate threads
    while (!g_shutdown.load()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    std::cout << "Shutting down participant service...\n";
    std::cout << "  Gallery size at shutdown: " << ctx.size_fn() << "\n";

    natsSubscription_Destroy(sub_batch);
    natsSubscription_Destroy(sub_match);
    natsSubscription_Destroy(sub_share_sync);
    natsConnection_Close(conn);
    natsConnection_Destroy(conn);
    natsOptions_Destroy(opts);

    return 0;
}
