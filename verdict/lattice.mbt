// verdict/lattice.mbt — executable side of the decision lattice.
//
// Kunloria composes policies over a three-valued logic (Kleene):
//
//   - `combine_and` (conjunction): a Deny dominates; Abstain propagates;
//     only Allow ∧ Allow yields Allow.
//   - `combine_or` (disjunction): an Allow dominates; Abstain propagates;
//     only Deny ∨ Deny yields Deny.
//   - `negate`: Allow ↔ Deny, Abstain stays Abstain.
//
// The engine's boundary converts ABSTAIN to DENY (fail-closed), so the
// lattice's "unknown" never escapes as an allow.

///|
/// Effect code: allow.
pub const ALLOW : Int = 0

///|
/// Effect code: deny.
pub const DENY : Int = 1

///|
/// Effect code: abstain (no opinion; the engine finalizes it to DENY).
pub const ABSTAIN : Int = 2

///|
/// Whether `code` is one of the three effects.
#proof_pure
pub fn valid_code(code : Int) -> Bool {
  code == ALLOW || code == DENY || code == ABSTAIN
}

///|
/// Conjunction of two effects: Deny dominates, Abstain propagates,
/// Allow ∧ Allow = Allow.
#proof_pure
pub fn combine_and(
  a : Int,
  b : Int,
) -> Int where {
  proof_require: valid_code(a) && valid_code(b),
  proof_ensure: result => and_ok(a, b, result),
} {
  if a == DENY || b == DENY {
    DENY
  } else if a == ABSTAIN || b == ABSTAIN {
    ABSTAIN
  } else {
    ALLOW
  }
}

///|
/// Disjunction of two effects: Allow dominates, Abstain propagates,
/// Deny ∨ Deny = Deny.
#proof_pure
pub fn combine_or(
  a : Int,
  b : Int,
) -> Int where {
  proof_require: valid_code(a) && valid_code(b),
  proof_ensure: result => or_ok(a, b, result),
} {
  if a == ALLOW || b == ALLOW {
    ALLOW
  } else if a == ABSTAIN || b == ABSTAIN {
    ABSTAIN
  } else {
    DENY
  }
}

///|
/// Negation: Allow ↔ Deny, Abstain stays Abstain.
#proof_pure
pub fn negate(
  a : Int,
) -> Int where {
  proof_require: valid_code(a),
  proof_ensure: result => negate_ok(a, result),
} {
  if a == ALLOW {
    DENY
  } else if a == DENY {
    ALLOW
  } else {
    ABSTAIN
  }
}
