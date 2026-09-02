# Kunloria

**A lightweight, formally-verified policy engine for Kubernetes admission
control and Ceph RGW authorization — an OPA/Rego alternative written in
[MoonBit](https://moonbitlang.com).**

Name: 昆仑 *Kunlun* + *loria* (realm of glory) — the supreme seat of judgment.

Kunloria receives authorization questions over HTTP, answers them from a
**mathematically verified decision core**, and attaches a human-readable
audit reason to every verdict:

- **Kubernetes**: `POST /validate` consumes `admission.k8s.io/v1`
  AdmissionReview objects and allows/denies them (privileged containers,
  risky ClusterRole bindings, namespace scoping).
- **Ceph RGW**: `POST /v1/data/rgw/authz/allow` speaks the OPA-compatible
  contract RGW's `rgw_use_opa_authz` integration expects and answers
  `{"result": true|false}` from group/role/path-prefix rules.

## Why

OPA is powerful but Rego evaluation is hard to predict and even harder to
prove properties about. Kunloria narrows the policy surface to what
multi-tenant S3/K8s authorization actually needs — roles (admin/reader/
writer), group-scoped path prefixes, fail-closed defaults — and verifies the
core decision table with `moon prove` (Why3 + SMT):

1. a **Reader can never be granted a write**, whatever the input;
2. an **Admin is always allowed**;
3. **no non-admin role is allowed outside its group prefix**
   (cross-group access is unrepresentable).

See [docs/verification.md](docs/verification.md).

## Quick start

```sh
moon run cmd/main          # serves on 0.0.0.0:8080 by default
```

```sh
# Ceph RGW style
curl -s localhost:8080/v1/data/rgw/authz/allow -d '{
  "input": {
    "user": {"id": "user1", "groups": ["groupA"]},
    "action": "s3:GetObject",
    "resource": {"bucket": "b", "object": "groupA/path/to/file"}
  }}'
# {"result":true}   with KUNLORIA_READER_GROUPS=groupA

# Kubernetes AdmissionReview style (privileged pod -> denied)
curl -s localhost:8080/validate -d '{
  "apiVersion": "admission.k8s.io/v1", "kind": "AdmissionReview",
  "request": {"uid": "u1", "kind": {"kind": "Pod"}, "operation": "CREATE",
    "object": {"spec": {"containers": [
      {"name": "evil", "securityContext": {"privileged": true}}]}}}}'
```

Every request logs one structured JSON line:

```json
{"ts":1735689600123,"level":"info","msg":"authz_decision","request_id":"req-...-4",
 "path":"/v1/data/rgw/authz/allow","client_ip":"10.42.0.17","allowed":true,
 "reason":"role reader permits read access within group 'groupA'"}
```

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/` | Service banner |
| GET | `/healthz` | Liveness/readiness probe |
| GET | `/metrics` | Prometheus text counters (`kunloria_requests_total`, `kunloria_allowed_total`, `kunloria_denied_total`) |
| POST | `/validate` | Kubernetes AdmissionReview (allow/deny + reason) |
| POST | `/v1/data/rgw/authz/allow` | Ceph RGW / OPA-compatible boolean decision |

## Configuration

Everything is injected via `KUNLORIA_*` environment variables (no external
database): listener, group→role mapping, admission settings. Full table in
[docs/configuration.md](docs/configuration.md); planned `config.yaml` schema
in [config/kunloria.yaml.example](config/kunloria.yaml.example).

## Repository layout

```
proof/   verified decision core (.mbt + .mbtp, moon prove)
auth/    roles, subjects, authorize() on top of the core
k8s/     AdmissionReview parsing + admission checks
ceph/    RGW payload parsing (native + stock Ceph shapes)
server/  moonback HTTP wiring, structured logging, metrics
cmd/main entry point
deploy/  Kubernetes manifests (TLS sidecar, webhook, PDB)
docs/    verification / deployment / RGW / configuration guides
```

## Development

```sh
make check    # moon check
make test     # moon test (39 tests: policy table, payloads, endpoints)
make prove    # moon prove proof (needs why3 + z3, see docs/verification.md)
make build    # native release binary
make docker-build
```

## Deployment

TLS 1.2+ is terminated by an nginx sidecar backed by a Kubernetes Secret
(cert-manager friendly); 2 replicas with pod anti-affinity, a
PodDisruptionBudget, and `failurePolicy: Fail` keep the cluster fail-closed.
See [docs/deployment.md](docs/deployment.md) and the manifests under
[deploy/](deploy/).

## Roadmap

- [ ] Native TLS listener (`moonbitlang/async/tls` OpenSSL binding)
- [ ] `config.yaml` loader for the documented schema
- [ ] Latency histograms on `/metrics`
- [ ] Additional admission checks (hostPath, hostNetwork, image registries)

## License

Apache-2.0
