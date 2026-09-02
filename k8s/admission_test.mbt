// k8s/admission_test.mbt — blackbox tests with simulated AdmissionReview
// payloads (trimmed to the fields the policy reads).

///|
fn settings() -> @k8s.AdmissionSettings {
  {
    enforce_namespaces: [],
    risky_cluster_roles: ["cluster-admin"],
    admitted_bindings: ["kube-system:deployer"],
  }
}

///|
test "privileged pod is denied" {
  let review = @json.parse(
    (
      #|{
      #|  "apiVersion": "admission.k8s.io/v1",
      #|  "kind": "AdmissionReview",
      #|  "request": {
      #|    "uid": "abc-123",
      #|    "kind": {"group": "", "version": "v1", "kind": "Pod"},
      #|    "namespace": "default",
      #|    "operation": "CREATE",
      #|    "object": {
      #|      "metadata": {"name": "bad-pod"},
      #|      "spec": {
      #|        "containers": [
      #|          {"name": "app", "image": "nginx"},
      #|          {"name": "sidecar", "image": "hack", "securityContext": {"privileged": true}}
      #|        ]
      #|      }
      #|    }
      #|  }
      #|}
    ),
  )
  let v = @k8s.evaluate(settings(), review)
  assert_eq(v.uid, "abc-123")
  assert_false(v.decision.allowed)
  assert_true(v.decision.reason.contains("sidecar"))
}

///|
test "normal pod is allowed" {
  let review = @json.parse(
    (
      #|{
      #|  "request": {
      #|    "uid": "u1",
      #|    "kind": {"kind": "Pod"},
      #|    "operation": "CREATE",
      #|    "object": {
      #|      "metadata": {"name": "good-pod"},
      #|      "spec": {"containers": [{"name": "app", "image": "nginx"}]}
      #|    }
      #|  }
      #|}
    ),
  )
  let v = @k8s.evaluate(settings(), review)
  assert_true(v.decision.allowed)
}

///|
test "privileged init container is denied too" {
  let review = @json.parse(
    (
      #|{
      #|  "request": {
      #|    "uid": "u2",
      #|    "kind": {"kind": "Pod"},
      #|    "operation": "CREATE",
      #|    "object": {
      #|      "spec": {
      #|        "initContainers": [
      #|          {"name": "setup", "securityContext": {"privileged": true}}
      #|        ],
      #|        "containers": []
      #|      }
      #|    }
      #|  }
      #|}
    ),
  )
  let v = @k8s.evaluate(settings(), review)
  assert_false(v.decision.allowed)
  assert_true(v.decision.reason.contains("setup"))
}

///|
test "cluster-admin binding to plain service account is denied" {
  let review = @json.parse(
    (
      #|{
      #|  "request": {
      #|    "uid": "u3",
      #|    "kind": {"kind": "ClusterRoleBinding"},
      #|    "operation": "CREATE",
      #|    "object": {
      #|      "roleRef": {"kind": "ClusterRole", "name": "cluster-admin"},
      #|      "subjects": [
      #|        {"kind": "ServiceAccount", "name": "default", "namespace": "app"}
      #|      ]
      #|    }
      #|  }
      #|}
    ),
  )
  let v = @k8s.evaluate(settings(), review)
  assert_false(v.decision.allowed)
  assert_true(v.decision.reason.contains("cluster-admin"))
}

///|
test "cluster-admin binding to admitted service account is allowed" {
  let review = @json.parse(
    (
      #|{
      #|  "request": {
      #|    "uid": "u4",
      #|    "kind": {"kind": "ClusterRoleBinding"},
      #|    "operation": "CREATE",
      #|    "object": {
      #|      "roleRef": {"kind": "ClusterRole", "name": "cluster-admin"},
      #|      "subjects": [
      #|        {"kind": "ServiceAccount", "name": "deployer", "namespace": "kube-system"}
      #|      ]
      #|    }
      #|  }
      #|}
    ),
  )
  let v = @k8s.evaluate(settings(), review)
  assert_true(v.decision.allowed)
}

///|
test "binding a human user to cluster-admin is denied" {
  let review = @json.parse(
    (
      #|{
      #|  "request": {
      #|    "uid": "u5",
      #|    "kind": {"kind": "RoleBinding"},
      #|    "operation": "CREATE",
      #|    "object": {
      #|      "roleRef": {"kind": "ClusterRole", "name": "cluster-admin"},
      #|      "subjects": [{"kind": "User", "name": "alice"}]
      #|    }
      #|  }
      #|}
    ),
  )
  let v = @k8s.evaluate(settings(), review)
  assert_false(v.decision.allowed)
}

///|
test "harmless role binding is allowed" {
  let review = @json.parse(
    (
      #|{
      #|  "request": {
      #|    "uid": "u6",
      #|    "kind": {"kind": "RoleBinding"},
      #|    "operation": "CREATE",
      #|    "object": {
      #|      "roleRef": {"kind": "Role", "name": "pod-reader"},
      #|      "subjects": [{"kind": "ServiceAccount", "name": "default", "namespace": "app"}]
      #|    }
      #|  }
      #|}
    ),
  )
  let v = @k8s.evaluate(settings(), review)
  assert_true(v.decision.allowed)
}

///|
test "namespaces outside the selection are skipped (allowed)" {
  let s : @k8s.AdmissionSettings = {
    enforce_namespaces: ["team-a"],
    risky_cluster_roles: ["cluster-admin"],
    admitted_bindings: [],
  }
  let review = @json.parse(
    (
      #|{
      #|  "request": {
      #|    "uid": "u7",
      #|    "kind": {"kind": "Pod"},
      #|    "namespace": "team-b",
      #|    "operation": "CREATE",
      #|    "object": {"spec": {"containers": [{"name": "x", "securityContext": {"privileged": true}}]}}
      #|  }
      #|}
    ),
  )
  let v = @k8s.evaluate(s, review)
  assert_true(v.decision.allowed)
  assert_true(v.decision.reason.contains("skipped"))
}

///|
test "malformed review fails closed" {
  let review = @json.parse(
    (
      #|{"apiVersion": "admission.k8s.io/v1", "kind": "AdmissionReview"}
    ),
  )
  let v = @k8s.evaluate(settings(), review)
  assert_false(v.decision.allowed)
}
