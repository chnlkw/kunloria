// engine/query.mbt — the structured question every policy answers.
//
// Parsers (k8s/, ceph/) lower their wire payloads into `Query`; policies
// never see raw JSON except through `object` when the source carries one.

///|
/// Which front end produced the query.
pub(all) enum Source {
  K8sAdmission
  Rgw
} derive(Eq, @debug.Debug)

///|
/// Coarse classification of the verb, computed by the parser.
/// Unknown verbs classify as `UnknownAccess` — never as read or write.
pub(all) enum AccessKind {
  ReadAccess
  WriteAccess
  UnknownAccess
} derive(Eq, @debug.Debug)

///|
/// A Kubernetes resource reference (`Target::K8s`).
pub(all) struct K8sRef {
  api_group : String // "" for the core group
  kind : String // e.g. "Pod", singular form from the request
  resource : String // e.g. "pods", best-effort plural of `kind`
  subresource : String // "" when absent
  name : String // "" when the request has no single object
  ns : String // "" for cluster-scoped objects
} derive(Eq, @debug.Debug)

///|
/// A Ceph RGW object reference (`Target::Rgw`).
pub(all) struct RgwRef {
  bucket : String
  object_key : String // "" for bucket-level operations
} derive(Eq, @debug.Debug)

///|
/// What the request wants to touch.
pub(all) enum Target {
  K8s(K8sRef)
  Rgw(RgwRef)
  Unrecognized(String)
} derive(Eq, @debug.Debug)

///|
/// The authenticated requester.
pub(all) struct Subject {
  user : String // user id or ServiceAccount name
  groups : Array[String]
} derive(Eq, @debug.Debug)

///|
/// The authorization question. `object` carries the full admitted object
/// for Kubernetes admission requests and is `None` everywhere else.
pub(all) struct Query {
  source : Source
  subject : Subject
  verb : String // lower-cased source verb, e.g. "create", "s3:getobject"
  kind : AccessKind
  target : Target
  object : Json?
}

///|
/// Namespace of a Kubernetes query, if any.
pub fn Query::ns(self : Query) -> String? {
  if self.target is K8s(kref) && kref.ns != "" {
    Some(kref.ns)
  } else {
    None
  }
}

///|
/// Whether `path` lies inside the namespace of one of `groups`.
pub fn path_in_any_namespace(path : String, groups : Array[String]) -> Bool {
  for g in groups {
    if path_in_namespace(path, g) {
      return true
    }
  }
  false
}

///|
/// Whether the subject acts inside its own namespace on either front end:
/// on Kubernetes the target namespace is one of its groups; on RGW the
/// resource path lies inside one of its group namespaces. Everything
/// else — other namespaces, other buckets, unrecognized targets — is out
/// of scope. This is the one gate that means the same thing on both
/// fronts, so "a tenant may act inside its own namespace" is a single
/// predicate instead of a per-source `match`.
pub fn Query::in_own_namespace(self : Query) -> Bool {
  match self.target {
    K8s(_) =>
      if self.ns() is Some(ns) {
        self.subject.groups.contains(ns)
      } else {
        false
      }
    Rgw(_) =>
      if self.rgw_path() is Some(path) {
        path_in_any_namespace(path, self.subject.groups)
      } else {
        false
      }
    Unrecognized(_) => false
  }
}

///|
/// Hierarchical RGW resource path: `"<bucket>/<object_key>"`, or just the
/// bucket name for bucket-level operations. Group namespaces are matched
/// against this joined path, so a group "team-a" owns bucket `team-a` and
/// everything in it.
pub fn Query::rgw_path(self : Query) -> String? {
  if self.target is Rgw(rref) {
    if rref.object_key == "" {
      Some(rref.bucket)
    } else {
      Some("\{rref.bucket}/\{rref.object_key}")
    }
  } else {
    None
  }
}

///|
/// Whether `path` lies inside the group namespace `group`: the path either
/// equals the group name or is nested under `"<group>/"`.
pub fn path_in_namespace(path : String, group : String) -> Bool {
  if group == "" {
    false
  } else if path == group {
    true
  } else {
    path.has_prefix("\{group}/")
  }
}
