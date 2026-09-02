// cmd/main — entry point.
//
// Run locally:   moon run cmd/main
// Configure:     KUNLORIA_HOST=127.0.0.1 KUNLORIA_PORT=8080 moon run cmd/main
// Container:     see Dockerfile / deploy/

///|
async fn main {
  let settings = @server.AppSettings::from_env()
  let metrics = @server.Metrics::new()
  let app = @moonback.App(@server.root_module(settings, metrics))
  defer app.close()
  let server = @moonback.listen(
    host=settings.host,
    port=settings.port.to_uint16(),
  )
  let boot : Map[String, Json] = Map([])
  boot.set("version", Json::string(@kunloria.KUNLORIA_VERSION))
  boot.set("host", Json::string(settings.host))
  boot.set("port", Json::number(settings.port.to_double()))
  boot.set(
    "endpoints",
    Json::array([
      Json::string("/healthz"),
      Json::string("/metrics"),
      Json::string("/validate"),
      Json::string("/v1/data/rgw/authz/allow"),
    ]),
  )
  @server.log_json("info", "kunloria listening", boot)
  app.serve(server)
}
