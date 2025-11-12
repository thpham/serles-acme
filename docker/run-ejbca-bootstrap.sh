#!/bin/bash
#
# Helper script to run EJBCA bootstrap automation
# This script orchestrates the bootstrap process and handles P12 to PEM conversion
#
# Usage: ./docker/run-ejbca-bootstrap.sh
#

set -e

echo "=============================================="
echo "Running EJBCA Bootstrap Automation"
echo "=============================================="
echo ""

# Check if containers are running
if ! docker ps | grep -q serles-ejbca; then
	echo "ERROR: EJBCA container is not running"
	echo "Start the stack first: docker-compose up -d"
	exit 1
fi

# Check if openssl is available on host
if ! command -v openssl >/dev/null 2>&1; then
	echo "ERROR: openssl not found on host system"
	echo "Please install openssl: brew install openssl (macOS) or apt-get install openssl (Linux)"
	exit 1
fi

# Create certs directory if it doesn't exist
mkdir -p ./docker/certs

echo "Step 1: Executing bootstrap script in EJBCA container..."
echo ""

# Execute bootstrap script (generates P12 file)
if ! docker exec serles-ejbca bash /opt/ejbca-bootstrap.sh; then
	echo ""
	echo "ERROR: Bootstrap script failed"
	exit 1
fi

echo ""
echo "Step 2: Converting P12 to PEM using host's openssl..."
echo ""

# Copy P12 and password file from container
docker cp serles-ejbca:/mnt/persistent/client01.p12 ./docker/certs/client01.p12
docker cp serles-ejbca:/mnt/persistent/client01.pwd ./docker/certs/client01.pwd

# Read password
P12_PASSWORD=$(cat ./docker/certs/client01.pwd)

# Convert P12 to PEM format (private key + certificate)
openssl pkcs12 -in ./docker/certs/client01.p12 \
	-passin "pass:$P12_PASSWORD" \
	-out ./docker/certs/client01-privpub.pem \
	-nodes

# Set proper permissions
chmod 600 ./docker/certs/client01-privpub.pem
chmod 600 ./docker/certs/client01.pwd

# Clean up temporary P12 file
rm -f ./docker/certs/client01.p12

echo "✓ Certificate converted successfully: ./docker/certs/client01-privpub.pem"
echo ""
echo "Step 3: Restarting Serles container..."
echo ""

# Restart Serles to pick up the new certificate
docker-compose restart serles

echo ""
echo "=============================================="
echo "Bootstrap Complete!"
echo "=============================================="
echo ""
echo "✓ EJBCA CA and roles configured"
echo "✓ Client certificate generated and converted"
echo "✓ Certificate saved to: ./docker/certs/client01-privpub.pem"
echo "✓ Serles container restarted"
echo ""
echo "Verifying Serles startup..."
sleep 5
docker-compose logs --tail=20 serles
echo ""
