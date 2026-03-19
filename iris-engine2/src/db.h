#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

#include <iris/core/iris_code_packed.hpp>
#include <iris/core/types.hpp>

struct DbTemplate {
    std::string template_id;
    std::string identity_id;
    std::string identity_name;
    std::string eye_side;
    iris::IrisTemplate tmpl;
};

class Database {
  public:
    ~Database();

    bool connect(const std::string& conninfo);
    void disconnect();
    bool is_connected() const;
    bool reconnect();

    // Load all templates for gallery initialization
    std::vector<DbTemplate> load_all_templates();

    // Persist a new identity (upsert)
    bool ensure_identity(const std::string& identity_id, const std::string& name);

    // Persist a new template (plaintext codes)
    bool persist_template(const std::string& template_id,
                          const std::string& identity_id,
                          const std::string& eye_side,
                          const iris::IrisTemplate& tmpl,
                          const std::string& device_id);

    // Persist a new template with pre-encrypted (serialized) code blobs.
    // The blobs are opaque ciphertext data stored directly in iris_codes/mask_codes.
    bool persist_encrypted_template(const std::string& template_id,
                                    const std::string& identity_id,
                                    const std::string& eye_side,
                                    const std::vector<uint8_t>& iris_blob,
                                    const std::vector<uint8_t>& mask_blob,
                                    int n_scales,
                                    const std::string& device_id);

    // Load a single template by template_id (with identity info and metadata)
    struct TemplateRow {
        std::string template_id;
        std::string identity_id;
        std::string identity_name;
        std::string eye_side;
        int width = 0;
        int height = 0;
        int n_scales = 0;
        double quality_score = 0.0;
        std::string device_id;
        iris::IrisTemplate tmpl;
        bool is_encrypted = false;
    };
    std::optional<TemplateRow> load_template(const std::string& template_id);

    // Delete identity and all templates, returns templates removed count
    int delete_identity(const std::string& identity_id);

    // Log a match attempt
    void log_match(const std::string& frame_id,
                   const std::string& matched_template_id,
                   const std::string& matched_identity_id,
                   double hamming_distance,
                   bool is_match,
                   const std::string& device_id,
                   int latency_ms);

    // Serialize/deserialize PackedIrisCodes for BYTEA storage
    static std::vector<uint8_t> serialize_codes(
        const std::vector<iris::PackedIrisCode>& codes);
    static std::vector<iris::PackedIrisCode> deserialize_codes(
        const uint8_t* data, size_t len);

    // Load raw BYTEA blobs for encrypted templates (no deserialization to PackedIrisCode)
    struct RawTemplate {
        std::string template_id;
        std::string identity_id;
        std::string identity_name;
        std::string eye_side;
        std::vector<uint8_t> iris_blob;
        std::vector<uint8_t> mask_blob;
        int n_scales = 0;
    };
    std::vector<RawTemplate> load_all_raw_templates();

  private:
    struct PGconn_deleter {
        void operator()(struct pg_conn* conn) const;
    };
    std::unique_ptr<struct pg_conn, PGconn_deleter> conn_;
    std::string conninfo_;
};
