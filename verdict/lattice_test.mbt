// verdict/lattice_test.mbt — executable truth tables pinning the lattice.

///|
fn all_codes() -> Array[Int] {
  [@verdict.ALLOW, @verdict.DENY, @verdict.ABSTAIN]
}

///|
test "conjunction: deny dominates, abstain propagates" {
  for a in all_codes() {
    for b in all_codes() {
      let r = @verdict.combine_and(a, b)
      if a == @verdict.DENY || b == @verdict.DENY {
        assert_eq(r, @verdict.DENY)
      } else if a == @verdict.ABSTAIN || b == @verdict.ABSTAIN {
        assert_eq(r, @verdict.ABSTAIN)
      } else {
        assert_eq(r, @verdict.ALLOW)
      }
    }
  }
}

///|
test "disjunction: allow dominates, abstain propagates" {
  for a in all_codes() {
    for b in all_codes() {
      let r = @verdict.combine_or(a, b)
      if a == @verdict.ALLOW || b == @verdict.ALLOW {
        assert_eq(r, @verdict.ALLOW)
      } else if a == @verdict.ABSTAIN || b == @verdict.ABSTAIN {
        assert_eq(r, @verdict.ABSTAIN)
      } else {
        assert_eq(r, @verdict.DENY)
      }
    }
  }
}

///|
test "negation flips allow and deny, keeps abstain" {
  assert_eq(@verdict.negate(@verdict.ALLOW), @verdict.DENY)
  assert_eq(@verdict.negate(@verdict.DENY), @verdict.ALLOW)
  assert_eq(@verdict.negate(@verdict.ABSTAIN), @verdict.ABSTAIN)
}

///|
test "algebra spot checks" {
  for a in all_codes() {
    // identities
    assert_eq(@verdict.combine_and(a, @verdict.ALLOW), a)
    assert_eq(@verdict.combine_or(a, @verdict.DENY), a)
    // idempotence
    assert_eq(@verdict.combine_and(a, a), a)
    assert_eq(@verdict.combine_or(a, a), a)
    // involution
    assert_eq(@verdict.negate(@verdict.negate(a)), a)
    for b in all_codes() {
      // commutativity
      assert_eq(@verdict.combine_and(a, b), @verdict.combine_and(b, a))
      // De Morgan
      assert_eq(
        @verdict.negate(@verdict.combine_and(a, b)),
        @verdict.combine_or(@verdict.negate(a), @verdict.negate(b)),
      )
    }
  }
}
