name = "chnlkw/kunloria"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/chnlkw/kunloria"

license = "Apache-2.0"

keywords = [
  "authorization",
  "policy-engine",
  "kubernetes",
  "admission-control",
  "ceph",
  "s3",
]

preferred_target = "native"

description = "Kunloria: a formally-verified, lightweight policy engine for Kubernetes admission control and Ceph RGW authorization (an OPA/Rego alternative written in MoonBit)."

import {
  "moonbitlang/async@0.21.0",
  "moonbitlang/moonback@0.8.2",
}
