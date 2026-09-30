extends RefCounted

## Single source for physical portals, rooms, signs and services. Edges reference
## the deterministic sector footprint; venue tests check containment after rebuilds.
const SPECS := {
	"supermarket": {"building_id": 1388635018, "front_edge": 1, "scale": 0.68, "origin": Vector3(420, 0, 0), "sign": "MERCADO AZUL", "service": "COMPRAR COMIDA  ·  15 €"},
	"restaurant": {"building_id": 1388940272, "front_edge": 1, "scale": 0.42, "origin": Vector3(840, 0, 0), "sign": "LA BRISA  ·  RESTAURANTE", "service": "PEDIR MENÚ  ·  35 €"},
	"bank": {"building_id": 1388635559, "front_edge": 2, "scale": 1.0, "origin": Vector3(1260, 0, 0), "sign": "CAJA PONIENTE", "service": "INGRESAR 100 €"},
	"jewellery": {"building_id": 1389157377, "front_edge": 18, "scale": 0.68, "origin": Vector3(1680, 0, 0), "sign": "JOYERÍA FARO", "service": "ROBAR VITRINA"},
	"church": {"building_id": 1136153313, "front_edge": 0, "scale": 1.0, "origin": Vector3(2100, 0, 0), "sign": "IGLESIA DE LA ENCARNACIÓN", "service": "DESCANSAR"},
	"mall": {"building_id": 1388629764, "front_edge": 0, "scale": 1.0, "origin": Vector3(2520, 0, 0), "sign": "GALERÍA COSTA TROPICAL", "service": "COMPRAR COMIDA  ·  15 €"},
	"cafe": {"building_id": 467627875, "front_edge": 10, "scale": 1.0, "origin": Vector3(2940, 0, 0), "sign": "BRISA Y LIMÓN · CAFETERÍA", "service": "CAFÉ Y TOSTADA · 8 €", "price": 8, "heal": 20.0},
	"palm_restaurant": {"building_id": 1154823706, "front_edge": 8, "scale": 1.0, "origin": Vector3(3360, 0, 0), "sign": "LA PALMERA · RESTAURANTE", "service": "PEDIR MENÚ · 35 €", "price": 35, "heal": 100.0},
}


static func fronts() -> Dictionary:
	var result := {}
	for spec in SPECS.values():
		result[int(spec["building_id"])] = [int(spec["front_edge"]), float(spec["scale"])]
	return result
