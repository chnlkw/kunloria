// examples/k8s-write-authz/policy.mbt — subject-based write-path
// authorization assembled from engine combinators.
//
// Policy, in plain words:
//   1. platform admins may do anything — except deploying privileged
//      pods or binding risky roles (content constraints bind everyone);
//   2. a tenant (a group with a namespace of the same name) may act
//      freely inside its own namespace;
//   3. everyone else is denied (the fail-closed boundary also turns any
//      abstain into a denial).

///|
/// ClusterRoles that may not be bound by anyone in this deployment.
fn risky_roles() -> Array[String] {
  ["cluster-admin"]
}

///|
/// Content constraint: the object must not be a privileged pod.
fn no_privileged_pod(q : @engine.Query) -> Bool {
  if q.object is Some(obj) {
    !(@k8s.targets_pod(q) && @k8s.pod_has_privileged_container(obj))
  } else {
    true
  }
}

///|
/// Content constraint: the object must not bind a risky role.
fn no_risky_binding(q : @engine.Query) -> Bool {
  if q.object is Some(obj) {
    !((
      @k8s.target_kind_is(q, "RoleBinding") ||
      @k8s.target_kind_is(q, "ClusterRoleBinding")
    ) &&
    @k8s.binding_grants_risky_role(obj, risky_roles()))
  } else {
    true
  }
}

///|
/// A constraint: denies when violated, abstains when satisfied. The
/// abstain (not an allow!) lets `otherwise` fall through to the
/// subject-based layers, while a denial dominates every later layer.
fn satisfies(pred : (@engine.Query) -> Bool, why : String) -> @engine.Policy {
  q => {
    if pred(q) {
      @engine.Decision::abstain()
    } else {
      @engine.Decision::deny("violated constraint: \{why}")
    }
  }
}

///|
/// A tenant may act inside the namespace named after one of its groups.
fn tenant_in_own_ns(q : @engine.Query) -> Bool {
  if q.ns() is Some(ns) {
    q.subject.groups.contains(ns)
  } else {
    false
  }
}

///|
/// The assembled policy.
pub fn policy(q : @engine.Query) -> @engine.Decision {
  @engine.otherwise(
    // 1. content constraints bind everyone, admins included
    @engine.and_(
      satisfies(no_privileged_pod, "pods must not run privileged"),
      satisfies(no_risky_binding, "risky roles must not be bound"),
    ),
    @engine.otherwise(
      // 2. platform admins: everything else goes
      @engine.and_(@engine.subject_in_group("platform"), @engine.allow_all),
      @engine.otherwise(
        // 3. tenants: free inside their own namespace
        @engine.scoped(
          tenant_in_own_ns,
          @engine.allow_all,
          reason="subject has no group matching the target namespace",
        ),
        // 4. deny everything else
        @engine.deny_all,
      ),
    ),
  )(q)
}
