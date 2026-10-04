extends MeshInstance3D

## Surface nets represent the boundary of solid mass. Once a cavity closes
## completely, an observer inside that mass also needs its filled volume.
## Only proven fully solid cells are represented here; partial cells keep
## the existing isosurface. The same bounded triangles serve local contact.
var field: Node3D
var _signature := ""
var _faces := PackedVector3Array()
var _face_cells: Array[Vector3i] = []
var observer_proof: Dictionary = {}
var last_proof_us := 0
var last_prepare_us := 0
var last_proof_triangle_count := 0
var proof_cache_hit := false
var geometry_rebuilds := 0
var _proof_eye := Vector3.INF
var _proof_state: Array = []
var _proof_mask := -1
var _proof_result := false
var _proof_cached: Dictionary = {}
var _proof_triangles_cached := 0
var _current_state: Array = []
var _current_mask := 0

func _observer_in_mass(eye: Vector3, cell: Vector3i) -> bool:
    var started := Time.get_ticks_usec()
    proof_cache_hit = false
    last_proof_triangle_count = 0
    _current_state = []
    _current_mask = 0
    var result := _compute_observer_in_mass(eye,cell)
    _proof_eye = eye
    _proof_state = _current_state
    _proof_mask = _current_mask
    _proof_result = result
    _proof_cached = observer_proof.duplicate()
    _proof_triangles_cached = last_proof_triangle_count
    last_proof_us = Time.get_ticks_usec()-started
    return result

func _compute_observer_in_mass(eye: Vector3, cell: Vector3i) -> bool:
    observer_proof = {}
    if _solid(cell):
        observer_proof = {"kind": "full_cell", "cell": cell}
        return true
    # Mixed corner occupancy is not proof that the observer is solid. Ray
    # toward an actual published triangle interior, intersecting every
    # local published triangle first. The first crossing's true orientation
    # distinguishes solid->empty from empty->solid even in concave cavities.
    var mixed := false
    for z in range(2):
        for y in range(2):
            for x in range(2):
                if field.corner_density_global(cell+Vector3i(x,y,z)) >= field.config.iso_level:
                    mixed = true
                    _current_mask |= 1 << (x+y*2+z*4)
    if not mixed: return false
    var triangles := PackedVector3Array()
    var target := Vector3.ZERO
    var closest := INF
    var radius := 1.5
    # Surface-net owners may emit a padded-border triangle outside their
    # nominal chunk box. Include that one-cell ownership padding, while
    # the accepted triangle/query radius remains unchanged.
    var ownership_radius: float = radius+field.config.cell_size*(1.0+field.config.facet_jitter)
    var cmin: Vector3i = field.world_to_chunk_coord(eye-Vector3.ONE*ownership_radius)
    var cmax: Vector3i = field.world_to_chunk_coord(eye+Vector3.ONE*ownership_radius)
    var candidates: Array = []
    for z in range(cmin.z,cmax.z+1):
        for y in range(cmin.y,cmax.y+1):
            for x in range(cmin.x,cmax.x+1):
                var chunk = field.get_chunk(Vector3i(x,y,z))
                _current_state.append([Vector3i(x,y,z), chunk._surface_revision if chunk != null else -1, chunk.global_transform if chunk != null else Transform3D.IDENTITY])
                if chunk == null: continue
                candidates.append(chunk)
    var patch_revision := -1
    if field != null and field.get("_surface_patch") != null:
        patch_revision = int(field.get("_surface_patch_revision"))
    _current_state.append(["patch", patch_revision])
    if eye == _proof_eye and _current_state == _proof_state and _current_mask == _proof_mask:
        observer_proof = _proof_cached.duplicate()
        last_proof_triangle_count = _proof_triangles_cached
        proof_cache_hit = true
        return _proof_result
    for chunk in candidates:
        var faces: PackedVector3Array = chunk._surface_faces
        for i in range(0,faces.size(),3):
            var a: Vector3 = chunk.to_global(faces[i])
            var b: Vector3 = chunk.to_global(faces[i+1])
            var c: Vector3 = chunk.to_global(faces[i+2])
            var lo := a.min(b).min(c)
            var hi := a.max(b).max(c)
            if eye.distance_squared_to(eye.clamp(lo,hi)) > radius*radius: continue
            triangles.append(a)
            triangles.append(b)
            triangles.append(c)
            var centroid := (a+b+c)/3.0
            var distance := centroid.distance_squared_to(eye)
            if distance < closest:
                closest = distance
                target = centroid
    if field != null and field.get("_surface_patch") != null:
        var patch = field.get("_surface_patch")
        if patch != null and not patch.faces.is_empty():
            var p_faces: PackedVector3Array = patch.faces
            for i in range(0, p_faces.size(), 3):
                var a: Vector3 = patch.to_global(p_faces[i]) if patch.is_inside_tree() else p_faces[i]
                var b: Vector3 = patch.to_global(p_faces[i+1]) if patch.is_inside_tree() else p_faces[i+1]
                var c: Vector3 = patch.to_global(p_faces[i+2]) if patch.is_inside_tree() else p_faces[i+2]
                var lo := a.min(b).min(c)
                var hi := a.max(b).max(c)
                if eye.distance_squared_to(eye.clamp(lo, hi)) > radius * radius:
                    continue
                triangles.append(a)
                triangles.append(b)
                triangles.append(c)
                var centroid := (a + b + c) / 3.0
                var distance := centroid.distance_squared_to(eye)
                if distance < closest:
                    closest = distance
                    target = centroid
    last_proof_triangle_count = triangles.size()/3
    if closest == INF: return false
    var direction := (target-eye).normalized()
    var first_distance := INF
    var outward := Vector3.ZERO
    var first := Vector3.ZERO
    for i in range(0,triangles.size(),3):
        var point = Geometry3D.ray_intersects_triangle(eye,direction,triangles[i],triangles[i+1],triangles[i+2])
        if point == null: continue
        var distance: float = (point-eye).dot(direction)
        if distance < 0.00001 or distance > radius or distance >= first_distance: continue
        first_distance = distance
        first = point
        outward = -(triangles[i+1]-triangles[i]).cross(triangles[i+2]-triangles[i]).normalized()
    if first_distance == INF or outward.dot(direction) <= 0.00001: return false
    observer_proof = {"kind":"published_surface_exit", "position":first, "outward":outward, "direction":direction,
        "distance":first_distance, "triangles_checked":triangles.size()/3}
    return true

func _ready() -> void:
    cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _solid(cell: Vector3i) -> bool:
    var size: int = field.config.chunk_size
    var coord := Vector3i(floori(float(cell.x)/size), floori(float(cell.y)/size), floori(float(cell.z)/size))
    if field.get_chunk(coord) == null:
        return false
    for z in range(2):
        for y in range(2):
            for x in range(2):
                if field.corner_density_global(cell + Vector3i(x,y,z)) < field.config.iso_level:
                    return false
    return true

func update_eye(eye: Vector3) -> void:
    var cs: float = field.config.cell_size
    var center := Vector3i(floori(eye.x/cs), floori(eye.y/cs), floori(eye.z/cs))
    if not _observer_in_mass(eye,center):
        visible = false
        _signature = ""
        _faces.clear()
        _face_cells.clear()
        mesh = null
        return
    visible = true
    var cells: Array[Vector3i] = []
    var tissues: Array[int] = []
    var touched := {}
    var signature := str(center)+":"+str(cs)
    # Three cells on either side include the first completely filled layer
    # beyond the corner-touched shell of a two-cell-wide closing cavity.
    # No generated chunk or speculative sampler volume is added.
    for z in range(-3, 4):
        for y in range(-3, 4):
            for x in range(-3, 4):
                var cell := center + Vector3i(x,y,z)
                if not _solid(cell): continue
                var location: Array = field.world_to_cell((Vector3(cell) + Vector3.ONE * 0.5) * cs)
                var chunk = field.get_chunk(location[0])
                var local: Vector3i = location[1]
                var tissue: int = chunk.get_tissue_at_cell(local.x, local.y, local.z)
                cells.append(cell)
                tissues.append(tissue)
                signature += str(cell) + ":" + str(tissue)
                var lo := Vector3(cell)*cs
                var hi := lo+Vector3.ONE*cs
                if eye.distance_squared_to(eye.clamp(lo,hi)) <= 0.00000001:
                    touched[cell] = true
                    signature += "@eye"
    if signature == _signature: return
    geometry_rebuilds += 1
    _signature = signature
    _faces.clear()
    _face_cells.clear()
    var vertices: Array = []
    var normals: Array = []
    var uvs: Array = []
    for tissue in range(FDKChunk.TISSUE_TEXTURES.size()):
        vertices.append(PackedVector3Array())
        normals.append(PackedVector3Array())
        uvs.append(PackedVector2Array())
    var included := {}
    for cell in cells: included[cell] = true
    var neighbor_offsets := [Vector3i(0,0,-1),Vector3i(0,0,1),Vector3i(-1,0,0),Vector3i(1,0,0),Vector3i(0,-1,0),Vector3i(0,1,0)]
    var cube_faces := [[0,3,2,1],[4,5,6,7],[0,4,7,3],[1,2,6,5],[0,1,5,4],[3,7,6,2]]
    for i in range(cells.size()):
        var cell := cells[i]
        var lo := Vector3(cell) * cs
        var hi := lo + Vector3.ONE * cs
        var corners := [Vector3(lo.x,lo.y,lo.z), Vector3(hi.x,lo.y,lo.z), Vector3(hi.x,hi.y,lo.z), Vector3(lo.x,hi.y,lo.z),
            Vector3(lo.x,lo.y,hi.z), Vector3(hi.x,lo.y,hi.z), Vector3(hi.x,hi.y,hi.z), Vector3(lo.x,hi.y,hi.z)]
        for side in range(cube_faces.size()):
            # Filled neighbors have no union boundary. Keep only the
            # observer's own cell subdivisions for contact from within mass.
            if not touched.has(cell) and included.has(cell+neighbor_offsets[side]): continue
            var face: Array = cube_faces[side]
            for triangle in [[face[0],face[1],face[2]],[face[0],face[2],face[3]]]:
                var a: Vector3 = corners[triangle[0]]
                var b: Vector3 = corners[triangle[1]]
                var c: Vector3 = corners[triangle[2]]
                var normal := (b-a).cross(c-a).normalized()
                # Cell faces are internal subdivisions, with the same final
                # clockwise winding convention as the outer surface.
                var tid: int = tissues[i] % vertices.size()
                for point in [a,c,b]:
                    vertices[tid].append(to_local(point))
                    normals[tid].append(normal)
                    var an := normal.abs()
                    uvs[tid].append(Vector2(point.z,point.y) if an.x > 0.5 else (Vector2(point.x,point.z) if an.y > 0.5 else Vector2(point.x,point.y)))
                    _faces.append(point)
                _face_cells.append(cell)
    var next_mesh := ArrayMesh.new()
    for tid in range(vertices.size()):
        if vertices[tid].is_empty(): continue
        var arrays := []
        arrays.resize(Mesh.ARRAY_MAX)
        arrays[Mesh.ARRAY_VERTEX] = vertices[tid]
        arrays[Mesh.ARRAY_NORMAL] = normals[tid]
        arrays[Mesh.ARRAY_TEX_UV] = uvs[tid]
        next_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
        next_mesh.surface_set_material(next_mesh.get_surface_count()-1, FDKChunk.terrain_material(tid))
    mesh = next_mesh

func contact_ray(from: Vector3, to: Vector3) -> Dictionary:
    # The field prepares membership once before querying these same faces.
    if not visible: return {}
    var offset := to-from
    var length := offset.length()
    if length < 0.00001: return {}
    var direction := offset/length
    var cs: float = field.config.cell_size
    var best := INF
    var best_owned := false
    var result := {}
    for i in range(0, _faces.size(), 3):
        var point = Geometry3D.ray_intersects_triangle(from, direction, _faces[i], _faces[i+1], _faces[i+2])
        if point == null: continue
        var distance: float = (point-from).dot(direction)
        if distance < 0.0001 or distance > length or distance > best+0.00001: continue
        var outward := -(_faces[i+1]-_faces[i]).cross(_faces[i+2]-_faces[i]).normalized()
        # Adjacent filled cells share opposite copies of an internal face.
        # Select the exited volume, never the entered neighbor's copy, so
        # the solid-side target belongs to the actual intersected volume.
        var facing := outward.dot(direction)
        var cell: Vector3i = _face_cells[i/3]
        var lo := Vector3(cell)*cs
        var hi := lo+Vector3.ONE*cs
        var from_inside := from.distance_squared_to(from.clamp(lo,hi)) <= 0.00000001
        if from_inside and facing <= 0.00001: continue
        if not from_inside and facing >= -0.00001: continue
        if absf(distance-best) <= 0.00001 and (best_owned or not from_inside): continue
        var normal := outward
        if normal.dot(direction) > 0: normal = -normal
        var location: Array = field.world_to_cell((Vector3(_face_cells[i/3]) + Vector3.ONE*0.5)*field.config.cell_size)
        var body: StaticBody3D = field.get_chunk(location[0]).get_body()
        best = distance
        best_owned = from_inside
        result = {"position": point, "normal": normal, "collider": body, "collider_id": body.get_instance_id(),
            "rid": body.get_rid(), "shape": -1, "face_index": i/3, "fdk_solid_volume": true, "fdk_volume_outward": outward}
    return result
