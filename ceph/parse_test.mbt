// ceph/parse_test.mbt — payload shapes, classification, fail-closed parsing.

///|
/// Parses a payload; a JSON-level parse error becomes `None` (malformed).
fn parse(s : String) -> @engine.Query? {
  let j : Json = @json.parse(s) catch { _ => "unparseable" }
  @ceph.parse_query(j)
}

///|
test "native payload: user, groups, action, resource" {
  let q = parse(
    (
      #|{"input": {"user": {"id": "alice", "groups": ["team-a", "audit"]},
      #|           "action": "s3:GetObject",
      #|           "resource": {"bucket": "team-a", "object": "reports/q3.bin"}}}
    ),
  )
  assert_true(q is Some(_))
  if q is Some(query) {
    assert_eq(query.subject.user, "alice")
    assert_eq(query.subject.groups, ["team-a", "audit"])
    assert_eq(query.verb, "s3:getobject")
    assert_eq(query.kind, @engine.AccessKind::ReadAccess)
    if query.target is @engine.Target::Rgw(rref) {
      assert_eq(rref.bucket, "team-a")
      assert_eq(rref.object_key, "reports/q3.bin")
      // joined namespace path: team-a/reports/q3.bin
      assert_eq(query.rgw_path().unwrap_or(""), "team-a/reports/q3.bin")
    } else {
      fail("expected an RGW target")
    }
  }
}

///|
test "stock payload: method mapping and user-doubles-as-group" {
  let q = parse(
    (
      #|{"input": {"method": "GET", "user_info": {"user_id": "john", "display_name": "John"},
      #|           "bucket_info": {"bucket": {"name": "john", "owner": "john"}, "acls": []}}}
    ),
  )
  assert_true(q is Some(_))
  if q is Some(query) {
    assert_eq(query.subject.user, "john")
    assert_eq(query.subject.groups, ["john"])
    assert_eq(query.verb, "s3:getobject")
    assert_eq(query.kind, @engine.AccessKind::ReadAccess)
    if query.target is @engine.Target::Rgw(rref) {
      assert_eq(rref.bucket, "john")
      assert_eq(rref.object_key, "")
    } else {
      fail("expected an RGW target")
    }
  }
}

///|
/// A (method, expected kind) pair for the stock-payload table.
struct Case {
  m : String
  k : @engine.AccessKind
} derive(Eq, @debug.Debug)

///|
test "stock payload methods classify" {
  for
    pair in [
      { m: "GET", k: @engine.AccessKind::ReadAccess, },
      { m: "HEAD", k: @engine.AccessKind::ReadAccess, },
      { m: "PUT", k: @engine.AccessKind::WriteAccess, },
      { m: "POST", k: @engine.AccessKind::WriteAccess, },
      { m: "DELETE", k: @engine.AccessKind::WriteAccess, },
    ] {
    let q = parse(
      "{\"input\":{\"method\":\"\{pair.m}\",\"user_info\":{\"user_id\":\"u\"},\"bucket_info\":{\"bucket\":{\"name\":\"b\"}}}}",
    )
    assert_true(q is Some(_))
    if q is Some(query) {
      assert_eq(query.kind, pair.k)
    }
  }
}

///|
test "classification table, case-insensitive, unknown stays unknown" {
  for a in ["s3:GetObject", "s3:headobject", "S3:ListBucket", "get", "HEAD"] {
    assert_eq(@ceph.classify_s3_action(a), @engine.AccessKind::ReadAccess)
  }
  for a in ["s3:PutObject", "s3:DeleteObject", "s3:UploadPart", "put", "POST"] {
    assert_eq(@ceph.classify_s3_action(a), @engine.AccessKind::WriteAccess)
  }
  for a in ["s3:TagBucket", "bogus", ""] {
    assert_eq(@ceph.classify_s3_action(a), @engine.AccessKind::UnknownAccess)
  }
}

///|
test "malformed payloads parse as None (fail-closed)" {
  // not an object
  assert_true(parse("[]") is None)
  // missing input envelope
  assert_true(parse("{\"user\": {}}") is None)
  // native shape without a user id
  assert_true(
    parse(
      (
        #|{"input": {"user": {"groups": []}, "action": "s3:GetObject",
        #|           "resource": {"bucket": "b", "object": "o"}}}
      ),
    )
    is None,
  )
  // stock shape without bucket_info
  assert_true(
    parse(
      "{\"input\": {\"method\": \"GET\", \"user_info\": {\"user_id\": \"u\"}}}",
    )
    is None,
  )
  // empty input object matches neither shape
  assert_true(parse("{\"input\": {}}") is None)
}

///|
test "reply body carries result:true/false" {
  if @ceph.reply(true) is Object(fields) {
    assert_true(fields.get("result") is Some(True))
  } else {
    fail("reply should be an object")
  }
  if @ceph.reply(false) is Object(fields) {
    assert_true(fields.get("result") is Some(False))
  } else {
    fail("reply should be an object")
  }
}
