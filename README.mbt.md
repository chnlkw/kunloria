# Kunloria

**A policy-as-code engine for Kubernetes admission control and Ceph RGW
authorization, written in [MoonBit](https://moonbitlang.com). Policies
are MoonBit functions; the engine is a library you embed and deploy.**

Name: 昆仑 *Kunlun* + *loria* (realm of glory) — the supreme seat of judgment.

Kunloria is *not* a configurable service: there is no policy DSL, no
policy YAML, no policy environment variables ([ADR-0001](docs/adr/0001-policy-as-code-engine.md)).
You write one pure function — `fn policy(Query) -> Decision` — assemble
it from verified combinators if you like, compile it with the engine
into a single binary/image, and ship it through your GitOps pipeline.
Unlike OPA's interpreted Rego, your policy is type-checked, unit-tested,
and (optionally) formally proven before it deploys.

## What you get

- **`verdict/`** — the decision lattice under proof contracts
  (`moon prove`, Why3 + SMT): Kleene three-valued conjunction /
  disjunction / negation with commutativity, associativity, identities,
  idempotence, De Morgan, distribution — and the boundary invariant
  *an abstain never finalizes into an allow* (fail-closed).
- **`engine/`** — the policy-author API: `Query`, `Decision`, predicate
  atoms (`subject_in_group`, `verb_in`, `kind_is`, `ns_is`,
  `rgw_path_in_group_ns`, ...) and combinators (`and_`, `or_`, `not_`,
  `otherwise`, `scoped`) built on the verified lattice.
- **`k8s/`, `ceph/`** — parsers lowering AdmissionReview (including
  `userInfo`, GVK/GVR, full object) and both RGW payload shapes into
  `Query`; malformed input is rejected fail-closed.
- **`server/`** — HTTP wiring, structured JSON logs, Prometheus
  counters, and a one-line boot (`async fn main { @server.run(policy) }`).
  Bring a policy; get `/healthz`, `/metrics`, `/validate`
  (AdmissionReview with 403 + reason on denial) and
  `/v1/data/rgw/authz/allow` (`{"result": bool}`, OPA-compatible for
  `rgw_use_opa_authz`).
- **`examples/`** — three deployable services (see below).

## Quick start

```sh
make run                    # runs examples/rgw-tenant on :8080
make test                   # 48 tests across all packages
curl -s localhost:8080/healthz
```

Write your own policy: copy `examples/minimal`, edit its `policy.mbt`,
run. See the [policy author guide](docs/policy-author-guide.md) — it
fixes the house style (numbered rules, layered decisions) every
`policy.mbt` in this repo follows.

## Examples

| Example | Shows |
| --- | --- |
| `examples/minimal` | the smallest deployable policy (deny everything) |
| `examples/rgw-tenant` | the classic three-role / group-prefix tenant model — the `match`-dispatch skeleton |
| `examples/k8s-write-authz` | subject-based write-path authorization — the `otherwise`-fallback skeleton |

```sh
docker build --build-arg EXAMPLE=k8s-write-authz -t kunloria-example .
```

## Why not OPA/Kyverno/Gatekeeper?

Kunloria deliberately narrows the scope (see
[ADR-0001](docs/adr/0001-policy-as-code-engine.md)): write-path policy
for Kubernetes admission plus S3 authorization for Ceph RGW, with the
policy written in a real programming language and the *decision algebra
formally verified*. Read-path authorization stays with native RBAC —
the ecosystem consensus (neither Kyverno nor Gatekeeper implements the
apiserver authorization webhook either).

## Is kunloria right for you?

An honest assessment — including what it costs you — lives in
[docs/tradeoffs.md](docs/tradeoffs.md), each point tagged by evidence
(fact in this repo / cited paper / inference). The short version:

- **Choose it** when your pain is exactly write-path Kubernetes
  admission plus S3/RGW authorization, your platform team reviews code,
  and you want a fail-closed posture that is proved, not promised.
- **Don't choose it** when your authorization is relationship-heavy
  (shares, ownership graphs), policies must be maintained by
  non-programmers, or you need hot-reloadable rules.

## Layout

```
verdict/    verified decision lattice (.mbt + .mbtp, moon prove)
engine/     Query / Decision / atoms / combinators
k8s/        AdmissionReview parser + reply + content predicates
ceph/       RGW payload parser (native + stock) + reply
server/     HTTP wiring, logging, metrics
examples/   three deployable policy services (policy lib + main)
deploy/     Kubernetes manifests (webhook, TLS sidecar, PDB)
docs/       adr, author guide, verification, deployment, rgw integration
```

## Docs

- [Policy author guide](docs/policy-author-guide.md) — start here
- [ADR-0001: policy-as-code engine](docs/adr/0001-policy-as-code-engine.md)
- [Verification](docs/verification.md) — what is proved and how to run it
- [Deployment](docs/deployment.md) — webhook wiring, TLS, HA
- [Ceph RGW integration](docs/ceph-rgw.md) — `rgw_use_opa_authz` setup
- [Tradeoffs](docs/tradeoffs.md) — what you gain, what it costs, how to decide
- [References & related work](docs/references.md) — annotated, verbatim-quoted

## Status

Pre-release; the API may change without notice. Tests: `make test`.
Prove the lattice: `make prove` (needs why3 + z3).
