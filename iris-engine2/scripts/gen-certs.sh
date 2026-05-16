#!/usr/bin/env bash
# Generate mTLS certificates for SMPC cluster.
#
# Creates:
#   certs/ca.crt, certs/ca.key             — Certificate Authority
#   certs/coordinator.crt, coordinator.key  — iris-engine2 (coordinator)
#   certs/nats-server.crt, nats-server.key  — NATS server
#   certs/party-1.crt … party-N.crt        — SMPC participant certs
#
# Usage: ./scripts/gen-certs.sh [output_dir] [party_prefix]
#   output_dir   — defaults to ./certs
#   party_prefix — Docker service name prefix (default: smpc-party)
#                  e.g. "smpc2-party" for SMPC2 services
#
# Environment:
#   SMPC_PARTIES — number of party certs to generate (default: 5)

set -euo pipefail

OUTDIR="${1:-./certs}"
PARTY_PREFIX="${2:-smpc-party}"
NUM_PARTIES="${SMPC_PARTIES:-5}"
DAYS_CA=3650
DAYS_CERT=365
KEY_BITS=4096

TOTAL_STEPS=$((NUM_PARTIES + 3))  # CA + coordinator + NATS + N parties

mkdir -p "$OUTDIR"

echo "=== Generating SMPC mTLS certificates in $OUTDIR ==="
echo "    Parties: $NUM_PARTIES (prefix: $PARTY_PREFIX)"

# --- CA ---
STEP=1
echo "[$STEP/$TOTAL_STEPS] Generating CA..."
openssl req -x509 -newkey "rsa:$KEY_BITS" -nodes \
    -keyout "$OUTDIR/ca.key" \
    -out "$OUTDIR/ca.crt" \
    -days "$DAYS_CA" \
    -subj "/CN=eyed-smpc-ca/O=EyeD/OU=SMPC" \
    2>/dev/null

generate_cert() {
    local name="$1"
    local cn="$2"
    local san="$3"

    echo "  Generating $name (CN=$cn)..."

    # Generate key + CSR
    openssl req -newkey "rsa:$KEY_BITS" -nodes \
        -keyout "$OUTDIR/$name.key" \
        -out "$OUTDIR/$name.csr" \
        -subj "/CN=$cn/O=EyeD/OU=SMPC" \
        2>/dev/null

    # Sign with CA (with SAN extension)
    openssl x509 -req \
        -in "$OUTDIR/$name.csr" \
        -CA "$OUTDIR/ca.crt" \
        -CAkey "$OUTDIR/ca.key" \
        -CAcreateserial \
        -out "$OUTDIR/$name.crt" \
        -days "$DAYS_CERT" \
        -extfile <(printf "subjectAltName=%s\nextendedKeyUsage=serverAuth,clientAuth" "$san") \
        2>/dev/null

    # Remove CSR (not needed at runtime)
    rm -f "$OUTDIR/$name.csr"
}

# --- Service certificates ---
STEP=$((STEP + 1))
echo "[$STEP/$TOTAL_STEPS] Generating coordinator certificate..."
generate_cert "coordinator" "iris-engine2" "DNS:iris-engine2,DNS:localhost,IP:127.0.0.1"

STEP=$((STEP + 1))
echo "[$STEP/$TOTAL_STEPS] Generating NATS server certificate..."
generate_cert "nats-server" "nats" "DNS:nats,DNS:localhost,IP:127.0.0.1"

# --- Party certificates ---
# SANs include both smpc-party-N and smpc2-party-N so one cert works for both services
for i in $(seq 1 "$NUM_PARTIES"); do
    STEP=$((STEP + 1))
    echo "[$STEP/$TOTAL_STEPS] Generating party-$i certificate..."
    generate_cert "party-$i" "${PARTY_PREFIX}-${i}" \
        "DNS:smpc-party-${i},DNS:smpc2-party-${i},DNS:localhost,IP:127.0.0.1"
done

# Clean up serial file
rm -f "$OUTDIR/ca.srl"

# Restrict key permissions
chmod 600 "$OUTDIR"/*.key
chmod 644 "$OUTDIR"/*.crt

echo ""
echo "=== Done. Certificates generated in $OUTDIR ==="
echo "  CA:          $OUTDIR/ca.crt"
echo "  Coordinator: $OUTDIR/coordinator.crt + .key"
echo "  NATS:        $OUTDIR/nats-server.crt + .key"
for i in $(seq 1 "$NUM_PARTIES"); do
    echo "  Party $i:     $OUTDIR/party-$i.crt + .key"
done
