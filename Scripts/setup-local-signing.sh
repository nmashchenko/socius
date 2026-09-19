#!/bin/bash
# Creates a persistent local identity, trusted for code signing only.
set -euo pipefail
IDENTITY="Socius Local Development"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
if security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Local signing certificate already exists."
    exit 0
fi
umask 077
SIGNING_TMP=$(mktemp -d "${TMPDIR:-/tmp/}socius-signing.XXXXXX")
trap 'rm -rf "$SIGNING_TMP"' EXIT
cat > "$SIGNING_TMP/openssl.cnf" <<'CONFIG'
[req]
prompt = no
distinguished_name = name
x509_extensions = signing
[name]
CN = Socius Local Development
[signing]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONFIG
/usr/bin/openssl req -new -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$SIGNING_TMP/openssl.cnf" -keyout "$SIGNING_TMP/key.pem" \
    -out "$SIGNING_TMP/cert.pem" 2>/dev/null
export SOCIUS_SIGNING_PASSWORD=$(/usr/bin/openssl rand -hex 24)
/usr/bin/openssl pkcs12 -export -inkey "$SIGNING_TMP/key.pem" -in "$SIGNING_TMP/cert.pem" \
    -name "$IDENTITY" -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES \
    -passout env:SOCIUS_SIGNING_PASSWORD -out "$SIGNING_TMP/identity.p12"
security import "$SIGNING_TMP/identity.p12" -k "$KEYCHAIN" -P "$SOCIUS_SIGNING_PASSWORD" -T /usr/bin/codesign
unset SOCIUS_SIGNING_PASSWORD
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$SIGNING_TMP/cert.pem"
echo "Installed a local signing identity. Its private key stays in your login Keychain."
