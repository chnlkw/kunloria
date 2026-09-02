// engine/decision.mbt — three-valued decisions and the fail-closed boundary.
//
// `Effect` mirrors the verified lattice in verdict/: composition happens on
// effect codes (combine_and / combine_or / negate, all under proof
// contracts); reasons ride along for audit logging and are never part of
// the algebra.

///|
/// The effect of a decision. `Abstain` means "this policy has no opinion";
/// the engine finalizes it to a denial before anything leaves the process.
pub(all) enum Effect {
  Allow
  Deny
  Abstain
} derive(Eq, @debug.Debug)

///|
/// An effect plus the reason that produced it (shown in audit logs and in
/// AdmissionReview denial messages).
pub(all) struct Decision {
  effect : Effect
  reason : String
} derive(Eq, @debug.Debug)

///|
/// A positive decision.
pub fn Decision::allow(reason : String) -> Decision {
  { effect: Allow, reason, }
}

///|
/// A negative decision.
pub fn Decision::deny(reason : String) -> Decision {
  { effect: Deny, reason, }
}

///|
/// No opinion; the engine turns this into a denial at the boundary.
pub fn Decision::abstain() -> Decision {
  { effect: Abstain, reason: "no opinion", }
}

///|
/// The lattice code of this effect.
pub fn Effect::code(self : Effect) -> Int {
  match self {
    Allow => @verdict.ALLOW
    Deny => @verdict.DENY
    Abstain => @verdict.ABSTAIN
  }
}

///|
/// The lattice code of this decision's effect.
pub fn Decision::code(self : Decision) -> Int {
  self.effect.code()
}

///|
/// Whether this is an allow.
pub fn Decision::is_allow(self : Decision) -> Bool {
  self.effect is Allow
}

///|
/// Conjunction on decisions: effects combine via the verified lattice;
/// the resulting reason comes from the side that determined the effect.
pub fn and_decision(d1 : Decision, d2 : Decision) -> Decision {
  let code = @verdict.combine_and(d1.code(), d2.code())
  if code == @verdict.DENY {
    if d1.effect is Deny {
      Decision::deny(d1.reason)
    } else {
      Decision::deny(d2.reason)
    }
  } else if code == @verdict.ALLOW {
    Decision::allow("\{d1.reason}; \{d2.reason}")
  } else {
    Decision::abstain()
  }
}

///|
/// Disjunction on decisions: effects combine via the verified lattice;
/// the resulting reason comes from the side that determined the effect.
pub fn or_decision(d1 : Decision, d2 : Decision) -> Decision {
  let code = @verdict.combine_or(d1.code(), d2.code())
  if code == @verdict.ALLOW {
    if d1.effect is Allow {
      Decision::allow(d1.reason)
    } else {
      Decision::allow(d2.reason)
    }
  } else if code == @verdict.DENY {
    Decision::deny("\{d1.reason}; \{d2.reason}")
  } else {
    Decision::abstain()
  }
}

///|
/// Negation on decisions: allow and deny swap, abstain stays abstain.
pub fn not_decision(d : Decision) -> Decision {
  match d.effect {
    Allow => Decision::deny("negated allow: \{d.reason}")
    Deny => Decision::allow("negated deny: \{d.reason}")
    Abstain => Decision::abstain()
  }
}

///|
/// The engine boundary (fail-closed): an abstain becomes a denial.
/// Every transport reply is produced through this function, which is the
/// executable counterpart of verdict's `fail_closed_exit` invariant.
pub fn finalize(d : Decision) -> Decision {
  if d.effect is Abstain {
    Decision::deny("no policy decided; failing closed")
  } else {
    d
  }
}

///|
/// Method form of `finalize`.
pub fn Decision::finalized(self : Decision) -> Decision {
  finalize(self)
}
