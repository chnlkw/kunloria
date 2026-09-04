// examples/k8s-write-authz/main/main.mbt — deployable entry point.
//
// Run locally:  KUNLORIA_PORT=8080 moon run examples/k8s-write-authz
// Container:    docker build --build-arg EXAMPLE=k8s-write-authz .

///|
async fn main {
  @server.run(@app.policy, name="kunloria-example:k8s-write-authz")
}
