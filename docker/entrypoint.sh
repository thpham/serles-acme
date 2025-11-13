#!/bin/bash
set -e

# Serles ACME Server - Docker Entrypoint Script
# Handles configuration, database initialization, and startup

echo "=========================================="
echo "Serles ACME Server - Starting up"
echo "=========================================="

# ============================================================================
# Configuration Management
# ============================================================================

# Function to substitute environment variables in template
substitute_env_vars() {
	local template_file="$1"
	local output_file="$2"

	echo "Processing configuration template..."

	# Use envsubst-like behavior with bash parameter expansion
	# This supports ${VAR:-default} syntax
	eval "cat <<EOF
$(cat "$template_file")
EOF
" >"$output_file"

	echo "Configuration generated at: $output_file"
}

# Determine config file location
CONFIG_FILE="${CONFIG:-/etc/serles/config.ini}"
CONFIG_TEMPLATE="/etc/serles/config.ini.template"

# If config file doesn't exist, create it from template
if [ ! -f "$CONFIG_FILE" ]; then
	echo "Config file not found, creating from template..."

	if [ -f "$CONFIG_TEMPLATE" ]; then
		# Auto-detect development mode (SQLite without explicit backend)
		if [[ -z "${BACKEND:-}" ]] && [[ "${DATABASE_URL:-}" == sqlite://* || -z "${DATABASE_URL:-}" ]]; then
			echo "Development mode detected (SQLite database)"
			echo "Defaulting to OpenSSL backend for local development"
			export BACKEND="serles.backends.openssl:Backend"
		fi

		substitute_env_vars "$CONFIG_TEMPLATE" "$CONFIG_FILE"
	else
		echo "ERROR: Neither config file nor template found!"
		echo "Please mount a config file at $CONFIG_FILE or provide environment variables"
		exit 1
	fi
else
	echo "Using existing config file: $CONFIG_FILE"
fi

# ============================================================================
# Database Connection Check
# ============================================================================

# Extract database URL from config (handle PostgreSQL)
DB_URL=$(grep -E "^database\s*=" "$CONFIG_FILE" | cut -d'=' -f2- | tr -d ' ')

# Check if using PostgreSQL
if [[ "$DB_URL" == postgresql://* ]] || [[ "$DB_URL" == postgres://* ]]; then
	echo "PostgreSQL database detected, waiting for connection..."

	# Parse connection details
	# Format: postgresql://user:password@host:port/database
	DB_HOST=$(echo "$DB_URL" | sed -E 's|.*@([^:/]+).*|\1|')
	DB_PORT=$(echo "$DB_URL" | sed -E 's|.*:([0-9]+)/.*|\1|')
	DB_PORT=${DB_PORT:-5432}

	echo "Waiting for PostgreSQL at ${DB_HOST}:${DB_PORT}..."

	# Wait for PostgreSQL to be ready (max 60 seconds)
	timeout=60
	counter=0
	until pg_isready -h "$DB_HOST" -p "$DB_PORT" 2>/dev/null || [ $counter -eq $timeout ]; do
		counter=$((counter + 1))
		echo "Waiting for PostgreSQL... ($counter/$timeout)"
		sleep 1
	done

	if [ $counter -eq $timeout ]; then
		echo "ERROR: PostgreSQL connection timeout after ${timeout}s"
		exit 1
	fi

	echo "PostgreSQL is ready!"
else
	echo "Using SQLite database: $DB_URL"
fi

# ============================================================================
# Database Initialization
# ============================================================================

echo "Initializing database schema..."

# Create a Python script to initialize the database
python3 <<EOF
import sys
from serles import create_app
from serles.models import db

try:
    app = create_app()
    with app.app_context():
        # Create all tables if they don't exist
        db.create_all()
        print("Database schema initialized successfully")
except Exception as e:
    import traceback
    print(f"ERROR: Database initialization failed: {e}", file=sys.stderr)
    traceback.print_exc(file=sys.stderr)
    sys.exit(1)
EOF

if [ $? -ne 0 ]; then
	echo "ERROR: Database initialization failed"
	exit 1
fi

# ============================================================================
# Validation
# ============================================================================

echo "Validating configuration..."

# Check if backend is specified
if ! grep -q "^backend\s*=" "$CONFIG_FILE"; then
	echo "ERROR: No backend specified in configuration"
	exit 1
fi

# Check EJBCA client certificate if using EJBCA backend
if grep -q "serles.backends.ejbca" "$CONFIG_FILE"; then
	CLIENT_CERT=$(grep -E "^clientCertificate\s*=" "$CONFIG_FILE" | cut -d'=' -f2- | tr -d ' ')

	if [ ! -f "$CLIENT_CERT" ]; then
		echo "WARNING: EJBCA client certificate not found at: $CLIENT_CERT"
		echo "EJBCA authentication will fail. Mount certificate or use OpenSSL backend for testing."
	else
		echo "EJBCA client certificate found: $CLIENT_CERT"
	fi
fi

echo "Configuration validation complete"

# ============================================================================
# Startup
# ============================================================================

echo "=========================================="
echo "Starting Serles ACME Server..."
echo "Config: $CONFIG_FILE"
echo "Backend: $(grep -E '^backend\s*=' "$CONFIG_FILE" | cut -d'=' -f2-)"
echo "Database: $(echo "$DB_URL" | sed -E 's|(://[^:]+:)[^@]+|\1***|')"
echo "=========================================="

# Execute the command passed to the script
exec "$@"
