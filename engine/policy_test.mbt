// engine/policy_test.mbt — blackbox tests for atoms, combinators, boundary.

///|
/// A Kubernetes create-pods query as test fodder.
fn k8s_query(
  user : String,
  groups : Array[String],
  verb? : String = "create",
  ns? : String = "team-a",
) -> @engine.Query {
  @engine.Query::{
    source: K8sAdmission,
    subject: @engine.Subject::{ user, groups, },
    verb,
    kind: @engine.AccessKind::WriteAccess,
    target: @engine.Target::K8s(@engine.K8sRef::{
      api_group: "",
      kind: "Pod",
      resource: "pods",
      subresource: "",
      name: "",
      ns,
    }),
    object: None,
  }
}

///|
/// An RGW query as test fodder.
fn rgw_query(
  user : String,
  groups : Array[String],
  bucket~ : String,
  object? : String = "",
  kind? : @engine.AccessKind = @engine.AccessKind::ReadAccess,
) -> @engine.Query {
  @engine.Query::{
    source: Rgw,
    subject: @engine.Subject::{ user, groups, },
    verb: "s3:getobject",
    kind,
    target: @engine.Target::Rgw(@engine.RgwRef::{ bucket, object_key: object, }),
    object: None,
  }
}

///|
fn effects() -> Array[@engine.Policy] {
  [@engine.allow_all, @engine.deny_all, @engine.abstain_all]
}

///|
fn codes() -> Array[Int] {
  [@verdict.ALLOW, @verdict.DENY, @verdict.ABSTAIN]
}

///|
test "and_ truth table mirrors combine_and" {
  for p1 in effects() {
    for p2 in effects() {
      let d = @engine.and_(p1, p2)(k8s_query("u", []))
      assert_eq(
        d.code(),
        @verdict.combine_and(
          p1(k8s_query("u", [])).code(),
          p2(k8s_query("u", [])).code(),
        ),
      )
    }
  }
}

///|
test "or_ truth table mirrors combine_or" {
  for p1 in effects() {
    for p2 in effects() {
      let d = @engine.or_(p1, p2)(k8s_query("u", []))
      assert_eq(
        d.code(),
        @verdict.combine_or(
          p1(k8s_query("u", [])).code(),
          p2(k8s_query("u", [])).code(),
        ),
      )
    }
  }
}

///|
test "and_ deny reason comes from the denying side" {
  let d = @engine.and_(@engine.allow_all, @engine.deny_all)(k8s_query("u", []))
  assert_true(d.effect is @engine.Effect::Deny)
  assert_eq(d.reason, "deny_all")
}

///|
test "or_ allow reason comes from the allowing side" {
  let d = @engine.or_(@engine.abstain_all, @engine.allow_all)(
    k8s_query("u", []),
  )
  assert_true(d.effect is @engine.Effect::Allow)
  assert_eq(d.reason, "allow_all")
}

///|
test "not_ flips effects, is an involution" {
  let q = k8s_query("u", [])
  assert_true(@engine.not_(@engine.allow_all)(q).effect is @engine.Effect::Deny)
  assert_true(@engine.not_(@engine.deny_all)(q).effect is @engine.Effect::Allow)
  assert_true(
    @engine.not_(@engine.abstain_all)(q).effect is @engine.Effect::Abstain,
  )
  let p = @engine.subject_in_group("team-a")
  assert_eq(@engine.not_(@engine.not_(p))(q).code(), p(q).code())
}

///|
test "otherwise falls through on abstain only" {
  let q = k8s_query("u", [])
  let d = @engine.otherwise(@engine.abstain_all, @engine.deny_all)(q)
  assert_true(d.effect is @engine.Effect::Deny)
  let d2 = @engine.otherwise(@engine.deny_all, @engine.allow_all)(q)
  assert_true(d2.effect is @engine.Effect::Deny)
  let d3 = @engine.otherwise(@engine.allow_all, @engine.deny_all)(q)
  assert_true(d3.effect is @engine.Effect::Allow)
}

///|
test "finalize is fail-closed: abstain becomes deny" {
  let d = @engine.finalize(@engine.abstain_all(k8s_query("u", [])))
  assert_true(d.effect is @engine.Effect::Deny)
  assert_eq(d.reason, "no policy decided; failing closed")
  assert_true(
    @engine.finalize(@engine.allow_all(k8s_query("u", []))).effect
    is @engine.Effect::Allow,
  )
  assert_true(
    @engine.finalize(@engine.deny_all(k8s_query("u", []))).effect
    is @engine.Effect::Deny,
  )
}

///|
test "predicate atoms allow on match, abstain otherwise" {
  let q = k8s_query("alice", ["team-a", "platform"], ns="team-a")
  assert_true(@engine.subject_is("alice")(q).effect is @engine.Effect::Allow)
  assert_true(@engine.subject_is("bob")(q).effect is @engine.Effect::Abstain)
  assert_true(
    @engine.subject_in_group("platform")(q).effect is @engine.Effect::Allow,
  )
  assert_true(
    @engine.subject_in_group("nobody")(q).effect is @engine.Effect::Abstain,
  )
  assert_true(
    @engine.verb_in(["create", "update"])(q).effect is @engine.Effect::Allow,
  )
  assert_true(@engine.verb_in(["delete"])(q).effect is @engine.Effect::Abstain)
  assert_true(
    @engine.kind_is(@engine.AccessKind::WriteAccess)(q).effect
    is @engine.Effect::Allow,
  )
  assert_true(
    @engine.kind_is(@engine.AccessKind::ReadAccess)(q).effect
    is @engine.Effect::Abstain,
  )
  assert_true(@engine.ns_is("team-a")(q).effect is @engine.Effect::Allow)
  assert_true(@engine.ns_is("team-b")(q).effect is @engine.Effect::Abstain)
  assert_true(@engine.k8s_kind_is("Pod")(q).effect is @engine.Effect::Allow)
  assert_true(
    @engine.k8s_kind_is("Secret")(q).effect is @engine.Effect::Abstain,
  )
  assert_true(
    @engine.k8s_resource_is("pods")(q).effect is @engine.Effect::Allow,
  )
}

///|
test "rgw_path_in_group_ns: prefix namespaces, no prefix confusion" {
  // exact namespace
  assert_true(
    @engine.rgw_path_in_group_ns()(
      rgw_query("u", ["team-a"], bucket="team-a", object="doc.txt"),
    ).effect
    is @engine.Effect::Allow,
  )
  // nested
  assert_true(
    @engine.rgw_path_in_group_ns()(
      rgw_query("u", ["team-a"], bucket="team-a", object="a/b/c.bin"),
    ).effect
    is @engine.Effect::Allow,
  )
  // "team-ab" must not match namespace "team-a"
  assert_true(
    @engine.rgw_path_in_group_ns()(
      rgw_query("u", ["team-a"], bucket="team-ab", object="doc.txt"),
    ).effect
    is @engine.Effect::Abstain,
  )
  // bucket-level operation counts the bucket as the path
  assert_true(
    @engine.rgw_path_in_group_ns()(rgw_query("u", ["team-a"], bucket="team-a")).effect
    is @engine.Effect::Allow,
  )
  // outside every namespace
  assert_true(
    @engine.rgw_path_in_group_ns()(
      rgw_query("u", ["team-a"], bucket="public", object="x"),
    ).effect
    is @engine.Effect::Abstain,
  )
  // non-RGW query abstains
  assert_true(
    @engine.rgw_path_in_group_ns()(k8s_query("u", [])).effect
    is @engine.Effect::Abstain,
  )
}

///|
test "scoped denies out-of-scope queries regardless of body" {
  let only_team_a : @engine.Policy = @engine.scoped(
    q => q.ns() == Some("team-a"),
    @engine.allow_all,
  )
  assert_true(
    only_team_a(k8s_query("u", [], ns="team-a")).effect is @engine.Effect::Allow,
  )
  let denied = only_team_a(k8s_query("u", [], ns="team-b"))
  assert_true(denied.effect is @engine.Effect::Deny)
  assert_eq(denied.reason, "out of scope: guard failed")
}

///|
test "composed example: platform admins full access, tenants in-namespace" {
  let is_platform = @engine.subject_in_group("platform")
  let tenant_scope = @engine.scoped(
    q => q.ns() is Some(ns) && q.subject.groups.contains(ns),
    @engine.allow_all,
    reason="requester has no group matching the target namespace",
  )
  let policy : @engine.Policy = @engine.otherwise(
    @engine.and_(is_platform, @engine.allow_all),
    @engine.otherwise(tenant_scope, @engine.deny_all),
  )
  // platform admin anywhere
  assert_true(
    policy(k8s_query("a", ["platform"], ns="team-z")).effect
    is @engine.Effect::Allow,
  )
  // tenant in own namespace
  assert_true(
    policy(k8s_query("t", ["team-a"], ns="team-a")).effect
    is @engine.Effect::Allow,
  )
  // tenant in another namespace -> denied (scoped), not abstain
  let d = policy(k8s_query("t", ["team-a"], ns="team-b"))
  assert_true(d.effect is @engine.Effect::Deny)
  // no groups -> denied
  assert_true(
    policy(k8s_query("t", [], ns="team-b")).effect is @engine.Effect::Deny,
  )
}

///|
test "code/effect bridge is total" {
  assert_eq(@engine.Effect::code(@engine.Effect::Allow), @verdict.ALLOW)
  assert_eq(@engine.Effect::code(@engine.Effect::Deny), @verdict.DENY)
  assert_eq(@engine.Effect::code(@engine.Effect::Abstain), @verdict.ABSTAIN)
  for c in codes() {
    // decisions built from atoms always carry valid codes
    for p in effects() {
      let code = p(k8s_query("u", [])).code()
      assert_true(
        code == @verdict.ALLOW ||
        code == @verdict.DENY ||
        code == @verdict.ABSTAIN,
      )
      ignore(c)
    }
  }
}
