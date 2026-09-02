// k8s/parse_test.mbt — review parsing, verb classification, reply envelope.

///|
fn review(
  pod_ns : String,
  verb? : String = "CREATE",
  user? : String = "alice",
) -> Json raise {
  @json.parse(
    (
      $|{"apiVersion": "admission.k8s.io/v1", "kind": "AdmissionReview",
      $| "request": {"uid": "abc-123", "verb": "\{verb}",
      $|   "userInfo": {"username": "\{user}", "groups": ["team-a", "system:authenticated"]},
      $|   "namespace": "\{pod_ns}",
      $|   "kind": {"group": "", "version": "v1", "kind": "Pod"},
      $|   "resource": {"group": "", "version": "v1", "resource": "pods"},
      $|   "name": "web-0",
      $|   "object": {"metadata": {"name": "web-0"}, "spec": {"containers": [
      $|     {"name": "app", "image": "nginx", "securityContext": {"privileged": true}}]}}}}
    ),
  )
}

///|
test "review carries subject, verb, gvk, namespace and object" {
  let r = @k8s.parse_review(review("prod"))
  assert_true(r is Some(_))
  if r is Some(rev) {
    assert_eq(rev.uid, "abc-123")
    let q = rev.query
    assert_eq(q.source, @engine.Source::K8sAdmission)
    assert_eq(q.subject.user, "alice")
    assert_eq(q.subject.groups, ["team-a", "system:authenticated"])
    assert_eq(q.verb, "create")
    assert_eq(q.kind, @engine.AccessKind::WriteAccess)
    if q.target is @engine.Target::K8s(kref) {
      assert_eq(kref.kind, "Pod")
      assert_eq(kref.resource, "pods")
      assert_eq(kref.api_group, "")
      assert_eq(kref.name, "web-0")
      assert_eq(kref.ns, "prod")
    } else {
      fail("expected a k8s target")
    }
    assert_true(q.object is Some(_))
    assert_eq(q.ns().unwrap_or(""), "prod")
  }
}

///|
test "verbs classify: writes vs reads vs unknown" {
  assert_eq(
    @k8s.classify_admission_verb("CREATE"),
    @engine.AccessKind::WriteAccess,
  )
  assert_eq(
    @k8s.classify_admission_verb("Update"),
    @engine.AccessKind::WriteAccess,
  )
  assert_eq(
    @k8s.classify_admission_verb("PATCH"),
    @engine.AccessKind::WriteAccess,
  )
  assert_eq(
    @k8s.classify_admission_verb("DELETE"),
    @engine.AccessKind::WriteAccess,
  )
  assert_eq(
    @k8s.classify_admission_verb("CONNECT"),
    @engine.AccessKind::WriteAccess,
  )
  assert_eq(@k8s.classify_admission_verb("GET"), @engine.AccessKind::ReadAccess)
  assert_eq(
    @k8s.classify_admission_verb("LIST"),
    @engine.AccessKind::ReadAccess,
  )
  assert_eq(
    @k8s.classify_admission_verb("bogus"),
    @engine.AccessKind::UnknownAccess,
  )
}

///|
test "pluralize covers the common shapes" {
  assert_eq(@k8s.pluralize("Pod"), "pods")
  assert_eq(@k8s.pluralize("Ingress"), "ingresses")
  assert_eq(@k8s.pluralize("NetworkPolicy"), "networkpolicies")
  assert_eq(@k8s.pluralize("Endpoints"), "endpoints")
  assert_eq(@k8s.pluralize("RoleBinding"), "rolebindings")
}

///|
test "malformed reviews parse as None (fail-closed)" {
  // missing request envelope
  assert_true(
    @k8s.parse_review(@json.parse("{\"kind\": \"AdmissionReview\"}")) is None,
  )
  // missing uid
  let no_uid = @json.parse(
    (
      $|{"request": {"verb": "CREATE", "userInfo": {"username": "u"},
      $|  "kind": {"kind": "Pod"}}}
    ),
  )
  assert_true(@k8s.parse_review(no_uid) is None)
  // missing userInfo block
  let no_user = @json.parse(
    (
      $|{"request": {"uid": "x", "verb": "CREATE",
      $|  "kind": {"kind": "Pod"}}}
    ),
  )
  assert_true(@k8s.parse_review(no_user) is None)
  // missing kind block
  let no_kind = @json.parse(
    (
      $|{"request": {"uid": "x", "verb": "CREATE", "userInfo": {"username": "u"}}}
    ),
  )
  assert_true(@k8s.parse_review(no_kind) is None)
}

///|
test "reply envelope: allow echoes uid, deny carries 403 + reason" {
  let allow = @k8s.reply("u1", @engine.Decision::allow("fine"))
  assert_true(jget(allow, ["response", "allowed"]) is Some(True))
  assert_true(jget(allow, ["response", "uid"]) is Some(String("u1")))
  assert_true(jget(allow, ["response", "status"]) is None)
  let deny = @k8s.reply("u2", @engine.Decision::deny("reader may not write"))
  assert_true(jget(deny, ["response", "allowed"]) is Some(False))
  if jget(deny, ["response", "status", "message"]) is Some(String(msg)) {
    assert_eq(msg, "reader may not write")
  } else {
    fail("denial should carry a status message")
  }
}

///|
test "privileged pod detection spans init containers" {
  let priv_pod = review("prod")
  assert_true(
    @k8s.pod_has_privileged_container(
      jget(priv_pod, ["request", "object"]).unwrap_or(Json::string("x")),
    ),
  )
  let unpriv = @json.parse(
    (
      $|{"spec": {"containers": [{"name": "app", "image": "nginx"}],
      $|          "initContainers": [{"name": "init", "image": "busybox"}]}}
    ),
  )
  assert_false(@k8s.pod_has_privileged_container(unpriv))
  let priv_init = @json.parse(
    (
      $|{"spec": {"containers": [{"name": "app"}],
      $|          "initContainers": [{"name": "init", "securityContext": {"privileged": true}}]}}
    ),
  )
  assert_true(@k8s.pod_has_privileged_container(priv_init))
  // not a pod spec at all
  assert_false(@k8s.pod_has_privileged_container(@json.parse("{}")))
}

///|
test "risky role binding detection" {
  let binding = @json.parse(
    (
      $|{"roleRef": {"apiGroup": "rbac.authorization.k8s.io", "kind": "ClusterRole",
      $|             "name": "cluster-admin"}, "subjects": []}
    ),
  )
  assert_true(@k8s.binding_grants_risky_role(binding, ["cluster-admin"]))
  assert_false(
    @k8s.binding_grants_risky_role(binding, [
      "system:controller:bootstrap-signer",
    ]),
  )
  assert_false(
    @k8s.binding_grants_risky_role(@json.parse("{}"), ["cluster-admin"]),
  )
}

///|
/// Fetches a nested field by path.
fn jget(v : Json, path : Array[String]) -> Json? {
  let mut cur : Json? = Some(v)
  for key in path {
    if cur is Some(obj) && obj is Object(fields) {
      cur = fields.get(key)
    } else {
      return None
    }
  }
  cur
}
