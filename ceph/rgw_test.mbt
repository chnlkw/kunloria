// ceph/rgw_test.mbt — blackbox tests with the RGW payload shape from the
// Ceph OPA integration.

///|
fn cfg() -> @auth.PolicyConfig {
  @auth.PolicyConfig::of_groups(admin=["ceph-admins"], reader=["groupA"], writer=[
    "groupB",
  ])
}

///|
fn query(
  user : String,
  groups : Array[String],
  action : String,
  bucket : String,
  object : String,
) -> @ceph.RgwQuery? {
  let groups_json = [ for g in groups => Json::string(g) ]
  let body : Json = {
    "input": {
      "user": { "id": user, "groups": Json::array(groups_json) },
      "action": action,
      "resource": { "bucket": bucket, "object": object },
    },
  }
  @ceph.parse_query(body)
}

///|
test "parse the documented RGW payload" {
  let body = @json.parse(
    (
      #|{
      #|  "input": {
      #|    "user": {"id": "user1", "groups": ["groupA"]},
      #|    "action": "s3:GetObject",
      #|    "resource": {"bucket": "my-bucket", "object": "path/to/file"}
      #|  }
      #|}
    ),
  )
  let q = @ceph.parse_query(body)
  assert_true(q is Some(_))
  if q is Some(parsed) {
    assert_eq(parsed.user_id, "user1")
    assert_eq(parsed.groups, ["groupA"])
    assert_eq(parsed.action, "s3:GetObject")
    assert_eq(parsed.bucket, "my-bucket")
    assert_eq(parsed.object, "path/to/file")
    assert_eq(parsed.resource_path(), "path/to/file")
  }
}

///|
test "reader reads its group prefix" {
  let q = query("user1", ["groupA"], "s3:GetObject", "b", "groupA/path/to/file")
  assert_true(q is Some(parsed) && @ceph.decide(cfg(), parsed).allowed)
}

///|
test "reader cannot cross into another group" {
  let q = query("user1", ["groupA"], "s3:GetObject", "b", "groupB/secret")
  if q is Some(parsed) {
    let d = @ceph.decide(cfg(), parsed)
    assert_false(d.allowed)
    assert_true(d.reason.contains("outside every group namespace"))
  } else {
    fail("parse failed")
  }
}

///|
test "reader cannot write" {
  let q = query("user1", ["groupA"], "s3:PutObject", "b", "groupA/file")
  if q is Some(parsed) {
    assert_false(@ceph.decide(cfg(), parsed).allowed)
  } else {
    fail("parse failed")
  }
}

///|
test "writer writes its group prefix but cannot read" {
  let w = query("user2", ["groupB"], "s3:PutObject", "b", "groupB/dir/obj")
  if w is Some(parsed) {
    assert_true(@ceph.decide(cfg(), parsed).allowed)
  } else {
    fail("parse failed")
  }
  let r = query("user2", ["groupB"], "s3:GetObject", "b", "groupB/dir/obj")
  if r is Some(parsed) {
    assert_false(@ceph.decide(cfg(), parsed).allowed)
  } else {
    fail("parse failed")
  }
}

///|
test "admin role is unrestricted" {
  let q = query("root", ["ceph-admins"], "s3:DeleteObject", "any", "x/y/z")
  if q is Some(parsed) {
    assert_true(@ceph.decide(cfg(), parsed).allowed)
  } else {
    fail("parse failed")
  }
}

///|
test "unknown verbs are denied to non-admins" {
  let q = query("user1", ["groupA"], "s3:AdminCreateUser", "b", "groupA/x")
  if q is Some(parsed) {
    assert_false(@ceph.decide(cfg(), parsed).allowed)
  } else {
    fail("parse failed")
  }
}

///|
test "bucket-level ListBucket checks the bucket as path" {
  let ok = query("user1", ["groupA"], "s3:ListBucket", "groupA", "")
  if ok is Some(parsed) {
    assert_true(@ceph.decide(cfg(), parsed).allowed)
  } else {
    fail("parse failed")
  }
  let bad = query("user1", ["groupA"], "s3:ListBucket", "groupB", "")
  if bad is Some(parsed) {
    assert_false(@ceph.decide(cfg(), parsed).allowed)
  } else {
    fail("parse failed")
  }
}

///|
test "payload without input or user is rejected by the parser" {
  let no_input = @json.parse("{\"result\": 0}")
  assert_true(@ceph.parse_query(no_input) is None)
  let no_user = @json.parse("{\"input\": {\"action\": \"s3:GetObject\"}}")
  assert_true(@ceph.parse_query(no_user) is None)
}

///|
test "missing optional fields default to empty strings" {
  let body = @json.parse(
    (
      #|{
      #|  "input": {
      #|    "user": {"id": "u"},
      #|    "action": "s3:GetObject"
      #|  }
      #|}
    ),
  )
  let q = @ceph.parse_query(body)
  if q is Some(parsed) {
    assert_eq(parsed.bucket, "")
    assert_eq(parsed.groups, [])
  } else {
    fail("parse failed")
  }
}

///|
test "stock ceph rgw payload is understood" {
  let body = @json.parse(
    (
      #|{
      #|  "input": {
      #|    "method": "GET",
      #|    "subuser": "sub",
      #|    "user_info": {"user_id": "john", "display_name": "John"},
      #|    "bucket_info": {
      #|      "bucket": {"name": "john-data", "bucket_id": "x"},
      #|      "owner": "john"
      #|    }
      #|  }
      #|}
    ),
  )
  let q = @ceph.parse_query(body)
  if q is Some(parsed) {
    assert_eq(parsed.user_id, "john")
    assert_eq(parsed.groups, ["john"])
    assert_eq(parsed.action, "s3:GetObject")
    assert_eq(parsed.bucket, "john-data")
    // Under cfg() "john" maps to no role, so even its own namespace is
    // denied (fail closed) ...
    assert_false(@ceph.decide(cfg(), parsed).allowed)
    // ... but a policy that grants "john" the reader role allows reads in
    // the namespace named after it, and still denies other namespaces.
    let john_cfg = @auth.PolicyConfig::of_groups(reader=["john"])
    let own = { ..parsed, bucket: "john", }
    assert_true(@ceph.decide(john_cfg, own).allowed)
    let foreign = { ..parsed, bucket: "other", }
    assert_false(@ceph.decide(john_cfg, foreign).allowed)
  } else {
    fail("stock payload should parse")
  }
}

///|
test "stock payload admin via user id in admin groups" {
  let admin_cfg = @auth.PolicyConfig::of_groups(admin=["ceph-admins"])
  let body = @json.parse(
    (
      #|{
      #|  "input": {
      #|    "method": "DELETE",
      #|    "user_info": {"user_id": "ceph-admins"},
      #|    "bucket_info": {"bucket": {"name": "any"}}
      #|  }
      #|}
    ),
  )
  let q = @ceph.parse_query(body)
  if q is Some(parsed) {
    assert_true(@ceph.decide(admin_cfg, parsed).allowed)
  } else {
    fail("parse failed")
  }
}

///|
test "stock payload write methods map to write actions" {
  let body = @json.parse(
    (
      #|{
      #|  "input": {
      #|    "method": "PUT",
      #|    "user_info": {"user_id": "john"},
      #|    "bucket_info": {"bucket": {"name": "john"}}
      #|  }
      #|}
    ),
  )
  let q = @ceph.parse_query(body)
  if q is Some(parsed) {
    assert_eq(@ceph.classify_s3_action(parsed.action), @auth.Write)
  } else {
    fail("parse failed")
  }
}
