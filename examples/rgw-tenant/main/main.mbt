// examples/rgw-tenant/main.mbt — deployable entry point.
//
// Run locally:  KUNLORIA_PORT=8080 moon run examples/rgw-tenant
// Container:    docker build --build-arg EXAMPLE=rgw-tenant .

///|
async fn main {
  let settings = @server.AppSettings::from_env()
  let metrics = @server.Metrics::new()
  let app = @moonback.App(@server.root_module(@app.policy, metrics))
  defer app.close()
  let server = @moonback.listen(
    host=settings.host,
    port=settings.port.to_uint16(),
  )
  let boot : Map[String, Json] = Map([])
  boot.set("service", Json::string("kunloria-example:rgw-tenant"))
  boot.set("policy", Json::string("examples/rgw-tenant/policy.mbt"))
  boot.set("host", Json::string(settings.host))
  boot.set("port", Json::number(settings.port.to_double()))
  @server.log_json("info", "kunloria example listening", boot)
  app.serve(server)
}
