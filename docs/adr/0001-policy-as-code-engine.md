# ADR-0001: Kunloria is a policy-as-code engine, not a configurable service

- **Status**: Accepted (2026-09-02)
- **Supersedes**: the implicit scope of the initial MVP
- **Release status**: unreleased — no tag, no mooncakes/registry publication; the working version in `moon.mod` stays at 0.1.0
- **Deciders**: repository owner; boundary discussion of 2026-09-02

## Context

The initial MVP (unreleased) implemented a *configurable authorization service*: fixed three-role
model (admin/reader/writer), group→role mapping injected via `KUNLORIA_*`
environment variables, OPA-compatible HTTP endpoints. A boundary review
re-opened the question of what Kunloria *is*: a service whose policy is
data, or a framework whose policy is code.

The owner decided on the second: **users reference kunloria as a MoonBit
library, write policies in MoonBit, and ship a binary/image embedding their
policy through a GitOps pipeline.** No DSL, no policy YAML, no policy
environment variables.

## Decision

### 1. Product shape: library + embedded server skeleton

`chnlkw/kunloria` (published on mooncakes) provides:

- **engine**: `Query` / `Decision` types, the policy entry point, HTTP
  transport (moonback), structured logging, metrics;
- **combinators**: pure atomic policies and composition operators;
- **parsers**: Kubernetes admission, Ceph RGW payloads → structured `Query`.

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
reads) is explicitly **not implemented** and **not committed to**:

- neither Kyverno nor Gatekeeper implements it — the ecosystem consensus is
  admission for constraints, RBAC for authorization;
- its failure mode couples cluster-wide API availability to the policy
  service; its decision cache delays policy revocation;
- RBAC is already declarative and GitOps-friendly.

The `Query` model stays channel-agnostic (`source` tag), so an
authorization-parser remains a cheap future addition for the narrow case
that justifies it (external identity federation, multi-cluster). Open
question, revisited on demand. See the capability matrix below.

| Channel | Covers | Object content | Failure blast radius |
| --- | --- | --- | --- |
| Admission (implemented) | write paths | ✅ | writes blocked |
| Authorization webhook (open) | all verbs incl. reads | ❌ | all API calls blocked |
| Native RBAC (out of scope) | all verbs | ❌ | none (in-process) |

### 4. Ceph RGW scope

Unchanged from the MVP: OPA-compatible `/v1/data/rgw/authz/allow`, native and
stock RGW payload shapes, group-prefix namespaces. Tenant semantics live in
the user's policy code, not in kunloria.

### 5. Fate of the MVP implementation

The fixed three-role model and its verified core are **rewritten, not
migrated**: the combinator library replaces the closed decision table, and
proof effort moves to (a) engine invariants (Abstain→Deny at the boundary)
and (b) combinator algebra (identity, associativity, distribution), which
assembled policies inherit automatically. The MVP behavior is reproduced as
an example (`rgw-tenant`), without API stability promises. The pre-rewrite
implementation remains in git history; nothing has been released.

### 6. Versioning surface

- semver applies to the **policy-author API** (types, entry point,
  combinators, parsers) published on mooncakes;
- wire contracts (`/validate` AdmissionReview reply, RGW `{"result":bool}`,
  and any future authorization reply) change only in major versions;
- Until the first public release there are no stability promises at all; the
  version in `moon.mod` is a working placeholder and is not bumped per
  iteration.

## Non-goals

- A policy DSL, policy YAML, or policy-bearing environment variables.
- Hot reload of policies (redeploy via GitOps; rolling restart).
- Interpretation of external policy documents of any kind.
- Read-path authorization via the apiserver authorization webhook (open
  question, see §3).
- In-cluster list filtering / result trimming (mechanically impossible for
  webhooks; not a K8s capability at all).
- Storing subject→role mappings inside kunloria (policies compute roles, or
  consult their own data).

## Consequences

- The README/positioning changes from "configurable policy service" to
  "policy-as-code engine with a proof story".
- The next-iteration deliverable is the library split, three parsers (admission gains
  `userInfo`/GVR), combinator library with proofs, and production-grade
  examples (`k8s-write-authz`, `rgw-tenant`, `minimal`) each with Dockerfile,
  CI and fork instructions.
- Documentation gains a "policy author guide" (API, combinators, writing
  `.mbtp` proofs, GitOps pipeline).
