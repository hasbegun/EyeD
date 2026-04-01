#include <doctest/doctest.h>

#include <chrono>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

#include <iris/crypto/smpc_tls.hpp>
#include <iris/crypto/smpc_audit.hpp>

// ---- TLSContext tests ----

TEST_CASE("TLSContext::create fails with empty paths") {
    iris::TLSConfig cfg{};
    auto r = iris::TLSContext::create(cfg);
    CHECK(!r.has_value());
    CHECK(r.error().message.find("must not be empty") != std::string::npos);
}

TEST_CASE("TLSContext::create succeeds with valid cert files") {
    auto tmp = std::filesystem::temp_directory_path() / "smpc_tls_test";
    std::filesystem::create_directories(tmp);

    // Write minimal dummy PEM files (content doesn't matter for TLSContext loading)
    auto write = [&](const std::string& name, const std::string& content) {
        std::ofstream f(tmp / name);
        f << content;
    };
    write("ca.crt",   "-----BEGIN CERTIFICATE-----\nfake\n-----END CERTIFICATE-----\n");
    write("cert.crt", "-----BEGIN CERTIFICATE-----\nfake\n-----END CERTIFICATE-----\n");
    write("cert.key", "-----BEGIN PRIVATE KEY-----\nfake\n-----END PRIVATE KEY-----\n");

    iris::TLSConfig cfg{};
    cfg.ca_cert_path = (tmp / "ca.crt").string();
    cfg.cert_path    = (tmp / "cert.crt").string();
    cfg.key_path     = (tmp / "cert.key").string();

    auto r = iris::TLSContext::create(cfg);
    CHECK(r.has_value());

    // Verify config is stored
    CHECK(r.value()->config().ca_cert_path == cfg.ca_cert_path);
    CHECK(r.value()->config().verify_peer == true);

    std::filesystem::remove_all(tmp);
}

TEST_CASE("TLSContext::create fails with missing file") {
    iris::TLSConfig cfg{};
    cfg.ca_cert_path = "/nonexistent/ca.crt";
    cfg.cert_path    = "/nonexistent/cert.crt";
    cfg.key_path     = "/nonexistent/cert.key";

    auto r = iris::TLSContext::create(cfg);
    CHECK(!r.has_value());
    CHECK(r.error().message.find("Failed to open file") != std::string::npos);
}

TEST_CASE("TLSContext::validate_peer_certificate rejects empty cert when verify_peer is true") {
    auto tmp = std::filesystem::temp_directory_path() / "smpc_tls_test2";
    std::filesystem::create_directories(tmp);

    auto write = [&](const std::string& name) {
        std::ofstream f(tmp / name);
        f << "-----BEGIN CERTIFICATE-----\nfake\n-----END CERTIFICATE-----\n";
    };
    write("ca.crt");
    write("cert.crt");
    std::ofstream(tmp / "cert.key") << "-----BEGIN PRIVATE KEY-----\nfake\n-----END PRIVATE KEY-----\n";

    iris::TLSConfig cfg{};
    cfg.ca_cert_path = (tmp / "ca.crt").string();
    cfg.cert_path    = (tmp / "cert.crt").string();
    cfg.key_path     = (tmp / "cert.key").string();
    cfg.verify_peer  = true;

    auto ctx = iris::TLSContext::create(cfg);
    REQUIRE(ctx.has_value());

    auto r = ctx.value()->validate_peer_certificate("");
    CHECK(!r.has_value());

    // Valid (non-empty) peer cert should pass
    auto r2 = ctx.value()->validate_peer_certificate("some-cert-data");
    CHECK(r2.has_value());

    std::filesystem::remove_all(tmp);
}

// ---- AuditLogger tests ----

TEST_CASE("AuditLogger logs enrollment events") {
    auto& logger = iris::AuditLogger::instance();

    // Set log file to a temp path
    auto tmp = std::filesystem::temp_directory_path() / "smpc_audit_test.log";
    logger.set_log_file(tmp.string());

    logger.log_enrollment("test-service", "subject-001", true, "enrollment ok");

    auto events = logger.get_recent_events(10);
    CHECK(!events.empty());

    bool found = false;
    for (const auto& e : events) {
        if (e.type == iris::AuditEventType::Enrollment &&
            e.subject_id == "subject-001" &&
            e.success == true) {
            found = true;
            break;
        }
    }
    CHECK(found);

    // Verify file was written
    std::ifstream f(tmp);
    std::string content((std::istreambuf_iterator<char>(f)),
                         std::istreambuf_iterator<char>());
    CHECK(content.find("subject=subject-001") != std::string::npos);

    std::filesystem::remove(tmp);
}

TEST_CASE("AuditLogger logs verification events with distance") {
    auto& logger = iris::AuditLogger::instance();

    auto tmp = std::filesystem::temp_directory_path() / "smpc_audit_verify.log";
    logger.set_log_file(tmp.string());

    logger.log_verification("test-service", "subject-002", true, 0.2345, "match found");

    auto events = logger.get_recent_events(10);
    bool found = false;
    for (const auto& e : events) {
        if (e.type == iris::AuditEventType::Verification &&
            e.subject_id == "subject-002" &&
            e.details.find("0.2345") != std::string::npos) {
            found = true;
            break;
        }
    }
    CHECK(found);

    std::filesystem::remove(tmp);
}

TEST_CASE("AuditLogger logs security violations") {
    auto& logger = iris::AuditLogger::instance();

    logger.log_security_violation("test-service", "unauthorized access attempt");

    auto events = logger.get_recent_events(10);
    bool found = false;
    for (const auto& e : events) {
        if (e.type == iris::AuditEventType::SecurityViolation &&
            e.success == false &&
            e.details.find("unauthorized") != std::string::npos) {
            found = true;
            break;
        }
    }
    CHECK(found);
}

// ---- SecurityMonitor tests ----

TEST_CASE("SecurityMonitor default state is healthy") {
    iris::SecurityMonitor monitor("test-service");
    CHECK(monitor.is_healthy());

    auto report = monitor.get_status_report();
    CHECK(report.find("test-service") != std::string::npos);
    CHECK(report.find("OK") != std::string::npos);
}

TEST_CASE("SecurityMonitor detects high failure rate") {
    iris::SecurityMonitor monitor("test-service");

    // 50% failure rate (threshold is 10%)
    monitor.monitor_failed_requests(50, 100);
    CHECK(!monitor.is_healthy());

    auto report = monitor.get_status_report();
    CHECK(report.find("HIGH") != std::string::npos);
}

TEST_CASE("SecurityMonitor detects latency anomaly") {
    iris::SecurityMonitor monitor("test-service");

    // 4x baseline (threshold is 3x)
    monitor.detect_anomalies(400.0, 100.0);
    CHECK(!monitor.is_healthy());

    auto report = monitor.get_status_report();
    CHECK(report.find("ANOMALY") != std::string::npos);
}

TEST_CASE("SecurityMonitor stays healthy under normal conditions") {
    iris::SecurityMonitor monitor("test-service");

    monitor.monitor_failed_requests(1, 100);   // 1% failure — OK
    monitor.detect_anomalies(150.0, 100.0);    // 1.5x baseline — OK
    CHECK(monitor.is_healthy());
}

// ---- HealthCheckService tests ----

TEST_CASE("HealthCheckService tracks requests") {
    iris::HealthCheckService health("test-svc", "1.0");

    health.record_request_success();
    health.record_request_success();
    health.record_request_success();

    auto status = health.get_status();
    CHECK(status.healthy == true);
    CHECK(status.service_name == "test-svc");
    CHECK(status.version == "1.0");
    CHECK(status.requests_processed == 3);
    CHECK(status.requests_failed == 0);
    CHECK(status.uptime_seconds >= 0);
}

TEST_CASE("HealthCheckService reports unhealthy on high failure rate") {
    iris::HealthCheckService health("test-svc", "1.0");

    // All requests fail → 100% failure rate → unhealthy
    health.record_request_failure("error1");
    auto status = health.get_status();
    CHECK(status.healthy == false);
    CHECK(status.requests_failed == 1);
    CHECK(status.last_error == "error1");
}

TEST_CASE("HealthCheckService reports gallery size") {
    iris::HealthCheckService health("test-svc", "1.0");
    health.set_gallery_size(1000);

    auto status = health.get_status();
    CHECK(status.gallery_size == 1000);
}
