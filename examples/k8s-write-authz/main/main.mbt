// examples/k8s-write-authz/main.mbt — deployable entry point.
//
// Run locally:  KUNLORIA_PORT=8080 moon run examples/k8s-write-authz
// Container:    docker build --build-arg EXAMPLE=k8s-write-authz .

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
  boot.set("service", Json::string("kunloria-example:k8s-write-authz"))
  boot.set("policy", Json::string("examples/k8s-write-authz/policy.mbt"))
  boot.set("host", Json::string(settings.host))
  boot.set("port", Json::number(settings.port.to_double()))
  @server.log_json("info", "kunloria example listening", boot)
  app.serve(server)
}
