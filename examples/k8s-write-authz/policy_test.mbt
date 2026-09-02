// examples/k8s-write-authz/policy_test.mbt — combinator assembly in action.

///|
fn q(
  groups : Array[String],
  ns? : String = "team-a",
  object? : Json? = None,
) -> @engine.Query {
  @engine.Query::{
    source: @engine.Source::K8sAdmission,
    subject: @engine.Subject::{ user: "u", groups, },
    verb: "create",
    kind: @engine.AccessKind::WriteAccess,
    target: @engine.Target::K8s(@engine.K8sRef::{
      api_group: "",
      kind: "Pod",
      resource: "pods",
      subresource: "",
      name: "",
      ns,
    }),
    object,
  }
}

///|
test "platform group: allowed, but not privileged pods or risky bindings" {
  assert_true(policy(q(["platform"])).effect is @engine.Effect::Allow)
  let priv_obj : Json? = Some(
    @json.parse(
      (
        #|{"spec": {"containers": [
        #|  {"name": "app", "securityContext": {"privileged": true}}]}}
      ),
    ),
  )
  let d = policy(q(["platform"], object=priv_obj))
  assert_true(d.effect is @engine.Effect::Deny)
}

///|
test "tenant allowed inside own namespace, denied outside" {
  assert_true(policy(q(["team-a"])).effect is @engine.Effect::Allow)
  let d = policy(q(["team-a"], ns="team-b"))
  assert_true(d.effect is @engine.Effect::Deny)
}

///|
test "groupless subject denied (fail-closed)" {
  assert_true(policy(q([])).effect is @engine.Effect::Deny)
}

///|
test "content constraints bind tenants too" {
  let priv_obj : Json? = Some(
    @json.parse(
      (
        #|{"spec": {"containers": [
        #|  {"name": "app", "securityContext": {"privileged": true}}]}}
      ),
    ),
  )
  // tenant in own namespace still cannot deploy privileged pods
  let d = policy(q(["team-a"], object=priv_obj))
  assert_true(d.effect is @engine.Effect::Deny)
}
