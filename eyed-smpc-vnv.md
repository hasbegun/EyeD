---
# EyeD SMPC Verification & Validation Plan

Version: 1.0
Owners: Platform & Security Engineering
Status: Approved
---

## 1. Objectives
- Verify the functional correctness of the SMPC implementation (simulated and distributed modes).
- Validate security properties: transport (mTLS), auditability, data-leakage resistance, and operational monitoring.
- Validate fault tolerance, concurrency, and latency SLAs.
- Verify migration from plaintext templates to SMPC shares and rollback behavior.
- Provide clear, reproducible, and visual procedures for verification in Dev, CI, and Docker Compose E2E.

## 2. Scope
- Components: iris-engine2 (C++), SMPC Coordinator/Participants, NATS bus, libiris SMPC.
- Interfaces verified:
  - HTTP: /health/*, /config, /enroll, /analyze/json, /gallery/*
  - NATS (internal, via libiris NATSSMPCBus)
  - Files: Audit log path; TLS certs directory

## 3. Environments & Modes
- Dev: SMPC simulated mode (fast, no NATS). CI default for unit/integration.
- E2E: SMPC distributed mode via Docker Compose (NATS + 3 participants).
- TLS: Optional mTLS for NATS (off by default; must be enabled for security validation).

## 4. Prerequisites
- Docker and docker compose
- Scripts and tests from repo:
  - iris-engine2/scripts/gen-certs.sh
  - iris-engine2/scripts/run-integration-tests.sh
  - CTest targets (unit, integration, migration)
- Ports:
  - Iris-engine2 on host:9510
  - NATS: host:9502 (4222), host:9501 (monitor)

## 5. Verification Matrix (What & How)
- Correctness — enrollment, verification, HD equality (SMPC vs plaintext)
  - How: `tests/test_smpc_integration` (I1, I2, I4) + `tests/test_smpc`
- Security — TLS, audit logs, leakage resistance, monitoring
  - How: `tests/test_smpc_security`, `scripts/run-integration-tests.sh` (I11), manual audit log check, share security test (I10)
- Fault tolerance — participant failures & recovery
  - How: `scripts/run-integration-tests.sh` (I5, I6)
- Concurrency & performance — 50 concurrent; P99 latency
  - How: `scripts/run-integration-tests.sh` (I7–I9)
- Migration & rollback — re-split on startup; plaintext fallback
  - How: `tests/test_migration`, `EYED_SMPC_FALLBACK_PLAINTEXT`

## 6. Procedures

### A) CI / Quick Verification (simulated mode)
1) Build test image and run CTest
   - make smpc-unit-test
     (equivalent: docker build --target test -t iris-engine2-test ./iris-engine2
                  docker run --rm iris-engine2-test ctest --test-dir /src/build --output-on-failure)
   - Expect: 100% pass (includes unit, security, integration, migration tests)

2) Spot-check a single suite
   - docker run --rm iris-engine2-test /src/build/tests/test_smpc_integration

### B) E2E Distributed Mode (Docker Compose)
1) Start cluster
   - make up
   - docker ps (check services; iris-engine2 should be healthy)

2) Visual readiness
   - curl -s http://localhost:9510/health/ready | jq
     - Expect: { "ready": true, "smpc_active": true, "nats_connected": true, "gallery_size": N }
   - curl -s http://localhost:9510/config | jq
     - Note: run with EYED_MODE=dev (or make up-dev) for full SMPC fields.
       In prod mode /config returns only gallery_size, db_connected, version.
     - Expect (dev/test): { "smpc_enabled": true, "smpc_mode": "distributed" }

3) Run distributed integration tests (faults, concurrency, latency, TLS rejection)
   - make smpc-integration
     (equivalent: ./iris-engine2/scripts/run-integration-tests.sh)
   - Expect: PASS summary with 0 FAIL, possible SKIP for TLS if not enabled

### C) Security Validation (mTLS, audit, leakage resistance)
1) Generate mTLS certs (once per workspace)
   - make smpc-gen-certs
   - Artifacts under iris-engine2/certs/

2) Enable TLS for all services via overlay
   - make down && make build && make up-tls
     (equivalent: docker compose -f docker-compose.yml -f docker-compose.tls.yml up -d)
   - docker-compose.tls.yml mounts iris-engine2/certs into all SMPC services,
     switches NATS to nats-server-tls.conf (verify: true), and sets TLS_CERT_DIR
     for all participants.

3) Visual TLS checks
   - scripts/run-integration-tests.sh will run I11 (TLS rejection test)
   - Manual negative test (no client cert):
     - openssl s_client -connect localhost:9502 -CAfile iris-engine2/certs/ca.crt
     - Expect: handshake failure if no client cert is provided

4) Audit log checks
   - Set EYED_AUDIT_LOG_PATH=/var/log/smpc_audit.log for iris-engine2
   - Tail logs during enroll/verify:
     - docker compose logs -f iris-engine2 | grep Audit  (or) docker exec ... tail /var/log/smpc_audit.log
   - Expect: structured entries for EnrollmentRequested/Completed, VerificationRequested/Completed

5) Leakage resistance (single-share cannot reconstruct)
   - Already covered by test I10 (test_smpc_integration)
   - Visual: run test executable and confirm PASS

6) Monitoring sanity
   - Security monitor enabled: EYED_SECURITY_MONITOR=true
   - Induce latency spike (temporary CPU load) and observe WARN/ALERT in logs

### D) Fault Tolerance & Recovery
1) Induce failure
   - docker compose stop smpc-party-1
   - curl http://localhost:9510/health/alive (should remain alive)
   - scripts/run-integration-tests.sh (I5): expect no crash; operations may error

2) Recovery
   - docker compose start smpc-party-1
   - wait until health/ready returns ready=true (script I6 validates this)

### E) Migration & Rollback
1) Migration
   - On startup with SMPC active, plaintext templates are re-enrolled via SMPCManager::migrate_templates()
   - Visual: iris-engine2 logs include
     - "[smpc] Migration complete: X/X templates in Y ms"

2) Rollback / Plaintext fallback
   - EYED_SMPC_FALLBACK_PLAINTEXT is wired in docker-compose.yml (defaults false)
   - To test: EYED_SMPC_FALLBACK_PLAINTEXT=true EYED_NATS_URL=nats://bad:9999 docker compose up -d iris-engine2
   - Expect: HTTP service stays up, /health/ready returns ready=true, smpc_active=false
   - Visual: /health/ready shows smpc_active=false; logs show "falling back to plaintext matching"

### F) Visual Verification Checklist
- Docker services healthy (docker ps) — iris-engine2, gateway, storage, nats, smpc-party-[1..3]
- /health/ready → ready=true, smpc_active=true, nats_connected=true (distributed) or smpc_active=false (fallback)
- make smpc-integration summary → PASS (0 FAIL)
- Audit log file contains expected events for enroll/verify
- TLS rejection test passes (no-cert connection rejected)
- Migration log prints "[smpc] Migration complete: N/N templates in Y ms"

## 7. Pass / Fail Criteria
- CI: 100% of unit/integration/migration/security tests pass (0 failures)
- E2E: run-integration-tests.sh returns exit 0 (I5–I9, I11)
- Security: TLS enabled → plain TCP connection to NATS rejected; audit log populated; share-security test passes
- Performance: P99 health latency < 1000ms under script load (I9)
- Fault tolerance: Killing/restarting one participant does not crash iris-engine2; recovery observed

## 8. Artifacts to Collect
- CTest report output (CI)
- run-integration-tests.sh summary (E2E)
- Audit log file (if enabled)
- Docker service logs for iris-engine2 and smpc-parties during tests
- Screenshot or saved JSON of /health/ready and /config responses (visual proof)

## 9. Troubleshooting
- CMake/Ninja failures in smpc-party images: ensure libpq-dev and ninja-build are installed (fixed in Dockerfile)
- TLS handshake issues: verify cert paths, SANs match service names; confirm NATS uses TLS config and verify=true
- High latency: verify resource limits; reduce parallel test load; check ONNX Runtime CPU features
- Participant offline: check NATS connectivity and subjects; restart smpc-party containers

## 10. Maintenance
- Re-run this plan on every major change to SMPC, NATS, or security features
- Update thresholds and scripts as production SLAs evolve
- Store artifacts in CI for 30 days for audit purposes
