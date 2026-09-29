class_name FDKPs1Material
extends RefCounted

## Builds/caches ShaderMaterial instances for the PS1 material shader, one
## per (texture, params) combo, so many mesh instances can share one material
## (cheap) instead of each getting a private one.

static var _cache: Dictionary = {}

static func get_material(tex_path: String, uv_scale: float = 1.0, use_vertex_color: bool = false, wetness: float = 0.4, roughness: float = 0.6) -> ShaderMaterial:
    var key := "%s|%.3f|%s|%.2f|%.2f" % [tex_path, uv_scale, use_vertex_color, wetness, roughness]
    if _cache.has(key):
        return _cache[key]
    var m := ShaderMaterial.new()
    m.shader = load("res://addons/flesh_dig_kit/common/fdk_ps1_material.gdshader")
    var tex: Texture2D = load(tex_path)
    m.set_shader_parameter("albedo_tex", tex)
    m.set_shader_parameter("uv_scale", uv_scale)
    m.set_shader_parameter("use_vertex_color", use_vertex_color)
    m.set_shader_parameter("wetness", wetness)
    m.set_shader_parameter("roughness_value", roughness)
    var settings := FDKPs1Settings.active
    m.set_shader_parameter("snap_precision", settings.vertex_snap_precision if settings.enabled else 100000.0)
    m.set_shader_parameter("fog_distance", settings.fog_distance)
    m.set_shader_parameter("fog_color", Color(0.08, 0.01, 0.02))
    _cache[key] = m
    return m

static func clear_cache() -> void:
    _cache.clear()
