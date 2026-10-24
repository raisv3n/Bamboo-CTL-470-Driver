#!/bin/zsh
# Exports the "BambooDriver Local Signing" identity for GitHub Actions, so release builds carry the
# same signature as local builds (Accessibility grants then survive updates on every Mac).
#
# Prints the two repository secrets to add (Settings > Secrets and variables > Actions):
#   MACOS_SIGNING_P12_BASE64   (copied to the clipboard)
#   MACOS_SIGNING_P12_PASSWORD (printed)
set -euo pipefail

KEYCHAIN=~/Library/Keychains/login.keychain-db
# `security export -t identities` exports every identity in the keychain; refuse unless ours is the only one.
identities=$(security find-identity "$KEYCHAIN" | grep -cE '^\s+[0-9]+\) ' || true)
if ! security find-identity "$KEYCHAIN" | grep -q '"BambooDriver Local Signing"' || (( identities > 1 )); then
    echo "Login keychain must contain exactly one identity, 'BambooDriver Local Signing' (found $identities)." >&2
    echo "Export it manually from Keychain Access > My Certificates instead." >&2
    exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
password=$(openssl rand -hex 16)
security export -k "$KEYCHAIN" -t identities -f pkcs12 -P "$password" -o "$work/signing.p12"
base64 -i "$work/signing.p12" | tr -d '\n' | pbcopy
echo "MACOS_SIGNING_P12_BASE64   -> copied to clipboard"
echo "MACOS_SIGNING_P12_PASSWORD -> $password"
