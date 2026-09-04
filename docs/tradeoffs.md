# Tradeoffs — what kunloria gives, what it costs

Every design decision in [ADR-0001](adr/0001-policy-as-code-engine.md)
buys something and charges something. This page states both sides for
production use, so you can decide before you deploy — not after.

How to read the tags on each point:

- **[fact]** — verifiable in this repository today (file named).
- **[paper]** — grounded in a cited work; see
  [references.md](references.md) for the verbatim quotes.
- **[inference]** — our reasoning, not measured. Treat it as an opinion
  with stated grounds, and check it against your own deployment.

---

## What you gain in production

### 1. When it breaks, it denies — and that is proved, not promised

Parse failure answers 400, which both fronts count as a denial; a
request no layer decides becomes `Abstain`, and finalize turns it into
`Deny`. The invariant that abstain can never finalize into an allow is
machine-checked (`verdict/lattice.mbtp`), and the deployed webhook runs
`failurePolicy: Fail` (`deploy/webhook.yaml`). XACML needs a full
appendix of combining algorithms to reach the same posture; kunloria
derives it from the lattice. **[fact] [paper]**

### 2. A policy change arrives as an MR with executable evidence

The compiler eliminates whole classes of mistakes (renamed fields,
missed enum cases); the truth-table tests prove each numbered rule in
CI. Cedar describes the same goal for its validator — "to help policy
writers avoid mistakes, but not get in their way" — and kunloria gets
an equivalent guarantee from the host compiler plus ordinary tests. **[fact]
[paper]**

### 3. The two enforcement points share one implementation

The `/validate` and `/v1/data/rgw/authz/allow` routes call the same
`policy` function (`server/app.mbt`). The failure mode measured in the
PaC literature — governance rules implemented independently per
enforcement stage, drifting apart — cannot occur *between these two
stages*, because there is only one implementation. **[fact] [paper]**

### 4. The operational footprint is a static binary

Roughly 5.5 MB, stateless, no database, no cache. The centralised
pole's hardest problem — SpiceDB's own words, "Strong consistency is
key to ensuring correctness, but caching is necessary for performance"
— does not arise, because a deployment holds no shared state. Scaling
is replicas; the fail-closed boundary is a local deterministic
function. **[fact] [paper]**

### 5. There is a formal channel for your own policy properties

`moon prove` runs Why3 over your predicates (`docs/verification.md`).
Most admission tooling offers users no proof path at all; Cedar proves
properties of its engine in Lean, and here even policy-level lemmas
have an exit. **[fact] [paper]**

---

## What it costs you in production

Ordered by how much it can hurt.

### 1. Fail-closed means the blast radius is the scope you registered

If the webhook is down and `failurePolicy: Fail`, the apiserver rejects
every write matching the registered rules. The shipped defaults are
deliberately narrow — pods and role bindings, in namespaces labelled
`kunloria.io/enforce=true` (`deploy/webhook.yaml`) — but widen the
rules to `*/*` and one kunloria bug freezes cluster writes. The same
logic applies to API evolution: a verb or resource the parser does not
recognise classifies as `UnknownAccess`, and typical policies deny it
until the policy is updated. XACML's `Indeterminate{D}/{P}` exists
precisely because "error → deny" is not always the semantics you want;
kunloria has no such knob — a stance, not an oversight. **[fact] [paper]**

### 2. The policy sees the request, and nothing else

`Policy = (Query) -> Decision` is pure: no I/O, no lookups, no
relationship store. Kubernetes admission carries the full object, so
content constraints work; an RGW query carries only bucket and key, so
"who owns this bucket" or "is this user in the bucket's project" is
not expressible. Zanzibar-class systems exist because real products
need relationship-based answers; oso markets the same family of needs
— "Show me only the records that Juno can see". If your authorization
is relationship-heavy, kunloria is the wrong tool. **[fact] [paper]**

### 3. No policy analysis tooling

Cedar can "ensure that when refactoring a set of policies, the
authorized permissions do not change". Kunloria has nothing
equivalent: refactor safety equals your own truth-table coverage, and
an under-covered edit can silently flip decisions into production.
Margrave asked "what changed?" of XACML edits two decades ago. This is
the most substantive capability gap against first-line tools today. **[paper]**

### 4. Your authorization stack is coupled to a young language

Policy reviewers must read MoonBit; a Kyverno YAML is reviewable by
any operator, a kunloria MR needs a programmer's eye. The ecosystems
around the nine PaC tools measured in the MSR study — rule libraries,
converters, community answers — do not exist here, and migrating an
existing OPA/Kyverno ruleset is a manual rewrite. oso's trajectory
(library → DSL → relationship model) is a warning about pure-library
policy in the market. MoonBit itself is young; this repository's own
development hit formatter and registry toolchain churn. **[paper]
[inference]**

### 5. No delegation semantics

The speaks-for lineage (ABLP, SecPAL) exists to answer "A is acting
for B". `Subject { user, groups }` is flat and Kubernetes impersonation
is not modelled; on-behalf-of flows must be invented in policy code if
you need them. **[fact] [paper]**

### 6. Governance coverage is two enforcement points, not the pipeline

The PaC literature warns about CI and admission implementing the same
rule independently until it drifts. Kunloria covers admission plus
RGW; your CI stage still needs its own tool, so overall governance
remains assembled. **[paper]**

### 7. RBAC is untouched

The Kubernetes formal-verification literature targets exactly the
read-path RBAC sprawl — rules that "silently create
privilege-escalation paths that elude linters and manual review".
Kunloria deliberately leaves that to RBAC (ADR-0001); a cluster can
run kunloria and still carry escalated RBAC. **[paper]**

### 8. No hot reload

Every policy change is a new image through GitOps. That is a design
decision, aligned with the governed-GitOps model — but "turn the knob
today" and "ship a release today" are different organisational
capabilities. Teams that need same-day tuning will feel the cadence. **[fact]
[paper]**

---

## Is kunloria right for you?

| Choose it when… | Do not choose it when… |
| --- | --- |
| your pain is exactly write-path Kubernetes admission plus S3/RGW authorization | your authorization is relationship-heavy (shares, ownership, org trees) |
| your platform team reviews code, and policy changes should go through MRs | policies must be maintained by non-programmers, or tuned hot |
| you want a fail-closed posture that is *proved*, not promised | you need error ≠ deny semantics (XACML's `Indeterminate` family) |
| you want a stateless binary with no datastore to operate | you need policy-level analysis (refactoring invariants) or an existing rule ecosystem |

One more honesty note: "one reviewed function is more maintainable
than thousands of rule files" is currently a design belief, not a
measured result. The empirical PaC literature measures the
many-files landscape; it has not measured this shape. **[inference]**
