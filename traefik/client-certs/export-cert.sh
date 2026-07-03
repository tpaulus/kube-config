#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <client-cert-secret-name>"
  echo "Example: $0 tom-iphone-client-cert"
  exit 1
fi

export CERT_NAME="$1"
export WORKDIR="$(mktemp -d)"
export OUT="${PWD}/${CERT_NAME}.p12"

cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

kubectl -n traefik get certificate "$CERT_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' | grep -qx True

kubectl -n traefik get secret "$CERT_NAME" -o jsonpath='{.data.tls\.crt}' | base64 --decode > "$WORKDIR/client.crt"
kubectl -n traefik get secret "$CERT_NAME" -o jsonpath='{.data.tls\.key}' | base64 --decode > "$WORKDIR/client.key"
kubectl -n traefik get secret "$CERT_NAME" -o jsonpath='{.data.ca\.crt}' | base64 --decode > "$WORKDIR/mtls-client-ca.crt"

openssl x509 -in "$WORKDIR/client.crt" -noout -subject -issuer -ext extendedKeyUsage

openssl pkcs12 -export \
  -inkey "$WORKDIR/client.key" \
  -in "$WORKDIR/client.crt" \
  -certfile "$WORKDIR/mtls-client-ca.crt" \
  -name "$CERT_NAME" \
  -out "$OUT"

echo "Created client identity: $OUT"
echo "AirDrop this .p12 file to the device, then delete it after installation."
