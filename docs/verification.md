# Formal verification

Kunloria's load-bearing decision — *who may do what inside which namespace* —
lives in the `proof/` package, a tiny integer-level core that MoonBit's
`moon prove` verifies with Why3 + SMT solvers.

## What is verified

`proof/policy.mbt` defines `#proof_pure fn decide(role, kind, prefix_ok)` with
a contract in terms of the predicates of `proof/policy.mbtp`:

* **Property 1** — a Reader can never obtain a write grant
  (`lemma reader_never_writes`);
* **Property 2** — an Admin is always allowed
  (`lemma admin_always_allowed`);
* **Property 3** — without a matching group prefix no non-admin role is
  allowed (`lemma group_isolation`, i.e. cross-group access is impossible).

Every runtime decision in `auth/policy.mbt` delegates to this verified core;
the typed layers (auth/k8s/ceph/server) only translate wire formats and
attach audit reasons, and are covered by `moon test` (39 tests).

## Running the verifier

`moon prove` needs external tooling (not bundled with the MoonBit toolchain):

```sh
# Why3 1.7.x (recommended via opam) and one solver, e.g. z3
opam install why3=1.7.2 z3
why3 config detect

# from the repo root
make prove        # = moon prove proof
```

The command lowers the proof-enabled package (`options("proof-enabled": true)`
in `proof/moon.pkg`) to WhyML, generates proof obligations from the
contracts, and dispatches them to the solver.

## Trust boundary

Verified: the boolean decision core (`proof/`).
Tested, not proved: JSON parsing of AdmissionReview/RGW payloads, HTTP
transport, logging, metrics. Fail-closed behaviour of the unverified layers
is pinned by tests such as "malformed review fails closed".
