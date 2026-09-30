class_name RoadNetwork
extends RefCounted

## Directed road graph of the real street network (sector JSON "graph"), plus every
## OSM way ("roads": driveable and walkable polylines) for names, geometry and the map.
## One-way streets are single directed edges. Spatial buckets keep lookups cheap.

const DEFAULT_PATH := "res://data/world/sector_center.json"
const BUCKET := 40.0

var roads: Array[Dictionary] = []  # {id, name, class, width, driveable, oneway, points: PackedVector3Array}
var nodes: Array[Vector3] = []
var edges: Dictionary = {}  # node -> Array[int] outgoing
var lane_offset := 1.8
var _segments: Array = []  # [a: Vector3, b: Vector3, road_index: int]
var _buckets: Dictionary = {}  # Vector2i -> Array[int] segment indices
var _node_buckets: Dictionary = {}


static func load_default() -> RoadNetwork:
	var network := RoadNetwork.new()
	var file := FileAccess.open(DEFAULT_PATH, FileAccess.READ)
	if file == null:
		push_error("Road network: sector data missing at %s" % DEFAULT_PATH)
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Road network: invalid sector JSON %s" % DEFAULT_PATH)
		return null
	network.load_sector(parsed)
	return network


func load_sector(data: Dictionary) -> void:
	for raw in data.get("roads", []):
		var points := PackedVector3Array()
		for p in raw["points"]:
			points.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
		roads.append({"id": raw["id"], "name": str(raw.get("name", "")), "class": str(raw["class"]),
			"width": float(raw["width"]), "driveable": bool(raw["driveable"]), "oneway": bool(raw["oneway"]), "points": points})
	var graph: Dictionary = data.get("graph", {})
	for n in graph.get("nodes", []):
		nodes.append(Vector3(float(n[0]), float(n[1]), float(n[2])))
		edges[nodes.size() - 1] = []
	for e in graph.get("edges", []):
		(edges[int(e[0])] as Array).append(int(e[1]))
	for i in range(roads.size()):
		var points: PackedVector3Array = roads[i]["points"]
		for j in range(points.size() - 1):
			_segments.append([points[j], points[j + 1], i])
			var index := _segments.size() - 1
			for key in _cells_between(points[j], points[j + 1]):
				if not _buckets.has(key):
					_buckets[key] = []
				(_buckets[key] as Array).append(index)
	for i in range(nodes.size()):
		var key := _cell(nodes[i])
		if not _node_buckets.has(key):
			_node_buckets[key] = []
		(_node_buckets[key] as Array).append(i)


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / BUCKET), floori(p.z / BUCKET))


func _cells_between(a: Vector3, b: Vector3) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var ca := _cell(a)
	var cb := _cell(b)
	for x in range(mini(ca.x, cb.x), maxi(ca.x, cb.x) + 1):
		for z in range(mini(ca.y, cb.y), maxi(ca.y, cb.y) + 1):
			result.append(Vector2i(x, z))
	return result


## Nearest point on any road centreline: {road, point, distance}. driveable_only
## restricts to car roads (default); names use all ways.
func nearest(point: Vector3, driveable_only: bool = true, search_cells: int = 2) -> Dictionary:
	var best := {}
	var best_distance := INF
	var center := _cell(point)
	for dx in range(-search_cells, search_cells + 1):
		for dz in range(-search_cells, search_cells + 1):
			for index in _buckets.get(Vector2i(center.x + dx, center.y + dz), []):
				var seg: Array = _segments[index]
				var road: Dictionary = roads[int(seg[2])]
				if driveable_only and not road["driveable"]:
					continue
				var projected := Geometry3D.get_closest_point_to_segment(point, seg[0], seg[1])
				var distance := Vector2(projected.x - point.x, projected.z - point.z).length()
				if distance < best_distance:
					best_distance = distance
					best = {"road": road, "point": projected, "distance": distance}
	if best.is_empty() and search_cells < 8:
		return nearest(point, driveable_only, search_cells * 2 + 1)
	return best


func road_name_at(point: Vector3, max_distance: float = 10.0) -> String:
	var hit := nearest(point, false, 1)
	if hit.is_empty() or float(hit["distance"]) > max_distance:
		return ""
	return str((hit["road"] as Dictionary).get("name", ""))


func nearest_node(point: Vector3) -> int:
	var center := _cell(point)
	var best := -1
	var best_distance := INF
	for radius in [1, 3, 8]:
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				for i in _node_buckets.get(Vector2i(center.x + dx, center.y + dz), []):
					var d := Vector2(nodes[i].x - point.x, nodes[i].z - point.z).length()
					if d < best_distance:
						best_distance = d
						best = i
		if best >= 0:
			return best
	return best


## A* over the directed graph from the node nearest `from` to the node nearest `to`.
## Returns node positions followed by the road projection of `to`. Avoid areas
## (Rect2 in X/Z) multiply edge cost by 20.
func find_path(from: Vector3, to: Vector3, avoid: Array[Rect2] = []) -> PackedVector3Array:
	var result := PackedVector3Array()
	var start := nearest_node(from)
	var goal := nearest_node(to)
	if start < 0 or goal < 0:
		return result
	var came: Dictionary = {start: -1}
	var cost: Dictionary = {start: 0.0}
	var heap := [[_flat(nodes[start], nodes[goal]), start]]
	while not heap.is_empty():
		var current: int = _heap_pop(heap)[1]
		if current == goal:
			break
		for next in edges[current]:
			var step := _flat(nodes[current], nodes[next]) * _cost_scale(nodes[current], nodes[next], avoid)
			var new_cost: float = cost[current] + step
			if not cost.has(next) or new_cost < float(cost[next]):
				cost[next] = new_cost
				came[next] = current
				_heap_push(heap, [new_cost + _flat(nodes[next], nodes[goal]), next])
	if not came.has(goal):
		return result
	var chain: Array[int] = []
	var step_node := goal
	while step_node >= 0:
		chain.push_front(step_node)
		step_node = int(came[step_node])
	for index in chain:
		result.append(nodes[index])
	var tail := nearest(to)
	if not tail.is_empty() and (tail["point"] as Vector3).distance_to(result[result.size() - 1]) > 1.0:
		result.append(tail["point"])
	return result


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _cost_scale(a: Vector3, b: Vector3, avoid: Array[Rect2]) -> float:
	for area in avoid:
		if area.has_point(Vector2(a.x, a.z)) or area.has_point(Vector2(b.x, b.z)):
			return 20.0
	return 1.0


func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if float(heap[parent][0]) <= float(heap[i][0]):
			break
		var swap = heap[parent]
		heap[parent] = heap[i]
		heap[i] = swap
		i = parent


func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var i := 0
		while true:
			var left := i * 2 + 1
			var right := left + 1
			var smallest := i
			if left < heap.size() and float(heap[left][0]) < float(heap[smallest][0]):
				smallest = left
			if right < heap.size() and float(heap[right][0]) < float(heap[smallest][0]):
				smallest = right
			if smallest == i:
				break
			var swap = heap[smallest]
			heap[smallest] = heap[i]
			heap[i] = swap
			i = smallest
	return top


## Right-hand lane point for travel from a to b (Spain drives on the right).
func lane_point(a: Vector3, b: Vector3, offset: float = -1.0) -> Vector3:
	var direction := b - a
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		return b
	direction = direction.normalized()
	var right := Vector3(-direction.z, 0.0, direction.x)
	return b + right * (lane_offset if offset < 0.0 else offset)


## True when a car travelling a->b can only continue one way (two-way edge back exists).
func is_two_way(a: int, b: int) -> bool:
	return (edges[b] as Array).has(a)
