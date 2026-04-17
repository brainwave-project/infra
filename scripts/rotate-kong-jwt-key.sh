#!/bin/bash
# =============================================================================
# rotate-kong-jwt-key.sh
#
# Rotates the RSA signing key used by Keycloak for JWT signing and Kong for
# JWT verification. Run this periodically or after a suspected key compromise.
#
# Steps:
#   1. Generate a new RSA-2048 key pair
#   2. Print instructions for updating:
#      - keycloak/realm-export.json (components.org.keycloak.keys.KeyProvider)
#      - kong/kong.yml (consumers[].jwt_secrets[].rsa_public_key)
#   3. Reminder: old tokens remain valid until their TTL expires (up to 15 min)
#      Kong MUST keep the old key until all old tokens expire.
#
# IMPORTANT:
#   - In production, rotate via your secrets manager (Vault, AWS SSM, etc.)
#   - Never commit the private key to version control
#   - For Keycloak production: use Admin API to add the new key, keep old key
#     active until all tokens with the old kid have expired, then remove it.
# =============================================================================

set -euo pipefail

OUTPUT_DIR="${1:-.}"
PRIVATE_KEY_FILE="${OUTPUT_DIR}/new-signing-key.pem"
PKCS8_KEY_FILE="${OUTPUT_DIR}/new-signing-key-pkcs8.pem"
PUBLIC_KEY_FILE="${OUTPUT_DIR}/new-signing-key-pub.pem"

echo "=== Brainwave JWT Key Rotation ==="
echo ""
echo "Generating new RSA-2048 key pair..."

openssl genrsa -out "${PRIVATE_KEY_FILE}" 2048 2>/dev/null
openssl pkcs8 -topk8 -inform PEM -outform PEM -nocrypt \
  -in "${PRIVATE_KEY_FILE}" \
  -out "${PKCS8_KEY_FILE}" 2>/dev/null
openssl rsa -in "${PRIVATE_KEY_FILE}" -pubout -out "${PUBLIC_KEY_FILE}" 2>/dev/null

echo "Keys written to:"
echo "  Private key (PKCS8 for Keycloak): ${PKCS8_KEY_FILE}"
echo "  Public key  (PEM for Kong):       ${PUBLIC_KEY_FILE}"
echo ""

PRIVATE_B64=$(grep -v "BEGIN\|END" "${PKCS8_KEY_FILE}" | tr -d '\n')
PUBLIC_PEM=$(cat "${PUBLIC_KEY_FILE}")

echo "================================================================"
echo "ACTION REQUIRED — UPDATE THESE FILES:"
echo "================================================================"
echo ""
echo "1. keycloak/realm-export.json"
echo "   In: components.org.keycloak.keys.KeyProvider[0].config.privateKey[0]"
echo "   Set to: (base64 value from ${PKCS8_KEY_FILE})"
echo ""
echo "   Private key (base64, PKCS8):"
echo "${PRIVATE_B64}"
echo ""
echo "2. kong/kong.yml"
echo "   In: consumers[0].jwt_secrets[0].rsa_public_key"
echo "   Set to:"
echo "${PUBLIC_PEM}"
echo ""
echo "================================================================"
echo "ROTATION SAFETY PROCEDURE:"
echo "================================================================"
echo ""
echo "  Old tokens remain valid until their exp claim (up to 15 min TTL)."
echo "  During the rotation window, BOTH old and new keys must be active."
echo ""
echo "  For Keycloak (production):"
echo "  1. Add the NEW key via Admin API (POST /admin/realms/brainwave/components)"
echo "     with a HIGHER priority than the old key."
echo "  2. Keycloak starts signing NEW tokens with the new key immediately."
echo "  3. The old key remains in JWKS for signature verification."
echo "  4. Wait for 1x access token TTL (15 minutes) for all old tokens to expire."
echo "  5. Remove the OLD key from Keycloak."
echo ""
echo "  For Kong (DB-less mode):"
echo "  1. Update kong.yml with the new rsa_public_key."
echo "  2. Reload Kong: docker compose exec kong kong reload"
echo "  3. If you need to support both keys simultaneously during rotation,"
echo "     add a second consumer entry with a different 'key' string."
echo ""
echo "  Clean up generated key files when done:"
echo "  rm ${PRIVATE_KEY_FILE} ${PKCS8_KEY_FILE} ${PUBLIC_KEY_FILE}"
echo ""
echo "=== Done ==="
