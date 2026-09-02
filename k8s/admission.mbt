// k8s/admission.mbt — Kubernetes admission policy.
//
// Kunloria receives `admission.k8s.io/v1` AdmissionReview objects on
// /validate and answers allow/deny for the object under review. Parsing is
// deliberately tolerant: the API server may add fields, and admission
// semantics must fail closed, never crash.

///|
/// Settings of the admission policy.
///
/// - `enforce_namespaces`: when non-empty, only requests for these
///   namespaces are evaluated; everything else is allowed as "not selected"
///   (server-side equivalent of a webhook namespaceSelector).
/// - `risky_cluster_roles`: ClusterRoles that may not be bound to
///   non-admitted subjects (default: cluster-admin).
/// - `admitted_bindings`: allowlist of `"<namespace>:<serviceaccount>"`
///   entries permitted to receive a risky role.
pub(all) struct AdmissionSettings {
  enforce_namespaces : Array[String]
  risky_cluster_roles : Array[String]
  admitted_bindings : Array[String]
} derive(Eq, @debug.Debug)

///|
/// Default settings: enforce everywhere, guard `cluster-admin`, admit no one.
pub fn AdmissionSettings::defaults() -> AdmissionSettings {
  {
    enforce_namespaces: [],
    risky_cluster_roles: ["cluster-admin"],
    admitted_bindings: [],
  }
}

///|
/// The result of evaluating one AdmissionReview: the request uid (echoed in
/// the response) plus the policy decision.
pub(all) struct AdmissionVerdict {
  uid : String
  decision : @auth.Decision
} derive(Eq, @debug.Debug)

///|
/// Child field of an optional JSON value; `None` when either is absent.
fn jfield(j : Json?, key : String) -> Json? {
  if j is Some(Object(map)) {
    map.get(key)
  } else {
    None
  }
}

///|
/// String field of an optional JSON value.
fn jstr(j : Json?, key : String) -> String? {
  jstring(jfield(j, key))
}

///|
/// Unwrap a JSON string, if that is what it is.
fn jstring(j : Json?) -> String? {
  if j is Some(String(s)) {
    Some(s)
  } else {
    None
  }
}

///|
/// Unwrap a JSON array, if that is what it is.
fn jarray(j : Json?) -> Array[Json]? {
  if j is Some(Array(list)) {
    Some(list)
  } else {
    None
  }
}

///|
/// Unwrap a JSON boolean, if that is what it is.
fn jbool(j : Json?) -> Bool? {
  if j is Some(True) {
    Some(true)
  } else if j is Some(False) {
    Some(false)
  } else {
    None
  }
}

///|
/// Evaluate an AdmissionReview object (already parsed from JSON).
///
/// Checks implemented:
/// - Pods: privileged containers (spec.containers / spec.initContainers
///   with securityContext.privileged == true) are denied.
/// - RoleBinding / ClusterRoleBinding: binding a risky ClusterRole (e.g.
///   cluster-admin) to a ServiceAccount outside the admitted list is denied.
/// - Everything else is allowed and tagged with the reason.
pub fn evaluate(
  settings : AdmissionSettings,
  review : Json,
) -> AdmissionVerdict {
  let request = jfield(Some(review), "request")
  let uid = match jstr(request, "uid") {
    Some(u) => u
    None => ""
  }
  let decision = match request {
    None =>
      @auth.Decision::deny(
        @auth.NoRole,
        "AdmissionReview carries no request; failing closed",
      )
    Some(req) => evaluate_request(settings, req)
  }
  { uid, decision, }
}

///|
fn evaluate_request(settings : AdmissionSettings, req : Json) -> @auth.Decision {
  let kind = match jstring(jfield(jfield(Some(req), "kind"), "kind")) {
    Some(k) => k
    None => ""
  }
  let obj_ns = match jstr(Some(req), "namespace") {
    Some(ns) => ns
    None => ""
  }
  let operation = match jstr(Some(req), "operation") {
    Some(op) => op
    None => ""
  }
  // Namespace scoping: unevaluated namespaces are allowed (skipped).
  if settings.enforce_namespaces.length() > 0 &&
    !settings.enforce_namespaces.contains(obj_ns) {
    return @auth.Decision::allow(
      @auth.NoRole,
      "namespace '\{obj_ns}' is not selected by the policy; skipped",
    )
  }
  let obj = jfield(Some(req), "object")
  match kind {
    "Pod" =>
      match obj {
        Some(o) => check_pod(o)
        None =>
          @auth.Decision::allow(
            @auth.NoRole,
            "operation \{operation} on Pod carries no object; nothing to check",
          )
      }
    "RoleBinding" =>
      match obj {
        Some(o) => check_role_binding(settings, o, false)
        None =>
          @auth.Decision::allow(
            @auth.NoRole,
            "operation \{operation} on RoleBinding carries no object",
          )
      }
    "ClusterRoleBinding" =>
      match obj {
        Some(o) => check_role_binding(settings, o, true)
        None =>
          @auth.Decision::allow(
            @auth.NoRole,
            "operation \{operation} on ClusterRoleBinding carries no object",
          )
      }
    other =>
      @auth.Decision::allow(
        @auth.NoRole,
        "kind '\{other}' has no admission policy; allowed",
      )
  }
}

///|
/// Deny privileged containers in Pod specs.
fn check_pod(obj : Json) -> @auth.Decision {
  match jfield(Some(obj), "spec") {
    None =>
      @auth.Decision::allow(
        @auth.NoRole,
        "Pod carries no spec; nothing to check",
      )
    Some(spec) => {
      let offenders : Array[String] = []
      collect_privileged(jfield(Some(spec), "containers"), offenders)
      collect_privileged(jfield(Some(spec), "initContainers"), offenders)
      if offenders.length() == 0 {
        @auth.Decision::allow(
          @auth.NoRole,
          "no privileged container in Pod spec",
        )
      } else {
        @auth.Decision::deny(
          @auth.NoRole,
          "privileged containers are forbidden: \{offenders.join(", ")}",
        )
      }
    }
  }
}

///|
fn collect_privileged(containers : Json?, offenders : Array[String]) -> Unit {
  let list = match jarray(containers) {
    Some(list) => list
    None => return
  }
  for container in list {
    let name = match jstr(Some(container), "name") {
      Some(n) => n
      None => "<unnamed>"
    }
    let privileged = jbool(
      jfield(jfield(Some(container), "securityContext"), "privileged"),
    )
    if privileged == Some(true) {
      offenders.push(name)
    }
  }
}

///|
/// Deny binding risky ClusterRoles to non-admitted subjects.
fn check_role_binding(
  settings : AdmissionSettings,
  obj : Json,
  cluster_scoped : Bool,
) -> @auth.Decision {
  let role = match jstr(jfield(Some(obj), "roleRef"), "name") {
    Some(r) => r
    None => ""
  }
  if !settings.risky_cluster_roles.contains(role) {
    return @auth.Decision::allow(
      @auth.NoRole,
      "role '\{role}' is not in the risky list; \{scope_name(cluster_scoped)} allowed",
    )
  }
  let subjects = match jarray(jfield(Some(obj), "subjects")) {
    Some(list) => list
    None => []
  }
  if subjects.length() == 0 {
    return @auth.Decision::deny(
      @auth.NoRole,
      "\{scope_name(cluster_scoped)} binds risky role '\{role}' with no subjects; failing closed",
    )
  }
  for subject in subjects {
    let kind = match jstr(Some(subject), "kind") {
      Some(k) => k
      None => ""
    }
    let name = match jstr(Some(subject), "name") {
      Some(n) => n
      None => "<unnamed>"
    }
    if kind != "ServiceAccount" {
      return @auth.Decision::deny(
        @auth.NoRole,
        "binding risky role '\{role}' to \{kind} '\{name}' is not admitted",
      )
    }
    let sa_ns = match jstr(Some(subject), "namespace") {
      Some(n) => n
      None => ""
    }
    if !settings.admitted_bindings.contains("\{sa_ns}:\{name}") {
      return @auth.Decision::deny(
        @auth.NoRole,
        "binding risky role '\{role}' to service account '\{sa_ns}:\{name}' is not admitted",
      )
    }
  }
  @auth.Decision::allow(
    @auth.NoRole,
    "risky role '\{role}' bound only to admitted service accounts",
  )
}

///|
fn scope_name(cluster_scoped : Bool) -> String {
  if cluster_scoped {
    "ClusterRoleBinding"
  } else {
    "RoleBinding"
  }
}
