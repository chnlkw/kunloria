// k8s/parse.mbt — AdmissionReview → Query plus the reply envelope.
//
// Parsing uses MoonBit's native map patterns (see the core/json README,
// "Object Navigation"): one nested `is` pattern both checks presence and
// types and binds the fields; anything unexpected falls through to `None`
// (fail-closed), which the transport answers with 400 — and with
// `failurePolicy: Fail` the apiserver denies the request.
//
// JSON keys are string literals, so wire names like "namespace" that
// collide with MoonBit reserved words are not a problem here.

///|
/// A parsed admission review: the engine query plus the request uid needed
/// to build the reply envelope.
pub(all) struct Review {
  uid : String
  query : @engine.Query
}

///|
/// Coarse classification of an admission verb (case-insensitive).
/// CREATE/UPDATE/PATCH/DELETE/CONNECT are writes; GET/LIST/WATCH are
/// reads (rare on this channel); anything else stays unknown.
pub fn classify_admission_verb(verb : String) -> @engine.AccessKind {
  let v = verb.to_lower()
  if v == "create" ||
    v == "update" ||
    v == "patch" ||
    v == "delete" ||
    v == "connect" {
    @engine.AccessKind::WriteAccess
  } else if v == "get" || v == "list" || v == "watch" {
    @engine.AccessKind::ReadAccess
  } else {
    @engine.AccessKind::UnknownAccess
  }
}

///|
/// Best-effort pluralization of a Kind for the resource field
/// ("Pod" → "pods", "Ingress" → "ingresses", "NetworkPolicy" →
/// "networkpolicies", "Endpoints" → "endpoints"). Used only when the
/// review does not carry an explicit `resource` attribute.
pub fn pluralize(kind : String) -> String {
  if kind == "Endpoints" {
    "endpoints"
  } else if kind.has_suffix("s") ||
    kind.has_suffix("x") ||
    kind.has_suffix("ch") ||
    kind.has_suffix("sh") {
    "\{kind.to_lower()}es"
  } else if kind.has_suffix("y") && kind.length() > 1 {
    let stem = kind[:kind.length() - 1].to_owned().to_lower()
    "\{stem}ies"
  } else {
    "\{kind.to_lower()}s"
  }
}

///|
/// String elements of an optional JSON array field; missing field or
/// non-string elements are skipped.
fn opt_strings(field : Json?) -> Array[String] {
  let out : Array[String] = []
  if field is Some(Array(items)) {
    for item in items {
      if item is String(s) {
        out.push(s)
      }
    }
  }
  out
}

///|
/// Lowers an AdmissionReview body into a `Review`; `None` = malformed.
pub fn parse_review(body : Json) -> Review? {
  if body
    is {
      "request": {
        "uid": String(uid),
        "verb": String(verb),
        "userInfo": { "username": String(user), "groups"? : groups, .. },
        "kind": { "kind": String(kind), "group"? : api_group, .. },
        "resource"? : resource,
        "subResource"? : subresource,
        "name"? : name,
        "namespace"? : ns,
        "object"? : object,
        ..
      },
      ..
    } {
    Some(Review::{
      uid,
      query: @engine.Query::{
        source: @engine.Source::K8sAdmission,
        subject: @engine.Subject::{ user, groups: opt_strings(groups), },
        verb: verb.to_lower(),
        kind: classify_admission_verb(verb),
        target: @engine.Target::K8s(@engine.K8sRef::{
          api_group: if api_group is Some(String(g)) {
            g
          } else {
            ""
          },
          kind,
          resource: if resource is Some({ "resource": String(r), .. }) {
            r
          } else {
            pluralize(kind)
          },
          subresource: if subresource is Some(String(s)) {
            s
          } else {
            ""
          },
          name: if name is Some(String(n)) {
            n
          } else {
            ""
          },
          ns: if ns is Some(String(n)) {
            n
          } else {
            ""
          },
        }),
        object,
      },
    })
  } else {
    None
  }
}

///|
/// The AdmissionReview reply envelope for a finalized decision.
/// Denials carry a 403 status with the reason so `kubectl describe`
/// surfaces it.
pub fn reply(uid : String, decision : @engine.Decision) -> Json {
  let allowed = decision.is_allow()
  let response : Map[String, Json] = {
    "uid": Json::string(uid),
    "allowed": Json::boolean(allowed),
  }
  if !allowed {
    response.set(
      "status",
      Json::object({
        "code": Json::number(403.0),
        "message": Json::string(decision.reason),
      }),
    )
  }
  {
    "apiVersion": Json::string("admission.k8s.io/v1"),
    "kind": Json::string("AdmissionReview"),
    "response": Json::object(response),
  }
}
