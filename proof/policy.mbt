// proof/policy.mbt — executable side of the verified decision core.
//
// The functions below are marked `#proof_pure` so the same definitions are
// visible to the program side (every other Kunloria package calls them at
// runtime) and to the logic side (the predicates and lemmas in policy.mbtp
// reason about them). Contracts are discharged by `moon prove`.

///|
/// Role code: unrestricted administrator.
pub const ROLE_ADMIN : Int = 0

///|
/// Role code: read-only access within the group namespace.
pub const ROLE_READER : Int = 1

///|
/// Role code: write access within the group namespace.
pub const ROLE_WRITER : Int = 2

///|
/// Role code: no known role (group maps to no role).
pub const ROLE_NONE : Int = 3

///|
/// Action-kind code: read operations (GET / HEAD / LIST).
pub const KIND_READ : Int = 0

///|
/// Action-kind code: write operations (PUT / POST / DELETE / PATCH).
pub const KIND_WRITE : Int = 1

///|
/// Action-kind code: verbs outside the Reader/Writer alphabets.
pub const KIND_UNKNOWN : Int = 2

///|
/// Decide whether `role` may perform an action of `kind` on a resource whose
/// group prefix matched (`prefix_ok`) the role's group namespace.
///
/// Verified properties (see policy.mbtp):
/// - an Admin is always allowed;
/// - a Reader is never allowed a write;
/// - a Writer is never allowed a read;
/// - anyone but an Admin is denied when the group prefix does not match.
#proof_pure
pub fn decide(
  role : Int,
  kind : Int,
  prefix_ok : Bool,
) -> Bool where {
  proof_require: valid_role(role) && valid_kind(kind),
  proof_ensure: result => decision_ok(role, kind, prefix_ok, result),
} {
  if role == ROLE_ADMIN {
    true
  } else if !prefix_ok {
    false
  } else if role == ROLE_READER {
    kind == KIND_READ
  } else if role == ROLE_WRITER {
    kind == KIND_WRITE
  } else {
    false
  }
}

///|
/// Whether `code` is one of the four defined roles.
#proof_pure
pub fn valid_role(code : Int) -> Bool {
  code == ROLE_ADMIN ||
  code == ROLE_READER ||
  code == ROLE_WRITER ||
  code == ROLE_NONE
}

///|
/// Whether `code` is one of the three defined action kinds.
#proof_pure
pub fn valid_kind(code : Int) -> Bool {
  code == KIND_READ || code == KIND_WRITE || code == KIND_UNKNOWN
}
