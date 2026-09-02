// examples/minimal/policy_test.mbt — the template denies everything.

///|
test "minimal template denies every query" {
  let q : @engine.Query = @engine.Query::{
    source: @engine.Source::Rgw,
    subject: @engine.Subject::{ user: "u", groups: ["platform"], },
    verb: "s3:getobject",
    kind: @engine.AccessKind::ReadAccess,
    target: @engine.Target::Rgw(@engine.RgwRef::{ bucket: "b", object_key: "", }),
    object: None,
  }
  let d = policy(q)
  assert_true(d.effect is @engine.Effect::Deny)
}
