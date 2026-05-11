#include <iostream>
#include <memory>
#include <csignal>
#include <atomic>
#include <thread>
#include <chrono>
#include <cstdlib>
#include <string>

#include <nats.h>

#include <iris/crypto/smpc2_participant.hpp>
#include <iris/crypto/smpc2_queue.hpp>

// Codec in iris-engine2/src/ — visible via target_include_directories
#include "smpc2_nats_codec.h"

namespace {

std::atomic<bool> g_shutdown{false};

void signal_handler(int sig) {
    if (sig == SIGINT || sig == SIGTERM) {
        std::cerr << "[smpc2-party] Shutdown signal received, exiting...\n";
        g_shutdown.store(true);
    }
}

std::string get_env(const char* name, const std::string& def = "") {
    const char* v = std::getenv(name);
    return v ? std::string(v) : def;
}

int get_env_int(const char* name, int def = 0) {
    const char* v = std::getenv(name);
    return v ? std::atoi(v) : def;
}

struct Ctx {
    std::shared_ptr<iris::SMPC2ParticipantService> service;
};

void on_share_sync(natsConnection* /*conn*/, natsSubscription* /*sub*/,
                   natsMsg* msg, void* closure) {
    auto* ctx = static_cast<Ctx*>(closure);

    const auto* data = reinterpret_cast<const uint8_t*>(natsMsg_GetData(msg));
    const int   len  = natsMsg_GetDataLength(msg);
    std::vector<uint8_t> payload(data, data + len);

    auto job_r = iris::decode_shamir_share_sync_job(payload);
    if (!job_r.has_value()) {
        std::cerr << "[smpc2-party] decode share_sync failed: "
                  << job_r.error().message << "\n";
        natsMsg_Destroy(msg);
        return;
    }

    auto result = ctx->service->handle_share_sync(*job_r);
    if (!result.has_value()) {
        std::cerr << "[smpc2-party] handle_share_sync failed: "
                  << result.error().message << "\n";
    }

    natsMsg_Destroy(msg);
}

void on_match(natsConnection* conn, natsSubscription* /*sub*/,
              natsMsg* msg, void* closure) {
    auto* ctx = static_cast<Ctx*>(closure);

    const auto* data = reinterpret_cast<const uint8_t*>(natsMsg_GetData(msg));
    const int   len  = natsMsg_GetDataLength(msg);
    std::vector<uint8_t> payload(data, data + len);
    const char* reply_to = natsMsg_GetReply(msg);

    auto job_r = iris::decode_shamir_match_job(payload);
    if (!job_r.has_value()) {
        std::cerr << "[smpc2-party] decode match job failed: "
                  << job_r.error().message << "\n";
        natsMsg_Destroy(msg);
        return;
    }

    auto resp_r = ctx->service->handle_match(*job_r);
    if (!resp_r.has_value()) {
        std::cerr << "[smpc2-party] handle_match failed: "
                  << resp_r.error().message << "\n";
        natsMsg_Destroy(msg);
        return;
    }

    auto enc_r = iris::encode_shamir_match_response(*resp_r);
    if (!enc_r.has_value()) {
        std::cerr << "[smpc2-party] encode match response failed: "
                  << enc_r.error().message << "\n";
        natsMsg_Destroy(msg);
        return;
    }

    if (reply_to && reply_to[0] != '\0') {
        natsConnection_Publish(conn, reply_to,
                               enc_r->data(),
                               static_cast<int>(enc_r->size()));
    }

    natsMsg_Destroy(msg);
}

}  // namespace

int main() {
    std::signal(SIGINT,  signal_handler);
    std::signal(SIGTERM, signal_handler);

    const int         party_id    = get_env_int("PARTY_ID", 1);
    const std::string nats_url    = get_env("NATS_URL", "nats://localhost:4222");
    const std::string prefix      = get_env("NATS_SUBJECT_PREFIX", "smpc2");
    const std::string tls_dir     = get_env("TLS_CERT_DIR");

    std::cout << "[smpc2-party] Starting SMPC2 Participant Service\n"
              << "  PARTY_ID: " << party_id << "\n"
              << "  NATS_URL: " << nats_url << "\n"
              << "  prefix:   " << prefix   << "\n";

    Ctx ctx;
    ctx.service = std::make_shared<iris::SMPC2ParticipantService>(
        static_cast<uint8_t>(party_id));

    // --- Connect to NATS ---
    natsOptions*    opts = nullptr;
    natsConnection* conn = nullptr;

    natsOptions_Create(&opts);
    natsOptions_SetURL(opts, nats_url.c_str());
    natsOptions_SetTimeout(opts, 10000);
    natsOptions_SetMaxReconnect(opts, -1);
    natsOptions_SetReconnectWait(opts, 2000);

    if (!tls_dir.empty()) {
        const std::string ca   = tls_dir + "/ca.crt";
        const std::string cert = tls_dir + "/party-" + std::to_string(party_id) + ".crt";
        const std::string key  = tls_dir + "/party-" + std::to_string(party_id) + ".key";
        natsOptions_SetSecure(opts, true);
        natsOptions_SetCATrustedCertificates(opts, ca.c_str());
        natsOptions_SetCertificatesChain(opts, cert.c_str(), key.c_str());
        std::cout << "  TLS: enabled (" << tls_dir << ")\n";
    }

    natsStatus s = natsConnection_Connect(&conn, opts);
    if (s != NATS_OK) {
        std::cerr << "[smpc2-party] Failed to connect to NATS: "
                  << natsStatus_GetText(s) << "\n";
        natsOptions_Destroy(opts);
        return 1;
    }
    std::cout << "[smpc2-party] Connected to NATS at " << nats_url << "\n";

    // --- Subscribe ---
    const std::string pid_str      = std::to_string(party_id);
    const std::string share_subj   = prefix + ".party." + pid_str + ".share_sync";
    const std::string match_subj   = prefix + ".party." + pid_str + ".match";

    natsSubscription* sub_share = nullptr;
    natsSubscription* sub_match = nullptr;

    s = natsConnection_Subscribe(&sub_share, conn, share_subj.c_str(), on_share_sync, &ctx);
    if (s != NATS_OK) {
        std::cerr << "[smpc2-party] Subscribe failed (" << share_subj << "): "
                  << natsStatus_GetText(s) << "\n";
        natsConnection_Destroy(conn);
        natsOptions_Destroy(opts);
        return 1;
    }

    s = natsConnection_Subscribe(&sub_match, conn, match_subj.c_str(), on_match, &ctx);
    if (s != NATS_OK) {
        std::cerr << "[smpc2-party] Subscribe failed (" << match_subj << "): "
                  << natsStatus_GetText(s) << "\n";
        natsSubscription_Destroy(sub_share);
        natsConnection_Destroy(conn);
        natsOptions_Destroy(opts);
        return 1;
    }

    std::cout << "[smpc2-party] Subscribed to:\n"
              << "  " << share_subj << "\n"
              << "  " << match_subj << "\n"
              << "[smpc2-party] Ready.\n";

    while (!g_shutdown.load()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    std::cout << "[smpc2-party] Shutting down (gallery size="
              << ctx.service->size() << ")\n";

    natsSubscription_Destroy(sub_match);
    natsSubscription_Destroy(sub_share);
    natsConnection_Close(conn);
    natsConnection_Destroy(conn);
    natsOptions_Destroy(opts);
    return 0;
}
