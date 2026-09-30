extends SceneTree

## Façade details must remain above the local terrain, including uphill bays.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var data := SectorData.load_default()
	var details: Array = []
	var boxes := {"slab": [], "rail": []}
	var steep_edges := 0
	for b in data.raw["buildings"]:
		var fp: Array = b["footprint"]
		var base := float(b["base"])
		var top := base + float(b["height"])
		for edge_index in range(fp.size()):
			var raw_a: Array = fp[edge_index]
			var raw_c: Array = fp[(edge_index + 1) % fp.size()]
			var a := Vector2(float(raw_a[0]), float(raw_a[1]))
			var c := Vector2(float(raw_c[0]), float(raw_c[1]))
			var span := c - a
			if span.length() < 0.05:
				continue
			if absf(data.height_at(a.x, a.y) - data.height_at(c.x, c.y)) > 1.5:
				steep_edges += 1
			var normal := Vector3(span.y, 0, -span.x) / span.length()
			BuildingBuilder._facade(details, boxes, b, str(b["zone"]), a, c, normal, data, top, int(b["street_edges"][edge_index]) == 1, int(b["id"]) * 31 + edge_index)
	var buried := 0
	var lowest := INF
	for item in details:
		var t: Transform3D = item[0]
		var bottom := t.origin.y - t.basis.y.length() * 0.5
		var clearance := bottom - data.height_at(t.origin.x, t.origin.z)
		lowest = minf(lowest, clearance)
		if clearance < -0.35:
			print("BURIED ", t.origin, " cell=", item[1], " clearance=", clearance)
			buried += 1
	if steep_edges < 100 or details.size() < 20000 or buried > 0:
		push_error("SLOPE BUILDINGS FAIL: %d buried of %d details, %d steep edges, lowest %.2f m" % [buried, details.size(), steep_edges, lowest])
		quit(1)
		return
	print("SLOPE BUILDINGS PASS: %d details, %d steep edges; lowest clearance %.2f m" % [details.size(), steep_edges, lowest])
	quit(0)
