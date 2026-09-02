// ceph/rgw.mbt — Ceph RGW authorization, OPA-compatible.
//
// Ceph's RGW `opa` authz module POSTs the request described below to
// `<opa>/v1/data/rgw/authz/allow` and expects `{"result": <bool>}`:
//
// ```json
// {
//   "input": {
//     "user":     {"id": "user1", "groups": ["groupA"]},
//     "action":   "s3:GetObject",
//     "resource": {"bucket": "my-bucket", "object": "path/to/file"}
//   }
// }
// ```
//
// Kunloria answers from the verified decision core: the user's group is
// both its role (via PolicyConfig) and its path namespace.

///|
/// A parsed RGW authorization query.
pub(all) struct RgwQuery {
  user_id : String
  groups : Array[String]
  action : String
  bucket : String
  object : String
} derive(Eq, @debug.Debug)

///|
/// Parse the OPA-style `{"input": ...}` payload.
///
/// Two shapes are accepted:
///
/// 1. Kunloria native (documented API): `input.user.{id,groups}`,
///    `input.action` (`s3:GetObject` style), `input.resource.{bucket,object}`.
/// 2. Stock Ceph RGW payload (what `rgw_use_opa_authz` actually sends):
///    `input.method`, `input.user_info.user_id`,
///    `input.bucket_info.bucket.name`. Under this shape the user id is also
///    used as its single group, i.e. the user namespace equals the user id;
///    map an id to a role via `KUNLORIA_*_GROUPS`.
///
/// Returns `None` when the payload carries no input object or user id.
pub fn parse_query(body : Json) -> RgwQuery? {
  let input = if body is Object(map) { map.get("input") } else { None }
  guard input is Some(inp) else { return None }
  let user = if inp is Object(m) { m.get("user") } else { None }
  if user is None {
    return parse_stock_query(inp)
  }
  let user_id = if user is Some(Object(um)) && um.get("id") is Some(String(id)) {
    id
  } else {
    return parse_stock_query(inp)
  }
  let groups : Array[String] = match user {
    Some(u) =>
      if u is Object(um) && um.get("groups") is Some(Array(list)) {
        let out = []
        for g in list {
          if g is String(s) {
            out.push(s)
          }
        }
        out
      } else {
        []
      }
    None => []
  }
  let action = match field_string(Some(inp), "action") {
    Some(a) => a
    None => ""
  }
  let resource = if inp is Object(m) { m.get("resource") } else { None }
  let bucket = match field_string(resource, "bucket") {
    Some(b) => b
    None => ""
  }
  let object = match field_string(resource, "object") {
    Some(o) => o
    None => ""
  }
  Some({ user_id, groups, action, bucket, object })
}

///|
/// Parse the stock Ceph RGW payload (`user_info` / `bucket_info` / `method`).
/// The user id doubles as its group, so a user owns the namespace named
/// after its id (or a role granted via `KUNLORIA_*_GROUPS`).
fn parse_stock_query(inp : Json) -> RgwQuery? {
  let user_info = if inp is Object(m) { m.get("user_info") } else { None }
  let user_id = if user_info is Some(Object(u)) &&
    u.get("user_id") is Some(String(id)) {
    id
  } else {
    return None
  }
  let bucket = if inp is Object(m) &&
    m.get("bucket_info") is Some(Object(bi)) &&
    bi.get("bucket") is Some(Object(b)) &&
    b.get("name") is Some(String(name)) {
    name
  } else {
    ""
  }
  let action = match field_string(Some(inp), "method") {
    Some("GET") | Some("HEAD") => "s3:GetObject"
    Some("PUT") | Some("POST") => "s3:PutObject"
    Some("DELETE") => "s3:DeleteObject"
    _ => ""
  }
  Some({ user_id, groups: [user_id], action, bucket, object: "" })
}

///|
/// The hierarchical resource path of a query: the object key when present,
/// otherwise the bucket name (bucket-level operations such as ListBucket).
pub fn RgwQuery::resource_path(self : RgwQuery) -> String {
  if self.object == "" {
    self.bucket
  } else {
    self.object
  }
}

///|
/// Classify an `s3:Verb` action string.
///
/// - Reader alphabet: s3:GetObject, s3:HeadObject, s3:ListBucket.
/// - Writer alphabet: s3:PutObject, s3:DeleteObject, s3:UploadPart.
/// - Anything else is Unknown (denied to every non-admin role).
pub fn classify_s3_action(action : String) -> @auth.ActionKind {
  match action {
    "s3:GetObject" | "s3:HeadObject" | "s3:ListBucket" => @auth.Read
    "s3:PutObject" | "s3:DeleteObject" | "s3:UploadPart" => @auth.Write
    _ => @auth.Unknown
  }
}

///|
/// Decide an RGW query under a policy configuration.
pub fn decide(cfg : @auth.PolicyConfig, query : RgwQuery) -> @auth.Decision {
  let subject = cfg.subject_for(id=query.user_id, groups=query.groups)
  let kind = classify_s3_action(query.action)
  @auth.authorize(subject, kind, query.resource_path())
}

///|
/// String field of an optional JSON value.
fn field_string(j : Json?, key : String) -> String? {
  if j is Some(Object(map)) && map.get(key) is Some(String(s)) {
    Some(s)
  } else {
    None
  }
}
