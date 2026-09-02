// ceph/parse.mbt — both RGW payload shapes lowered into engine Query.
//
// Parsing uses MoonBit's native map patterns (see the core/json README,
// "Object Navigation"); anything unexpected falls through to `None`
// (fail-closed), which the transport answers with 400 and RGW treats as
// a denial.
//
// Shape 1 (kunloria native):
//   {"input": {"user": {"id", "groups"}, "action": "s3:GetObject",
//              "resource": {"bucket", "object"}}}
//
// Shape 2 (stock Ceph `rgw_opa_authz` payload):
//   {"input": {"method": "GET", "user_info": {"user_id"},
//              "bucket_info": {"bucket": {"name"}}}}
//   The user_id doubles as the group (single-tenant convention); method
//   maps GET/HEAD → s3:GetObject, PUT/POST → s3:PutObject, DELETE →
//   s3:DeleteObject.

///|
/// Coarse classification of an S3 action string (case-insensitive).
/// Read: get / head / list / listbucket; write: put / post / delete /
/// uploadpart; anything else is unknown and never classifies as read or
/// write.
pub fn classify_s3_action(action : String) -> @engine.AccessKind {
  let a = action.to_lower()
  if a == "get" ||
    a == "head" ||
    a.has_prefix("s3:get") ||
    a.has_prefix("s3:head") ||
    a.has_prefix("s3:list") {
    @engine.AccessKind::ReadAccess
  } else if a == "put" ||
    a == "post" ||
    a == "delete" ||
    a.has_prefix("s3:put") ||
    a.has_prefix("s3:post") ||
    a.has_prefix("s3:delete") ||
    a.has_prefix("s3:uploadpart") {
    @engine.AccessKind::WriteAccess
  } else {
    @engine.AccessKind::UnknownAccess
  }
}

///|
/// String elements of an optional JSON array field.
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
/// Lowers an RGW authorization payload into a `Query`.
/// `None` means malformed (or no user) — the transport answers 400 and
/// RGW treats that as a denial.
pub fn parse_query(body : Json) -> @engine.Query? {
  if body is { "input": input, .. } {
    match parse_native(input) {
      Some(q) => Some(q)
      None => parse_stock(input)
    }
  } else {
    None
  }
}

///|
/// The native payload shape.
fn parse_native(input : Json) -> @engine.Query? {
  if input
    is {
      "user": { "id": String(user), "groups"? : groups, .. },
      "action": String(action),
      "resource": { "bucket": String(bucket), "object"? : object, .. },
      ..
    } {
    Some(@engine.Query::{
      source: @engine.Source::Rgw,
      subject: @engine.Subject::{ user, groups: opt_strings(groups), },
      verb: action.to_lower(),
      kind: classify_s3_action(action),
      target: @engine.Target::Rgw(@engine.RgwRef::{
        bucket,
        object_key: if object is Some(String(key)) {
          key
        } else {
          ""
        },
      }),
      object: None,
    })
  } else {
    None
  }
}

///|
/// The stock Ceph payload shape.
fn parse_stock(input : Json) -> @engine.Query? {
  if input
    is {
      "method": String(raw),
      "user_info": { "user_id": String(user), .. },
      "bucket_info": { "bucket": { "name": String(bucket), .. }, .. },
      ..
    } {
    let action = match raw.to_upper() {
      "GET" => "s3:GetObject"
      "HEAD" => "s3:HeadObject"
      "PUT" => "s3:PutObject"
      "POST" => "s3:PostObject"
      "DELETE" => "s3:DeleteObject"
      other => "s3:\{other}"
    }
    Some(@engine.Query::{
      source: @engine.Source::Rgw,
      subject: @engine.Subject::{
        user,
        groups: [user], // stock payload has no groups; user doubles as its own group
      },
      verb: action.to_lower(),
      kind: classify_s3_action(action),
      target: @engine.Target::Rgw(@engine.RgwRef::{ bucket, object_key: "", }),
      object: None,
    })
  } else {
    None
  }
}

///|
/// The OPA-compatible reply body: `{"result": true|false}`.
pub fn reply(allowed : Bool) -> Json {
  Json::object({ "result": Json::boolean(allowed) })
}
