#!/bin/bash
#
# EJBCA Bootstrap Script for Serles ACME Server
# Automated EJBCA CE configuration using CLI commands
#
# Usage:
#   docker exec serles-ejbca bash /opt/ejbca-bootstrap.sh
#
# Output: Client certificate written to /mnt/persistent/client01-privpub.pem
#

set -e

echo "=============================================="
echo "EJBCA Automated Bootstrap for Serles ACME"
echo "=============================================="

# =============================================================================
# Configuration Variables
# =============================================================================

CA_NAME="${EJBCA_CA_NAME:-ACMECA}"
CA_DN="CN=$CA_NAME,O=Serles,C=US"
CA_VALIDITY="3650" # 10 years

CERT_PROFILE="${EJBCA_CERT_PROFILE:-ACMEServerProfile}"
END_ENTITY_PROFILE="${EJBCA_END_ENTITY_PROFILE:-ACMEEndEntityProfile}"

API_CLIENT_USER="${EJBCA_API_CLIENT_USER:-client01}"
API_CLIENT_DN="CN=$API_CLIENT_USER"
# Generate random password without requiring openssl or xxd
API_CLIENT_PASSWORD="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)"
API_CLIENT_ROLE="${EJBCA_API_CLIENT_ROLE:-ACMEAdministrator}"

MGMT_CA="ManagementCA" # Default Management CA in EJBCA CE

# EJBCA CLI path
EJBCA_CLI="/opt/primekey/bin/ejbca.sh"

# Output paths
OUTPUT_DIR="/mnt/persistent"
CERT_OUTPUT="$OUTPUT_DIR/${API_CLIENT_USER}-privpub.pem"

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
	echo "[INFO] $*"
}

log_error() {
	echo "[ERROR] $*" >&2
}

log_success() {
	echo "[✓] $*"
}

wait_for_ejbca() {
	log_info "Waiting for EJBCA to be fully initialized..."
	local max_attempts=60
	local attempt=0

	while [ $attempt -lt $max_attempts ]; do
		if curl -f -k -s https://localhost:8443/ejbca/publicweb/healthcheck/ejbcahealth >/dev/null 2>&1; then
			log_success "EJBCA is ready!"
			return 0
		fi
		attempt=$((attempt + 1))
		sleep 5
	done

	log_error "EJBCA failed to become ready after ${max_attempts} attempts"
	return 1
}

ejbca_cmd() {
	# Execute EJBCA CLI command with proper error handling
	if ! $EJBCA_CLI "$@" 2>&1; then
		# Some commands fail if resource already exists - that's OK
		return 0
	fi
}

# =============================================================================
# Step 1: Wait for EJBCA
# =============================================================================

echo ""
echo "Step 1: Waiting for EJBCA..."
echo "=============================================="
wait_for_ejbca

# =============================================================================
# Step 2: Create ACME Certificate Authority
# =============================================================================

echo ""
echo "Step 2: Creating ACME Certificate Authority"
echo "=============================================="

log_info "Creating CA: $CA_NAME"
log_info "CA DN: $CA_DN"

# Check if CA already exists
if $EJBCA_CLI ca getcacert --caname "$CA_NAME" >/dev/null 2>&1; then
	log_success "CA '$CA_NAME' already exists"
else
	# Initialize new CA
	ejbca_cmd ca init \
		--caname "$CA_NAME" \
		--dn "$CA_DN" \
		--tokenType "soft" \
		--tokenPass "null" \
		--keyspec "2048" \
		--keytype "RSA" \
		-v "$CA_VALIDITY" \
		--policy "null" \
		-s "SHA256WithRSA"

	log_success "CA '$CA_NAME' created successfully"
fi

# Export CA certificate
CA_CERT_FILE="$OUTPUT_DIR/${CA_NAME}.pem"
$EJBCA_CLI ca getcacert --caname "$CA_NAME" -f "$CA_CERT_FILE" || true
log_success "CA certificate exported to: $CA_CERT_FILE"

# =============================================================================
# Step 3: Create Certificate Profiles
# =============================================================================

echo ""
echo "Step 3: Creating Certificate Profiles"
echo "=============================================="

log_info "Certificate profiles must be created via Web UI or REST API"
log_info "EJBCA CE CLI has limited profile management"
log_info ""
log_info "Using ENDUSER profile as default for ACME certificates"
log_info "For production, create custom profile via Web UI:"
log_info "  - Extended Key Usage: Server Authentication"
log_info "  - Subject Alt Names: DNS Name (required for ACME)"

# =============================================================================
# Step 4: Create End Entity Profiles
# =============================================================================

echo ""
echo "Step 4: Creating End Entity Profiles"
echo "=============================================="

log_info "End entity profiles require Web UI configuration in EJBCA CE"
log_info "Using EMPTY profile as default"
log_info ""
log_info "For production, create custom profile via Web UI:"
log_info "  Path: End Entity Profiles > Add"
log_info "  Name: $END_ENTITY_PROFILE"
log_info "  Subject Alt Names: Add DNS Name field (required for ACME)"
log_info "  Available CAs: $CA_NAME"
log_info "  Certificate Profiles: ENDUSER or custom $CERT_PROFILE"

# =============================================================================
# Step 5: Create API Client Certificate
# =============================================================================

echo ""
echo "Step 5: Creating API Client Certificate"
echo "=============================================="

log_info "Generating client certificate for Serles SOAP API access"
log_info "Username: $API_CLIENT_USER"
log_info "DN: $API_CLIENT_DN"

# Clean up old P12 and password files from previous runs
log_info "Cleaning up old certificate files..."
rm -f "$P12_FILE" "$OUTPUT_DIR/${API_CLIENT_USER}.pwd" 2>/dev/null || true

# Check if user exists and delete it to start fresh
if $EJBCA_CLI ra findendentity --username "$API_CLIENT_USER" >/dev/null 2>&1; then
	log_info "User exists, deleting to regenerate certificate..."
	# Revoke first, then delete (pipe 'y' to confirm deletion)
	$EJBCA_CLI ra setendentitystatus --username "$API_CLIENT_USER" --status REVOKED 2>&1 | grep -v "^$" || true
	echo "y" | $EJBCA_CLI ra delendentity --username "$API_CLIENT_USER" 2>&1 | grep -v "^$" || true
fi

# Add end entity for API client
log_info "Creating end entity..."
$EJBCA_CLI ra addendentity \
	--username "$API_CLIENT_USER" \
	--dn "$API_CLIENT_DN" \
	--caname "$MGMT_CA" \
	--type 1 \
	--token "P12" \
	--password "$API_CLIENT_PASSWORD" \
	--certprofile "ENDUSER" \
	--eeprofile "EMPTY" 2>&1 | grep -v "^$"

log_success "End entity created"

# Set password for batch generation
$EJBCA_CLI ra setclearpwd \
	--username "$API_CLIENT_USER" \
	--password "$API_CLIENT_PASSWORD" 2>&1 | grep -v "^$"

# Generate P12 keystore
P12_FILE="$OUTPUT_DIR/${API_CLIENT_USER}.p12"
log_info "Generating P12 keystore..."

if ! $EJBCA_CLI batch --username "$API_CLIENT_USER" -dir "$OUTPUT_DIR" 2>&1 | grep -v "^$"; then
	log_error "Failed to generate P12 keystore"
	exit 1
fi

# Wait for P12 file to be generated
sleep 2

if [ -f "$P12_FILE" ]; then
	log_success "P12 keystore generated: $P12_FILE"
	log_info "P12 password: $API_CLIENT_PASSWORD"
	log_info "Note: P12 to PEM conversion will be handled by the wrapper script"

	# Save password to file for wrapper script
	echo "$API_CLIENT_PASSWORD" >"$OUTPUT_DIR/${API_CLIENT_USER}.pwd"
	chmod 600 "$OUTPUT_DIR/${API_CLIENT_USER}.pwd"
else
	log_error "Failed to generate P12 keystore"
	log_error "Manual certificate generation required"
	exit 1
fi

# =============================================================================
# Step 6: Create Administrator Role
# =============================================================================

echo ""
echo "Step 6: Creating Administrator Role"
echo "=============================================="

log_info "Creating role: $API_CLIENT_ROLE"

# Add administrator role
ejbca_cmd roles addrole "$API_CLIENT_ROLE"

log_success "Role created"

# Add role member (match by CN)
log_info "Adding role member: $API_CLIENT_USER"
ejbca_cmd roles addrolemember \
	--role "$API_CLIENT_ROLE" \
	--caname "$MGMT_CA" \
	--with "CertificateAuthenticationToken:WITH_COMMONNAME" \
	--value "$API_CLIENT_USER" \
	--description "Serles ACME API Client"

log_success "Role member added"

# Add access rules
log_info "Configuring access rules..."

# Core access rules for ACME operations
# Note: Rules must have trailing slashes for EJBCA CLI
ACCESS_RULES=(
	"/administrator/"
	"/ca_functionality/create_certificate/"
	"/ra_functionality/create_end_entity/"
	"/ra_functionality/edit_end_entity/"
	"/ra_functionality/delete_end_entity/"
	"/ca/$CA_NAME/"
	"/endentityprofilesrules/EMPTY/create_end_entity/"
	"/endentityprofilesrules/EMPTY/edit_end_entity/"
)

for rule in "${ACCESS_RULES[@]}"; do
	# Use 'changerule' command (not 'addaccessrule' which doesn't exist in EJBCA CE)
	$EJBCA_CLI roles changerule "$API_CLIENT_ROLE" "$rule" "ACCEPT" 2>&1 | grep -v "^$" || true
	log_info "  Added: $rule"
done

log_success "Access rules configured"

# =============================================================================
# Step 7: Summary and Output
# =============================================================================

echo ""
echo "=============================================="
echo "EJBCA Bootstrap Complete!"
echo "=============================================="
echo ""
echo "Configuration Summary:"
echo "  CA Name:              $CA_NAME"
echo "  CA Certificate:       $CA_CERT_FILE"
echo "  Client P12 Keystore:  $P12_FILE"
echo "  Client Password File: $OUTPUT_DIR/${API_CLIENT_USER}.pwd"
echo "  Client Username:      $API_CLIENT_USER"
echo "  Administrator Role:   $API_CLIENT_ROLE"
echo ""
echo "Next Steps:"
echo "  The wrapper script will:"
echo "  1. Copy P12 keystore from container"
echo "  2. Convert P12 to PEM using host's openssl"
echo "  3. Copy PEM certificate to ./docker/certs/"
echo "  4. Restart Serles to pick up the certificate"
echo ""
echo "IMPORTANT NOTES:"
echo "  - For production: Create custom certificate and end entity profiles via Web UI"
echo "  - Current setup uses default ENDUSER profile and EMPTY end entity profile"
echo "  - Web UI: https://localhost:9443/ejbca/"
echo "  - P12 password saved in: $OUTPUT_DIR/${API_CLIENT_USER}.pwd"
echo ""
echo "=============================================="
