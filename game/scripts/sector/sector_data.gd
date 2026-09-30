class_name SectorData
extends RefCounted

## Parsed res://data/world/sector_center.json (tools/world/build_sector.py) with
## terrain height and surface lookups.

const PATH := "res://data/world/sector_center.json"
const SURFACES := ["sea", "beach", "urban", "park", "natural", "promenade"]

var raw: Dictionary = {}
var x0 := 0.0
var z0 := 0.0
var cell := 4.0
var cols := 0
var rows := 0
var heights := PackedFloat32Array()
var surface := PackedByteArray()


static func load_default() -> SectorData:
	var data := SectorData.new()
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_error("SectorData: missing %s (run tools/world/build_sector.py)" % PATH)
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or str(parsed.get("schema", "")) != "brisa.sector.v1":
		push_error("SectorData: invalid or outdated sector file %s" % PATH)
		return null
	data._init_from(parsed)
	return data


func _init_from(parsed: Dictionary) -> void:
	raw = parsed
	var terrain: Dictionary = raw["terrain"]
	x0 = float(terrain["x0"])
	z0 = float(terrain["z0"])
	cell = float(terrain["cell"])
	cols = int(terrain["cols"])
	rows = int(terrain["rows"])
	var bytes := Marshalls.base64_to_raw(str(terrain["heights_cm_b64"]))
	heights.resize(cols * rows)
	for i in range(cols * rows):
		heights[i] = bytes.decode_s16(i * 2) / 100.0
	surface = Marshalls.base64_to_raw(str(terrain["surface_b64"]))


func height_at(x: float, z: float) -> float:
	var fx := clampf((x - x0) / cell, 0.0, cols - 1.001)
	var fz := clampf((z - z0) / cell, 0.0, rows - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var a := heights[iz * cols + ix]
	var b := heights[iz * cols + ix + 1]
	var c := heights[(iz + 1) * cols + ix]
	var d := heights[(iz + 1) * cols + ix + 1]
	# Match TerrainBuilder's two triangles exactly. Bilinear interpolation can be
	# metres below the rendered slope, exposing terrain through roads and façades.
	if tx + tz <= 1.0:
		return a + (b - a) * tx + (c - a) * tz
	return b * (1.0 - tz) + c * (1.0 - tx) + d * (tx + tz - 1.0)


func surface_at(x: float, z: float) -> String:
	var ix := clampi(int(round((x - x0) / cell)), 0, cols - 1)
	var iz := clampi(int(round((z - z0) / cell)), 0, rows - 1)
	return SURFACES[surface[iz * cols + ix]]


func anchor(name: String) -> Vector3:
	var p: Array = raw["anchors"].get(name, [0, 0, 0])
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
