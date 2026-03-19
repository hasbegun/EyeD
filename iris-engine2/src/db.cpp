#include "db.h"

#include <iostream>

#include <libpq-fe.h>

#include <iris/utils/template_serializer.hpp>

// --- PGconn custom deleter ---

void Database::PGconn_deleter::operator()(struct pg_conn* conn) const {
    if (conn) PQfinish(conn);
}

// --- Connection management ---

Database::~Database() { disconnect(); }

bool Database::connect(const std::string& conninfo) {
    conninfo_ = conninfo;
    auto* raw = PQconnectdb(conninfo.c_str());
    if (PQstatus(raw) != CONNECTION_OK) {
        std::cerr << "[db] Connection failed: " << PQerrorMessage(raw) << std::endl;
        PQfinish(raw);
        return false;
    }
    conn_.reset(raw);
    std::cout << "[db] Connected to PostgreSQL" << std::endl;
    return true;
}

bool Database::reconnect() {
    if (conninfo_.empty()) return false;
    std::cerr << "[db] Reconnecting to PostgreSQL..." << std::endl;
    conn_.reset();  // close stale connection
    auto* raw = PQconnectdb(conninfo_.c_str());
    if (PQstatus(raw) != CONNECTION_OK) {
        std::cerr << "[db] Reconnect failed: " << PQerrorMessage(raw) << std::endl;
        PQfinish(raw);
        return false;
    }
    conn_.reset(raw);
    std::cout << "[db] Reconnected to PostgreSQL" << std::endl;
    return true;
}

void Database::disconnect() {
    conn_.reset();
}

bool Database::is_connected() const {
    return conn_ && PQstatus(conn_.get()) == CONNECTION_OK;
}

// --- Template serialization (native IRTB binary format) ---

std::vector<uint8_t> Database::serialize_codes(
    const std::vector<iris::PackedIrisCode>& codes) {
    std::vector<uint8_t> result;
    result.reserve(codes.size() * iris::TemplateSerializer::kBinarySize);
    for (const auto& code : codes) {
        auto bin = iris::TemplateSerializer::to_binary(code);
        result.insert(result.end(), bin.begin(), bin.end());
    }
    return result;
}

std::vector<iris::PackedIrisCode> Database::deserialize_codes(
    const uint8_t* data, size_t len) {
    std::vector<iris::PackedIrisCode> codes;
    constexpr auto kSize = iris::TemplateSerializer::kBinarySize;
    for (size_t i = 0; i + kSize <= len; i += kSize) {
        auto result = iris::TemplateSerializer::from_binary({data + i, kSize});
        if (result) codes.push_back(std::move(*result));
    }
    return codes;
}

// --- Load all templates ---

std::vector<DbTemplate> Database::load_all_templates() {
    std::vector<DbTemplate> out;
    if (!is_connected()) return out;

    const char* sql =
        "SELECT t.template_id, t.identity_id, i.name, t.eye_side, "
        "       t.iris_codes, t.mask_codes "
        "FROM templates t JOIN identities i ON t.identity_id = i.identity_id";

    // Use text result format (0) so text columns are returned properly
    auto* res = PQexecParams(conn_.get(), sql, 0, nullptr, nullptr, nullptr, nullptr, 0);
    if (PQresultStatus(res) != PGRES_TUPLES_OK) {
        std::cerr << "[db] load_all_templates failed: " << PQresultErrorMessage(res)
                  << std::endl;
        PQclear(res);
        return out;
    }

    int n = PQntuples(res);
    for (int row = 0; row < n; ++row) {
        DbTemplate dt;
        dt.template_id = PQgetvalue(res, row, 0);
        dt.identity_id = PQgetvalue(res, row, 1);
        dt.identity_name = PQgetvalue(res, row, 2) ? PQgetvalue(res, row, 2) : "";
        dt.eye_side = PQgetvalue(res, row, 3);

        // BYTEA in text format: use PQunescapeBytea to decode
        size_t iris_len = 0;
        auto* iris_data = PQunescapeBytea(
            reinterpret_cast<const unsigned char*>(PQgetvalue(res, row, 4)), &iris_len);
        size_t mask_len = 0;
        auto* mask_data = PQunescapeBytea(
            reinterpret_cast<const unsigned char*>(PQgetvalue(res, row, 5)), &mask_len);

        dt.tmpl.iris_codes = deserialize_codes(iris_data, iris_len);
        dt.tmpl.mask_codes = deserialize_codes(mask_data, mask_len);
        dt.tmpl.iris_code_version = "v2.0";

        PQfreemem(iris_data);
        PQfreemem(mask_data);

        out.push_back(std::move(dt));
    }

    PQclear(res);
    std::cout << "[db] Loaded " << out.size() << " templates from database" << std::endl;
    return out;
}

// --- Load single template ---

std::optional<Database::TemplateRow> Database::load_template(
    const std::string& template_id) {
    if (!is_connected()) return std::nullopt;

    const char* sql =
        "SELECT t.template_id, t.identity_id, i.name, t.eye_side, "
        "       t.width, t.height, t.n_scales, t.quality_score, t.device_id, "
        "       t.iris_codes, t.mask_codes "
        "FROM templates t JOIN identities i ON t.identity_id = i.identity_id "
        "WHERE t.template_id = $1";

    const char* params[] = {template_id.c_str()};
    int param_formats[] = {0};
    auto* res = PQexecParams(conn_.get(), sql, 1, nullptr, params,
                             nullptr, param_formats, 0);
    if (PQresultStatus(res) != PGRES_TUPLES_OK || PQntuples(res) == 0) {
        PQclear(res);
        return std::nullopt;
    }

    TemplateRow row;
    row.template_id = PQgetvalue(res, 0, 0);
    row.identity_id = PQgetvalue(res, 0, 1);
    row.identity_name = PQgetvalue(res, 0, 2) ? PQgetvalue(res, 0, 2) : "";
    row.eye_side = PQgetvalue(res, 0, 3);
    row.width = std::atoi(PQgetvalue(res, 0, 4));
    row.height = std::atoi(PQgetvalue(res, 0, 5));
    row.n_scales = std::atoi(PQgetvalue(res, 0, 6));
    row.quality_score = std::atof(PQgetvalue(res, 0, 7));
    row.device_id = PQgetvalue(res, 0, 8) ? PQgetvalue(res, 0, 8) : "";

    // BYTEA in text format comes as hex-escaped; use PQunescapeBytea to decode
    // Check for NULL values before unescaping
    size_t iris_len = 0;
    unsigned char* iris_data = nullptr;
    if (!PQgetisnull(res, 0, 9)) {
        iris_data = PQunescapeBytea(
            reinterpret_cast<const unsigned char*>(PQgetvalue(res, 0, 9)), &iris_len);
    }

    size_t mask_len = 0;
    unsigned char* mask_data = nullptr;
    if (!PQgetisnull(res, 0, 10)) {
        mask_data = PQunescapeBytea(
            reinterpret_cast<const unsigned char*>(PQgetvalue(res, 0, 10)), &mask_len);
    }

    // Only deserialize if data is not NULL
    if (iris_data && iris_len > 0) {
        row.tmpl.iris_codes = deserialize_codes(iris_data, iris_len);
    }
    if (mask_data && mask_len > 0) {
        row.tmpl.mask_codes = deserialize_codes(mask_data, mask_len);
    }
    row.tmpl.iris_code_version = "v2.0";

    // Template is encrypted if iris_codes deserialized to empty (encrypted format uses different structure)
    // When allow_plaintext=true, templates are stored as plaintext and iris_codes will have data
    row.is_encrypted = row.tmpl.iris_codes.empty() && iris_len > 4;

    if (iris_data) PQfreemem(iris_data);
    if (mask_data) PQfreemem(mask_data);
    PQclear(res);
    return row;
}

// --- Ensure identity exists ---

bool Database::ensure_identity(const std::string& identity_id,
                               const std::string& name) {
    if (!is_connected()) return false;

    const char* sql =
        "INSERT INTO identities (identity_id, name) VALUES ($1, $2) "
        "ON CONFLICT (identity_id) DO UPDATE SET name = EXCLUDED.name";

    const char* params[] = {identity_id.c_str(), name.c_str()};
    auto* res = PQexecParams(conn_.get(), sql, 2, nullptr, params, nullptr, nullptr, 0);
    bool ok = PQresultStatus(res) == PGRES_COMMAND_OK;
    if (!ok) {
        std::cerr << "[db] ensure_identity failed: " << PQresultErrorMessage(res)
                  << std::endl;
    }
    PQclear(res);
    return ok;
}

// --- Persist template ---

bool Database::persist_template(const std::string& template_id,
                                const std::string& identity_id,
                                const std::string& eye_side,
                                const iris::IrisTemplate& tmpl,
                                const std::string& device_id) {
    if (!is_connected()) return false;

    auto iris_bin = serialize_codes(tmpl.iris_codes);
    auto mask_bin = serialize_codes(tmpl.mask_codes);

    int width = 512;   // PackedIrisCode: 256 cols × 2 channels
    int height = 16;   // PackedIrisCode: 16 rows
    int n_scales = static_cast<int>(tmpl.iris_codes.size());

    auto w_str = std::to_string(width);
    auto h_str = std::to_string(height);
    auto ns_str = std::to_string(n_scales);
    auto q_str = std::to_string(0.0);

    const char* sql =
        "INSERT INTO templates "
        "(template_id, identity_id, eye_side, iris_codes, mask_codes, "
        " width, height, n_scales, quality_score, device_id) "
        "VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)";

    const char* params[] = {
        template_id.c_str(), identity_id.c_str(), eye_side.c_str(),
        reinterpret_cast<const char*>(iris_bin.data()),
        reinterpret_cast<const char*>(mask_bin.data()),
        w_str.c_str(), h_str.c_str(), ns_str.c_str(),
        q_str.c_str(), device_id.c_str()};

    int param_lengths[] = {0, 0, 0,
                           static_cast<int>(iris_bin.size()),
                           static_cast<int>(mask_bin.size()),
                           0, 0, 0, 0, 0};
    int param_formats[] = {0, 0, 0, 1, 1, 0, 0, 0, 0, 0};

    auto* res = PQexecParams(conn_.get(), sql, 10, nullptr, params,
                             param_lengths, param_formats, 0);
    bool ok = PQresultStatus(res) == PGRES_COMMAND_OK;
    if (!ok) {
        std::cerr << "[db] persist_template failed: " << PQresultErrorMessage(res)
                  << std::endl;
    }
    PQclear(res);
    return ok;
}

// --- Persist encrypted template ---

bool Database::persist_encrypted_template(const std::string& template_id,
                                          const std::string& identity_id,
                                          const std::string& eye_side,
                                          const std::vector<uint8_t>& iris_blob,
                                          const std::vector<uint8_t>& mask_blob,
                                          int n_scales,
                                          const std::string& device_id) {
    if (!is_connected()) return false;

    int width = 512;   // PackedIrisCode: 256 cols × 2 channels
    int height = 16;   // PackedIrisCode: 16 rows

    auto w_str = std::to_string(width);
    auto h_str = std::to_string(height);
    auto ns_str = std::to_string(n_scales);
    auto q_str = std::to_string(0.0);

    const char* sql =
        "INSERT INTO templates "
        "(template_id, identity_id, eye_side, iris_codes, mask_codes, "
        " width, height, n_scales, quality_score, device_id) "
        "VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)";

    const char* params[] = {
        template_id.c_str(), identity_id.c_str(), eye_side.c_str(),
        reinterpret_cast<const char*>(iris_blob.data()),
        reinterpret_cast<const char*>(mask_blob.data()),
        w_str.c_str(), h_str.c_str(), ns_str.c_str(),
        q_str.c_str(), device_id.c_str()};

    int param_lengths[] = {0, 0, 0,
                           static_cast<int>(iris_blob.size()),
                           static_cast<int>(mask_blob.size()),
                           0, 0, 0, 0, 0};
    int param_formats[] = {0, 0, 0, 1, 1, 0, 0, 0, 0, 0};

    auto* res = PQexecParams(conn_.get(), sql, 10, nullptr, params,
                             param_lengths, param_formats, 0);
    bool ok = PQresultStatus(res) == PGRES_COMMAND_OK;
    if (!ok) {
        std::cerr << "[db] persist_encrypted_template failed: "
                  << PQresultErrorMessage(res) << std::endl;
    }
    PQclear(res);
    return ok;
}

// --- Load all raw templates (for FHE mode) ---

std::vector<Database::RawTemplate> Database::load_all_raw_templates() {
    std::vector<RawTemplate> out;
    if (!is_connected()) return out;

    const char* sql =
        "SELECT t.template_id, t.identity_id, i.name, t.eye_side, "
        "       t.iris_codes, t.mask_codes, t.n_scales "
        "FROM templates t JOIN identities i ON t.identity_id = i.identity_id";

    auto* res = PQexecParams(conn_.get(), sql, 0, nullptr, nullptr,
                             nullptr, nullptr, 0);
    if (PQresultStatus(res) != PGRES_TUPLES_OK) {
        std::cerr << "[db] load_all_raw_templates failed: "
                  << PQresultErrorMessage(res) << std::endl;
        PQclear(res);
        return out;
    }

    int n = PQntuples(res);
    for (int row = 0; row < n; ++row) {
        RawTemplate rt;
        rt.template_id = PQgetvalue(res, row, 0);
        rt.identity_id = PQgetvalue(res, row, 1);
        rt.identity_name = PQgetvalue(res, row, 2) ? PQgetvalue(res, row, 2) : "";
        rt.eye_side = PQgetvalue(res, row, 3);

        size_t iris_len = 0;
        auto* iris_data = PQunescapeBytea(
            reinterpret_cast<const unsigned char*>(PQgetvalue(res, row, 4)), &iris_len);
        size_t mask_len = 0;
        auto* mask_data = PQunescapeBytea(
            reinterpret_cast<const unsigned char*>(PQgetvalue(res, row, 5)), &mask_len);

        rt.iris_blob.assign(iris_data, iris_data + iris_len);
        rt.mask_blob.assign(mask_data, mask_data + mask_len);
        rt.n_scales = std::atoi(PQgetvalue(res, row, 6));

        PQfreemem(iris_data);
        PQfreemem(mask_data);

        out.push_back(std::move(rt));
    }

    PQclear(res);
    std::cout << "[db] Loaded " << out.size() << " raw templates from database"
              << std::endl;
    return out;
}

// --- Delete identity ---

int Database::delete_identity(const std::string& identity_id) {
    if (!is_connected()) return 0;

    // Delete identity (cascades to templates); return affected template count
    const char* sql =
        "WITH deleted AS (DELETE FROM templates WHERE identity_id = $1 RETURNING 1) "
        "SELECT COUNT(*) FROM deleted";
    const char* params[] = {identity_id.c_str()};
    auto* res = PQexecParams(conn_.get(), sql, 1, nullptr, params,
                             nullptr, nullptr, 0);
    int count = 0;
    if (PQresultStatus(res) == PGRES_TUPLES_OK && PQntuples(res) > 0) {
        count = std::atoi(PQgetvalue(res, 0, 0));
    }
    PQclear(res);

    // Delete the identity row itself
    const char* del_sql = "DELETE FROM identities WHERE identity_id = $1";
    res = PQexecParams(conn_.get(), del_sql, 1, nullptr, params,
                       nullptr, nullptr, 0);
    PQclear(res);

    return count;
}

// --- Log match ---

void Database::log_match(const std::string& frame_id,
                         const std::string& matched_template_id,
                         const std::string& matched_identity_id,
                         double hamming_distance,
                         bool is_match,
                         const std::string& device_id,
                         int latency_ms) {
    if (!is_connected()) return;

    const char* sql =
        "INSERT INTO match_log "
        "(probe_frame_id, matched_template_id, matched_identity_id, "
        " hamming_distance, is_match, device_id, latency_ms) "
        "VALUES ($1, $2, $3, $4, $5, $6, $7)";

    auto hd_str = std::to_string(hamming_distance);
    auto match_str = is_match ? std::string("true") : std::string("false");
    auto lat_str = std::to_string(latency_ms);

    // Use NULL for template/identity IDs when no match
    const char* tid = matched_template_id.empty() ? nullptr : matched_template_id.c_str();
    const char* iid = matched_identity_id.empty() ? nullptr : matched_identity_id.c_str();

    const char* params[] = {
        frame_id.c_str(), tid, iid,
        hd_str.c_str(), match_str.c_str(),
        device_id.c_str(), lat_str.c_str()};

    auto* res = PQexecParams(conn_.get(), sql, 7, nullptr, params,
                             nullptr, nullptr, 0);
    if (PQresultStatus(res) != PGRES_COMMAND_OK) {
        std::cerr << "[db] log_match failed: " << PQresultErrorMessage(res)
                  << std::endl;
    }
    PQclear(res);
}
