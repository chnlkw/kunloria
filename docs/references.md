# References — related work, honestly cited

Kunloria stands on thirty-plus years of work on authorization logics,
policy languages, and verified decision procedures. This file maps that
landscape relative to what kunloria does.

Ground rules for this file, because an open-source project must be
honest about its sources and about itself:

- **Provenance.** The decisions in ADR-0001 predate this survey; none
  of the works below motivated them. This file was compiled afterwards
  to position kunloria in the landscape. Accordingly, every "For
  kunloria" note below states a *comparison* — what the source does and
  what kunloria does — never a derivation or an endorsement. Where
  kunloria's choice is untested against a paper's measurements, the
  note says so.
- Every quotation below is **verbatim** from a source fetched on
  **2026-09-04**. Curly quotes and line breaks are normalized to plain
  ASCII; nothing else is altered; `[...]` marks omission.
- Items we could **not** open are listed with metadata verified via
  Crossref and are explicitly marked *"no quote — not openly accessible
  at access time"* rather than paraphrased from memory.
- If a citation here is wrong, please open an issue; we will fix it.

---

## A. The decision algebra vs `verdict/`

Kunloria's `Effect { Allow; Deny; Abstain }` lattice with
deny-dominating `and_`, allow-dominating `or_`, and a finalize step
that turns `Abstain` into `Deny` (fail-closed) sits in the design
region XACML occupies.

### OASIS XACML 3.0 core specification (primary standard)

OASIS, *eXtensible Access Control Markup Language (XACML) Version 3.0*,
2013. <http://docs.oasis-open.org/xacml/3.0/xacml-3.0-core-spec-os-en.html>

> Authorization decision — The result of evaluating applicable policy,
> returned by the PDP to the PEP. A function that evaluates to "Permit",
> "Deny", "Indeterminate" or "NotApplicable", and (optionally) a set of
> obligations and advice

> If a rule evaluates to "False", then it returns a result of
> "NotApplicable". If an error occurs when evaluating the rule, then
> the rule returns a result of "Indeterminate".

> C.2 Deny-overrides — This section defines the "Deny-overrides"
> rule-combining algorithm of a policy and policy-combining algorithm of
> a policy set. This combining algorithm makes use of the extended
> "Indeterminate".

**Comparison.** XACML distinguishes no-match ("NotApplicable") from
evaluation error ("Indeterminate"), plus extended-Indeterminate
variants for combining. Kunloria's `Abstain` collapses both cases into
one value and `@engine.finalize` resolves it to `Deny` at the boundary;
`and_`/`or_` play the role combining algorithms play in XACML. The
truth tables of this collapse are pinned by tests in
`engine/policy_test.mbt`; the algebra is proved in
`verdict/lattice.mbtp`.

### The Logic of XACML

Kencana Ramli, Hanne Riis Nielson, Flemming Nielson, *The Logic of
XACML*, LNCS, 2012. DOI
[10.1007/978-3-642-35743-5_13](https://link.springer.com/chapter/10.1007/978-3-642-35743-5_13).
*No quote — not openly accessible at access time.*

**Comparison.** A formal treatment of XACML's combining operators —
the same corner of the design space `verdict/` addresses for a
three-valued system.

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

**Comparison.** The lemma names in `verdict/lattice.mbtp`
(commutativity, associativity, identities, idempotence, De Morgan,
distribution) name the same axiom family this AFP entry formalizes in
Isabelle/HOL; kunloria checks its three-valued variant in Why3 via
`moon prove`.

---

## B. Verification-guided engines vs the `verdict/` + `moon prove` loop

### Cedar

Joseph W. Cutler, Craig Disselkoen, Aaron Eline, Shaobo He, Kyle
Headley, Michael Hicks, Kesha Hietala, et al., *Cedar: A New Language
for Expressive, Fast, Safe, and Analyzable Authorization (Extended
Version)*, arXiv, 2024. <https://arxiv.org/abs/2403.04651>

> Cedar is a new authorization policy language designed to be
> ergonomic, fast, safe, and analyzable. Rather than embed authorization
> logic in an application's code, developers can write that logic as
> Cedar policies and delegate access decisions to Cedar's evaluation
> engine.

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

**Comparison.** Cedar's abstract states a preference — "rather than
embed authorization logic in an application's code" — that is the exact
opposite of ADR-0001's choice; kunloria stands deliberately on the
other side of that stated line. What the two share is the verification
posture: Cedar models its language in Lean and proves properties of
the design; kunloria proves its decision algebra in Why3
(`verdict/lattice.mbtp`). Cedar additionally gets policy-level analysis
from its logical encoding ("when refactoring a set of policies, the
authorized permissions do not change"); kunloria has no equivalent
today — the nearest artifact is truth-table tests per policy.

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

**Comparison.** Their verification target is the *configuration state
of a running cluster* (deployed RBAC and admission rules); kunloria's
is the *decision algebra* plus whatever properties a policy author
proves of their own function (`docs/verification.md`). The objects are
different, and neither subsumes the other.

---

## C. Policy-language lineage vs ADR-0001

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

**Comparison.** ABLP treats authorization as a logic over principals
speaking for principals. Kunloria's `Subject { user, groups }` carries
no delegation reasoning; it is the flat subject that the Kubernetes
and RGW authentication layers actually hand over.

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

**Comparison.** SecPAL evaluates policies by deduction over logical
clauses — the ancestor of Datalog-style engines such as Rego. Kunloria
has no deduction engine: the host compiler evaluates an ordinary
function, and composition is by three lattice combinators.

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

**Comparison.** The SACMAT paper asks what an ABAC *language* must be
able to express; the Haskell paper encodes authorization semantics as
typed functional programs rather than an interpreted DSL — the corner
ADR-0001 also occupies. Kunloria's answer to the expressiveness
question is uninteresting by design: anything the host language
expresses, inside `Query -> Decision`.

---

## D. Policy-as-Code empirics

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

**Comparison.** This study measures the declarative-file PaC landscape
(many files, nine tools) that ADR-0001 departs from — one typed
function per deployment. ADR-0001 predates this survey, so it is not
evidence for that decision; whether the one-function structure avoids
the maintenance costs this study measures has not been established.

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

**Comparison.** The measured problem is governance rules implemented
independently per enforcement stage drifting apart. In kunloria both
fronts call the same `policy` function, so the reuse structure is
different; whether that prevents the measured drift is not established
here.

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

**Comparison.** Describes the delivery channel kunloria assumes — git
as source of truth, controllers reconciling, policy enforced
continuously.

---

## E. Embedded-engine precedents vs the library shape

### oso / Polar

*oso*, open-source project.
<https://github.com/osohq/oso>

> Oso is a batteries-included framework for building authorization in
> your application.

> Set up common permissions patterns like role-based access control
> (RBAC) and relationships using Oso's built-in primitives. Extend them
> however you need with Oso's declarative policy language, Polar.

**Comparison.** oso embeds as a library but couples it with a DSL,
Polar; kunloria embeds without a DSL (ADR-0001). The projects made
different choices; this entry records the neighbor, not a verdict.

### Margrave

*Margrave: An API for XACML Policy Verification and Change Analysis*,
Brown PLT. <http://www.margrave-tool.org/v1+v2/margrave/>

> An API for XACML Policy Verification and Change Analysis

**Comparison.** Answers "what decisions changed?" over XACML policy
edits. Kunloria has no such tool; the cheap nearest artifact is
diffing truth-table outputs of a policy function before and after an
edit.

---

## F. Centralized scale-out vs what kunloria is not

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

**Comparison.** Zanzibar-class systems are centralized stores of
relationship data serving whole fleets. Kunloria is a per-deployment,
stateless decision function for two write-path fronts; it does not
store relationships or serve read-path authorization.

### SpiceDB on consistency

*Consistency is the Key to Performance and Safety*, authzed blog.
<https://authzed.com/blog/consistency-is-the-key-to-performance-and-safety>

> Both SpiceDB and Zanzibar combine performance, scalability, and
> correctness into one manageable, global authorization solution.
> Strong consistency is key to ensuring correctness, but caching is
> necessary for performance.

**Comparison.** The caching-versus-consistency tension these systems
manage arises from centralized state. A kunloria deployment holds no
state; its fail-closed boundary (`Abstain` → `Deny`, malformed → 400 →
denied) is a local, deterministic function of the request.
