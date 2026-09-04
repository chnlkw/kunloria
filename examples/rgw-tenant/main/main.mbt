// examples/rgw-tenant/main/main.mbt — deployable entry point.
//
// Run locally:  KUNLORIA_PORT=8080 moon run examples/rgw-tenant
// Container:    docker build --build-arg EXAMPLE=rgw-tenant .

///|
async fn main {
  @server.run(@app.policy, name="kunloria-example:rgw-tenant")
}
