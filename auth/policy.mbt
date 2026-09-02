// auth/policy.mbt — the authorization policy of Kunloria.
//
// `authorize` is a thin, auditable wrapper around the verified decision
// core: it resolves the group-prefix fact, delegates to `@proof.decide`,
// and turns the boolean into a `Decision` carrying an audit reason.

///|
/// Whether a resource path belongs to a group namespace: the path either
/// equals the group name or is nested under `"<group>/"`.
pub fn path_in_group(path : String, group : String) -> Bool {
  if group == "" {
    false
  } else if path == group {
    true
  } else {
    path.has_prefix("\{group}/")
  }
}

///|
/// The first group of `groups` whose namespace contains `path`, if any.
pub fn matching_group(path : String, groups : Array[String]) -> String? {
  for group in groups {
    if path_in_group(path, group) {
      return Some(group)
    }
  }
  None
}

///|
/// Core authorization.
///
/// Rules (implemented by the verified core in `proof/`):
/// - Admin: every action allowed, no prefix restriction.
/// - Reader: read actions only, and only inside a group-owned prefix.
/// - Writer: write actions only, and only inside a group-owned prefix.
/// - Any other role: denied.
///
/// The `resource_path` is the hierarchical resource identifier
/// (object key, or bucket for bucket-level operations).
pub fn authorize(
  subject : Subject,
  kind : ActionKind,
  resource_path : String,
) -> Decision {
  let group = matching_group(resource_path, subject.groups)
  let prefix_ok = group is Some(_)
  // The load-bearing call: this boolean is the one `moon prove` reasons about.
  let allowed = @proof.decide(subject.role.code(), kind.code(), prefix_ok)
  if allowed {
    let scope = match group {
      Some(g) => g
      None => "*"
    }
    Decision::allow(
      subject.role,
      "role \{subject.role.name()} permits \{kind_name(kind)} access within group '\{scope}'",
    )
  } else if subject.role == NoRole {
    Decision::deny(
      subject.role,
      "user '\{subject.id}' belongs to no role-mapped group",
    )
  } else if group is None {
    Decision::deny(
      subject.role,
      "resource '\{resource_path}' is outside every group namespace of user '\{subject.id}'",
    )
  } else {
    Decision::deny(
      subject.role,
      "role \{subject.role.name()} does not permit \{kind_name(kind)} access",
    )
  }
}

///|
/// Lowercase name of an action kind, for audit reasons.
fn kind_name(kind : ActionKind) -> String {
  match kind {
    Read => "read"
    Write => "write"
    Unknown => "unknown"
  }
}
