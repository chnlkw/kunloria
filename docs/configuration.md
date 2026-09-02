# Configuration

Kunloria follows the "no external database" constraint: all policy data is
injected at startup. The MVP reads environment variables; `config.yaml`
loading is planned (tracked in the roadmap) — `config/kunloria.yaml.example`
documents the target schema.

## Environment variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `KUNLORIA_HOST` | `0.0.0.0` | Listen address |
| `KUNLORIA_PORT` | `8080` | Listen port |
| `KUNLORIA_LOG_LEVEL` | `info` | `info` or `debug` |
| `KUNLORIA_ADMIN_GROUPS` | `admin` | Comma-separated groups granting the Admin role |
| `KUNLORIA_READER_GROUPS` | `reader,readers` | Groups granting the Reader role |
| `KUNLORIA_WRITER_GROUPS` | `writer,writers` | Groups granting the Writer role |
| `KUNLORIA_ENFORCE_NAMESPACES` | *(empty)* | When set, only these namespaces are evaluated; others are allowed as "skipped" |
| `KUNLORIA_RISKY_CLUSTER_ROLES` | `cluster-admin` | ClusterRoles that trigger the binding check |
| `KUNLORIA_ADMITTED_BINDINGS` | *(empty)* | `<namespace>:<serviceaccount>` entries allowed to receive a risky role |

## Semantics

* A user's group is both its **role** (via the lists above) and its
  **namespace prefix**: resources are group-scoped by construction.
* Most privileged role wins when a user carries several mapped groups
  (Admin > Writer > Reader); unmapped groups grant nothing.
* Everything not explicitly allowed is denied (fail closed), including
  malformed payloads and unknown verbs.
