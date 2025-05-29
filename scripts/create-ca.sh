#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
# !! IMPORTANT: Change these details, especially passwords !!
CA_DIR="$HOME/certs"
CA_DAYS=3650 # Validity of CA certificate in days (10 years)
CA_COUNTRY="<COUNTRY>"
CA_STATE="<STATE/PROVINCE>"
CA_LOCALITY="<CITY>"
CA_ORG="<NAME>, CA"
CA_CN="<NAME>, PDF CA" # Common Name for the CA

USER_DAYS=1095 # Validity of user certificate in days (3 years)
USER_COUNTRY="<COUNTRY>"
USER_STATE="<STATE/PROVINCE>"
USER_LOCALITY="<CITY>"
USER_ORG="<NAME>, <COMPANY>"
USER_EMAIL="<EMAIIL>"                       # IMPORTANT: Often used by PDF readers to identify the signer
USER_CN="<NAME>"                            # Common Name for the User (Your Full Name)
USER_PKCS12_NAME="<NAME>, PDF Signing Cert" # Friendly name in certificate stores

# NSS Database Location (usually correct for most desktop Linux)
NSS_DIR="${HOME}/.pki/nssdb"
# --- End Configuration ---

# --- Helper Functions ---
check_tool() {
	if ! command -v "$1" &>/dev/null; then
		echo "Error: Required command '$1' not found."
		echo "Please install it."
		# Provide install hints based on common package managers
		if command -v apt-get &>/dev/null; then
			echo "Try: sudo apt update && sudo apt install libnss3-tools"
		elif command -v dnf &>/dev/null; then
			echo "Try: sudo dnf install nss-tools"
		elif command -v yum &>/dev/null; then
			echo "Try: sudo yum install nss-tools"
		elif command -v pacman &>/dev/null; then
			echo "Try: sudo pacman -S nss"
		fi
		exit 1
	fi
}

# --- Tool Checks ---
check_tool "openssl"
check_tool "certutil"
check_tool "pk12util"

# --- Main Script ---

echo "Creating directory structure..."
mkdir -p "${CA_DIR}/ca"
mkdir -p "${CA_DIR}/user"
cd "${CA_DIR}"

CA_KEY="ca/ca.key.pem"
CA_CERT="ca/ca.cert.pem"
USER_KEY="user/user.key.pem"
USER_CSR="user/user.csr.pem"
USER_CERT="user/user.cert.pem"
USER_PKCS12="user/user_cert.p12"
SERIAL_FILE="ca/serial"
INDEX_FILE="ca/index.txt"
OPENSSL_CONF="user/openssl_ext.cnf"

echo "--- Creating Certificate Authority (CA) ---"

echo "Generating CA private key (${CA_KEY})..."
# Use -aes256 for password protection, remove -passout for interactive prompt
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 \
	-aes256 -pass \
	-out "${CA_KEY}"

echo "Generating CA self-signed certificate (${CA_CERT})..."
openssl req -x509 -new -nodes -sha256 \
	-key "${CA_KEY}" \
	-passin \
	-days ${CA_DAYS} \
	-out "${CA_CERT}" \
	-subj "/C=${CA_COUNTRY}/ST=${CA_STATE}/L=${CA_LOCALITY}/O=${CA_ORG}/CN=${CA_CN}"

# Prepare CA database files (needed for signing user certs)
echo "01" >"${SERIAL_FILE}"
touch "${INDEX_FILE}"

echo "--- Creating User Certificate ---"

echo "Generating User private key (${USER_KEY})..."
# User key doesn't strictly need password protection here as it gets bundled into PKCS12 later
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
	-out "${USER_KEY}"

echo "Generating User Certificate Signing Request (CSR) (${USER_CSR})..."
openssl req -new -sha256 \
	-key "${USER_KEY}" \
	-out "${USER_CSR}" \
	-subj "/C=${USER_COUNTRY}/ST=${USER_STATE}/L=${USER_LOCALITY}/O=${USER_ORG}/emailAddress=${USER_EMAIL}/CN=${USER_CN}"

echo "Creating OpenSSL config for extensions..."
cat >"${OPENSSL_CONF}" <<EOF
[ pdf_signing_ext ]
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, nonRepudiation
# 'emailProtection' is often expected/used for document signing identities
extendedKeyUsage = emailProtection
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
subjectAltName = email:${USER_EMAIL}
EOF

echo "Signing User CSR with CA (${USER_CERT})..."
openssl x509 -req -sha256 \
	-in "${USER_CSR}" \
	-CA "${CA_CERT}" \
	-CAkey "${CA_KEY}" \
	-passin \
	-CAserial "${SERIAL_FILE}" \
	-out "${USER_CERT}" \
	-days ${USER_DAYS} \
	-extfile "${OPENSSL_CONF}" -extensions pdf_signing_ext

echo "Verifying user certificate against CA..."
openssl verify -CAfile "${CA_CERT}" "${USER_CERT}"

echo "--- Preparing for NSS Import ---"

echo "Creating PKCS#12 file (${USER_PKCS12}) containing user key and certificate..."
# Include the CA cert in the PKCS12 bundle as the chain
openssl pkcs12 -export \
	-inkey "${USER_KEY}" \
	-in "${USER_CERT}" \
	-certfile "${CA_CERT}" \
	-out "${USER_PKCS12}" \
	-name "${USER_PKCS12_NAME}" \
	-password pass:"${USER_KEY_PASS}" # Password needed for import into NSS

echo "--- Managing NSS Database (${NSS_DIR}) ---"

# Ensure NSS directory exists and initialize if necessary
if [ ! -d "${NSS_DIR}" ]; then
	echo "NSS database directory (${NSS_DIR}) not found."
	echo "Creating and initializing NSS database..."
	mkdir -p "${NSS_DIR}"
	# Initialize database - THIS WILL PROMPT FOR A NEW MASTER PASSWORD
	# You MUST remember this password.
	certutil -N -d sql:"${NSS_DIR}"
	echo "NSS database created. You were prompted to set a master password."
else
	echo "Found existing NSS database at ${NSS_DIR}."
	# Check if we can list certs to see if password is needed/cached
	if ! certutil -L -d sql:"${NSS_DIR}" -h all &>/dev/null; then
		echo "You might be prompted for the NSS database master password."
	fi
fi

echo "Importing CA certificate (${CA_CERT}) into NSS database..."
# Trust flags: C = SSL CA, T = Email CA, c = SSL Client
# CT,C,C is a common trust setting for a CA issuing user certs for signing/email/ssl
# Using "CT,," marks it trusted to issue Email (signing) and SSL server certs.
certutil -A -n "${CA_CN}" -t "CT,," -i "${CA_CERT}" -d sql:"${NSS_DIR}"

echo "Importing User PKCS#12 file (${USER_PKCS12}) into NSS database..."
# This will prompt for:
# 1. The NSS database master password (set earlier or previously)
# 2. The PKCS#12 file password (USER_KEY_PASS defined above)
pk12util -i "${USER_PKCS12}" -d sql:"${NSS_DIR}" -W "${USER_KEY_PASS}"

echo "--- Verification in NSS ---"
echo "Listing certificates in NSS database (verify CA and User cert are present):"
certutil -L -d sql:"${NSS_DIR}"

cd .. # Go back to original directory

echo "--- Summary ---"
echo "CA Certificate:      ${CA_DIR}/${CA_CERT}"
echo "CA Private Key:      ${CA_DIR}/${CA_KEY} (Password: ${CA_KEY_PASS})"
echo "User Certificate:    ${CA_DIR}/${USER_CERT}"
echo "User Private Key:    ${CA_DIR}/${USER_KEY}"
echo "User PKCS#12 Bundle: ${CA_DIR}/${USER_PKCS12} (Password: ${USER_KEY_PASS})"
echo ""
echo "CA certificate and User certificate/key have been imported into:"
echo "NSS Database: ${NSS_DIR}"
echo ""
echo "The user certificate '${USER_PKCS12_NAME}' should now be available for PDF signing in Okular."
echo "You may need to restart Okular."
echo "When signing, select the certificate named '${USER_PKCS12_NAME}' or associated with '${USER_EMAIL}'."
echo ""
echo "IMPORTANT: Keep your CA private key (${CA_DIR}/${CA_KEY}) and its password (${CA_KEY_PASS}) extremely safe!"
echo "Keep your User PKCS#12 password (${USER_KEY_PASS}) safe!"
echo "Consider backing up the entire ${CA_DIR} directory securely."
echo "Consider deleting intermediate files like ${CA_DIR}/${USER_CSR} if no longer needed."
echo "Script finished successfully."
