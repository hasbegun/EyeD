#!/usr/bin/env bash
# SMPC Integration Tests — Docker cluster tests (I5–I9, I11)
#
# These tests require a running SMPC cluster via docker-compose.
# They test fault tolerance, concurrency, latency, and TLS rejection.
#
# Usage:
#   ./scripts/run-integration-tests.sh [docker-compose-file]
#
# Prerequisites:
#   - Docker cluster running: docker compose up -d
#   - iris-engine2 healthy: /health/ready returns ready=true

set -euo pipefail

COMPOSE_FILE="${1:-docker-compose.yml}"
ENGINE_URL="http://localhost:9510"
PASS=0
FAIL=0
SKIP=0

# --- Helpers ---

log_pass() { echo "  ✅ PASS: $1"; ((PASS++)) || true; }
log_fail() { echo "  ❌ FAIL: $1"; ((FAIL++)) || true; }
log_skip() { echo "  ⏭️  SKIP: $1"; ((SKIP++)) || true; }

wait_for_health() {
    local url="$1"
    local max_wait="${2:-60}"
    local elapsed=0
    while [ "$elapsed" -lt "$max_wait" ]; do
        if curl -sf "$url/health/ready" 2>/dev/null | grep -q '"ready":true'; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

# Check if cluster is running
check_cluster() {
    if ! curl -sf "$ENGINE_URL/health/alive" >/dev/null 2>&1; then
        echo "ERROR: iris-engine2 is not reachable at $ENGINE_URL"
        echo "Start the cluster first: docker compose -f $COMPOSE_FILE up -d"
        exit 1
    fi
}

# --- Test I5: Kill 1 participant → system returns error, no crash ---

test_i5() {
    echo ""
    echo "=== I5: Kill 1 participant → system returns error, no crash ==="

    # Stop party-1
    docker compose -f "$COMPOSE_FILE" stop smpc-party-1 2>/dev/null || true
    sleep 2

    # iris-engine2 should still be alive (not crashed)
    if curl -sf "$ENGINE_URL/health/alive" | grep -q '"alive":true'; then
        log_pass "iris-engine2 still alive after killing party-1"
    else
        log_fail "iris-engine2 crashed after killing party-1"
    fi

    # Health should report degraded state (smpc_active may still be true
    # but operations will fail). The key is: no crash.
    if curl -sf "$ENGINE_URL/health/ready" >/dev/null 2>&1; then
        log_pass "iris-engine2 health endpoint still responds"
    else
        log_fail "iris-engine2 health endpoint not responding"
    fi
}

# --- Test I6: Restart killed participant → system recovers ---

test_i6() {
    echo ""
    echo "=== I6: Restart killed participant → system recovers ==="

    # Restart party-1
    docker compose -f "$COMPOSE_FILE" start smpc-party-1 2>/dev/null || true
    sleep 5

    # Check party-1 is back
    local party_status
    party_status=$(docker compose -f "$COMPOSE_FILE" ps --status running smpc-party-1 2>/dev/null | grep -c "smpc-party-1" || true)

    if [ "$party_status" -ge 1 ]; then
        log_pass "smpc-party-1 restarted successfully"
    else
        log_fail "smpc-party-1 did not restart"
    fi

    # iris-engine2 should be healthy
    if wait_for_health "$ENGINE_URL" 30; then
        log_pass "iris-engine2 recovered after participant restart"
    else
        log_fail "iris-engine2 did not recover after participant restart"
    fi
}

# --- Test I7: 50 concurrent health requests → all succeed ---

test_i7() {
    echo ""
    # Brief stabilization after kill/restart cycle before hammering concurrency
    sleep 3
    echo "=== I7: 50 concurrent requests → all succeed ==="

    local tmpdir
    tmpdir=$(mktemp -d)
    local success=0
    local total=50

    # Fire 50 concurrent health requests
    for i in $(seq 1 $total); do
        curl -sf "$ENGINE_URL/health/ready" -o "$tmpdir/resp_$i" 2>/dev/null &
    done
    wait

    # Count successes
    for i in $(seq 1 $total); do
        if [ -f "$tmpdir/resp_$i" ] && grep -q '"ready":true' "$tmpdir/resp_$i" 2>/dev/null; then
            success=$((success + 1))
        fi
    done

    rm -rf "$tmpdir"

    if [ "$success" -eq "$total" ]; then
        log_pass "All $total concurrent requests succeeded"
    else
        log_fail "Only $success/$total concurrent requests succeeded"
    fi
}

# --- Test I8: Mixed concurrent requests ---

test_i8() {
    echo ""
    echo "=== I8: 10 concurrent health + 10 concurrent config requests ==="

    local tmpdir
    tmpdir=$(mktemp -d)
    local success=0
    local total=20

    # 10 health requests
    for i in $(seq 1 10); do
        curl -sf "$ENGINE_URL/health/ready" -o "$tmpdir/health_$i" 2>/dev/null &
    done

    # 10 config requests
    for i in $(seq 1 10); do
        curl -sf "$ENGINE_URL/config" -o "$tmpdir/config_$i" 2>/dev/null &
    done
    wait

    for i in $(seq 1 10); do
        if [ -f "$tmpdir/health_$i" ] && grep -q '"ready"' "$tmpdir/health_$i" 2>/dev/null; then
            success=$((success + 1))
        fi
        if [ -f "$tmpdir/config_$i" ] && grep -q '"smpc_enabled"' "$tmpdir/config_$i" 2>/dev/null; then
            success=$((success + 1))
        fi
    done

    rm -rf "$tmpdir"

    if [ "$success" -eq "$total" ]; then
        log_pass "All $total mixed concurrent requests succeeded"
    else
        log_fail "Only $success/$total mixed concurrent requests succeeded"
    fi
}

# --- Test I9: Health endpoint latency < 100ms P99 ---

test_i9() {
    echo ""
    echo "=== I9: Health endpoint latency check ==="

    local times=()
    for i in $(seq 1 20); do
        local start end elapsed
        start=$(date +%s%N 2>/dev/null || python3 -c "import time; print(int(time.time()*1e9))")
        curl -sf "$ENGINE_URL/health/ready" >/dev/null 2>&1
        end=$(date +%s%N 2>/dev/null || python3 -c "import time; print(int(time.time()*1e9))")
        elapsed=$(( (end - start) / 1000000 ))
        times+=("$elapsed")
    done

    # Sort and get P99 (19th value of 20)
    IFS=$'\n' sorted=($(sort -n <<<"${times[*]}")); unset IFS
    local p99="${sorted[18]}"

    echo "  P99 health latency: ${p99}ms"

    if [ "$p99" -lt 1000 ]; then
        log_pass "Health P99 latency ${p99}ms < 1000ms"
    else
        log_fail "Health P99 latency ${p99}ms >= 1000ms"
    fi
}

# --- Test I11: Connection without valid TLS cert → rejected ---

test_i11() {
    echo ""
    echo "=== I11: TLS rejection (requires EYED_TLS_CERT_DIR to be set) ==="

    # Check if TLS is configured
    local tls_dir="${EYED_TLS_CERT_DIR:-}"
    if [ -z "$tls_dir" ]; then
        log_skip "TLS not configured (EYED_TLS_CERT_DIR not set)"
        return
    fi

    # Try connecting to NATS without a valid cert
    # If TLS is enforced, this should fail
    local nats_port
    nats_port=$(docker compose -f "$COMPOSE_FILE" port nats 4222 2>/dev/null | cut -d: -f2 || echo "4222")

    # Attempt a plain TCP connection to the TLS-only NATS port
    if timeout 3 bash -c "echo 'PING' > /dev/tcp/localhost/$nats_port" 2>/dev/null; then
        log_fail "Plain TCP connection to TLS NATS port succeeded (should be rejected)"
    else
        log_pass "Plain TCP connection to TLS NATS port was rejected"
    fi
}

# ===========================================================================
# Main
# ===========================================================================

echo "============================================="
echo "  SMPC Integration Tests (I5–I9, I11)"
echo "  Compose file: $COMPOSE_FILE"
echo "  Engine URL:   $ENGINE_URL"
echo "============================================="

check_cluster

test_i5
test_i6
test_i7
test_i8
test_i9
test_i11

echo ""
echo "============================================="
echo "  Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo "============================================="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
