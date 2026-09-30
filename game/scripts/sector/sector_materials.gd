class_name SectorMaterials
extends RefCounted

## Shared material cache for the generated sector (CC0 ambientCG textures, triplanar
## in world space, tinted). One instance per world keeps draw calls and memory low.

const TEXTURE_DIR := "res://assets/third_party/ambientcg/"
const PALM_BARK_DIR := "res://assets/third_party/polyhaven/"
const CLEAN_ASPHALT_DIR := "res://assets/third_party/polyhaven/"

var cache: Dictionary = {}


func road_asphalt() -> StandardMaterial3D:
	if cache.has("road_asphalt"):
		return cache["road_asphalt"]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(CLEAN_ASPHALT_DIR + "clean_asphalt_diff_2k.jpg") as Texture2D
	mat.albedo_color = Color(1.25, 1.23, 1.19)
	mat.normal_enabled = true
	mat.normal_texture = load(CLEAN_ASPHALT_DIR + "clean_asphalt_nor_gl_2k.jpg") as Texture2D
	mat.normal_scale = 0.65
	mat.roughness_texture = load(CLEAN_ASPHALT_DIR + "clean_asphalt_rough_2k.jpg") as Texture2D
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.roughness = 0.94
	# RoadBuilder supplies stable world-space planar UVs. A road is horizontal,
	# so triplanar sampling only adds three texture reads per map per pixel.
	mat.uv1_triplanar = false
	mat.uv1_world_triplanar = false
	mat.vertex_color_use_as_albedo = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	cache["road_asphalt"] = mat
	return mat


func palm_bark() -> StandardMaterial3D:
	if cache.has("palm_bark"):
		return cache["palm_bark"]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(PALM_BARK_DIR + "palm_tree_bark_diffuse_1k.jpg") as Texture2D
	mat.normal_enabled = true
	mat.normal_texture = load(PALM_BARK_DIR + "palm_tree_bark_normal_gl_1k.jpg") as Texture2D
	mat.normal_scale = 0.75
	mat.roughness = 0.95
	mat.uv1_scale = Vector3(2.0, 1.0, 1.0)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	cache["palm_bark"] = mat
	return mat


func textured(key: String, texture_id: String, tint: Color, tile_m: float, roughness: float = 0.9, vertex_tint: bool = false) -> StandardMaterial3D:
	if cache.has(key):
		return cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = roughness
	mat.albedo_texture = load(TEXTURE_DIR + texture_id + "_color.png") as Texture2D
	mat.normal_enabled = true
	mat.normal_texture = load(TEXTURE_DIR + texture_id + "_normal.png") as Texture2D
	mat.normal_scale = 0.8
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / tile_m
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.vertex_color_use_as_albedo = vertex_tint
	cache[key] = mat
	return mat


func plain(key: String, color: Color, roughness: float = 0.8, metallic: float = 0.0) -> StandardMaterial3D:
	if cache.has(key):
		return cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	cache[key] = mat
	return mat


func facade_detail() -> ShaderMaterial:
	if cache.has("facade_detail"):
		return cache["facade_detail"]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/facade_detail.gdshader") as Shader
	mat.set_shader_parameter("atlas", load("res://assets/generated/facade_atlas.png") as Texture2D)
	cache["facade_detail"] = mat
	return mat


func sea() -> StandardMaterial3D:
	if cache.has("sea"):
		return cache["sea"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.07, 0.30, 0.38, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.08
	mat.metallic = 0.1
	mat.metallic_specular = 0.8
	mat.normal_enabled = true
	mat.normal_texture = load(TEXTURE_DIR + "ground080_normal.png") as Texture2D
	mat.normal_scale = 0.5
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / 9.0
	cache["sea"] = mat
	return mat
