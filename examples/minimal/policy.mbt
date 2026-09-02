// examples/minimal/policy.mbt — the smallest deployable policy.
//
// Copy this directory to start your own service: swap `deny_all` for
// your decision function and everything else (transport, logging,
// metrics, fail-closed boundary) keeps working.

///|
/// The whole policy: deny everything. The engine finalizes any abstain
/// into a denial, so this deployment cannot allow anything until you
/// edit this function.
pub fn policy(_q : @engine.Query) -> @engine.Decision {
  @engine.deny_all(_q)
}
