// server/handlers_test.mbt — integration tests with simulated request
// bodies: the full parse -> decide -> respond pipeline without sockets.

///|
fn settings() -> @server.AppSettings {
  {
    host: "127.0.0.1",
    port: 8080,
    policy: @auth.PolicyConfig::of_groups(admin=["admin"], reader=["groupA"], writer=[
      "groupB",
    ]),
    admission: {
      enforce_namespaces: [],
      risky_cluster_roles: ["cluster-admin"],
      admitted_bindings: [],
    },
    log_level: "info",
  }
}

///|
fn admission_body() -> String {
  let text =
    #|{
    #|  "apiVersion": "admission.k8s.io/v1",
    #|  "kind": "AdmissionReview",
    #|  "request": {
    #|    "uid": "e2e-1",
    #|    "kind": {"group": "", "version": "v1", "kind": "Pod"},
    #|    "namespace": "default",
    #|    "operation": "CREATE",
    #|    "object": {
    #|      "spec": {"containers": [
    #|        {"name": "evil", "image": "x", "securityContext": {"privileged": true}}
    #|      ]}
    #|    }
    #|  }
    #|}
  text
}

///|
test "validate denies a privileged pod end to end" {
  let m = @server.Metrics::new()
  let r = @server.handle_validate(settings(), m, admission_body())
  assert_eq(r.status, 200)
  assert_false(r.allowed)
  // Response envelope is a well-formed AdmissionReview.
  let obj = if r.body is Object(map) {
    map
  } else {
    fail("response is not an object")
  }
  assert_true(obj.get("apiVersion") is Some(String("admission.k8s.io/v1")))
  assert_true(obj.get("kind") is Some(String("AdmissionReview")))
  if obj.get("response") is Some(Object(response)) {
    assert_true(response.get("uid") is Some(String("e2e-1")))
    assert_true(response.get("allowed") is Some(False))
    if response.get("status") is Some(Object(status)) {
      assert_true(
        status.get("message")
        is Some(String("privileged containers are forbidden: evil")),
      )
    } else {
      fail("denied response must carry a status")
    }
  } else {
    fail("response field missing")
  }
  // Metrics recorded one denial.
  assert_true(m.render().contains("kunloria_denied_total 1"))
}

///|
test "validate answers 400 on malformed JSON" {
  let m = @server.Metrics::new()
  let r = @server.handle_validate(settings(), m, "not json {")
  assert_eq(r.status, 400)
  assert_false(r.allowed)
  assert_true(r.body is Object(map) && map.get("error") is Some(_))
}

///|
test "rgw allow endpoint answers OPA-style result" {
  let m = @server.Metrics::new()
  let ok = @server.handle_rgw_allow(
    settings(),
    m,
    "{\"input\":{\"user\":{\"id\":\"u1\",\"groups\":[\"groupA\"]},\"action\":\"s3:GetObject\",\"resource\":{\"bucket\":\"b\",\"object\":\"groupA/f\"}}}",
  )
  assert_eq(ok.status, 200)
  assert_true(ok.allowed)
  assert_true(ok.body is Object(map) && map.get("result") is Some(True))
  let deny = @server.handle_rgw_allow(
    settings(),
    m,
    "{\"input\":{\"user\":{\"id\":\"u1\",\"groups\":[\"groupA\"]},\"action\":\"s3:PutObject\",\"resource\":{\"bucket\":\"b\",\"object\":\"groupA/f\"}}}",
  )
  assert_eq(deny.status, 200)
  assert_false(deny.allowed)
  assert_true(deny.body is Object(map) && map.get("result") is Some(False))
}

///|
test "rgw endpoint rejects payloads without a user" {
  let m = @server.Metrics::new()
  let r = @server.handle_rgw_allow(settings(), m, "{\"input\": {}}")
  assert_eq(r.status, 400)
  assert_false(r.allowed)
}

///|
test "banner mentions the version" {
  assert_true(@server.banner().contains(@kunloria.KUNLORIA_VERSION))
}
