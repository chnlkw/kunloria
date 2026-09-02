// auth — policy types shared by every Kunloria front end.
//
// Types here mirror the integer codes of the verified core in `proof/`;
// `Role::code` and `ActionKind::code` are the only bridge between the
// typed world and `@proof.decide`.

///|
/// Role of a subject. Codes: Admin = 0, Reader = 1, Writer = 2, NoRole = 3.
pub(all) enum Role {
  Admin
  Reader
  Writer
  NoRole
} derive(Eq, @debug.Debug)

///|
/// Map a role to its code in the verified decision core.
pub fn Role::code(self : Role) -> Int {
  match self {
    Admin => @proof.ROLE_ADMIN
    Reader => @proof.ROLE_READER
    Writer => @proof.ROLE_WRITER
    NoRole => @proof.ROLE_NONE
  }
}

///|
/// Human-readable name of a role (also used in audit reasons).
pub fn Role::name(self : Role) -> String {
  match self {
    Admin => "admin"
    Reader => "reader"
    Writer => "writer"
    NoRole => "none"
  }
}

///|
/// Kind of access an action requests.
/// Codes: Read = 0, Write = 1, Unknown = 2.
pub(all) enum ActionKind {
  Read
  Write
  Unknown
} derive(Eq, @debug.Debug)

///|
/// Map an action kind to its code in the verified decision core.
pub fn ActionKind::code(self : ActionKind) -> Int {
  match self {
    Read => @proof.KIND_READ
    Write => @proof.KIND_WRITE
    Unknown => @proof.KIND_UNKNOWN
  }
}

///|
/// The outcome of a policy evaluation: an effect plus an audit reason.
pub(all) struct Decision {
  allowed : Bool
  role : Role
  reason : String
} derive(Eq, @debug.Debug)

///|
/// Construct an allowing decision.
pub fn Decision::allow(role : Role, reason : String) -> Decision {
  { allowed: true, role, reason, }
}

///|
/// Construct a denying decision.
pub fn Decision::deny(role : Role, reason : String) -> Decision {
  { allowed: false, role, reason, }
}

///|
/// Group-to-role mapping injected via configuration (environment variables
/// in the MVP; see server/config). A group both names the tenant namespace
/// (path prefix) and selects the role.
pub(all) struct PolicyConfig {
  admin_groups : Array[String]
  reader_groups : Array[String]
  writer_groups : Array[String]
} derive(Eq, @debug.Debug)

///|
/// Build a policy configuration from explicit group lists.
pub fn PolicyConfig::of_groups(
  admin? : Array[String] = ["admin"],
  reader? : Array[String] = ["reader", "readers"],
  writer? : Array[String] = ["writer", "writers"],
) -> PolicyConfig {
  { admin_groups: admin, reader_groups: reader, writer_groups: writer, }
}

///|
/// The role a group grants. A group appears in at most one list; when
/// configuration overlaps, the most privileged role wins
/// (Admin > Writer > Reader).
pub fn PolicyConfig::role_for_group(
  self : PolicyConfig,
  group : String,
) -> Role {
  if self.admin_groups.contains(group) {
    Admin
  } else if self.writer_groups.contains(group) {
    Writer
  } else if self.reader_groups.contains(group) {
    Reader
  } else {
    NoRole
  }
}

///|
/// The role granted by a subject's group set, most privileged first.
pub fn PolicyConfig::role_for_groups(
  self : PolicyConfig,
  groups : Array[String],
) -> Role {
  let mut role = NoRole
  for group in groups {
    let granted = self.role_for_group(group)
    if granted == Admin {
      return Admin
    } else if granted == Writer {
      role = Writer
    } else if granted == Reader && role == NoRole {
      role = Reader
    }
  }
  role
}

///|
/// A user or service account requesting access.
pub(all) struct Subject {
  id : String
  groups : Array[String]
  role : Role
} derive(Eq, @debug.Debug)

///|
/// Build the subject for a user id with its groups under a policy.
pub fn PolicyConfig::subject_for(
  self : PolicyConfig,
  id~ : String,
  groups~ : Array[String],
) -> Subject {
  { id, groups, role: self.role_for_groups(groups), }
}
