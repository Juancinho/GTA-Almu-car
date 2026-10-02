extends RefCounted

## Enterable residential blocks. Each one opens a real street portal (no loading,
## no teleport) in a surveyed building: lobby with conserje, a switchback stair
## that climbs every floor, a lift, landings with neighbours' doors and, on some
## floors, a flat you can walk into (the player's safehouse, Ferrer's penthouse).
## The interior box is WIDTH × DEPTH behind the midpoint of the front edge; the
## candidates were checked to fit inside their footprints with a margin.

const WIDTH := 9.0
const DEPTH := 15.0
const FLOOR_H := 3.1
const DOOR_HALF := 1.2
const DOOR_HEIGHT := 2.75

const SPECS := {
	"residencial_poniente": {"building_id": 467627864, "front_edge": 0, "levels": 4, "name": "Residencial Poniente", "number": "Nº 14",
		"safehouse_floor": 1, "lift_floor": 1, "garage": [7.0, 4.6]},
	"torre_mediterraneo": {"building_id": 1388942451, "front_edge": 4, "levels": 6, "name": "Torre Mediterráneo", "number": "Nº 3",
		"penthouse_floor": 5, "lift_floor": 5, "doorman": true},
	"edificio_mar_azul": {"building_id": 1388635903, "front_edge": 1, "levels": 4, "name": "Edificio Mar Azul", "number": "Nº 7",
		"office_floor": 3, "lift_floor": 3, "office": "CONSTRUCCIONES MAR AZUL"},
}


## building id -> [edge, aperture scale, portal] (same shape as VenueCatalog.fronts()).
static func fronts() -> Dictionary:
	var result := {}
	for spec in SPECS.values():
		result[int(spec["building_id"])] = [int(spec["front_edge"]), DOOR_HALF / 7.0, true]
	return result


static func spec_for_building(data: SectorData, building_id: int) -> Dictionary:
	for spec in SPECS.values():
		if int(spec["building_id"]) == building_id:
			return spec
	return {}


## Door frame of a block: origin on the façade at the lobby floor, yaw that turns
## local +Z towards the street, the pavement height outside and the street normal.
static func frame(data: SectorData, spec: Dictionary) -> Dictionary:
	for building in data.raw["buildings"]:
		if int(building["id"]) != int(spec["building_id"]):
			continue
		var footprint: Array = building["footprint"]
		var edge_index := int(spec["front_edge"])
		var a := Vector2(float(footprint[edge_index][0]), float(footprint[edge_index][1]))
		var b := Vector2(float(footprint[(edge_index + 1) % footprint.size()][0]), float(footprint[(edge_index + 1) % footprint.size()][1]))
		var edge := (b - a).normalized()
		var normal := Vector3(edge.y, 0, -edge.x)
		var side := Vector3(edge.x, 0, edge.y)
		var mid := Vector3((a.x + b.x) * 0.5, 0, (a.y + b.y) * 0.5)
		# The lobby floor sits just above the highest ground inside the box so no
		# terrain pokes through it; a ramp outside absorbs any step at the door.
		var top := -INF
		var sx := -WIDTH * 0.5 - 0.2
		while sx <= WIDTH * 0.5 + 0.21:
			var sz := -0.2
			while sz <= DEPTH + 0.21:
				var p := mid + side * sx - normal * sz
				top = maxf(top, data.height_at(p.x, p.z))
				sz += 0.5
			sx += 0.5
		var outside := mid + normal * 2.4
		var pavement := data.height_at(outside.x, outside.z)
		var door_ground := data.height_at(mid.x + normal.x * 0.3, mid.z + normal.z * 0.3)
		var floor_y := maxf(top, door_ground) + 0.06
		return {"origin": Vector3(mid.x, floor_y, mid.z), "angle": atan2(normal.x, normal.z), "normal": normal,
			"floor_y": floor_y, "pavement": pavement, "outside": Vector3(outside.x, pavement + 0.2, outside.z)}
	return {}


## Top of the portal opening cut in the façade (BuildingBuilder), or -INF.
static func portal_lintel(data: SectorData, building_id: int) -> float:
	var spec := spec_for_building(data, building_id)
	if spec.is_empty():
		return -INF
	var f := frame(data, spec)
	return float(f["floor_y"]) + DOOR_HEIGHT if not f.is_empty() else -INF
