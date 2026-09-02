# Formal verification

Kunloria's decision algebra — what every composed policy ultimately
evaluates through — lives in the `verdict/` package, a tiny integer-level
core that MoonBit's `moon prove` verifies with Why3 + SMT solvers.

## What is verified

`verdict/lattice.mbt` defines three pure functions with proof contracts:

- `combine_and(a, b)` — Kleene conjunction: a deny dominates, abstain
  propagates, only allow ∧ allow yields allow;
- `combine_or(a, b)` — Kleene disjunction: an allow dominates, abstain
  propagates, only deny ∨ deny yields deny;
- `negate(a)` — allow ↔ deny, abstain stays abstain.

`verdict/lattice.mbtp` proves, for **all** inputs:

| Lemma family | Statement |
| --- | --- |
| `and_/or_ commutative, associative` | the lattice is a proper algebra |
| `and_/or_ identity` | `ALLOW` for `and_`, `DENY` for `or_` |
| `and_/or_ idempotent` | composing a policy with itself changes nothing |
| `negate_involution` | double negation is the identity |
| `de_morgan_and/or` | negation distributes over both operations |
| `and_/or_ distributes` | full distributive lattice |
| `fail_closed_exit` / `abstain_never_allows` | **the engine boundary invariant**: finalizing an abstain can only yield a denial |

The last family is the load-bearing property: policies may abstain (that
is how `otherwise` composes), but an abstain can never escape the engine
as an allow. `engine/decision.mbt::finalize` is the executable
counterpart.

## What is *not* verified — and what backs it instead

Parsers (`k8s/`, `ceph/`) and policies are plain MoonBit, outside the
SMT model. Their fail-closed discipline is backed by **truth-table
tests**: malformed payloads, missing fields, wrong types and unknown
verbs are all pinned to deny/400 by `moon test` (see the
`parse_test.mbt` files and each example's `policy_test.mbt`).

## Running the verifier

`moon prove` needs external tooling (not bundled with the MoonBit
toolchain):

```sh
# Why3 1.7.x (recommended via opam) and one solver, e.g. z3
opam install why3=1.7.2 z3
why3 config detect
```

Then:

```sh
make prove        # runs: moon prove verdict
```

Without why3/z3 installed, the contracts still type-check under
`moon check` and the executable tables are pinned by `moon test`.

## Proving your own policy

The pattern scales to policy code: keep decision helpers `#proof_pure`
over ints/enums, state predicates and lemmas in a `.mbtp` file next to
the code, and let `moon prove` discharge them. The verified lattice
means combinator-level properties (see
[the author guide](policy-author-guide.md)) come for free — you only
prove what is specific to *your* policy.
