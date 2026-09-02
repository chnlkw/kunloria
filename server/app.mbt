// server/app.mbt — moonback wiring.
//
// Transport only: every decision comes from the user policy through the
// pure handlers, so the route table below is deliberately boring.

///|
/// Build the moonback module serving every kunloria route around one
/// policy:
///
/// - GET  /                        service banner
/// - GET  /healthz                 liveness probe
/// - GET  /metrics                 Prometheus text counters
/// - POST /validate                Kubernetes AdmissionReview
/// - POST /v1/data/rgw/authz/allow Ceph RGW (OPA-compatible)
pub fn root_module(
  policy : @engine.Policy,
  metrics : Metrics,
) -> @moonback.Module {
  @moonback.Module(ctx => {
    ctx.get("/", (req, res) => {
      metrics.touch()
      log_request(next_request_id(), "/".to_string(), ip_of(req), "banner")
      res.send_json(banner())
    })
    ctx.get("/healthz", (req, res) => {
      metrics.touch()
      log_request(next_request_id(), "/healthz".to_string(), ip_of(req), "ok")
      res.send_text("ok")
    })
    ctx.get("/metrics", (req, res) => {
      metrics.touch()
      log_request(next_request_id(), "/metrics".to_string(), ip_of(req), "ok")
      res.send_text(metrics.render())
    })
    ctx.post("/validate", (req, res) => {
      let body = req.body.text()
      let answer = handle_validate(policy, body)
      record(metrics, answer)
      log_decision(
        next_request_id(),
        "/validate".to_string(),
        ip_of(req),
        answer.allowed,
        answer.reason,
      )
      res.send_json(answer.body, status=answer.status)
    })
    ctx.post("/v1/data/rgw/authz/allow", (req, res) => {
      let body = req.body.text()
      let answer = handle_rgw_allow(policy, body)
      record(metrics, answer)
      log_decision(
        next_request_id(),
        "/v1/data/rgw/authz/allow".to_string(),
        ip_of(req),
        answer.allowed,
        answer.reason,
      )
      res.send_json(answer.body, status=answer.status)
    })
  })
}

///|
/// Counts a decision into the metrics (malformed requests count as
/// denied — they never become allows).
fn record(metrics : Metrics, answer : EndpointResponse) -> Unit {
  metrics.record(answer.allowed == Some(true))
}

///|
/// Best-effort client IP of a request ("" when unavailable).
fn ip_of(req : @moonback.Request) -> String {
  match req.ip() {
    Some(ip) => ip.to_owned()
    None => ""
  }
}
