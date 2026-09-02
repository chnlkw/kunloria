// examples/rgw-tenant/policy_test.mbt — the v0.1 truth tables as code.
//
// These pin the semantics the MVP shipped: role precedence, group-prefix
// isolation on RGW, reader-never-writes, and the Kubernetes content
// constraints.

///|
fn rgw_q(
  user : String,
  groups : Array[String],
  bucket : String,
  object_ : String,
  write~ : Bool,
) -> @engine.Query {
  @engine.Query::{
    source: @engine.Source::Rgw,
    subject: @engine.Subject::{ user, groups, },
    verb: if write {
      "s3:putobject"
    } else {
      "s3:getobject"
    },
    kind: if write {
      @engine.AccessKind::WriteAccess
    } else {
      @engine.AccessKind::ReadAccess
    },
    target: @engine.Target::Rgw(@engine.RgwRef::{ bucket, object_key: object_, }),
    object: None,
  }
}

///|
fn k8s_q(
  user : String,
  groups : Array[String],
  kind? : String = "Pod",
  object? : Json? = None,
) -> @engine.Query {
  @engine.Query::{
    source: @engine.Source::K8sAdmission,
    subject: @engine.Subject::{ user, groups, },
    verb: "create",
    kind: @engine.AccessKind::WriteAccess,
    target: @engine.Target::K8s(@engine.K8sRef::{
      api_group: "",
      kind,
      resource: "pods",
      subresource: "",
      name: "",
      ns: "prod",
    }),
    object,
  }
}

///|
test "admin groups are always allowed" {
  for g in ["platform", "admins"] {
    let d = policy(rgw_q("u", [g], "anywhere", "deep/x.bin", write=true))
    assert_true(d.effect is @engine.Effect::Allow)
  }
}

///|
test "reader: reads inside its namespace, never writes" {
  let read = policy(
    rgw_q("u", ["readers", "team-a"], "team-a", "doc.txt", write=false),
  )
  assert_true(read.effect is @engine.Effect::Allow)
  let write = policy(
    rgw_q("u", ["readers", "team-a"], "team-a", "doc.txt", write=true),
  )
  assert_true(write.effect is @engine.Effect::Deny)
}

///|
test "writer: writes inside its namespace, no reads of other kinds" {
  let write = policy(
    rgw_q("u", ["writers", "team-a"], "team-a", "doc.txt", write=true),
  )
  assert_true(write.effect is @engine.Effect::Allow)
}

///|
test "group isolation: outside every namespace denied, no prefix confusion" {
  // bucket not named after any group
  let d = policy(rgw_q("u", ["readers", "team-a"], "public", "x", write=false))
  assert_true(d.effect is @engine.Effect::Deny)
  // "team-ab" is not the namespace "team-a"
  let d2 = policy(
    rgw_q("u", ["readers", "team-a"], "team-ab", "x", write=false),
  )
  assert_true(d2.effect is @engine.Effect::Deny)
}

///|
test "roleless subject inside its own namespace is denied" {
  // group "team-a" matches the path but maps to no role
  let d = policy(rgw_q("u", ["team-a"], "team-a", "x", write=false))
  assert_true(d.effect is @engine.Effect::Deny)
}

///|
test "unknown access kind is denied for reader and writer" {
  let q : @engine.Query = @engine.Query::{
    source: @engine.Source::Rgw,
    subject: @engine.Subject::{ user: "u", groups: ["readers", "team-a"], },
    verb: "s3:tagbucket",
    kind: @engine.AccessKind::UnknownAccess,
    target: @engine.Target::Rgw(@engine.RgwRef::{
      bucket: "team-a",
      object_key: "",
    }),
    object: None,
  }
  assert_true(policy(q).effect is @engine.Effect::Deny)
}

///|
test "k8s: privileged pod denied, normal pod allowed" {
  let priv_obj : Json? = Some(
    @json.parse(
      (
        #|{"spec": {"containers": [
        #|  {"name": "app", "securityContext": {"privileged": true}}]}}
      ),
    ),
  )
  let d = policy(k8s_q("dev", ["team-a"], object=priv_obj))
  assert_true(d.effect is @engine.Effect::Deny)
  let plain : Json? = Some(
    @json.parse("{\"spec\": {\"containers\": [{\"name\": \"app\"}]}}"),
  )
  let d2 = policy(k8s_q("dev", ["team-a"], object=plain))
  assert_true(d2.effect is @engine.Effect::Allow)
}

///|
test "k8s: risky binding denied unless subject is admitted" {
  let risky : Json? = Some(
    @json.parse(
      (
        #|{"roleRef": {"kind": "ClusterRole", "name": "cluster-admin"},
        #| "subjects": [{"kind": "User", "name": "eve"}]}
      ),
    ),
  )
  let d = policy(
    k8s_q("dev", ["team-a"], kind="ClusterRoleBinding", object=risky),
  )
  assert_true(d.effect is @engine.Effect::Deny)
  let admitted : Json? = Some(
    @json.parse(
      (
        #|{"roleRef": {"kind": "ClusterRole", "name": "cluster-admin"},
        #| "subjects": [{"kind": "ServiceAccount", "namespace": "kube-system",
        #|               "name": "boundary-automation"}]}
      ),
    ),
  )
  let d2 = policy(
    k8s_q("dev", ["team-a"], kind="ClusterRoleBinding", object=admitted),
  )
  assert_true(d2.effect is @engine.Effect::Allow)
}
