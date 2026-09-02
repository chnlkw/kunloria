// k8s/inspect.mbt — content predicates over the admitted object.
//
// Building blocks for content-constraint policies (the part of admission
// authorization RBAC cannot express). Pure Json predicates via map
// patterns; the policy decides what to do with them.

///|
/// Whether the query targets Kubernetes objects of `kind`
/// (e.g. "Pod", "RoleBinding").
pub fn target_kind_is(q : @engine.Query, kind : String) -> Bool {
  q.target is @engine.Target::K8s(kref) && kref.kind == kind
}

///|
/// Whether the query targets Pods (shorthand for target_kind_is(_, "Pod")).
pub fn targets_pod(q : @engine.Query) -> Bool {
  target_kind_is(q, "Pod")
}

///|
/// Whether any container (regular or init) of this Pod object runs
/// privileged.
pub fn pod_has_privileged_container(pod : Json) -> Bool {
  if pod is { "spec": { "containers"? : cs, "initContainers"? : ic, .. }, .. } {
    scan_containers(cs) || scan_containers(ic)
  } else {
    false
  }
}

///|
fn scan_containers(containers : Json?) -> Bool {
  if containers is Some(Array(list)) {
    for c in list {
      if c is { "securityContext": { "privileged": True, .. }, .. } {
        return true
      }
    }
  }
  false
}

///|
/// Whether this RoleBinding/ClusterRoleBinding object references any of
/// the `risky` role names (e.g. cluster-admin).
pub fn binding_grants_risky_role(binding : Json, risky : Array[String]) -> Bool {
  if binding is { "roleRef": { "name": String(role_name), .. }, .. } {
    risky.contains(role_name)
  } else {
    false
  }
}
