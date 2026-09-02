# Configuration

Kunloria has almost nothing to configure, by design
([ADR-0001](adr/0001-policy-as-code-engine.md)): **the policy is code**,
compiled into the deployment. There is no policy DSL, no policy YAML,
and no policy-bearing environment variable. Roles, groups, namespaces
and content constraints are constants in `policy.mbt`; changing them is
a code change that ships through your GitOps pipeline.

## Runtime environment variables

The only knobs are deployment parameters, read by `examples/*/main`:

| Variable | Default | Meaning |
| --- | --- | --- |
| `KUNLORIA_HOST` | `0.0.0.0` | Listen address |
| `KUNLORIA_PORT` | `8080` | Listen port |
| `KUNLORIA_LOG_LEVEL` | `info` | `info` or `debug` |

Missing or malformed values fall back to the defaults.

## Where the policy knobs went

The pre-rewrite service exposed `KUNLORIA_ADMIN_GROUPS`,
`KUNLORIA_READER_GROUPS`, `KUNLORIA_WRITER_GROUPS`,
`KUNLORIA_ENFORCE_NAMESPACES`, `KUNLORIA_RISKY_CLUSTER_ROLES` and
`KUNLORIA_ADMITTED_BINDINGS`. All of them became **constants owned by
`examples/rgw-tenant/policy.mbt`** (`admin_groups()`, `reader_groups()`,
`writer_groups()`, `risky_roles()`, `admitted_bindings()`) — that
example reproduces the old behavior exactly. Copy it and make the lists
yours.

## Semantics that never changed

* Most privileged role wins (admin > writer > reader); unmapped groups
  grant nothing.
* Everything not explicitly allowed is denied — fail closed — including
  malformed payloads, unknown verbs, and any policy that abstains.
