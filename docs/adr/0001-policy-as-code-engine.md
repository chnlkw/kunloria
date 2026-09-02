# ADR-0001: Kunloria is a policy-as-code engine, not a configurable service

- **Status**: Accepted (2026-09-02)
- **Supersedes**: the implicit scope of the initial implementation
- **Deciders**: repository owner; boundary discussion of 2026-09-02

## Context

The initial implementation was a *configurable authorization service*: a
fixed three-role model (admin/reader/writer), group→role mapping injected
via `KUNLORIA_*` environment variables, OPA-compatible HTTP endpoints. A
boundary review re-opened the question of what Kunloria *is*: a service
whose policy is data, or a framework whose policy is code.

The owner decided on the second: **users reference kunloria as a MoonBit
library, write policies in MoonBit, and ship a binary/image embedding their
policy through a GitOps pipeline.** No DSL, no policy YAML, no policy
environment variables.

## Decision

### 1. Product shape: library + embedded server skeleton

`chnlkw/kunloria` is a mooncakes library providing:

- **engine**: `Query` / `Decision` types, the policy entry point, HTTP
  transport (moonback), structured logging, metrics;
- **combinators**: pure atomic policies and composition operators;
- **parsers**: Kubernetes admission and Ceph RGW payloads → structured
  `Query`.

The user's repository owns `fn policy(Query) -> Decision` (or assembles one
from combinators), `main.mbt`, Dockerfile and CI. Deployment parameters
(listen address, log level) remain runtime configuration; **policy is never
configuration**.

### 2. Policy API: single entry point + atoms & combinators

One pure function is the bottom of every deployment. On top of it the
library offers composable atoms (`verb_is`, `resource_is`, `ns_is`,
`subject_in_group`, `path_in_group_ns`, ...) and combinators
(`&`, `|`, `scoped`, `otherwise`, `not_`).

Decisions are **three-valued**: `Allow | Deny | Abstain`. `Abstain` lets
`otherwise` compose policies; the engine converts `Abstain` to `Deny` at the
boundary, making **fail-closed an engine invariant, not the policy author's
responsibility** — and a proof target (`moon prove`).

### 3. Kubernetes scope: write-path policy, aligned with Kyverno/Gatekeeper

Kunloria covers what admission webhooks can enforce: authorization and
content constraints on **write paths** (create/update/delete/connect),
including subject info (`userInfo`), verb, GVR, name/namespace and the full
object. Read-path authorization stays with native RBAC.

The apiserver **authorization webhook** channel (SubjectAccessReview, covers
reads) is not implemented and not planned:

- neither Kyverno nor Gatekeeper implements it — the ecosystem consensus is
  admission for constraints, RBAC for authorization;
- its failure mode couples cluster-wide API availability to the policy
  service; its decision cache delays policy revocation;
- RBAC is already declarative and GitOps-friendly.

The `Query` model stays channel-agnostic (`source` tag), so an
authorization parser remains a cheap future addition if a concrete need
appears (external identity federation, multi-cluster). That need is an open
question, revisited on demand — not a roadmap item.

| Channel | Covers | Object content | Failure blast radius |
| --- | --- | --- | --- |
| Admission (implemented) | write paths | ✅ | writes blocked |
| Authorization webhook (not planned) | all verbs incl. reads | ❌ | all API calls blocked |
| Native RBAC (out of scope) | all verbs | ❌ | none (in-process) |

### 4. Ceph RGW scope

Unchanged: OPA-compatible `/v1/data/rgw/authz/allow`, native and stock RGW
payload shapes, group-prefix namespaces. Tenant semantics live in the
user's policy code, not in kunloria.

### 5. Fate of the current implementation

The fixed three-role model and its verified core are **rewritten, not
migrated**: the combinator library replaces the closed decision table, and
proof effort moves to (a) engine invariants (Abstain→Deny at the boundary)
and (b) combinator algebra (identity, associativity, distribution), which
assembled policies inherit automatically. Until the rewrite lands, the
current implementation keeps serving as the working baseline; afterwards the
`rgw-tenant` example preserves its behavior as a reference.

### 6. Versioning surface

- The project is pre-release: the policy-author API (types, entry point,
  combinators, parsers) may change without notice.
- From the first tagged release onward, semver governs the policy-author
  API, and the wire contracts (`/validate` AdmissionReview reply, RGW
  `{"result":bool}`, and any future authorization reply) change only in
  major versions.

## Non-goals

- A policy DSL, policy YAML, or policy-bearing environment variables.
- Hot reload of policies (redeploy via GitOps; rolling restart).
- Interpretation of external policy documents of any kind.
- In-cluster list filtering / result trimming (mechanically impossible for
  webhooks; not a K8s capability at all).
- Storing subject→role mappings inside kunloria (policies compute roles, or
  consult their own data).

## Consequences

- The README/positioning changes from "configurable policy service" to
  "policy-as-code engine with a proof story".
- The next iteration delivers the library split, three parsers (admission
  gains `userInfo`/GVR), the combinator library with proofs, and
  production-grade examples (`k8s-write-authz`, `rgw-tenant`, `minimal`)
  each with Dockerfile, CI and fork instructions.
- Documentation gains a "policy author guide" (API, combinators, writing
  `.mbtp` proofs, GitOps pipeline).
