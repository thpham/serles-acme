#!/bin/bash
#
# Generate self-signed TLS certificate for Serles ACME Server
# For development and testing purposes only
#
# Usage: ./docker/generate-tls-cert.sh [hostname]
#

set -e

HOSTNAME="${1:-localhost}"
CERT_DIR="./docker/certs"
KEY_FILE="$CERT_DIR/server.key"
CERT_FILE="$CERT_DIR/server.crt"
VALIDITY_DAYS=365

echo "=============================================="
echo "Generating Self-Signed TLS Certificate"
echo "=============================================="
echo ""
echo "Hostname: $HOSTNAME"
echo "Validity: $VALIDITY_DAYS days"
echo "Output:"
echo "  Key:  $KEY_FILE"
echo "  Cert: $CERT_FILE"
echo ""

# Create certs directory if it doesn't exist
mkdir -p "$CERT_DIR"

# Check if openssl is available
if ! command -v openssl >/dev/null 2>&1; then
	echo "ERROR: openssl not found"
	echo "Please install openssl: brew install openssl (macOS) or apt-get install openssl (Linux)"
	exit 1
fi

# Generate private key and self-signed certificate
openssl req -x509 -newkey rsa:2048 \
	-keyout "$KEY_FILE" \
	-out "$CERT_FILE" \
	-days "$VALIDITY_DAYS" \
	-nodes \
	-subj "/CN=$HOSTNAME/O=Serles ACME Development/C=US" \
	-addext "subjectAltName=DNS:$HOSTNAME,DNS:localhost,IP:127.0.0.1"

# Set proper permissions
chmod 600 "$KEY_FILE"
chmod 644 "$CERT_FILE"

echo ""
echo "✓ Certificate generated successfully"
echo ""
echo "Certificate details:"
openssl x509 -in "$CERT_FILE" -noout -subject -dates -ext subjectAltName
echo ""
echo "=============================================="
echo "Next Steps:"
echo "=============================================="
echo ""
echo "1. Enable TLS in docker-compose.yaml:"
echo "   Set TLS_ENABLED=true in environment section"
echo ""
echo "2. Restart Serles container:"
echo "   docker-compose restart serles"
echo ""
echo "3. Access ACME server via HTTPS:"
echo "   curl -k https://localhost:8443/directory"
echo ""
echo "Note: This is a self-signed certificate for development only."
echo "      Use --insecure/-k flag with curl or ACME clients."
echo ""
