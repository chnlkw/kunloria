// kunloria.mbt — module-level metadata.

///|
/// Version of the Kunloria policy engine.
pub const KUNLORIA_VERSION : String = "0.1.0"

///|
/// Short service description, also used by the root endpoint banner.
pub fn describe() -> String {
  "Kunloria \{KUNLORIA_VERSION} — policy-as-code engine for Kubernetes admission control and Ceph RGW"
}
