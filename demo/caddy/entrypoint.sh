#!/bin/sh
#
# Caddy Demo Entrypoint with ACME Proxy Workaround
#
# This script runs ncat in the background to proxy localhost:4000 -> serles-acme:8080
# This allows Caddy to use HTTP ACME (Caddy only allows HTTP for localhost/127.0.0.1)
#
# Reference: https://github.com/caddyserver/caddy/issues/1592
#

set -e

echo "Starting ACME proxy workaround..."

# Install ncat (nmap-ncat package in Alpine)
apk add --no-cache nmap-ncat >/dev/null 2>&1

# Start ncat proxy in background (localhost:4000 -> serles-acme:8080)
# This makes Serles ACME appear as localhost to Caddy
ncat -lk -p 4000 -c 'ncat serles-acme 8080' &
PROXY_PID=$!

echo "ACME proxy started (PID: $PROXY_PID)"
echo "Forwarding localhost:4000 -> serles-acme:8080"

# Wait a moment for proxy to be ready
sleep 2

# Test proxy connectivity
if nc -z 127.0.0.1 4000 2>/dev/null; then
	echo "ACME proxy is ready"
else
	echo "WARNING: ACME proxy may not be ready"
fi

# Start Caddy (this will block and run as PID 1 replacement)
echo "Starting Caddy..."
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
