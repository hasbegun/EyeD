#!/usr/bin/env bash
# Generate mTLS certificates for SMPC cluster.
#
# Creates:
#   certs/ca.crt, certs/ca.key           — Certificate Authority
#   certs/coordinator.crt, coordinator.key — iris-engine2 (coordinator)
#   certs/party-1.crt, party-1.key        — SMPC participant 1
#   certs/party-2.crt, party-2.key        — SMPC participant 2
#   certs/party-3.crt, party-3.key        — SMPC participant 3
#   certs/nats-server.crt, nats-server.key — NATS server
#
# Usage: ./scripts/gen-certs.sh [output_dir]
#   output_dir defaults to ./certs

set -euo pipefail

OUTDIR="${1:-./certs}"
DAYS_CA=3650
DAYS_CERT=365
KEY_BITS=4096

mkdir -p "$OUTDIR"

echo "=== Generating SMPC mTLS certificates in $OUTDIR ==="

# --- CA ---
echo "[1/6] Generating CA..."
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
echo "[2/6] Generating coordinator certificate..."
generate_cert "coordinator" "iris-engine2" "DNS:iris-engine2,DNS:localhost,IP:127.0.0.1"

echo "[3/6] Generating NATS server certificate..."
generate_cert "nats-server" "nats" "DNS:nats,DNS:localhost,IP:127.0.0.1"

echo "[4/6] Generating party-1 certificate..."
generate_cert "party-1" "smpc-party-1" "DNS:smpc-party-1,DNS:localhost,IP:127.0.0.1"

echo "[5/6] Generating party-2 certificate..."
generate_cert "party-2" "smpc-party-2" "DNS:smpc-party-2,DNS:localhost,IP:127.0.0.1"

echo "[6/6] Generating party-3 certificate..."
generate_cert "party-3" "smpc-party-3" "DNS:smpc-party-3,DNS:localhost,IP:127.0.0.1"

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
echo "  Party 1:     $OUTDIR/party-1.crt + .key"
echo "  Party 2:     $OUTDIR/party-2.crt + .key"
echo "  Party 3:     $OUTDIR/party-3.crt + .key"
