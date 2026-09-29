extends SceneTree
# Winding check: a quad built with FDKLowPoly facing +Z (toward a camera on +Z).
func _init() -> void:
    var root := Node3D.new()
    get_root().add_child(root)
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    FDKLowPoly.add_quad(st, Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(1, 1, 0), Vector3(-1, 1, 0), Vector3.BACK, Color(0, 1, 0))
    var mi := MeshInstance3D.new()
    mi.mesh = st.commit()
    var m := StandardMaterial3D.new()
    m.vertex_color_use_as_albedo = true
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mi.material_override = m
    if OS.get_cmdline_user_args().has("nocull"):
        m.cull_mode = BaseMaterial3D.CULL_DISABLED
    print("verts ", mi.mesh.surface_get_array_len(0))
    root.add_child(mi)
    var cam := Camera3D.new()
    cam.position = Vector3(0, 0, 3)
    root.add_child(cam)
    cam.current = true
    get_root().size = Vector2i(64, 64)
    var ref := MeshInstance3D.new()
    ref.mesh = BoxMesh.new()
    ref.position = Vector3(-1.6, 0, 0)
    root.add_child(ref)

var f := 0
func _process(_d: float) -> bool:
    f += 1
    if f < 10:
        return false
    RenderingServer.force_draw()
    var img := get_root().get_texture().get_image()
    print("CENTER ", img.get_pixel(img.get_width() / 2, img.get_height() / 2), " size ", img.get_size(), " cam ", get_root().get_camera_3d(), " left ", img.get_pixel(4, 32))
    quit(0)
    return true
