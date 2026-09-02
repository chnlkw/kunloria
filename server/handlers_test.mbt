// server/handlers_test.mbt — endpoint behavior around a fixed test policy.

///|
/// Test policy: platform group allows everything; everyone else is denied.
fn test_policy(q : @engine.Query) -> @engine.Decision {
  @engine.otherwise(@engine.subject_in_group("platform"), @engine.deny_all)(q)
}

///|
fn review_body(group : String) -> String {
  let template =
    $|{"apiVersion": "admission.k8s.io/v1", "kind": "AdmissionReview",
    $| "request": {"uid": "u-42", "verb": "CREATE",
    $|   "userInfo": {"username": "dev", "groups": ["\{group}"]},
    $|   "namespace": "prod",
    $|   "kind": {"group": "", "version": "v1", "kind": "Pod"},
    $|   "object": {"spec": {"containers": []}}}}
  template.to_string()
}

///|
test "validate: platform member admitted, envelope echoes uid" {
  let res = @server.handle_validate(test_policy, review_body("platform"))
  assert_eq(res.status, 200)
  assert_eq(res.allowed, Some(true))
  if res.body is { "response": { "uid": String(uid), "allowed": True, .. }, .. } {
    assert_eq(uid, "u-42")
  } else {
    fail("envelope should echo uid with allowed:true")
  }
}

///|
test "validate: non-member denied with 403 status message" {
  let res = @server.handle_validate(test_policy, review_body("team-a"))
  assert_eq(res.status, 200)
  assert_eq(res.allowed, Some(false))
  if res.body
    is {
      "response": {
        "uid": String(uid),
        "allowed": False,
        "status": { "message": String(_), .. },
        ..
      },
      ..
    } {
    assert_eq(uid, "u-42")
  } else {
    fail("denial should carry a status message")
  }
}

///|
test "validate: malformed review answers 400" {
  let res = @server.handle_validate(test_policy, "{\"request\": {}}")
  assert_eq(res.status, 400)
  assert_eq(res.allowed, None)
  let res2 = @server.handle_validate(test_policy, "not json at all")
  assert_eq(res2.status, 400)
}

///|
test "rgw: native payload member allows, outsider denies" {
  let member_payload = (
    $|{"input": {"user": {"id": "u", "groups": ["platform"]},
    $| "action": "s3:GetObject", "resource": {"bucket": "any", "object": "o"}}}
  ).to_string()
  let res = @server.handle_rgw_allow(test_policy, member_payload)
  assert_eq(res.status, 200)
  assert_eq(res.allowed, Some(true))
  if res.body is { "result": True, .. } {
    ()
  } else {
    fail("member should get result:true")
  }
  let outsider = (
    $|{"input": {"user": {"id": "u", "groups": ["team-a"]},
    $| "action": "s3:GetObject", "resource": {"bucket": "any", "object": "o"}}}
  ).to_string()
  let res2 = @server.handle_rgw_allow(test_policy, outsider)
  assert_eq(res2.allowed, Some(false))
  if res2.body is { "result": False, .. } {
    ()
  } else {
    fail("outsider should get result:false")
  }
}

///|
test "rgw: malformed payload answers 400" {
  let res = @server.handle_rgw_allow(test_policy, "{\"input\": {}}")
  assert_eq(res.status, 400)
  assert_eq(res.allowed, None)
}

///|
test "banner names the service and version" {
  if @server.banner()
    is {
      "service": String("kunloria"),
      "version": String(_),
      "policy": String(_),
      ..
    } {
    ()
  } else {
    fail("banner should identify the service")
  }
}
