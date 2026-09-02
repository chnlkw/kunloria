# Ceph RGW integration

Kunloria speaks the OPA HTTP contract Ceph RGW uses for authorization
offload, so RGW needs no patches — only configuration.

## 1. Configure RGW

Point RGW's OPA integration at Kunloria (run on every `client.rgw.*`, or via
`ceph config set`):

```ini
[client.rgw]
rgw use opa authz = true
rgw opa url = http://kunloria.kunloria-system.svc:443/v1/data/rgw/authz/allow
rgw opa verify ssl = true
# rgw opa token = <bearer token>   # if you front Kunloria with auth
```

Or with `ceph config set`:

```sh
ceph config set client.rgw rgw_use_opa_authz true
ceph config set client.rgw rgw_opa_url "http://kunloria.kunloria-system.svc:443/v1/data/rgw/authz/allow"
ceph config set client.rgw rgw_opa_verify_ssl false   # true once CA-trusted
systemctl restart ceph-radosgw@rgw.default   # or ceph orch restart rgw.<realm>
```

The URL path follows the OPA data-API convention
(`/v1/data/<package>/<rule>`); Kunloria registers `/v1/data/rgw/authz/allow`
and answers `{"result": true|false}`.

## 2. Payload shapes

### Kunloria native (group-aware)

```json
{
  "input": {
    "user":     {"id": "user1", "groups": ["groupA"]},
    "action":   "s3:GetObject",
    "resource": {"bucket": "my-bucket", "object": "groupA/path/to/file"}
  }
}
```

* `action` is classified into read (`s3:GetObject`, `s3:HeadObject`,
  `s3:ListBucket`), write (`s3:PutObject`, `s3:DeleteObject`, `s3:UploadPart`)
  or unknown (denied to every non-admin).
* The user's **group is its namespace**: a request is prefix-authorized only
  when the resource path (object key, else bucket name) equals the group or
  starts with `<group>/`. Cross-group access is denied by construction.

### Stock Ceph payload (what `rgw_use_opa_authz` actually sends)

```json
{
  "input": {
    "method": "GET",
    "user_info": {"user_id": "john", "display_name": "John"},
    "bucket_info": {"bucket": {"name": "john-data"}, "owner": "john"}
  }
}
```

Kunloria also parses this shape and applies the convention:
`user_id` doubles as the user's single group (its namespace), `method` maps
GET/HEAD → read, PUT/POST → write, DELETE → delete-write. Grant elevated
roles by listing user ids in the policy's role constants — see
`examples/rgw-tenant/policy.mbt` (`admin_groups()`, `reader_groups()`,
`writer_groups()`); policies are code, not environment (ADR-0001).

## 3. Policy matrix

| Role (from group) | Reads               | Writes              | Prefix scope          |
| ----------------- | ------------------- | ------------------- | --------------------- |
| admin             | all                 | all                 | none (unrestricted)   |
| reader            | Get/Head/ListBucket | —                   | own group namespace   |
| writer            | —                   | Put/Delete/UploadPart | own group namespace |
| (unmapped)        | —                   | —                   | — (deny everything)   |

Unknown verbs (e.g. `s3:CreateBucket`) are denied to every non-admin role.

## 4. Smoke test

```sh
curl -s http://127.0.0.1:8080/v1/data/rgw/authz/allow \
  -H 'Content-Type: application/json' \
  -d '{"input":{"user":{"id":"user1","groups":["readers","groupA"]},"action":"s3:GetObject","resource":{"bucket":"groupA","object":"f"}}}'
# -> {"result":true}   (with groupA listed in the policy's reader groups)
```

References: [Ceph RGW OPA integration](https://docs.ceph.com/en/latest/radosgw/opa/).
