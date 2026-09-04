// examples/minimal/main/main.mbt — deployable entry point.
//
// Run locally:  KUNLORIA_PORT=8080 moon run examples/minimal
// Container:    docker build --build-arg EXAMPLE=minimal .

///|
async fn main {
  @server.run(@app.policy, name="kunloria-example:minimal")
}
