// engine/query_test.mbt — truth tables for the cross-front-end tenant
// gates: one predicate must mean the same thing on Kubernetes and RGW.
// (query fodder `k8s_query` / `rgw_query` lives in policy_test.mbt)

///|
test "in_own_namespace on k8s: own ns yes, foreign ns no" {
  assert_true(k8s_query("u", ["team-a"], ns="team-a").in_own_namespace())
  assert_false(k8s_query("u", ["team-a"], ns="team-b").in_own_namespace())
}

///|
test "in_own_namespace on k8s: cluster-scoped is never in scope" {
  assert_false(k8s_query("u", ["team-a"], ns="").in_own_namespace())
}

///|
test "in_own_namespace on rgw: bucket or object under the group" {
  assert_true(
    rgw_query("u", ["team-a"], bucket="team-a", object="doc.txt").in_own_namespace(),
  )
  assert_true(rgw_query("u", ["team-a"], bucket="team-a").in_own_namespace())
}

///|
test "in_own_namespace on rgw: no prefix confusion, foreign bucket" {
  assert_false(
    rgw_query("u", ["team-a"], bucket="team-ab", object="x").in_own_namespace(),
  )
  assert_false(
    rgw_query("u", ["team-a"], bucket="prod", object="x").in_own_namespace(),
  )
}

///|
test "in_own_namespace: unrecognized targets are out of scope" {
  let q : @engine.Query = @engine.Query::{
    source: K8sAdmission,
    subject: @engine.Subject::{ user: "u", groups: ["team-a"], },
    verb: "create",
    kind: @engine.AccessKind::WriteAccess,
    target: @engine.Target::Unrecognized("weird"),
    object: None,
  }
  assert_false(q.in_own_namespace())
}

///|
test "path_in_any_namespace: any of the groups may own the path" {
  assert_true(path_in_any_namespace("team-b/x", ["team-a", "team-b"]))
  assert_false(path_in_any_namespace("team-a", []))
  assert_false(path_in_any_namespace("other/x", ["team-a", "team-b"]))
}
