#!/usr/bin/env bash
# deploy/gen-cert.sh — development helper: self-signed serving certificate for
# the ValidatingWebhookConfiguration.
#
# Creates a CA + leaf certificate valid for kunloria.<ns>.svc, writes the
# kubernetes.io/tls Secret, and prints the base64 caBundle to paste into
# deploy/webhook.yaml.
#
# Usage: NS=kunloria-system ./deploy/gen-cert.sh | kubectl apply -f -
set -euo pipefail

NS="${NS:-kunloria-system}"
SVC="${SVC:-kunloria}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1. CA
openssl req -x509 -newkey rsa:2048 -sha256 -days 1825 -nodes \
  -keyout "$TMP/ca.key" -out "$TMP/ca.crt" \
  -subj "/CN=kunloria-ca"

# 2. Leaf certificate for the webhook service
cat > "$TMP/san.cnf" <<EOF
[req]
distinguished_name = dn
req_extensions = ext
prompt = no
[dn]
CN = ${SVC}.${NS}.svc
[ext]
subjectAltName = DNS:${SVC},DNS:${SVC}.${NS},DNS:${SVC}.${NS}.svc,DNS:${SVC}.${NS}.svc.cluster.local
EOF
openssl req -newkey rsa:2048 -sha256 -nodes \
  -keyout "$TMP/tls.key" -out "$TMP/tls.csr" -config "$TMP/san.cnf"
openssl x509 -req -sha256 -days 365 \
  -in "$TMP/tls.csr" -CA "$TMP/ca.crt" -CAkey "$TMP/ca.key" \
  -CAcreateserial -out "$TMP/tls.crt" \
  -extensions ext -extfile "$TMP/san.cnf"

CA_B64="$(base64 -w0 < "$TMP/ca.crt")"

cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: kunloria-tls
  namespace: ${NS}
type: kubernetes.io/tls
stringData:
  tls.crt: |
$(sed 's/^/    /' "$TMP/tls.crt")
  tls.key: |
$(sed 's/^/    /' "$TMP/tls.key")
EOF

cat >&2 <<EOF

Secret manifest printed to stdout. Next steps:
  1. kubectl create namespace ${NS} (if needed)
  2. patch the caBundle of deploy/webhook.yaml with:
     kubectl patch validatingwebhookconfiguration kunloria \\
       --type='json' -p="[{\"op\":\"replace\",\"path\":\"/webhooks/0/clientConfig/caBundle\",\"value\":\"${CA_B64}\"}]"
EOF
