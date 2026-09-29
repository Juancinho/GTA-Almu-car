class_name RoadNetwork
extends RefCounted

## Road graph built from res://data/world/road_network.json.
## Roads are axis-aligned segments; nodes are road ends and intersections.
## Used for road geometry, minimap drawing, AI navigation and tests.

const DEFAULT_PATH := "res://data/world/road_network.json"

var roads: Array[Dictionary] = []
var lane_offset := 3.0
var nodes: Array[Vector3] = []
var edges: Dictionary = {}  # node index -> Array of neighbour indices
var road_nodes: Dictionary = {}  # road id -> Array of node indices sorted along the road


static func load_default() -> RoadNetwork:
	var network := RoadNetwork.new()
	if not network.load_file(DEFAULT_PATH):
		return null
	return network


func load_file(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Road network missing: %s (%d)" % [path, FileAccess.get_open_error()])
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not (parsed as Dictionary).has("roads"):
		push_error("Invalid road network data: %s" % path)
		return false
	lane_offset = float(parsed.get("lane_offset_m", 3.0))
	for road in parsed["roads"]:
		var entry: Dictionary = road
		if not entry.has_all(["id", "axis", "fixed", "from", "to", "width"]):
			push_error("Road entry missing fields in %s: %s" % [path, str(entry)])
			return false
		roads.append(entry)
	_build_graph()
	return true


func _point(road: Dictionary, t: float) -> Vector3:
	if str(road["axis"]) == "x":
		return Vector3(t, 0.0, float(road["fixed"]))
	return Vector3(float(road["fixed"]), 0.0, t)


func _param(road: Dictionary, point: Vector3) -> float:
	return point.x if str(road["axis"]) == "x" else point.z


func _node_index(point: Vector3) -> int:
	for i in range(nodes.size()):
		if nodes[i].distance_squared_to(point) < 0.25:
			return i
	nodes.append(point)
	edges[nodes.size() - 1] = []
	return nodes.size() - 1


func _build_graph() -> void:
	for road in roads:
		var params: Array[float] = [float(road["from"]), float(road["to"])]
		for other in roads:
			if other == road or str(other["axis"]) == str(road["axis"]):
				continue
			var cross := float(other["fixed"])
			var own := float(road["fixed"])
			if cross > float(road["from"]) and cross < float(road["to"]) and own >= float(other["from"]) and own <= float(other["to"]):
				params.append(cross)
		params.sort()
		var indices: Array[int] = []
		for t in params:
			var index := _node_index(_point(road, t))
			if indices.is_empty() or indices[-1] != index:
				indices.append(index)
		road_nodes[str(road["id"])] = indices
		for i in range(indices.size() - 1):
			_link(indices[i], indices[i + 1])


func _link(a: int, b: int) -> void:
	if not (edges[a] as Array).has(b):
		(edges[a] as Array).append(b)
	if not (edges[b] as Array).has(a):
		(edges[b] as Array).append(a)


## Returns {road, t, point, distance} for the nearest point on any road centreline.
func nearest(point: Vector3) -> Dictionary:
	var best := {}
	var best_distance := INF
	for road in roads:
		var t := clampf(_param(road, point), float(road["from"]), float(road["to"]))
		var projected := _point(road, t)
		var distance := Vector2(projected.x - point.x, projected.z - point.z).length()
		if distance < best_distance:
			best_distance = distance
			best = {"road": road, "t": t, "point": projected, "distance": distance}
	return best


func road_name_at(point: Vector3, max_distance: float = 12.0) -> String:
	var hit := nearest(point)
	if hit.is_empty() or float(hit["distance"]) > max_distance:
		return ""
	return str((hit["road"] as Dictionary).get("name", ""))


## Nodes bracketing parameter t on a road (one or two indices).
func _segment_nodes(road: Dictionary, t: float) -> Array[int]:
	var indices: Array = road_nodes[str(road["id"])]
	var result: Array[int] = []
	for i in range(indices.size() - 1):
		var a := _param(road, nodes[indices[i]])
		var b := _param(road, nodes[indices[i + 1]])
		if t >= a - 0.01 and t <= b + 0.01:
			result.append(indices[i])
			result.append(indices[i + 1])
			return result
	result.append(indices[0])
	return result


## Shortest road path from `from` to `to`. Returns centreline waypoints ending at the
## projection of `to`. Optional avoid areas (Rect2 in X/Z) multiply edge cost by 20.
func find_path(from: Vector3, to: Vector3, avoid: Array[Rect2] = []) -> PackedVector3Array:
	var result := PackedVector3Array()
	var start := nearest(from)
	var goal := nearest(to)
	if start.is_empty() or goal.is_empty():
		return result
	var goal_point: Vector3 = goal["point"]
	if (start["road"] as Dictionary)["id"] == (goal["road"] as Dictionary)["id"]:
		result.append(goal_point)
		return result
	var start_point: Vector3 = start["point"]
	var start_nodes := _segment_nodes(start["road"], float(start["t"]))
	var goal_nodes := _segment_nodes(goal["road"], float(goal["t"]))
	# Dijkstra over the small intersection graph.
	var dist: Dictionary = {}
	var previous: Dictionary = {}
	var open: Array[int] = []
	for index in start_nodes:
		dist[index] = start_point.distance_to(nodes[index]) * _cost_scale(start_point, nodes[index], avoid)
		previous[index] = -1
		open.append(index)
	var best_goal := -1
	var best_total := INF
	while not open.is_empty():
		var current := open[0]
		for candidate in open:
			if float(dist[candidate]) < float(dist[current]):
				current = candidate
		open.erase(current)
		if float(dist[current]) >= best_total:
			continue
		if goal_nodes.has(current):
			var total := float(dist[current]) + nodes[current].distance_to(goal_point) * _cost_scale(nodes[current], goal_point, avoid)
			if total < best_total:
				best_total = total
				best_goal = current
		for neighbour in edges[current]:
			var cost := float(dist[current]) + nodes[current].distance_to(nodes[neighbour]) * _cost_scale(nodes[current], nodes[neighbour], avoid)
			if not dist.has(neighbour) or cost < float(dist[neighbour]):
				dist[neighbour] = cost
				previous[neighbour] = current
				if not open.has(neighbour):
					open.append(neighbour)
	if best_goal < 0:
		result.append(goal_point)
		return result
	var chain: Array[int] = []
	var step := best_goal
	while step >= 0:
		chain.push_front(step)
		step = int(previous[step])
	for index in chain:
		result.append(nodes[index])
	if result[-1].distance_to(goal_point) > 0.5:
		result.append(goal_point)
	return result


func _cost_scale(a: Vector3, b: Vector3, avoid: Array[Rect2]) -> float:
	if avoid.is_empty():
		return 1.0
	var mid := (a + b) * 0.5
	for area in avoid:
		for sample in [a, mid, b]:
			if area.has_point(Vector2(sample.x, sample.z)):
				return 20.0
	return 1.0


## Right-hand lane point for travel from a to b (Spain drives on the right).
func lane_point(a: Vector3, b: Vector3, offset: float = -1.0) -> Vector3:
	var direction := b - a
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		return b
	direction = direction.normalized()
	var right := Vector3(-direction.z, 0.0, direction.x)
	return b + right * (lane_offset if offset < 0.0 else offset)
