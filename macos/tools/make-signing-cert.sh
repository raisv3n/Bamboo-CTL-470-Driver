#!/bin/zsh
# Creates the self-signed "BambooDriver Local Signing" code-signing identity in the login keychain.
# Remove it later in Keychain Access (My Certificates) if no longer needed.
set -euo pipefail
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
/usr/bin/openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 3650 -nodes \
    -subj "/CN=BambooDriver Local Signing" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false"
/usr/bin/openssl pkcs12 -export -out id.p12 -inkey key.pem -in cert.pem -passout pass:bamboo
security import id.p12 -k ~/Library/Keychains/login.keychain-db -P bamboo -T /usr/bin/codesign
