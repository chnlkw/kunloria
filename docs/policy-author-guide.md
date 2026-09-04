# Writing policies

A kunloria deployment is *your* MoonBit program that embeds the engine.
You own one function; the engine owns everything else (transport,
parsing, logging, metrics, the fail-closed boundary).

This guide walks through the pieces you will touch.

## The one function

```moonbit skip
pub fn policy(q : @engine.Query) -> @engine.Decision
```

`Query` is the structured question (who, what verb, which resource,
optional full object); `Decision` is `Allow(reason)`, `Deny(reason)` or
`Abstain` — no opinion. **The engine finalizes `Abstain` into `Deny` at
the boundary**, so an unmatched request can never leak as an allow.

Start from `examples/minimal` (denies everything) and grow from there:

```moonbit skip
pub fn policy(q : @engine.Query) -> @engine.Decision {
  @engine.otherwise(
    @engine.and_(@engine.subject_in_group("platform"), @engine.allow_all),
    @engine.otherwise(
      @engine.scoped(
        q => q.ns() is Some(ns) && q.subject.groups.contains(ns),
        @engine.allow_all,
        reason="subject has no group matching the target namespace",
      ),
      @engine.deny_all,
    ),
  )(q)
}
```

## Style: numbered rules, layered decisions

Every policy in this repo follows one canon, so any `policy.mbt` reads
the same way:

| # | Rule | Why |
| --- | --- | --- |
| 1 | **Plain words first** — the file header states the policy as numbered rules, most powerful first; `policy()` carries the same numbers as inline comments | a reviewer reads the header for intent and the numbered lines to check the code |
| 2 | **Layers in priority order** — constraints that bind everyone on top (the `satisfies` idiom below), then allow layers most-privileged-first, `deny_all` last | priority lives in the layer order, never in scattered early returns |
| 3 | **Dispatch with `match`, fall back with `otherwise`** — an exhaustive `match` when layers switch on data (role, source); `otherwise` when layers are fallbacks | either way the compiler checks you covered every case |
| 4 | **Categories are enums, not strings** — anything you branch on is an enum plus an exhaustive match | a mistyped string compiles; a missed enum case does not |
| 5 | **Gates are named predicates** — `fn path_in_any_group_ns(path, groups) -> Bool`, never a `let mut` flag with a loop inside the decision | decisions stay declarative |
| 6 | **Atoms for leaves, helpers for computation** — prefer engine atoms; a named `-> Bool` predicate when a layer computes; a small `-> Decision` helper only when the layer needs computed data or dynamic denial reasons (role matrices, joined paths) | helpers stay small and named after the layer they decide |
| 7 | **Every denial says why**, with the facts interpolated (path, verb, role) | denial reasons are the policy's UI — they surface verbatim in 403s and logs |
| 8 | **Knobs live at the top** — group lists and allow lists as const-style accessor functions, grouped in one place | one place to edit, one diff to review |
| 9 | **Truth tables pin every rule** — each numbered rule gets at least one allow and one deny test in `policy_test.mbt` | refactors cannot silently drift |

The two skeletons the canon allows, both in `examples/`:

- `k8s-write-authz` — fallback tower: `otherwise(and_(constraints), otherwise(admin, otherwise(tenant, deny_all)))`. Use when layers are priorities.
- `rgw-tenant` — data dispatch: `match (role, source) { (Admin, _) => ..., (role, Rgw) => ..., (_, K8sAdmission) => ... }` with one small `-> Decision` helper per branch. Use when the first cut of the decision is *which case is this?*

Both state their per-deployment choices in the header — `rgw-tenant`
lets admins bypass the content constraints, `k8s-write-authz` binds
everyone; a reader of either file sees that in rule 1, not in the code.

## What a Query carries

| Field | Meaning |
| --- | --- |
| `source` | `K8sAdmission` or `Rgw` — which front end asked |
| `subject` | `user : String`, `groups : Array[String]` (authenticated upstream) |
| `verb` | lower-cased raw verb: `create`, `delete`, `s3:getobject`, ... |
| `kind` | `ReadAccess` / `WriteAccess` / `UnknownAccess` — classified by the parser; unknown verbs never classify as read or write |
| `target` | `K8s(K8sRef)` (group, kind, resource, subresource, name, ns) or `Rgw(RgwRef)` (bucket, object_key) |
| `object` | the full admitted object as `Json?` — present only for admission requests |

Helpers: `q.ns()`, `q.rgw_path()`
(`"<bucket>/<object>"`), `@engine.path_in_namespace(path, group)`.

## Atoms

Decision atoms: `allow_all`, `deny_all`, `abstain_all`.

Predicate atoms **allow** on match and **abstain** otherwise (so they
compose as conditions, not verdicts):

- `subject_is(user)`, `subject_in_group(group)`
- `verb_in(["create", "update"])`, `kind_is(WriteAccess)`
- `ns_is("prod")`, `k8s_kind_is("Pod")`, `k8s_resource_is("pods")`
- `rgw_path_in_group_ns()` — RGW path under one of the subject's groups

Content predicates over `q.object` (from `@k8s`):
`target_kind_is(q, "Pod")`, `targets_pod(q)`,
`pod_has_privileged_container(obj)`,
`binding_grants_risky_role(obj, ["cluster-admin"])`.

## Combinators

Effects combine through a **verified three-valued (Kleene) lattice** —
see `verdict/` and `docs/verification.md`:

| combinator | semantics |
| --- | --- |
| `and_(p1, p2)` | deny dominates; abstain propagates; both must allow |
| `or_(p1, p2)` | allow dominates; abstain propagates; both must deny |
| `not_(p)` | flips allow/deny, abstain stays |
| `otherwise(p1, p2)` | `p1`'s decision unless it abstains |
| `scoped(gate, p)` | gate fails → hard deny "out of scope" |

The idiomatic shape for "constraints bind everyone, then who may act":

```moonbit skip
// constraint: deny when violated, ABSTAIN when satisfied — the abstain
// is what lets `otherwise` fall through to the subject layers.
fn satisfies(pred : (Query) -> Bool, why : String) -> Policy { ... }

let policy = otherwise(
  and_(satisfies(no_privileged, "..."), satisfies(no_risky, "...")),
  otherwise(admin_layer, otherwise(tenant_layer, deny_all)),
)
```

The truth-table semantics you can rely on (all proved in
`verdict/lattice.mbtp`): commutativity, associativity, identities
(`allow_all` for `and_`, `deny_all` for `or_`), idempotence, De Morgan,
distribution — and the boundary invariant *abstain never finalizes into
an allow*.

## Endpoints your binary serves

`@server.root_module(policy, metrics)` wires:

| Route | Purpose |
| --- | --- |
| `GET /healthz`, `GET /metrics` | probes; Prometheus counters |
| `POST /validate` | Kubernetes AdmissionReview (uid echo, 403 + reason on denial) |
| `POST /v1/data/rgw/authz/allow` | OPA-compatible `{"result": bool}` for Ceph RGW |

Malformed payloads answer **400**, which both fronts treat as a denial —
fail-closed parsing is the engine's job, not yours.

`main.mbt` is a dozen lines (see any example); the only configuration is
`KUNLORIA_HOST`, `KUNLORIA_PORT`, `KUNLORIA_LOG_LEVEL`. **Policy is
never configuration** (ADR-0001): constants live in `policy.mbt`, and
changes ship through your GitOps pipeline as a new image.

## Testing and proving your policy

Write blackbox tests against `policy` directly (`*_test.mbt`) — every
example ships its truth tables this way. For properties, mirror the
pattern in `verdict/`: pure helpers with `#proof_pure`, predicates and
lemmas in a `.mbtp` file, then `moon prove` (Why3 + z3; see
`docs/verification.md`).

## Deploying

```sh
docker build --build-arg EXAMPLE=rgw-tenant -t registry/kunloria-rgw:dev .
kubectl apply -k deploy/   # after pointing the image at your build
```

See `docs/deployment.md` for the webhook/TLS wiring and
`docs/ceph-rgw.md` for the RGW integration.
