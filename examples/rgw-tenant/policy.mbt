// examples/rgw-tenant/policy.mbt — the kunloria v0.1 behavior as code.
//
// Three roles (admin / writer / reader) mapped from groups, group-prefix
// namespaces on RGW buckets, and Kubernetes content constraints
// (privileged pods, risky role bindings). In v0.1 these knobs were
// environment variables; per ADR-0001 they are compile-time constants
// owned by this file — change them and redeploy through your GitOps
// pipeline.

///|
/// Groups granted the admin role (always allowed inside their namespace).
fn admin_groups() -> Array[String] {
  ["platform", "admins"]
}

///|
/// Groups granted the writer role (write access inside their namespace).
fn writer_groups() -> Array[String] {
  ["writers"]
}

///|
/// Groups granted the reader role (read-only inside their namespace).
fn reader_groups() -> Array[String] {
  ["readers"]
}

///|
/// RoleBinding targets that may receive risky roles; everything else is
/// denied. "<namespace>:<serviceaccount>" identifies a ServiceAccount.
fn admitted_bindings() -> Array[String] {
  ["kube-system:boundary-automation"]
}

///|
/// ClusterRoles nobody may bind (except admitted service accounts).
fn risky_roles() -> Array[String] {
  ["cluster-admin", "system:node"]
}

///|
/// The most privileged role a subject holds (admin > writer > reader).
fn role_of(groups : Array[String]) -> String {
  if has_any(groups, admin_groups()) {
    "admin"
  } else if has_any(groups, writer_groups()) {
    "writer"
  } else if has_any(groups, reader_groups()) {
    "reader"
  } else {
    "none"
  }
}

///|
/// Whether `groups` and `wanted` share at least one entry.
fn has_any(groups : Array[String], wanted : Array[String]) -> Bool {
  for g in wanted {
    if groups.contains(g) {
      return true
    }
  }
  false
}

///|
/// Whether the admitted ServiceAccount subject is on the allow list.
fn binding_subject_admitted(binding : Json) -> Bool {
  if binding is { "subjects": Array(subjects), .. } {
    for subject in subjects {
      if subject
        is {
          "kind": "ServiceAccount",
          "namespace": String(ns),
          "name": String(name),
          ..
        } {
        if admitted_bindings().contains("\{ns}:\{name}") {
          return true
        }
      }
    }
  }
  false
}

///|
/// The deployed policy.
pub fn policy(q : @engine.Query) -> @engine.Decision {
  let role = role_of(q.subject.groups)
  if role == "admin" {
    return @engine.Decision::allow("admin group")
  }
  match q.source {
    Rgw => rgw_decision(q, role)
    K8sAdmission => k8s_decision(q)
  }
}

///|
/// RGW: group-prefix namespaces — a subject may only touch paths under
/// one of its groups; readers read, writers write.
fn rgw_decision(q : @engine.Query, role : String) -> @engine.Decision {
  let path = q.rgw_path().unwrap_or("")
  let mut in_own_ns = false
  for g in q.subject.groups {
    if @engine.path_in_namespace(path, g) {
      in_own_ns = true
      break
    }
  }
  if !in_own_ns {
    return @engine.Decision::deny(
      "resource \{path} is outside every group namespace of the subject",
    )
  }
  if role == "none" {
    return @engine.Decision::deny("subject holds no role")
  }
  let readable = q.kind is @engine.AccessKind::ReadAccess
  if role == "reader" && readable {
    return @engine.Decision::allow("reader in own namespace")
  }
  if role == "writer" && q.kind is @engine.AccessKind::WriteAccess {
    return @engine.Decision::allow("writer in own namespace")
  }
  @engine.Decision::deny("role \{role} may not perform \{q.verb}")
}

///|
/// Kubernetes admission: content constraints RBAC cannot express.
/// Everything the policy does not object to is allowed.
fn k8s_decision(q : @engine.Query) -> @engine.Decision {
  if q.object is Some(obj) {
    if @k8s.target_kind_is(q, "Pod") && @k8s.pod_has_privileged_container(obj) {
      return @engine.Decision::deny("privileged containers are not allowed")
    }
    if (
        @k8s.target_kind_is(q, "RoleBinding") ||
        @k8s.target_kind_is(q, "ClusterRoleBinding")
      ) &&
      @k8s.binding_grants_risky_role(obj, risky_roles()) {
      if binding_subject_admitted(obj) {
        return @engine.Decision::allow(
          "risky role bound by an admitted service account",
        )
      }
      return @engine.Decision::deny("binding a risky role is not allowed")
    }
  }
  @engine.Decision::allow("no content constraint violated")
}
