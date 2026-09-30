"""Fetch or verify pinned Poly Haven Clean Asphalt CC0 maps."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "assets/third_party/clean_asphalt.json"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify local files without network")
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    for item in manifest["maps"]:
        target = ROOT / item["dest"]
        if not args.check and not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            with urlopen(item["url"], timeout=90) as response:
                target.write_bytes(response.read())
        if not target.exists():
            raise FileNotFoundError(f"clean asphalt {item['type']} missing: {target}")
        actual = hashlib.sha256(target.read_bytes()).hexdigest()
        if actual != item["sha256"]:
            raise ValueError(f"clean asphalt {item['type']} hash mismatch: {target}")
    print(f"CLEAN ASPHALT PASS: {len(manifest['maps'])} Poly Haven CC0 maps match pinned SHA-256")


if __name__ == "__main__":
    main()
