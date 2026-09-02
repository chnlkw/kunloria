// engine/policy.mbt — the policy entry point, atoms and combinators.
//
// A policy is one pure function from `Query` to `Decision`. Everything in
// this file is about assembling such functions: decision atoms, predicate
// atoms (match -> Allow, else -> Abstain), and combinators built on the
// verified lattice in verdict/.

///|
/// The type every user policy implements.
pub type Policy = (Query) -> Decision

///|
/// Runs a policy against a query.
pub fn decide(policy : Policy, query : Query) -> Decision {
  policy(query)
}

// ---------------------------------------------------------------------------
// Decision atoms
// ---------------------------------------------------------------------------

///|
/// Allows everything.
pub fn allow_all(_q : Query) -> Decision {
  Decision::allow("allow_all")
}

///|
/// Denies everything.
pub fn deny_all(_q : Query) -> Decision {
  Decision::deny("deny_all")
}

///|
/// Never decides; useful only as a `otherwise` fallback terminator.
pub fn abstain_all(_q : Query) -> Decision {
  Decision::abstain()
}

// ---------------------------------------------------------------------------
// Predicate atoms: on match they Allow, otherwise they Abstain
// ---------------------------------------------------------------------------

///|
/// Allows when the subject is exactly `user`.
pub fn subject_is(user : String) -> Policy {
  q => {
    if q.subject.user == user {
      Decision::allow("subject is \{user}")
    } else {
      Decision::abstain()
    }
  }
}

///|
/// Allows when the subject belongs to `group`.
pub fn subject_in_group(group : String) -> Policy {
  q => {
    if q.subject.groups.contains(group) {
      Decision::allow("subject in group \{group}")
    } else {
      Decision::abstain()
    }
  }
}

///|
/// Allows when the (lower-cased) verb is one of `verbs`, e.g. "create".
pub fn verb_in(verbs : Array[String]) -> Policy {
  q => {
    if verbs.contains(q.verb) {
      Decision::allow("verb \{q.verb}")
    } else {
      Decision::abstain()
    }
  }
}

///|
/// Allows when the request classifies as `kind` (read / write / unknown).
pub fn kind_is(kind : AccessKind) -> Policy {
  q => {
    if q.kind == kind {
      Decision::allow("verb \{q.verb} matches the requested access kind")
    } else {
      Decision::abstain()
    }
  }
}

///|
/// Allows when the target object lives in namespace `ns`.
pub fn ns_is(ns : String) -> Policy {
  q => {
    if q.ns() == Some(ns) {
      Decision::allow("namespace \{ns}")
    } else {
      Decision::abstain()
    }
  }
}

///|
/// Allows when the target is a Kubernetes object of `kind`
/// (e.g. "Pod", "RoleBinding").
pub fn k8s_kind_is(kind : String) -> Policy {
  q => {
    if q.target is K8s(kref) && kref.kind == kind {
      Decision::allow("kubernetes \{kind}")
    } else {
      Decision::abstain()
    }
  }
}

///|
/// Allows when the target is the Kubernetes resource `resource`
/// (plural form, e.g. "pods", "rolebindings").
pub fn k8s_resource_is(resource : String) -> Policy {
  q => {
    if q.target is K8s(kref) && kref.resource == resource {
      Decision::allow("kubernetes \{resource}")
    } else {
      Decision::abstain()
    }
  }
}

///|
/// Allows when this is an RGW request whose resource path (object key, or
/// bucket for bucket-level operations) lies inside one of the subject's
/// group namespaces: the path equals the group or starts with `"<group>/"`.
pub fn rgw_path_in_group_ns() -> Policy {
  q => {
    match q.rgw_path() {
      Some(path) => {
        let mut in_ns = false
        for group in q.subject.groups {
          if path_in_namespace(path, group) {
            in_ns = true
            break
          }
        }
        if in_ns {
          Decision::allow("path \{path} inside a group namespace")
        } else {
          Decision::abstain()
        }
      }
      None => Decision::abstain()
    }
  }
}

// ---------------------------------------------------------------------------
// Combinators (effects combine through the verified lattice)
// ---------------------------------------------------------------------------

///|
/// Both policies must allow; a denial on either side denies.
pub fn and_(p1 : Policy, p2 : Policy) -> Policy {
  q => and_decision(p1(q), p2(q))
}

///|
/// Either policy may allow; both must deny to deny.
pub fn or_(p1 : Policy, p2 : Policy) -> Policy {
  q => or_decision(p1(q), p2(q))
}

///|
/// Flips allow and deny; abstain stays abstain.
pub fn not_(p : Policy) -> Policy {
  q => not_decision(p(q))
}

///|
/// Takes the first policy's decision unless it abstains, then falls back
/// to the second. Chain with `abstain_all` as the final fallback to make
/// unmatched requests fail closed.
pub fn otherwise(p1 : Policy, p2 : Policy) -> Policy {
  q => {
    let d1 = p1(q)
    if d1.effect is Abstain {
      p2(q)
    } else {
      d1
    }
  }
}

///|
/// Restricts `body` to queries satisfying `guard`; everything else is
/// denied with the given reason. Unlike predicate atoms (which abstain),
/// `scoped` is a hard boundary.
pub fn scoped(
  gate : (Query) -> Bool,
  body : Policy,
  reason? : String,
) -> Policy {
  q => {
    if gate(q) {
      body(q)
    } else {
      Decision::deny("out of scope: \{reason.unwrap_or("guard failed")}")
    }
  }
}
