// server/metrics.mbt — minimal Prometheus text-format counters.
//
// Counters are plain mutable refs: moonbitlang/async drives the event loop
// on a single thread, so no synchronization is required. Latency histograms
// and a dedicated client library are roadmap items (see docs/observability).

///|
/// Server-wide counters exposed on /metrics.
pub(all) struct Metrics {
  requests_total : Ref[Int]
  allowed_total : Ref[Int]
  denied_total : Ref[Int]
}

///|
/// Fresh zeroed metrics.
pub fn Metrics::new() -> Metrics {
  {
    requests_total: { val: 0 },
    allowed_total: { val: 0 },
    denied_total: { val: 0 },
  }
}

///|
/// Count one policy decision.
pub fn Metrics::record(self : Metrics, allowed : Bool) -> Unit {
  self.requests_total.val = self.requests_total.val + 1
  if allowed {
    self.allowed_total.val = self.allowed_total.val + 1
  } else {
    self.denied_total.val = self.denied_total.val + 1
  }
}

///|
/// Count one plain (non-decision) request.
pub fn Metrics::touch(self : Metrics) -> Unit {
  self.requests_total.val = self.requests_total.val + 1
}

///|
/// Render counters in the Prometheus text exposition format.
pub fn Metrics::render(self : Metrics) -> String {
  let requests = "# TYPE kunloria_requests_total counter\nkunloria_requests_total \{self.requests_total.val}\n"
  let allowed = "# TYPE kunloria_allowed_total counter\nkunloria_allowed_total \{self.allowed_total.val}\n"
  let denied = "# TYPE kunloria_denied_total counter\nkunloria_denied_total \{self.denied_total.val}\n"
  "\{requests}\{allowed}\{denied}"
}
