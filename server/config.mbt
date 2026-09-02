// server/config.mbt — runtime configuration, injected via environment
// variables (the constraint "no external database" makes env the MVP
// source; a config.yaml loader is on the roadmap, see docs/configuration.md).

///|
/// Everything the server needs at runtime.
pub(all) struct AppSettings {
  host : String
  port : Int
  policy : @auth.PolicyConfig
  admission : @k8s.AdmissionSettings
  log_level : String
} derive(Eq, @debug.Debug)

///|
/// Read settings from `KUNLORIA_*` environment variables.
///
/// - `KUNLORIA_HOST` (default `0.0.0.0`)
/// - `KUNLORIA_PORT` (default `8080`)
/// - `KUNLORIA_LOG_LEVEL` (`debug` or `info`, default `info`)
/// - `KUNLORIA_ADMIN_GROUPS` / `KUNLORIA_READER_GROUPS` /
///   `KUNLORIA_WRITER_GROUPS`: comma-separated group lists
/// - `KUNLORIA_ENFORCE_NAMESPACES`: comma-separated; empty enforces everywhere
/// - `KUNLORIA_RISKY_CLUSTER_ROLES`: comma-separated, default `cluster-admin`
/// - `KUNLORIA_ADMITTED_BINDINGS`: comma-separated `<ns>:<serviceaccount>`
pub fn AppSettings::from_env() -> AppSettings {
  let admin = env_list("KUNLORIA_ADMIN_GROUPS", ["admin"])
  let reader = env_list("KUNLORIA_READER_GROUPS", ["reader", "readers"])
  let writer = env_list("KUNLORIA_WRITER_GROUPS", ["writer", "writers"])
  let admission : @k8s.AdmissionSettings = {
    enforce_namespaces: env_list("KUNLORIA_ENFORCE_NAMESPACES", []),
    risky_cluster_roles: env_list("KUNLORIA_RISKY_CLUSTER_ROLES", [
      "cluster-admin",
    ]),
    admitted_bindings: env_list("KUNLORIA_ADMITTED_BINDINGS", []),
  }
  {
    host: env_string("KUNLORIA_HOST", "0.0.0.0"),
    port: env_int("KUNLORIA_PORT", 8080),
    policy: @auth.PolicyConfig::of_groups(admin~, reader~, writer~),
    admission,
    log_level: env_string("KUNLORIA_LOG_LEVEL", "info"),
  }
}

///|
/// Read a string variable with a default.
fn env_string(name : String, fallback : String) -> String {
  match @env.get_env_var(name) {
    Some(v) => v
    None => fallback
  }
}

///|
/// Read an integer variable with a default.
fn env_int(name : String, fallback : Int) -> Int {
  match @env.get_env_var(name) {
    Some(v) => @string.parse_int(v) catch { _ => fallback }
    None => fallback
  }
}

///|
/// Read a comma-separated list variable with a default.
fn env_list(name : String, fallback : Array[String]) -> Array[String] {
  match @env.get_env_var(name) {
    Some(v) => {
      let out : Array[String] = []
      for part in v.split(",") {
        let trimmed = part.trim()
        if trimmed != "" {
          out.push(trimmed.to_owned())
        }
      }
      if out.length() == 0 {
        fallback
      } else {
        out
      }
    }
    None => fallback
  }
}
