#!/usr/bin/env python3
"""Add or remove the `crw` MCP server in a Claude Desktop or Codex config file.

Usage: mcp_config.py <claude-desktop|codex> <install|uninstall> <in> <out> [bin url]

Reads <in> (may not exist), writes the edited config to <out>, and leaves every
other server untouched. The caller diffs, backs up and moves it into place.
"""
import json
import os
import re
import sys

try:
    import tomllib
except ImportError:  # python < 3.11 (macOS's stock 3.9); install-mcp.sh still checks with `codex mcp get`
    tomllib = None


def claude_desktop(action, text, bin_path, url):
    data = json.loads(text) if text.strip() else {}
    servers = data.setdefault("mcpServers", {})
    if action == "install":
        servers["crw"] = {"command": bin_path, "args": [], "env": {"CRW_API_URL": url}}
    else:
        servers.pop("crw", None)
    newline = "\n" if text.endswith("\n") or not text else ""
    return json.dumps(data, indent=2, ensure_ascii=False) + newline


TABLE_HEADER = re.compile(r"^\s*\[\[?\s*([^\]]+?)\s*\]\]?\s*(#.*)?$")


def codex(action, text, bin_path, url):
    kept, skipping = [], False
    for line in text.splitlines():
        header = TABLE_HEADER.match(line)
        if header:
            key = header.group(1).replace('"', "").replace("'", "")
            skipping = key == "mcp_servers.crw" or key.startswith("mcp_servers.crw.")
        if not skipping:
            kept.append(line)
    while kept and not kept[-1].strip():
        kept.pop()
    if action == "install":
        # Camoufox scrapes can outlast Codex's 60s default tool timeout.
        kept += [
            "",
            "[mcp_servers.crw]",
            f"command = {json.dumps(bin_path)}",
            "args = []",
            "startup_timeout_sec = 30",
            "tool_timeout_sec = 300",
            "",
            "[mcp_servers.crw.env]",
            f"CRW_API_URL = {json.dumps(url)}",
        ]
    result = "\n".join(kept) + "\n"
    if tomllib:
        tomllib.loads(result)  # never hand back a file Codex can't parse
    return result


def main():
    kind, action, src, out, *rest = sys.argv[1:]
    bin_path, url = (rest + ["", ""])[:2]
    text = open(src).read() if os.path.exists(src) else ""
    edit = {"claude-desktop": claude_desktop, "codex": codex}[kind]
    with open(out, "w") as f:
        f.write(edit(action, text, bin_path, url))


if __name__ == "__main__":
    main()
