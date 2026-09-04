// examples/rgw-tenant/policy.mbt — the kunloria v0.1 behavior as code.
//
// Policy, in plain words:
//   1. admins are always allowed — on Kubernetes admission too, where
//      this deployment deliberately lets them bypass the content
//      constraints (examples/k8s-write-authz makes the opposite
//      choice: constraints that bind everyone, admins included);
//   2. on RGW, a subject may only touch paths inside one of its group
//      namespaces: readers read, writers write, nobody else acts;
//   3. on Kubernetes admission, deny privileged pods and risky role
//      bindings — an admitted service account may still bind them —
//      and allow everything else.
//
// In v0.1 these knobs were environment variables; per ADR-0001 they are
// compile-time constants owned by this file — change them and redeploy
// through your GitOps pipeline.

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
/// The roles a subject can hold, most privileged first. An enum — not
/// strings — so the compiler checks every layer below covers each case.
priv enum Role {
  Admin
  Writer
  Reader
  Roleless
}

///|
/// The reason-facing name of the role.
fn Role::label(self : Role) -> String {
  match self {
    Admin => "admin"
    Writer => "writer"
    Reader => "reader"
    Roleless => "none"
  }
}

///|
/// The most privileged role a subject holds (admin > writer > reader).
fn role_of(groups : Array[String]) -> Role {
  if has_any(groups, admin_groups()) {
    Admin
  } else if has_any(groups, writer_groups()) {
    Writer
  } else if has_any(groups, reader_groups()) {
    Reader
  } else {
    Roleless
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
/// The deployed policy: dispatch by role and source. The numbers refer
/// to the plain words in the header.
pub fn policy(q : @engine.Query) -> @engine.Decision {
  match (role_of(q.subject.groups), q.source) {
    // 1. admins are always allowed
    (Admin, _) => @engine.Decision::allow("admin group")
    // 2. RGW: group-namespace isolation plus the role matrix
    (role, Rgw) => rgw_decision(q, role)
    // 3. K8s admission: content constraints
    (_, K8sAdmission) => k8s_decision(q)
  }
}

///|
/// Rule 2: a subject may only touch paths under one of its groups;
/// readers read, writers write, nobody else acts.
fn rgw_decision(q : @engine.Query, role : Role) -> @engine.Decision {
  let path = q.rgw_path().unwrap_or("")
  if !@engine.path_in_any_namespace(path, q.subject.groups) {
    return @engine.Decision::deny(
      "resource \{path} is outside every group namespace of the subject",
    )
  }
  match (role, q.kind) {
    (Roleless, _) => @engine.Decision::deny("subject holds no role")
    (Reader, @engine.AccessKind::ReadAccess) =>
      @engine.Decision::allow("reader in own namespace")
    (Writer, @engine.AccessKind::WriteAccess) =>
      @engine.Decision::allow("writer in own namespace")
    (_, _) =>
      @engine.Decision::deny("role \{role.label()} may not perform \{q.verb}")
  }
}

///|
/// Rule 3: content constraints RBAC cannot express. Everything the
/// policy does not object to is allowed.
fn k8s_decision(q : @engine.Query) -> @engine.Decision {
  if q.object is Some(obj) {
    if @k8s.target_kind_is(q, "Pod") && @k8s.pod_has_privileged_container(obj) {
      return @engine.Decision::deny("privileged containers are not allowed")
    }
    if binds_a_role(q) && @k8s.binding_grants_risky_role(obj, risky_roles()) {
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

///|
/// Whether the target of `q` is a role binding.
fn binds_a_role(q : @engine.Query) -> Bool {
  @k8s.target_kind_is(q, "RoleBinding") ||
  @k8s.target_kind_is(q, "ClusterRoleBinding")
}
