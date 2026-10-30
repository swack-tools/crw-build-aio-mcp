#!/usr/bin/env bash
# Assemble the release bundle (the DMG's contents):
#   install.sh, README.txt, LICENSE
#   payload/docker-compose.yml our docker-compose.yml, flattened, images pinned
#                              to <prefix><name>:<tag>
#   payload/<bind mounts>      the config files docker-compose.yml mounts
#   payload/scripts/           lib.sh and the scripts it drives, as in this repo
#   payload/bin/crw-aio        the command install.sh links onto PATH
#   payload/bin/crw-mcp        copied from bin/ when present (CI adds the signed one)
# Usage: release-bundle.sh <image-prefix> <tag> <out-dir> [version]
#   e.g. release-bundle.sh docker.io/you/crw-config- 0.1.0 build/bundle
source "$(dirname "$0")/lib.sh"

usage="usage: release-bundle.sh <image-prefix> <tag> <out-dir> [version]"
prefix="${1:?$usage}"
tag="${2:?$usage}"
out="${3:?$usage}"
version="${4:-$tag}"

[[ ! -e "$out" ]] || die "$out already exists; remove it first"
payload="$out/payload"
mkdir -p "$payload/bin" "$payload/scripts"

# Flatten the stack without interpolating ${VARS} (the secrets come from the
# installed .env) or resolving paths (bind mounts stay relative to payload/).
compose config --format json --no-interpolate --no-path-resolution > "$out/stack.json"
python3 -I - "$out/stack.json" "$payload/compose.json" "$prefix" "$tag" "$ROOT" "$payload" <<'PY'
import json, os, shutil, sys
src, dst, prefix, tag, root, payload = sys.argv[1:]
stack = json.load(open(src))
OURS = {"crw", "camofox", "chrome-stealth", "searxng"}
stack.pop("name", None)
stack.pop("networks", None)
services = stack["services"]
for name, svc in services.items():
    if name not in OURS:
        sys.exit(f"unexpected service {name!r}: decide whether the bundle ships it")
    svc["image"] = f"{prefix}{name}:{tag}"
    for key in ("profiles", "pull_policy", "networks", "build"):
        svc.pop(key, None)
    for vol in svc.get("volumes", []):
        if vol.get("type") == "bind":
            rel = os.path.normpath(vol["source"])
            if rel.startswith(".."):
                sys.exit(f"{name}: bind mount {vol['source']} is outside this repo")
            os.makedirs(os.path.dirname(os.path.join(payload, rel)) or payload, exist_ok=True)
            shutil.copy(os.path.join(root, rel), os.path.join(payload, rel))
            vol["source"] = "./" + rel
json.dump(stack, open(dst, "w"), indent=2)
print("\n".join(f"  {s['image']}" for s in services.values()))
PY
rm "$out/stack.json"
images="$(python3 -I -c 'import json, sys; print("\n".join("  " + s["image"] for s in json.load(open(sys.argv[1]))["services"].values()))' "$payload/compose.json")"

# Normalise back to YAML; docker-compose.yml is what users read and edit.
docker compose -p crw-aio -f "$payload/compose.json" config --no-interpolate --no-path-resolution > "$payload/docker-compose.yml"
rm "$payload/compose.json"

cp "$ROOT"/scripts/{lib.sh,pick-port.sh,up.sh,install-mcp.sh,mcp_config.py,test-stealth.sh} "$payload/scripts/"
cp "$ROOT/release/crw-aio" "$payload/bin/"
[[ ! -x "$BIN/crw-mcp" ]] || cp "$BIN/crw-mcp" "$payload/bin/"
cat > "$payload/.env.example" <<'EOF'
# Copied to .env on first use; empty secrets are generated then.
PROJECT=crw-aio

# Where crw listens. `crw-aio up` offers the next free port if this one is
# taken, and saves the choice here.
CRW_HOST_PORT=3000
CRW_BIND_ADDRESS=127.0.0.1

SEARXNG_SECRET_KEY=
EOF

cp "$ROOT/release/install.sh" "$out/"
cp "$ROOT/LICENSE" "$out/"
python3 -I - "$ROOT/release/README.txt" "$out/README.txt" "$version" "$images" <<'PY'
import sys
src, dst, version, images = sys.argv[1:]
open(dst, "w").write(open(src).read().replace("@VERSION@", version).replace("@IMAGES@", images))
PY
chmod +x "$out/install.sh" "$payload/bin/crw-aio" "$payload"/scripts/*.sh
log "bundle for $version in $out"
