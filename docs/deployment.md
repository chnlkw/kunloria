# Deployment & TLS

## Topology

```
Kubernetes API server ──HTTPS──▶ nginx sidecar :8443 ──HTTP──▶ kunloria :8080
Ceph RGW            ──── HTTP(S) ───▶ service kunloria :443 ──▶ nginx :8443 ──▶ kunloria :8080
Prometheus          ──scrape──▶ /metrics
```

The MVP binary serves plain HTTP (an OpenSSL-terminated listener via
`moonbitlang/async/tls` is on the roadmap); TLS is terminated by the nginx
sidecar, which satisfies the webhook's HTTPS requirement. Certificates are
delivered through a `kubernetes.io/tls` Secret.

## Install

```sh
kubectl create namespace kunloria-system
kubectl label ns kunloria-system kunloria.io/enforce=true

# dev certificates (self-signed) + Secret
NS=kunloria-system ./deploy/gen-cert.sh | kubectl apply -f -
# then patch caBundle as printed by the script

kubectl apply -k deploy/
```

With cert-manager, replace the generated Secret with a `Certificate` resource
(see the comment in `deploy/secret.example.yaml`) and let
`cert-manager.io/inject-ca-from` fill `caBundle`.

## Availability

* `deploy/deployment.yaml`: 2 replicas, `podAntiAffinity` across nodes,
  resource requests/limits (100m/128Mi → 500m/256Mi), readiness+liveness on
  `/healthz`, non-root + read-only rootfs + dropped capabilities.
* `deploy/pdb.yaml`: `minAvailable: 1` survives node drains.
* `failurePolicy: Fail` keeps the cluster fail-closed if Kunloria is
  unreachable.

## Hardening notes

* The webhook's `namespaceSelector` (`kunloria.io/enforce=true`) limits
  blast radius; additionally `KUNLORIA_ENFORCE_NAMESPACES` skips evaluation
  server-side.
* Put RGW traffic on a private path or add an auth token at the ingress;
  the MVP accepts requests without authentication on the pod network.
