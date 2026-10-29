# Every image the stack runs, built from the checkouts in src/.
# Driven by scripts/build-images.sh, which sets the CTX_*/SHA_* variables.
# Base images that upstream Dockerfiles pull FROM a registry are swapped for
# targets built here via `contexts = { "<image ref>" = "target:<name>" }`.

variable "PROJECT" { default = "crw-config" }
variable "TAG" { default = "local" }
variable "REGISTRY" { default = "" } # e.g. "docker.io/you/" — note the trailing slash
variable "PLATFORMS" { default = "" } # comma-separated; empty = builder's native platform
# CI builds each arch on its own runner and pushes it untagged; the publish step
# joins the per-arch digests into one multi-arch tag (scripts/ci-publish.sh).
variable "PUSH_BY_DIGEST" { default = false }
# Where camofox gets the Camoufox zips: dist/ by default, or an image holding
# them, e.g. "docker-image://docker.io/you/crw-config-camoufox-dist:<key>-arm64".
variable "CAMOUFOX_DIST" { default = "" }
# A registry repo for build cache, e.g. "docker.io/you/crw-config-buildcache"
# (CI sets it). crw's cargo-chef dependency layer is kept there as
# <repo>:crw-<arch>, so a crw change that leaves Cargo.lock alone skips
# recompiling its dependencies. Used only for single-platform builds.
variable "BUILD_CACHE" { default = "" }

variable "BUILD_DIR" { default = "build" }
variable "DIST_DIR" { default = "dist" }
variable "CTX_CRW" { default = "src/crw" }
variable "CTX_CAMOFOX_BROWSER" { default = "src/camofox-browser" }
variable "CTX_SEARXNG" { default = "src/searxng" }
variable "CTX_SEARXNG_BASE" { default = "src/searxng-base" }

variable "SHA_CRW" { default = "" }
variable "SHA_CAMOUFOX" { default = "" }
variable "SHA_CAMOFOX_BROWSER" { default = "" }
variable "SHA_SEARXNG" { default = "" }
variable "SHA_SEARXNG_BASE" { default = "" }

variable "CAMOUFOX_VERSION" { default = "" }
variable "CAMOUFOX_RELEASE" { default = "" }
variable "SEARXNG_VERSION" { default = "unknown" }

# Local: crw-config/<name>:local. Registry: <REGISTRY>crw-config-<name>:<TAG>,
# since Docker Hub allows only one path segment after the namespace.
function "repo" {
  params = [name]
  result = REGISTRY == "" ? "${PROJECT}/${name}" : "${REGISTRY}${PROJECT}-${name}"
}

function "image" {
  params = [name]
  result = PUSH_BY_DIGEST ? [] : ["${repo(name)}:${TAG}"]
}

function "output" {
  params = [name]
  result = PUSH_BY_DIGEST ? ["type=image,name=${repo(name)},push-by-digest=true,name-canonical=true,push=true"] : []
}

function "cache_from" {
  params = [name]
  result = BUILD_CACHE == "" || length(split(",", PLATFORMS)) != 1 || PLATFORMS == "" ? [] : ["type=registry,ref=${BUILD_CACHE}:${name}-${replace(PLATFORMS, "linux/", "")}"]
}

function "cache_to" {
  params = [name]
  result = [for c in cache_from(name) : "${c},mode=max,ignore-error=true"]
}

function "oci" {
  params = [url, sha]
  result = {
    "org.opencontainers.image.source"   = url
    "org.opencontainers.image.revision" = sha
  }
}

target "_common" {
  platforms = PLATFORMS == "" ? [] : split(",", PLATFORMS)
}

group "default" {
  targets = ["crw", "camofox", "chrome-stealth", "searxng"]
}

target "crw" {
  inherits = ["_common"]
  context  = CTX_CRW
  args = {
    CARGO_PKGS = "-p crw-server --features cdp,impersonated,camoufox -p crw-mcp -p crw-cli"
  }
  labels     = oci("https://github.com/fastcrw/crw", SHA_CRW)
  tags       = image("crw")
  output     = output("crw")
  cache-from = cache_from("crw")
  cache-to   = cache_to("crw")
}

target "camofox-browser" {
  inherits   = ["_common"]
  context    = CTX_CAMOFOX_BROWSER
  dockerfile = "${BUILD_DIR}/camofox-browser.Dockerfile"
  target     = "camofox-browser"
  contexts = {
    camoufox = CAMOUFOX_DIST == "" ? DIST_DIR : CAMOUFOX_DIST
  }
  args = {
    CAMOUFOX_VERSION = CAMOUFOX_VERSION
    CAMOUFOX_RELEASE = CAMOUFOX_RELEASE
  }
  labels = merge(oci("https://github.com/jo-inc/camofox-browser", SHA_CAMOFOX_BROWSER), {
    "io.github.daijro.camoufox.revision" = SHA_CAMOUFOX
  })
  tags = image("camofox-browser")
}

# camofox-browser plus a plugin that clicks Cloudflare's Turnstile checkbox
# (docker/camofox).
target "camofox" {
  inherits = ["_common"]
  context  = "docker/camofox"
  contexts = {
    camofox-browser = "target:camofox-browser"
  }
  labels = merge(oci("https://github.com/jo-inc/camofox-browser", SHA_CAMOFOX_BROWSER), {
    "io.github.daijro.camoufox.revision" = SHA_CAMOUFOX
  })
  tags   = image("camofox")
  output = output("camofox")
}

# Google Chrome on a virtual display (docker/chrome-stealth).
target "chrome-stealth" {
  inherits = ["_common"]
  context  = "docker/chrome-stealth"
  tags     = image("chrome-stealth")
  output   = output("chrome-stealth")
}

target "searxng-base-builder" {
  inherits = ["_common"]
  context  = CTX_SEARXNG_BASE
  target   = "searxng-builder"
  labels   = oci("https://codeberg.org/searxng/base", SHA_SEARXNG_BASE)
  tags     = image("searxng-base-builder")
}

target "searxng-base" {
  inherits = ["_common"]
  context  = CTX_SEARXNG_BASE
  target   = "searxng"
  labels   = oci("https://codeberg.org/searxng/base", SHA_SEARXNG_BASE)
  tags     = image("searxng-base")
}

target "searxng" {
  inherits   = ["_common"]
  context    = CTX_SEARXNG
  dockerfile = "container/Dockerfile"
  contexts = {
    "docker.io/searxng/base:searxng-builder" = "target:searxng-base-builder"
    "docker.io/searxng/base:searxng"         = "target:searxng-base"
  }
  args = {
    VERSION      = SEARXNG_VERSION
    VCS_URL      = "https://github.com/searxng/searxng"
    VCS_REVISION = SHA_SEARXNG
  }
  tags = image("searxng")
  output = output("searxng")
}
