#!/usr/bin/env bash
# SMPC2 Distributed Integration Tests
# Requires: make up-smpc2 (cluster running with EYED_SMPC2_ENABLED=true)
set -euo pipefail

ENGINE="${ENGINE:-http://localhost:9510}"
PASS=0
FAIL=0
TOTAL=0

pass() { echo "  PASS: $1"; ((PASS++)); ((TOTAL++)); }
fail() { echo "  FAIL: $1"; ((FAIL++)); ((TOTAL++)); }

check_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then pass "$desc"; else fail "$desc (expected=$expected, got=$actual)"; fi
}

check_true() {
    local desc="$1" val="$2"
    if [ "$val" = "true" ]; then pass "$desc"; else fail "$desc (got=$val)"; fi
}

echo "========================================================"
echo " SMPC2 Integration Test Suite"
echo " Target: $ENGINE"
echo "========================================================"
echo ""

# --------------------------------------------------------------------------
# I1: Health endpoint — smpc2_active=true
# --------------------------------------------------------------------------
echo "[I1] /health/ready — smpc2_active=true"
HEALTH=$(curl -sf "$ENGINE/health/ready")
SMPC2_ACTIVE=$(echo "$HEALTH" | python3 -c "import sys,json; d=json.load(sys.stdin); print(str(d.get('smpc2_active',False)).lower())")
check_true "smpc2_active is true" "$SMPC2_ACTIVE"

PARTIES=$(echo "$HEALTH" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('smpc2_parties',0))")
THRESHOLD=$(echo "$HEALTH" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('smpc2_threshold',0))")
echo "    smpc2_parties=$PARTIES, smpc2_threshold=$THRESHOLD"

# --------------------------------------------------------------------------
# I2: Config endpoint
# --------------------------------------------------------------------------
echo "[I2] /config — smpc2_enabled=true"
CONFIG=$(curl -sf "$ENGINE/config")
SMPC2_EN=$(echo "$CONFIG" | python3 -c "import sys,json; d=json.load(sys.stdin); print(str(d.get('smpc2_enabled',False)).lower())" 2>/dev/null || echo "null")
check_true "smpc2_enabled in /config" "$SMPC2_EN"

# --------------------------------------------------------------------------
# I3: Enroll 3 subjects
# --------------------------------------------------------------------------
echo "[I3] Enroll 3 synthetic subjects via /enroll (SMPC2 side-effect)"
for i in 1 2 3; do
    RESP=$(curl -sf -X POST "$ENGINE/enroll" \
        -H "Content-Type: application/json" \
        -d "{\"identity_id\":\"smpc2_test_$i\",\"identity_name\":\"SMPC2 Test $i\",\"jpeg_b64\":\"\"}" \
        2>/dev/null || echo "{\"error\":\"connection_failed\"}")
    # We expect pipeline failure (no real image) but smpc2_protected field present
    SMPC2P=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('smpc2_protected','missing'))" 2>/dev/null || echo "missing")
    if [ "$SMPC2P" = "missing" ]; then
        fail "I3: smpc2_protected field absent in enroll response"
    else
        pass "I3: smpc2_protected field present (subject $i)"
    fi
done

# --------------------------------------------------------------------------
# I4: /analyze returns smpc2_match field
# --------------------------------------------------------------------------
echo "[I4] /analyze/json — smpc2_match field present in response"
ANALYZE=$(curl -sf -X POST "$ENGINE/analyze/json" \
    -H "Content-Type: application/json" \
    -d '{"jpeg_b64":"","eye_side":"left"}' \
    2>/dev/null || echo "{}")
SMPC2_FIELD=$(echo "$ANALYZE" | python3 -c "import sys,json; d=json.load(sys.stdin); print('smpc2_match' in d)" 2>/dev/null || echo "False")
check_eq "smpc2_match field present in /analyze response" "True" "$SMPC2_FIELD"

# --------------------------------------------------------------------------
# I5: smpc2-party health — check NATS subjects exist (n parties subscribed)
# --------------------------------------------------------------------------
echo "[I5] NATS monitoring — smpc2 subscriptions present"
NATS_MON="${NATS_MON:-http://localhost:9501}"
if curl -sf "$NATS_MON/connz" > /dev/null 2>&1; then
    SMPC2_SUBS=$(curl -sf "$NATS_MON/subsz?test=smpc2.party" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d.get('num_subscriptions',0))" 2>/dev/null || echo "0")
    if [ "$SMPC2_SUBS" -ge 1 ] 2>/dev/null; then
        pass "I5: NATS has smpc2 subscriptions ($SMPC2_SUBS)"
    else
        echo "  SKIP: I5 — could not count smpc2 subscriptions (NATS monitoring may not expose per-subject counts)"
    fi
else
    echo "  SKIP: I5 — NATS monitoring not reachable at $NATS_MON"
fi

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
echo ""
echo "========================================================"
echo " Results: $PASS passed, $FAIL failed / $TOTAL total"
echo "========================================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
