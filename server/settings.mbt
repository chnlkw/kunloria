// server/settings.mbt — deployment parameters (the only configuration
// kunloria itself has; the policy is code, not configuration, per
// ADR-0001).

///|
/// Runtime settings for the embedded server.
pub(all) struct AppSettings {
  host : String
  port : Int
  log_level : String
} derive(Eq, @debug.Debug)

///|
/// Defaults: all interfaces, port 8080, info logging.
pub fn AppSettings::defaults() -> AppSettings {
  { host: "0.0.0.0", port: 8080, log_level: "info", }
}

///|
/// Parses a TCP port with a fallback; rejects non-numeric and out-of-range.
fn parse_port(raw : String, fallback : Int) -> Int {
  try {
    let p = @string.parse_int(raw)
    if p > 0 && p < 65536 {
      p
    } else {
      fallback
    }
  } catch {
    _ => fallback
  }
}

///|
/// Reads `KUNLORIA_HOST`, `KUNLORIA_PORT` and `KUNLORIA_LOG_LEVEL` from
/// the environment; missing or malformed values fall back to defaults.
pub fn AppSettings::from_env() -> AppSettings {
  let defaults = AppSettings::defaults()
  let host = @env.get_env_var("KUNLORIA_HOST").unwrap_or(defaults.host)
  let port = if @env.get_env_var("KUNLORIA_PORT") is Some(raw) {
    parse_port(raw, defaults.port)
  } else {
    defaults.port
  }
  let log_level = @env.get_env_var("KUNLORIA_LOG_LEVEL").unwrap_or(
    defaults.log_level,
  )
  { host, port, log_level, }
}
