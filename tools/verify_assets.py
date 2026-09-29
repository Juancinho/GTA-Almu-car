"""Check shipped generated binaries against their deterministic manifests."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import wave

ROOT = Path(__file__).resolve().parents[1]


def check_glb(kind: str) -> None:
    base = ROOT / "game/assets/procedural" / kind
    glb = base.with_suffix(".glb")
    report = json.loads(base.with_suffix(".json").read_text(encoding="utf-8"))
    payload = glb.read_bytes()
    assert payload[:4] == b"glTF", f"{glb}: invalid GLB signature"
    assert hashlib.sha256(payload).hexdigest() == report["output_sha256"], f"{glb}: hash differs from report"
    assert report["mesh_count"] > 0 and report["triangles"] > 0, f"{glb}: empty asset"
    assert all(item["uv_layers"] > 0 and item["materials"] for item in report["objects"]), f"{glb}: UV/material failure"
    print(f"GLB OK {kind}: {report['mesh_count']} meshes, {report['triangles']} triangles")


def check_audio() -> None:
    base = ROOT / "game/assets/audio"
    report = json.loads((base / "generation_report.json").read_text(encoding="utf-8"))
    for item in report["files"]:
        # Reports written on Windows use backslashes; normalise so checks run on any OS.
        path = base / Path(str(item["file"]).replace("\\", "/")).name
        assert hashlib.sha256(path.read_bytes()).hexdigest() == item["sha256"], f"{path}: hash differs"
        with wave.open(str(path), "rb") as sound:
            assert sound.getnframes() > 100 and sound.getframerate() == report["sample_rate"], f"{path}: invalid WAV"
    print(f"AUDIO OK: {len(report['files'])} original placeholder WAVs")


def check_osm() -> None:
    raw = ROOT / "source_assets/osm/altillo_2026-09-29.json"
    metadata = json.loads(raw.with_suffix(".metadata.json").read_text(encoding="utf-8"))
    digest = hashlib.sha256(raw.read_bytes()).hexdigest()
    assert digest == metadata["sha256"], "raw OSM cache hash differs"
    reference = json.loads((ROOT / "game/data/world/osm_reference.json").read_text(encoding="utf-8"))
    assert reference["raw_sha256"] == digest, "normalized OSM input hash differs"
    assert sum(reference["counts"].values()) == len(reference["features"]), "normalized feature counts differ"
    print(f"OSM OK: {len(reference['features'])} cached reference features")


def main() -> None:
    for kind in ("palm", "building", "compact_car"):
        check_glb(kind)
    check_audio()
    check_osm()


if __name__ == "__main__":
    main()
