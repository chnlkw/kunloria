// proof/policy_test.mbt — executable truth-table tests for the verified core.
//
// These complement `moon prove`: the contracts guarantee the security
// properties; the tests pin the concrete decision table so any accidental
// change of the core semantics fails `moon test` immediately.

///|
test "admin allows every kind regardless of prefix" {
  assert_true(@proof.decide(@proof.ROLE_ADMIN, @proof.KIND_READ, false))
  assert_true(@proof.decide(@proof.ROLE_ADMIN, @proof.KIND_WRITE, false))
  assert_true(@proof.decide(@proof.ROLE_ADMIN, @proof.KIND_UNKNOWN, false))
}

///|
test "reader allows reads only inside its group prefix" {
  assert_true(@proof.decide(@proof.ROLE_READER, @proof.KIND_READ, true))
  assert_false(@proof.decide(@proof.ROLE_READER, @proof.KIND_READ, false))
  assert_false(@proof.decide(@proof.ROLE_READER, @proof.KIND_WRITE, true))
  assert_false(@proof.decide(@proof.ROLE_READER, @proof.KIND_UNKNOWN, true))
}

///|
test "writer allows writes only inside its group prefix" {
  assert_true(@proof.decide(@proof.ROLE_WRITER, @proof.KIND_WRITE, true))
  assert_false(@proof.decide(@proof.ROLE_WRITER, @proof.KIND_WRITE, false))
  assert_false(@proof.decide(@proof.ROLE_WRITER, @proof.KIND_READ, true))
  assert_false(@proof.decide(@proof.ROLE_WRITER, @proof.KIND_UNKNOWN, true))
}

///|
test "unmapped role is always denied" {
  assert_false(@proof.decide(@proof.ROLE_NONE, @proof.KIND_READ, true))
  assert_false(@proof.decide(@proof.ROLE_NONE, @proof.KIND_UNKNOWN, true))
}
