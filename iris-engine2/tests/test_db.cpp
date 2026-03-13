#include "db.h"

#include <doctest/doctest.h>
#include <memory>
#include <string>
#include <vector>

// Mock PGconn to avoid requiring actual PostgreSQL connection
// We test the Database class logic without needing a real database

TEST_CASE("Database instantiation") {
    Database db;
    // Initially not connected
    CHECK_FALSE(db.is_connected());
}

TEST_CASE("Database connect with invalid connection string") {
    Database db;
    // Using invalid connection string should fail gracefully
    bool result = db.connect("invalid_connection_string");
    CHECK_FALSE(result);
    CHECK_FALSE(db.is_connected());
}

TEST_CASE("Database disconnect") {
    Database db;
    // Disconnecting when not connected should be safe
    db.disconnect();
    CHECK_FALSE(db.is_connected());

    // Connecting and then disconnecting
    db.connect("postgresql://invalid");
    CHECK_FALSE(db.is_connected());
    db.disconnect();
    CHECK_FALSE(db.is_connected());
}

TEST_CASE("Database is_connected state machine") {
    Database db;

    // Initial state
    CHECK_FALSE(db.is_connected());

    // Failed connection
    db.connect("invalid");
    CHECK_FALSE(db.is_connected());

    // Disconnect after failed connection
    db.disconnect();
    CHECK_FALSE(db.is_connected());
}

TEST_CASE("Database load_all_templates when not connected") {
    Database db;
    auto templates = db.load_all_templates();
    // Should return empty vector when not connected
    CHECK(templates.empty());
}

TEST_CASE("Database load_template when not connected") {
    Database db;
    auto tmpl = db.load_template("some-template-id");
    // Should return nullopt when not connected
    CHECK_FALSE(tmpl.has_value());
}

TEST_CASE("Database ensure_identity when not connected") {
    Database db;
    bool result = db.ensure_identity("test-identity", "Test Name");
    // Should fail gracefully when not connected
    CHECK_FALSE(result);
}

TEST_CASE("Database persist_template when not connected") {
    Database db;
    iris::IrisTemplate tmpl;
    bool result = db.persist_template("template-id", "identity-id", "left", tmpl, "device");
    // Should fail gracefully when not connected
    CHECK_FALSE(result);
}

TEST_CASE("Database delete_identity when not connected") {
    Database db;
    int count = db.delete_identity("test-identity");
    // Should return 0 when not connected
    CHECK(count == 0);
}

TEST_CASE("Database log_match when not connected") {
    Database db;
    // Should not crash when not connected (is_match = true)
    db.log_match("frame-1", "template-1", "identity-1", 0.3, true, "device-1", 100);
    CHECK_FALSE(db.is_connected());
}

TEST_CASE("Database log_match no-match when not connected") {
    Database db;
    // Should not crash when not connected (is_match = false, empty ids)
    db.log_match("frame-2", "", "", 0.9, false, "device-1", 50);
    CHECK_FALSE(db.is_connected());
}

TEST_CASE("Database IrisTemplate default state") {
    iris::IrisTemplate tmpl;
    // Default-constructed IrisTemplate should have empty code vectors
    CHECK(tmpl.iris_codes.empty());
    CHECK(tmpl.mask_codes.empty());
}

// Test with invalid connection info
TEST_CASE("Database connect null string") {
    Database db;
    // Should handle empty/null connection string gracefully
    bool result = db.connect("");
    CHECK_FALSE(result);
}

TEST_CASE("Database multiple connect calls") {
    Database db;

    // First connect attempt
    bool first = db.connect("invalid");
    CHECK_FALSE(first);
    CHECK_FALSE(db.is_connected());

    // Second connect attempt
    bool second = db.connect("invalid2");
    CHECK_FALSE(second);
    CHECK_FALSE(db.is_connected());
}

TEST_CASE("Database connect then disconnect then connect") {
    Database db;

    // First connection attempt
    db.connect("invalid");
    CHECK_FALSE(db.is_connected());

    // Disconnect
    db.disconnect();
    CHECK_FALSE(db.is_connected());

    // Second connection attempt
    db.connect("invalid2");
    CHECK_FALSE(db.is_connected());
}

TEST_CASE("Database template row structure") {
    Database::TemplateRow row;

    // Verify default values
    CHECK(row.template_id.empty());
    CHECK(row.identity_id.empty());
    CHECK(row.identity_name.empty());
    CHECK(row.eye_side.empty());
    CHECK(row.width == 0);
    CHECK(row.height == 0);
    CHECK(row.n_scales == 0);
    CHECK(row.quality_score == 0.0);
    CHECK(row.device_id.empty());
}

TEST_CASE("Database db template structure") {
    DbTemplate dt;

    // Verify default values
    CHECK(dt.template_id.empty());
    CHECK(dt.identity_id.empty());
    CHECK(dt.identity_name.empty());
    CHECK(dt.eye_side.empty());
}

