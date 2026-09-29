"""Import pinned third-party CC0 assets listed in assets/third_party/manifest.json.

Each source is a Git repository pinned to a commit. The script sparse-fetches only
the listed files, copies models, decodes KTX2 (UASTC/ETC1S) textures to PNG with
Khronos `ktx` (KTX-Software 4.x), and writes a provenance report plus CREDITS.md.

Usage:
    python tools/third_party/import_assets.py --ktx path/to/ktx [--cache tmp/third_party]
    python tools/third_party/import_assets.py --check   # verify outputs against the report
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "assets/third_party/manifest.json"
REPORT = ROOT / "assets/third_party/import_report.json"
CREDITS = ROOT / "game/assets/third_party/CREDITS.md"


class ImportError_(RuntimeError):
    """Raised with the asset, stage and path that failed."""


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(args: list[str], cwd: Path) -> None:
    env = dict(os.environ, GIT_LITERAL_PATHSPECS="1")
    result = subprocess.run(["git", *args], cwd=cwd, env=env, capture_output=True, text=True)
    if result.returncode != 0:
        raise ImportError_(f"git {' '.join(args[:2])} failed in {cwd}: {result.stderr.strip()}")


def fetch_source(name: str, source: dict, paths: list[str], cache: Path) -> Path:
    checkout = cache / name
    if not (checkout / ".git").exists():
        checkout.mkdir(parents=True, exist_ok=True)
        git(["init", "-q"], checkout)
        git(["remote", "add", "origin", source["repo"]], checkout)
    git(["fetch", "-q", "--depth", "1", "--filter=blob:none", "origin", source["commit"]], checkout)
    git(["checkout", "-q", source["commit"], "--", *paths], checkout)
    for path in paths:
        if not (checkout / path).is_file():
            raise ImportError_(f"source {name}: stage checkout: missing {path}")
    return checkout


def decode_ktx2(ktx: str, source: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as scratch:
        out = Path(scratch) / "level0.png"
        result = subprocess.run([ktx, "extract", "--level", "0", str(source), str(out)], capture_output=True, text=True)
        if result.returncode != 0 or not out.exists():
            raise ImportError_(f"texture {source.name}: stage decode: {result.stderr.strip()[:300]}")
        shutil.copyfile(out, target)
    if target.read_bytes()[:8] != b"\x89PNG\r\n\x1a\n":
        raise ImportError_(f"texture {target}: stage validate: not a PNG")


def run_import(ktx: str, cache: Path) -> dict:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    sources: dict = manifest["sources"]
    wanted: dict[str, list[str]] = {name: [src["license_file"]] for name, src in sources.items()}
    for model in manifest["models"]:
        wanted[model["source"]].append(model["path"])
    for texture in manifest["textures"]:
        for kind in texture["maps"]:
            wanted[texture["source"]].append(f"packs/ambientcg-textures/textures/{texture['id']}/{texture['id']}_1K-PNG_{kind}.ktx2")
    checkouts = {name: fetch_source(name, sources[name], paths, cache) for name, paths in wanted.items()}
    outputs = []
    for model in manifest["models"]:
        target = ROOT / model["dest"]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(checkouts[model["source"]] / model["path"], target)
        outputs.append({"file": model["dest"], "source": model["source"], "from": model["path"], "sha256": sha256(target)})
    texture_root = ROOT / manifest["texture_dest"]
    for texture in manifest["textures"]:
        for kind in texture["maps"]:
            source = checkouts[texture["source"]] / f"packs/ambientcg-textures/textures/{texture['id']}/{texture['id']}_1K-PNG_{kind}.ktx2"
            suffix = {"Color": "color", "NormalGL": "normal", "Roughness": "roughness"}[kind]
            target = texture_root / f"{texture['id'].lower()}_{suffix}.png"
            decode_ktx2(ktx, source, target)
            outputs.append({"file": target.relative_to(ROOT).as_posix(), "source": texture["source"], "from": source.relative_to(checkouts[texture["source"]]).as_posix(), "sha256": sha256(target)})
    report = {"manifest_sha256": sha256(MANIFEST), "sources": sources, "outputs": outputs}
    REPORT.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    write_credits(manifest)
    return report


def write_credits(manifest: dict) -> None:
    lines = ["# Third-party assets", "", "All files in this folder are CC0 1.0 (public domain). Credit is given voluntarily.", ""]
    for name, source in manifest["sources"].items():
        lines.append(f"- **{source['author']}** — {source['license']}, via {source['repo']} @ `{source['commit'][:10]}` ({name})")
    lines += ["", "Imported by `tools/third_party/import_assets.py`; provenance and hashes in `assets/third_party/import_report.json`.", ""]
    CREDITS.parent.mkdir(parents=True, exist_ok=True)
    CREDITS.write_text("\n".join(lines), encoding="utf-8")


def check() -> int:
    report = json.loads(REPORT.read_text(encoding="utf-8"))
    if report["manifest_sha256"] != sha256(MANIFEST):
        print("THIRD PARTY FAIL: manifest changed since last import; rerun the import", file=sys.stderr)
        return 1
    for item in report["outputs"]:
        path = ROOT / item["file"]
        if not path.is_file() or sha256(path) != item["sha256"]:
            print(f"THIRD PARTY FAIL: {item['file']} missing or hash differs", file=sys.stderr)
            return 1
    print(f"THIRD PARTY OK: {len(report['outputs'])} CC0 files match {REPORT.relative_to(ROOT).as_posix()}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ktx", default="ktx", help="Path to the Khronos ktx CLI (KTX-Software 4.x)")
    parser.add_argument("--cache", type=Path, default=ROOT / "tmp/third_party", help="Sparse checkout cache directory")
    parser.add_argument("--check", action="store_true", help="Only verify outputs against the import report")
    args = parser.parse_args()
    if args.check:
        return check()
    try:
        report = run_import(args.ktx, args.cache)
    except ImportError_ as error:
        print(f"THIRD PARTY FAIL: {error}", file=sys.stderr)
        return 1
    print(f"THIRD PARTY PASS: {len(report['outputs'])} files imported")
    return 0


if __name__ == "__main__":
    sys.exit(main())
