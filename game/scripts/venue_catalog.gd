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
	"casino": {"building_id": 467627872, "front_edge": 7, "scale": 0.9, "origin": Vector3(3780, 0, 0), "sign": "CASINO COSTA TROPICAL", "service": "RULETA · ROJO · 100 €", "secondary": "TRAGAPERRAS · 20 €", "floors": 2},
	"gun_shop": {"building_id": 1388943439, "front_edge": 2, "scale": 0.7, "origin": Vector3(4200, 0, 0), "sign": "ARMERÍA EL COTO", "service": "MUNICIÓN · 100 €", "secondary": "COMPRAR ARMA"},
	"nightclub": {"building_id": 1132878853, "front_edge": 0, "scale": 0.9, "origin": Vector3(4620, 0, 0), "sign": "DISCOTECA LEVANTE", "service": "COPA · 10 €", "price": 10, "heal": 15.0},
	"seafood": {"building_id": 1389158521, "front_edge": 2, "scale": 0.9, "origin": Vector3(5040, 0, 0), "sign": "MARISQUERÍA EL ESPIGÓN", "service": "FRITURA Y ESPETOS · 30 €", "price": 30, "heal": 100.0},
	"bakery": {"building_id": 1056656677, "front_edge": 5, "scale": 0.65, "origin": Vector3(5460, 0, 0), "sign": "HORNO DE SAL · PANADERÍA", "service": "DESAYUNO · 6 €", "price": 6, "heal": 15.0},
	"pharmacy": {"building_id": 467627856, "front_edge": 0, "scale": 0.65, "origin": Vector3(5880, 0, 0), "sign": "BOTICA DEL SOL", "service": "BOTIQUÍN · 25 €", "price": 25, "heal": 80.0},
	"barber": {"building_id": 1388941225, "front_edge": 14, "scale": 0.65, "origin": Vector3(6300, 0, 0), "sign": "ESTUDIO MAREA · ESTILISMO", "service": "CAMBIAR ESTILO · 35 €", "price": 35},
	"gym": {"building_id": 1389326430, "front_edge": 0, "scale": 0.65, "origin": Vector3(6720, 0, 0), "sign": "GIMNASIO HORIZONTE", "service": "RECUPERACIÓN · 10 €", "price": 10, "heal": 40.0},
	"record_shop": {"building_id": 467627862, "front_edge": 2, "scale": 0.65, "origin": Vector3(7140, 0, 0), "sign": "SURCO SUR · DISCOS", "service": "ESCUCHAR SESIÓN ORIGINAL"},
	"clothing": {"building_id": 467627877, "front_edge": 0, "scale": 0.65, "origin": Vector3(7560, 0, 0), "sign": "LINO Y MAR · MODA", "service": "CAMBIAR ROPA · 60 €", "price": 60},
	"residence_altillo": {"building_id": 1056656685, "front_edge": 2, "scale": 0.65, "origin": Vector3(7980, 0, 0), "sign": "RESIDENCIAL ALTILLO", "service": "DESCANSAR EN APARTAMENTO", "floors": 2, "residential": true},
	"residence_centro": {"building_id": 1388941226, "front_edge": 3, "scale": 0.65, "origin": Vector3(8400, 0, 0), "sign": "PATIO DEL CENTRO", "service": "DESCANSAR EN APARTAMENTO", "floors": 2, "residential": true},
	"residence_mirador": {"building_id": 467627861, "front_edge": 9, "scale": 0.65, "origin": Vector3(8820, 0, 0), "sign": "APARTAMENTOS MIRADOR", "service": "DESCANSAR EN APARTAMENTO", "floors": 2, "residential": true},
}


static func fronts() -> Dictionary:
	var result := {}
	for spec in SPECS.values():
		result[int(spec["building_id"])] = [int(spec["front_edge"]), float(spec["scale"])]
	return result
