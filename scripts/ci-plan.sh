#!/usr/bin/env bash
# CI: pin every upstream to the commit its checkout is at, and give each image
# a key derived from its inputs (upstream commits + this repo's build recipe).
# An image is pushed as <name>:src-<key>, so a run whose key already exists in
# the registry reuses it instead of rebuilding.
# Prints GITHUB_OUTPUT lines:
#   refs=CRW_REF=<sha> CAMOUFOX_REF=<sha> ...  (export to check out the same commits)
#   keys={"crw": "<key>", ...}
#   camoufox_key=<key>                         (tag prefix of the camoufox-dist image)
# With REGISTRY set, it also checks what already exists there:
#   build=["crw", ...]                         (images with no src-<key> tag yet)
#   camoufox_arches=["arm64", ...]             (Camoufox zips to compile for them)
# Usage: ci-plan.sh   (after fetch-sources.sh)
source "$(dirname "$0")/lib.sh"

shas=()
for entry in "${SOURCES[@]}"; do
  name="${entry%%|*}"
  shas+=("$name=$(src_sha "$name")")
done

python3 -I - "$ROOT" "${REGISTRY:-}" "$PROJECT" "${shas[@]}" <<'PY'
import glob, hashlib, json, os, re, subprocess, sys, urllib.request
root, registry, project, pairs = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
sha = dict(p.split("=", 1) for p in pairs)

def digest(*parts):
    return hashlib.sha256("\n".join(parts).encode()).hexdigest()

def recipe(*files):
    return digest(*(open(f"{root}/{f}").read() for f in files))

IMAGES = {
    "crw": ["crw"],
    "camofox": ["camofox-browser", "camoufox"],
    "chrome-stealth": [],
    "searxng": ["searxng", "searxng-base"],
}
patches = sorted(os.path.relpath(p, root) for p in glob.glob(f"{root}/patches/*/*.patch"))
ours = sorted(os.path.relpath(p, root) for p in glob.glob(f"{root}/docker/**/*", recursive=True) if os.path.isfile(p))
common = recipe("docker-bake.hcl", "scripts/prep-sources.sh", "scripts/build-images.sh", *patches, *ours)
camoufox = recipe("scripts/build-camoufox.sh")

# chrome-stealth installs the current Chrome stable from Google's repository,
# so a new Chrome release is what changes it.
def chrome_stable(arch):
    url = f"https://dl.google.com/linux/chrome/deb/dists/stable/main/binary-{arch}/Packages"
    index = urllib.request.urlopen(url, timeout=30).read().decode()
    return re.search(r"^Package: google-chrome-stable\n(?:.+\n)*?Version: (.+)$", index, re.M).group(1)
chrome = [f"chrome-{arch}={chrome_stable(arch)}" for arch in ("amd64", "arm64")]
keys = {}
for image, sources in IMAGES.items():
    parts = [image, common] + [f"{s}={sha[s]}" for s in sources]
    if image == "camofox":
        parts.append(camoufox)
    if image == "chrome-stealth":
        parts += chrome
    keys[image] = digest(*parts)[:16]

refs = " ".join(f"{name.upper().replace('-', '_')}_REF={value}" for name, value in sha.items())
print(f"refs={refs}")
print(f"keys={json.dumps(keys)}")
camoufox_key = f"{sha['camoufox'][:12]}-{camoufox[:8]}"
print(f"camoufox_key={camoufox_key}")

if registry:
    def exists(ref):
        return subprocess.run(["docker", "buildx", "imagetools", "inspect", ref],
                              capture_output=True).returncode == 0
    build = [i for i, k in keys.items() if not exists(f"{registry}{project}-{i}:src-{k}")]
    arches = [a for a in ("arm64", "x86_64")
              if "camofox" in build and not exists(f"{registry}{project}-camoufox-dist:{camoufox_key}-{a}")]
    print(f"build={json.dumps(build)}")
    print(f"camoufox_arches={json.dumps(arches)}")
PY
