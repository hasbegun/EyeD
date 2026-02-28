-- EyeD Phase 5a: Core persistence schema
-- Loaded by PostgreSQL on first database creation via /docker-entrypoint-initdb.d/

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enrolled identities
CREATE TABLE identities (
    identity_id   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name          TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata      JSONB
);

-- Iris templates (one identity can have multiple enrollments, e.g. left + right eye)
CREATE TABLE templates (
    template_id   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    identity_id   UUID NOT NULL REFERENCES identities(identity_id) ON DELETE CASCADE,
    eye_side      TEXT NOT NULL CHECK (eye_side IN ('left', 'right')),
    iris_codes    BYTEA NOT NULL,       -- NPZ (plaintext/AES) or HEv1 (HE ciphertext) blob
    mask_codes    BYTEA NOT NULL,       -- NPZ (plaintext/AES) or HEv1 (HE ciphertext) blob
    width         INT NOT NULL,
    height        INT NOT NULL,
    n_scales      INT NOT NULL,
    quality_score REAL NOT NULL DEFAULT 0.0,
    device_id     TEXT,
    -- Popcount metadata for HE Hamming distance computation (NULL when not using HE)
    iris_popcount INT[],
    mask_popcount INT[],
    enrolled_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Match audit log (every comparison attempt, not just matches)
CREATE TABLE match_log (
    log_id              BIGSERIAL PRIMARY KEY,
    probe_frame_id      TEXT NOT NULL,
    matched_template_id UUID REFERENCES templates(template_id) ON DELETE SET NULL,
    matched_identity_id UUID REFERENCES identities(identity_id) ON DELETE SET NULL,
    hamming_distance    REAL NOT NULL,
    is_match            BOOLEAN NOT NULL,
    device_id           TEXT,
    latency_ms          INT,
    matched_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_templates_identity ON templates(identity_id, eye_side);
CREATE INDEX idx_match_log_time ON match_log(matched_at);
CREATE INDEX idx_match_log_identity ON match_log(matched_template_id);
