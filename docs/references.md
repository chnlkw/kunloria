# References — related work, honestly cited

Kunloria stands on thirty-plus years of work on authorization logics,
policy languages, and verified decision procedures. This file maps that
landscape onto our design decisions.

Ground rules for this file, because an open-source project must be
honest about its sources:

- Every quotation below is **verbatim** from a source fetched on
  **2026-09-04**. Curly quotes and line breaks are normalized to plain
  ASCII; nothing else is altered; `[...]` marks omission.
- Items we could **not** open are listed with metadata verified via
  Crossref and are explicitly marked *"no quote — not openly accessible
  at access time"* rather than paraphrased from memory.
- If a citation here is wrong, please open an issue; we will fix it.

---

## A. The decision algebra → `verdict/`

Kunloria's `Effect { Allow; Deny; Abstain }` Kleene lattice with
deny-dominating `and_`, allow-dominating `or_`, and a finalize step
that turns `Abstain` into `Deny` (fail-closed) is a minimal descendant
of the XACML decision model.

### OASIS XACML 3.0 core specification (primary standard)

OASIS, *eXtensible Access Control Markup Language (XACML) Version 3.0*,
2013. <http://docs.oasis-open.org/xacml/3.0/xacml-3.0-core-spec-os-en.html>

> Authorization decision — The result of evaluating applicable policy,
> returned by the PDP to the PEP. A function that evaluates to "Permit",
> "Deny", "Indeterminate" or "NotApplicable", and (optionally) a set of
> obligations and advice

> C.2 Deny-overrides — This section defines the "Deny-overrides"
> rule-combining algorithm of a policy and policy-combining algorithm of
> a policy set. This combining algorithm makes use of the extended
> "Indeterminate".

**For kunloria:** XACML needs four values plus extended-Indeterminate
because evaluation errors and "rule did not match" must be
distinguishable inside a distributed XML pipeline. A compiled library
does not have that constraint, so kunloria keeps three: `Abstain`
covers both "no layer matched" and layers that decline, and
`@engine.finalize` collapses it to `Deny` at the boundary — the same
deny-biased posture as deny-overrides, with one value fewer to reason
about. The 15 lemmas in `verdict/lattice.mbtp` pin this algebra down
mechanically.

### The Logic of XACML

Kencana Ramli, Hanne Riis Nielson, Flemming Nielson, *The Logic of
XACML*, LNCS, 2012. DOI
[10.1007/978-3-642-35743-5_13](https://link.springer.com/chapter/10.1007/978-3-642-35743-5_13).
*No quote — not openly accessible at access time.*

**For kunloria:** one of the formal treatments of XACML's combining
operators; the closest published cousin of `verdict/`'s truth tables.

### Kleene Algebra in the Archive of Formal Proofs

Alasdair Armstrong, Georg Struth, Tjark Weber, *Kleene Algebra*,
Isabelle AFP.
<https://www.isa-afp.org/entries/Kleene_Algebra.html>

> Kleene algebras are foundational structures in computing with
> applications ranging from automata and language theory to
> computational modeling, program construction and verification.

> We start with formalising dioids, which are additively idempotent
> semirings, and expand them by axiomatisations of the Kleene star for
> finite iteration and an omega operation for infinite iteration.

**For kunloria:** our `#proof_pure` helpers in `verdict/lattice.mbt`
and the lemma names in `lattice.mbtp` (commutativity, associativity,
identities, idempotence, De Morgan, distribution) are exactly the
Kleene-algebra axiom family this entry formalizes in Isabelle/HOL —
independent evidence that this lemma set is the right machine-checked
contract for a decision combinator library. We use Why3 (`moon prove`)
instead of Isabelle because the MoonBit toolchain ships it.

---

## B. Verification-guided engines → the `verdict/` + `moon prove` loop

### Cedar

Joseph W. Cutler, Craig Disselkoen, Aaron Eline, Shaobo He, Kyle
Headley, Michael Hicks, Kesha Hietala, et al., *Cedar: A New Language
for Expressive, Fast, Safe, and Analyzable Authorization (Extended
Version)*, arXiv, 2024. <https://arxiv.org/abs/2403.04651>

> Cedar is a new authorization policy language designed to be
> ergonomic, fast, safe, and analyzable.

> Cedar's design has been finely balanced to allow for a sound and
> complete logical encoding, which enables precise policy analysis,
> e.g., to ensure that when refactoring a set of policies, the
> authorized permissions do not change. We have modeled Cedar in the
> Lean programming language, and used Lean's proof assistant to prove
> important properties of Cedar's design. We have implemented Cedar in
> Rust, and released it open-source.

Craig Disselkoen, Aaron Eline, Shaobo He, Kyle Headley, Michael Hicks,
*How We Built Cedar: A Verification-Guided Approach*, Companion
Proceedings of the 32nd ACM International Conference on the Foundations
of Software Engineering (FSE Companion '24), 2024. DOI
[10.1145/3663529.3663854](https://dl.acm.org/doi/10.1145/3663529.3663854).
*No quote — ACM DL not openly accessible at access time.*

**For kunloria:** the closest industrial relative. Cedar verifies the
engine and keeps policy in an interpreted DSL so policies can be
analyzed without a compiler; kunloria makes the opposite trade
(ADR-0001): policy is host-language code that is type-checked and
unit-tested before deploy, and what gets verified is the decision
algebra every policy composes through. Reading Cedar's "refactoring
does not change permissions" goal states cleanly what a future kunloria
policy-diff tool would have to prove.

### Formal verification of Kubernetes access policies

Sissodiya, Chiquito, Bodin, Kristiansson, *Formal Verification for
Preventing Misconfigured Access Policies in Kubernetes Clusters*, IEEE
Access, 2025. DOI
[10.1109/ACCESS.2025.3597504](https://ieeexplore.ieee.org/document/11122676).

> Kubernetes clusters now underpin the bulk of modern production
> workloads, recent 2024 Cloud Native Computing Foundation surveys
> report >96% enterprise adoption [...]

> In practice these controls are brittle: minor syntactic oversights,
> wildcard privileges, or conflicting rules can silently create
> privilege-escalation paths that elude linters and manual review. This
> paper presents a framework that models both RBAC and admission
> policies as first-order logic and uses an SMT solver to exhaustively
> search for counter-examples [...]

**For kunloria:** this line of work verifies the *configuration state
of a cluster*; kunloria's `make prove` verifies the *decision algebra
itself*, and `docs/verification.md` shows a policy author how to add
properties of their own policy. The two are complementary: their
counter-example search over deployed RBAC/admission rules is exactly
what a kunloria deployment never accumulates, because policy is one
reviewed function rather than thousands of YAML rules.

---

## C. Policy-language lineage → ADR-0001 "policy is code, not a DSL"

### The speaks-for calculus

Martín Abadi, Michael Burrows, Butler Lampson, Gordon Plotkin, *A
Calculus for Access Control in Distributed Systems*, ACM TOPLAS 15(3),
1993. DOI
[10.1145/155183.155225](https://dl.acm.org/doi/10.1145/155183.155225).
Quoted from the author's page
<http://www.bwlampson.site/44-CalculusAccessControl/44-CalculusAccessControlAbstract.html>.

> We study some of the concepts, protocols, and algorithms for access
> control in distributed systems from a logical perspective. We account
> for how a principal may come to believe that another principal is
> making a request, either on his own or on someone else's behalf. We
> also provide a logical language for access control lists and theories
> for deciding whether requests should be granted.

**For kunloria:** the founding move of the field — treat authorization
as a logic, not a configuration format. Kunloria keeps the move but
changes the host: the logic is a typed functional language, and
`Subject { user, groups }` is the pragmatic subset of "speaks-for"
that K8s and RGW actually authenticate.

### SecPAL

Moritz Y. Becker, Cédric Fournet, Andrew D. Gordon, *SecPAL: Design
and semantics of a decentralized authorization language*, Microsoft
Research TR MSR-TR-2006-120, 2006; Journal of Computer Security 18(3),
2010. DOI
[10.3233/jcs-2009-0364](https://doi.org/10.3233/jcs-2009-0364). Quoted
from the openly posted TR
<https://courses.cs.vt.edu/cs5204/fall10-kafura-BB/Papers/Security/SecPal-Reference.pdf>.

> We present a declarative authorization language. Policies and
> credentials are expressed using predicates defined by logical
> clauses, in the style of constraint logic programming.

> Our language strikes a fine balance between semantic simplicity,
> policy expressiveness, and execution efficiency. The semantics
> consists of just three deduction rules.

**For kunloria:** SecPAL is the direct ancestor of Rego-style
Datalog engines. Its "just three deduction rules" is the same economy
kunloria aims at from the other side — three lattice combinators plus
atoms, and no deduction engine at all because the host compiler does
the evaluating.

### Expressiveness limits

Jason Crampton, Claire Williams, *On Completeness in Languages for
Attribute-Based Access Control*, SACMAT '16. DOI
[10.1145/2914642.2914654](https://dl.acm.org/doi/10.1145/2914642.2914654).
*No quote — not openly accessible at access time.*

Doaa Hassan, Amr Sabry, *Encoding secure information flow with
restricted delegation and revocation in Haskell*, Proceedings of the
1st annual workshop on Functional programming concepts in
domain-specific languages, 2013. DOI
[10.1145/2505351.2505354](https://dl.acm.org/doi/10.1145/2505351.2505354).
*No quote — not openly accessible at access time.*

**For kunloria:** the SACMAT paper frames what a policy language must
be able to express; the Haskell paper is a precedent for the position
ADR-0001 takes — authorization semantics encoded as typed functional
programs rather than an interpreted DSL. Kunloria's answer to
expressiveness is deliberately boring: any computation MoonBit can
express, inside `Query -> Decision`.

---

## D. Policy-as-Code empirics → the product thesis

### An Empirical Study of Policy as Code

Ruben Opdebeeck, Mahmoud Alfadel, Akond Rahman, Yutaro Kashiwa, João F.
Ferreira, Raula Gaikovina Kula, Coen De Roover, *An Empirical Study of
Policy as Code: Adoption, Purpose, and Maintenance*, MSR 2026.
<https://2026.msrconf.org/details/msr-2026-technical-papers/22/>

> Policy as Code (PaC) is an emerging DevOps practice that enables
> teams to specify organisational and technical policies, such as
> regulatory compliance, security requirements, and resource limits,
> through machine-enforceable declarative code.

> This paper aims to address this gap through an empirical study of
> PaC based on 10,560 PaC files from 499 open-source repositories
> spanning nine PaC tools.

**For kunloria:** the field evidence ADR-0001 reasons from — PaC is
real and spreading, but as thousands of small declarative files across
nine tools. Kunloria's bet is the other corner of the design space:
one typed, testable, provable function per deployment.

### Reusing PaC across enforcement stages

Nogueira, Resende, *Reusing Policy-as-Code Across CI/CD and Kubernetes
Admission Control: An Empirical Assessment of Governance Consistency*,
Computers (MDPI), 2026. DOI
[10.3390/computers15070453](https://www.mdpi.com/2073-431X/15/7/453).

> Although Policy-as-Code is widely adopted within Continuous
> Integration (CI) pipelines and Kubernetes admission-control
> frameworks, governance requirements are often implemented
> independently, potentially increasing maintenance effort and creating
> opportunities for policy drift.

**For kunloria:** this is kunloria's own deployment domain, measured:
the same governance rule re-implemented per stage drifts apart. A
kunloria policy is one MoonBit function that both fronts call, which
is the reuse structure this paper finds missing.

### Governed GitOps

Sumit Kaul, *Governed GitOps: Converging Infrastructure-as-Code,
Policy-as-Code, and Progressive Delivery*, Journal of Computational
Analysis and Applications 34(12), 2025. DOI
[10.48047/jocaaa.2025.34.12.19](https://eudoxuspress.com/index.php/pub/article/download/4340/3182/8663).

> Governed GitOps represents a transformative paradigm that unifies
> traditionally fragmented practices in cloud infrastructure
> management. By converging Infrastructure-as-Code modules,
> Policy-as-Code enforcement, and Progressive Delivery mechanisms into
> a cohesive framework, organizations can address endemic challenges
> including configuration drift, compliance friction, and subjective
> release decisions.

**For kunloria:** the academic sketch of the delivery channel kunloria
already assumes — git as the source of truth, controllers reconciling,
policy enforced continuously rather than reviewed periodically.

---

## E. Embedded-engine precedents → the library shape

### oso / Polar

*oso*, open-source project.
<https://github.com/osohq/oso>

> Oso is a batteries-included framework for building authorization in
> your application.

> Set up common permissions patterns like role-based access control
> (RBAC) and relationships using Oso's built-in primitives. Extend them
> however you need with Oso's declarative policy language, Polar.

**For kunloria:** the precedent for "authorization as a library you
embed" — and a cautionary data point: oso grew a DSL (Polar) and later
moved toward relationship-based FGA. Kunloria's reading is that the
DSL step is exactly where type-checking and ordinary tooling are lost,
which is why ADR-0001 declines it.

### Margrave

*Margrave: An API for XACML Policy Verification and Change Analysis*,
Brown PLT. <http://www.margrave-tool.org/v1+v2/margrave/>

> An API for XACML Policy Verification and Change Analysis

**For kunloria:** the reference shape for the analysis tooling kunloria
does not have yet — ask "what decisions changed?" of a policy edit.
A kunloria answer would diff truth-table outputs, which is cheap
because policies are functions.

---

## F. Centralized scale-out → what kunloria is not

### Zanzibar

Ruoming Pang, Ramón Cáceres, Mike Burrows, et al., *Zanzibar: Google's
Consistent, Global Authorization System*, USENIX ATC '19.
<https://www.usenix.org/conference/atc19/presentation/pang> (PDF quoted:
<https://www.cs.wm.edu/~smherwig/readings/papers/19-atc-zanzibar.pdf>)

> This paper presents the design, implementation, and deployment of
> Zanzibar, a global system for storing and evaluating access control
> lists.

> Its authorization decisions respect causal ordering of user actions
> and thus provide external consistency amid changes to access control
> lists and object contents. Zanzibar scales to trillions of access
> control lists and millions of authorization requests per second [...]

**For kunloria:** the centralized-service pole of the design space.
Zanzibar-class systems own relationship data for whole fleets; kunloria
is an embedded, write-path, per-deployment decision function that
complements rather than replaces them.

### SpiceDB on consistency

*Consistency is the Key to Performance and Safety*, authzed blog.
<https://authzed.com/blog/consistency-is-the-key-to-performance-and-safety>

> Both SpiceDB and Zanzibar combine performance, scalability, and
> correctness into one manageable, global authorization solution.
> Strong consistency is key to ensuring correctness, but caching is
> necessary for performance.

**For kunloria:** the hardest problem of the centralized pole —
consistent caching across a global relationship store — is a problem
kunloria structurally does not have: a policy deployment is stateless,
and its fail-closed boundary (`Abstain` → `Deny`, malformed → 400 →
denied) is local and deterministic.
