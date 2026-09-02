// server/handlers.mbt — request handling around the user policy.
//
// The transport is policy-agnostic: parse wire JSON into a `Query`, run
// the policy, finalize (fail-closed) and render the reply. Handlers are
// plain functions so they are testable without a socket.

///|
/// What a handler produced: HTTP status, body and the audit fields.
pub(all) struct EndpointResponse {
  status : Int
  body : Json
  allowed : Bool?
  reason : String
} derive(Eq, @debug.Debug)

///|
/// The error body for malformed requests.
fn bad_request(what : String) -> Json {
  Json::object({ "error": Json::string(what) })
}

///|
/// POST /validate — Kubernetes AdmissionReview.
/// Malformed reviews answer 400; with `failurePolicy: Fail` the
/// apiserver treats that (and any transport failure) as a denial.
pub fn handle_validate(
  policy : @engine.Policy,
  body_text : String,
) -> EndpointResponse {
  let parsed : Json? = Some(@json.parse(body_text)) catch { _ => None }
  if parsed is None {
    return {
      status: 400,
      body: bad_request("request body is not valid JSON"),
      allowed: None,
      reason: "malformed body",
    }
  }
  if parsed is Some(json) && @k8s.parse_review(json) is Some(review) {
    let decision = @engine.finalize(policy(review.query))
    {
      status: 200,
      body: @k8s.reply(review.uid, decision),
      allowed: Some(decision.is_allow()),
      reason: decision.reason,
    }
  } else {
    {
      status: 400,
      body: bad_request(
        "malformed AdmissionReview (missing uid/verb/userInfo/kind)",
      ),
      allowed: None,
      reason: "malformed AdmissionReview",
    }
  }
}

///|
/// POST /v1/data/rgw/authz/allow — the OPA-compatible RGW endpoint.
/// Malformed payloads answer 400; RGW treats non-200 as a denial.
pub fn handle_rgw_allow(
  policy : @engine.Policy,
  body_text : String,
) -> EndpointResponse {
  let parsed : Json? = Some(@json.parse(body_text)) catch { _ => None }
  if parsed is None {
    return {
      status: 400,
      body: bad_request("request body is not valid JSON"),
      allowed: None,
      reason: "malformed body",
    }
  }
  if parsed is Some(json) && @ceph.parse_query(json) is Some(query) {
    let decision = @engine.finalize(policy(query))
    {
      status: 200,
      body: @ceph.reply(decision.is_allow()),
      allowed: Some(decision.is_allow()),
      reason: decision.reason,
    }
  } else {
    {
      status: 400,
      body: bad_request("malformed RGW payload (missing user/method/bucket)"),
      allowed: None,
      reason: "malformed RGW payload",
    }
  }
}

///|
/// GET / — service banner: what this deployment embeds.
pub fn banner() -> Json {
  Json::object({
    "service": Json::string("kunloria"),
    "version": Json::string(@kunloria.KUNLORIA_VERSION),
    "policy": Json::string("policy-as-code engine (see docs/adr/0001)"),
  })
}
