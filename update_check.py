#!/usr/bin/env python3
"""Print the remote Boxtop version when the repo has a newer release.

Called by the widget when the card opens: fetches the manifest published on
GitHub and prints its version only when it is strictly newer than the local
one, so the card can offer an in-place update. Any network or parse failure
prints nothing and exits quietly - the notice simply stays hidden.
"""

import json
import re
import sys
import urllib.request

RAW_MANIFEST = (
    "https://raw.githubusercontent.com/Maftuuh1922/omarchy-boxtop/main/manifest.json"
)


def version_key(value):
    """'v1.4.0-beta' -> (1, 4, 0)"""
    parts = [int(n) for n in re.findall(r"\d+", str(value))][:3]
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts)


def main():
    local_path = __file__.rsplit("/", 1)[0] + "/manifest.json"
    try:
        with open(local_path, encoding="utf-8") as handle:
            local = json.load(handle).get("version", "0.0.0")
        with urllib.request.urlopen(RAW_MANIFEST, timeout=6) as response:
            remote = json.load(response).get("version", "")
    except Exception:
        return
    if remote and version_key(remote) > version_key(local):
        sys.stdout.write(str(remote))


if __name__ == "__main__":
    main()
