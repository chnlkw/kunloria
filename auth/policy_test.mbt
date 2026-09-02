// auth/policy_test.mbt — blackbox tests of the authorization policy.
//
// These exercise the same decision table as the verified properties in
// proof/policy.mbtp, through the typed `authorize` entry point.

///|
fn cfg() -> @auth.PolicyConfig {
  @auth.PolicyConfig::of_groups(admin=["admin"], reader=["groupA"], writer=[
    "groupB",
  ])
}

///|
test "admin is always allowed" {
  let c = cfg()
  let subj = c.subject_for(id="root", groups=["admin", "other"])
  let d = @auth.authorize(subj, @auth.Write, "any/path/at/all")
  assert_true(d.allowed)
  let d = @auth.authorize(subj, @auth.Read, "")
  assert_true(d.allowed)
}

///|
test "reader reads only inside its group prefix" {
  let c = cfg()
  let subj = c.subject_for(id="alice", groups=["groupA"])
  let ok = @auth.authorize(subj, @auth.Read, "groupA/path/to/file")
  assert_true(ok.allowed)
  let cross = @auth.authorize(subj, @auth.Read, "groupB/secret")
  assert_false(cross.allowed)
}

///|
test "reader never writes" {
  let c = cfg()
  let subj = c.subject_for(id="alice", groups=["groupA"])
  let d = @auth.authorize(subj, @auth.Write, "groupA/file")
  assert_false(d.allowed)
  assert_eq(d.role, @auth.Reader)
}

///|
test "writer writes only inside its group prefix" {
  let c = cfg()
  let subj = c.subject_for(id="bob", groups=["groupB"])
  let ok = @auth.authorize(subj, @auth.Write, "groupB/dir/object")
  assert_true(ok.allowed)
  let read = @auth.authorize(subj, @auth.Read, "groupB/dir/object")
  assert_false(read.allowed)
  let cross = @auth.authorize(subj, @auth.Write, "groupA/file")
  assert_false(cross.allowed)
}

///|
test "unmapped groups carry no role and are denied" {
  let c = cfg()
  let subj = c.subject_for(id="eve", groups=["strangers"])
  let d = @auth.authorize(subj, @auth.Read, "strangers/file")
  assert_false(d.allowed)
  assert_eq(d.role, @auth.NoRole)
}

///|
test "unknown actions are denied to every non-admin role" {
  let c = cfg()
  let reader = c.subject_for(id="alice", groups=["groupA"])
  let writer = c.subject_for(id="bob", groups=["groupB"])
  assert_false(@auth.authorize(reader, @auth.Unknown, "groupA/x").allowed)
  assert_false(@auth.authorize(writer, @auth.Unknown, "groupB/x").allowed)
}

///|
test "group namespace matches the group itself and nested paths only" {
  assert_true(@auth.path_in_group("groupA", "groupA"))
  assert_true(@auth.path_in_group("groupA/x", "groupA"))
  assert_true(@auth.path_in_group("groupA/x/y", "groupA"))
  // Prefix confusion is rejected: "groupAB" is a different namespace.
  assert_false(@auth.path_in_group("groupAB/x", "groupA"))
  assert_false(@auth.path_in_group("groupA", ""))
  assert_false(@auth.path_in_group("prefixgroupA", "groupA"))
}

///|
test "decision carries an audit reason" {
  let c = cfg()
  let subj = c.subject_for(id="alice", groups=["groupA"])
  let d = @auth.authorize(subj, @auth.Write, "groupA/file")
  assert_false(d.allowed)
  assert_true(d.reason.contains("reader"))
}
