// server/logging.mbt — structured JSON logging on stdout.
//
// Every request logs one JSON line with timestamp, request_id, path,
// client_ip, allowed and reason, as required by the observability spec.

///|
/// Mutable counter for request ids (single-threaded async event loop).
let request_counter : Ref[Int] = { val: 0, }

///|
/// Generate a fresh request id.
pub fn next_request_id() -> String {
  request_counter.val = request_counter.val + 1
  "req-\{@env.now()}-\{request_counter.val}"
}

///|
/// Emit one structured log line to stdout.
///
/// `extra` fields are merged after ts/level/msg, preserving insertion order.
pub fn log_json(
  level : String,
  msg : String,
  extra : Map[String, Json],
) -> Unit {
  let fields : Map[String, Json] = Map([])
  fields.set("ts", Json::number(@env.now().to_double()))
  fields.set("level", Json::string(level))
  fields.set("msg", Json::string(msg))
  for k, v in extra.iter2() {
    fields.set(k, v)
  }
  println(Json::object(fields).stringify())
}

///|
/// Log an authorization decision (allowed or denied) with audit fields.
pub fn log_decision(
  request_id : String,
  path : String,
  client_ip : String,
  allowed : Bool?,
  reason : String,
) -> Unit {
  let fields : Map[String, Json] = Map([])
  fields.set("request_id", Json::string(request_id))
  fields.set("path", Json::string(path))
  fields.set("client_ip", Json::string(client_ip))
  if allowed is Some(b) {
    fields.set("allowed", Json::boolean(b))
  } else {
    fields.set("allowed", Json::string("error"))
  }
  fields.set("reason", Json::string(reason))
  log_json("info", "authz_decision", fields)
}

///|
/// Log a plain HTTP request (non-decision endpoints).
pub fn log_request(
  request_id : String,
  path : String,
  client_ip : String,
  reason : String,
) -> Unit {
  let fields : Map[String, Json] = Map([])
  fields.set("request_id", Json::string(request_id))
  fields.set("path", Json::string(path))
  fields.set("client_ip", Json::string(client_ip))
  fields.set("allowed", Json::boolean(true))
  fields.set("reason", Json::string(reason))
  log_json("info", "http_request", fields)
}

///|
/// Log at debug level (shown when log_level is `debug`).
pub fn log_debug(msg : String, extra : Map[String, Json]) -> Unit {
  log_json("debug", msg, extra)
}
