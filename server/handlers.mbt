// server/handlers.mbt — endpoint logic, pure and testable.
//
// Each endpoint is a pure function from request body to
// (status, response JSON). The moonback wiring in app.mbt only adds
// transport, logging and metrics around them, which keeps the full
// parse -> decide -> respond pipeline coverable by unit tests.

///|
/// An endpoint's HTTP answer plus the audit facts for structured logging.
pub(all) struct EndpointResponse {
  status : Int
  body : Json
  allowed : Bool
  reason : String
} derive(Eq, @debug.Debug)

///|
/// POST /validate — Kubernetes AdmissionReview.
///
/// Returns an `admission.k8s.io/v1` AdmissionReview carrying the verdict.
/// Malformed bodies answer 400 with an error object (fail closed: the API
/// server treats non-200 as denial with `failurePolicy: Fail`).
pub fn handle_validate(
  settings : AppSettings,
  metrics : Metrics,
  body : String,
) -> EndpointResponse {
  let review = @json.parse(body) catch {
    e => return bad_request(metrics, "invalid AdmissionReview JSON: \{e}")
  }
  let verdict = @k8s.evaluate(settings.admission, review)
  metrics.record(verdict.decision.allowed)
  let response : Map[String, Json] = Map([])
  response.set("uid", Json::string(verdict.uid))
  response.set("allowed", Json::boolean(verdict.decision.allowed))
  if !verdict.decision.allowed {
    let status : Map[String, Json] = Map([])
    status.set("code", Json::number(403))
    status.set("message", Json::string(verdict.decision.reason))
    response.set("status", Json::object(status))
  }
  let envelope : Map[String, Json] = Map([])
  envelope.set("apiVersion", Json::string("admission.k8s.io/v1"))
  envelope.set("kind", Json::string("AdmissionReview"))
  envelope.set("response", Json::object(response))
  {
    status: 200,
    body: Json::object(envelope),
    allowed: verdict.decision.allowed,
    reason: verdict.decision.reason,
  }
}

///|
/// POST /v1/data/rgw/authz/allow — Ceph RGW (OPA-compatible).
///
/// Answers `{"result": <bool>}` as RGW expects. Malformed payloads answer
/// 400; RGW then treats the request as denied.
pub fn handle_rgw_allow(
  settings : AppSettings,
  metrics : Metrics,
  body : String,
) -> EndpointResponse {
  let parsed = @json.parse(body) catch {
    e => return bad_request(metrics, "invalid RGW JSON: \{e}")
  }
  let query = @ceph.parse_query(parsed)
  guard query is Some(q) else {
    return bad_request(
      metrics, "payload misses input.user.id; nothing to authorize",
    )
  }
  let decision = @ceph.decide(settings.policy, q)
  metrics.record(decision.allowed)
  let result : Map[String, Json] = Map([])
  result.set("result", Json::boolean(decision.allowed))
  {
    status: 200,
    body: Json::object(result),
    allowed: decision.allowed,
    reason: decision.reason,
  }
}

///|
/// 400 helper that also counts the request as denied.
fn bad_request(metrics : Metrics, message : String) -> EndpointResponse {
  metrics.record(false)
  let error : Map[String, Json] = Map([])
  error.set("error", Json::string(message))
  { status: 400, body: Json::object(error), allowed: false, reason: message, }
}

///|
/// GET / — service banner used as the MVP landing page.
pub fn banner() -> String {
  "kunloria policy engine \{@kunloria.KUNLORIA_VERSION}\n"
}
