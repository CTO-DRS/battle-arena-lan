extends CharacterBody3D
## Bot — عدو آلي لوضع اللعب الفردي (لا يحتاج شبكة إطلاقاً).
##
## سلوك مبسط لكن حيوي:
##   - يتجول عشوائياً في الساحة عندما لا يرى أحداً.
##   - إذا اقترب لاعب أو بوت آخر وكانت خط النظر مفتوحة: يطارد ويصوّب ويطلق النار
##     بتشتت مقصود حتى لا يكون قناصاً مثالياً.
##   - نفس نظام الصحة/التجدد/الإحياء الخاص باللاعب، ويشارك في لوحة النتائج.
##   - يشتغل محلياً 100%: لا RPC شبكية، والقتل يُسجل عبر نفس دالة report_kill
##     (تعمل محلياً في الوضع الفردي لأن RPC call_local يُنفذ على نفس الجهاز).

const SPEED := 5.2
const AIR_SPEED := 3.5
const GRAVITY := 22.0
const MAX_HEALTH := 100
const DAMAGE := 15
const FIRE_COOLDOWN_MIN := 0.55
const FIRE_COOLDOWN_MAX := 1.5
const AIM_ERROR := 0.10
const SIGHT_RANGE := 45.0
const ENGAGE_DISTANCE := 16.0
const REGEN_DELAY := 5.0
const REGEN_RATE := 12.0
const RESPAWN_DELAY := 3.0
const RAY_LENGTH := 60.0
const WANDER_MARGIN := 26.0
const TURN_SPEED := 8.0
const BOT_COLOR := Color(0.72, 0.2, 0.16)

var bot_id := 2
var health := MAX_HEALTH
var display_name := "بوت"
var dead := false
var fire_cooldown := 0.0
var regen_timer := 0.0
var respawn_timer := 0.0

var _wander_target := Vector3.ZERO
var _wander_timer := 0.0
var _flash_timer := 0.0

var _head: Node3D
var _body_mesh: MeshInstance3D
var _body_material: StandardMaterial3D


func _ready() -> void:
        _build_body()
        _pick_wander_target()


func _build_body() -> void:
        collision_layer = 2
        collision_mask = 1 | 2

        var shape := CollisionShape3D.new()
        var capsule := CapsuleShape3D.new()
        capsule.radius = 0.4
        capsule.height = 1.8
        shape.shape = capsule
        shape.position = Vector3(0, 0.9, 0)
        add_child(shape)

        _body_material = StandardMaterial3D.new()
        _body_material.albedo_color = BOT_COLOR
        _body_material.roughness = 0.7

        _body_mesh = MeshInstance3D.new()
        var mesh := CapsuleMesh.new()
        mesh.radius = 0.4
        mesh.height = 1.8
        _body_mesh.mesh = mesh
        _body_mesh.material_override = _body_material
        _body_mesh.position = Vector3(0, 0.9, 0)
        add_child(_body_mesh)

        _head = Node3D.new()
        _head.position = Vector3(0, 1.55, 0)
        add_child(_head)

        var plate := Label3D.new()
        plate.text = display_name
        plate.font = load("res://fonts/Cairo.ttf")
        plate.font_size = 40
        plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        plate.no_depth_test = true
        plate.position = Vector3(0, 2.2, 0)
        plate.modulate = Color(1, 0.65, 0.6, 0.9)
        add_child(plate)


func _physics_process(delta: float) -> void:
        fire_cooldown = maxf(0.0, fire_cooldown - delta)

        if dead:
                velocity = Vector3.ZERO
                respawn_timer -= delta
                if respawn_timer <= 0.0:
                        _respawn()
                return

        # التجدد التدريجي للصحة.
        regen_timer += delta
        if regen_timer > REGEN_DELAY and health < MAX_HEALTH:
                health = mini(MAX_HEALTH, health + int(REGEN_RATE * delta))

        # وميض الضرر.
        if _flash_timer > 0.0:
                _flash_timer -= delta
                if _flash_timer <= 0.0:
                        _body_material.albedo_color = BOT_COLOR

        # الجاذبية.
        if not is_on_floor():
                velocity.y -= GRAVITY * delta

        var move_dir := Vector3.ZERO
        var target := _find_target()

        if target != null:
                move_dir = _engage_target(target, delta)
        else:
                move_dir = _wander(delta)

        var speed := SPEED if is_on_floor() else AIR_SPEED
        if move_dir != Vector3.ZERO:
                velocity.x = move_dir.x * speed
                velocity.z = move_dir.z * speed
        else:
                velocity.x = move_toward(velocity.x, 0, SPEED * delta)
                velocity.z = move_toward(velocity.z, 0, SPEED * delta)

        move_and_slide()


# ----------------------------------------------------------------------
# سلوك القتال والتجوال
# ----------------------------------------------------------------------

func _engage_target(target: Node3D, delta: float) -> Vector3:
        var to_target := target.global_position - global_position
        to_target.y = 0.0
        var dist := to_target.length()
        var dir := to_target.normalized()

        # التوجه نحو الهدف أفقياً + تصويب الرأس عمودياً.
        rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), minf(1.0, delta * TURN_SPEED * 2.0))
        var aim_to := target.global_position + Vector3(0, 1.35, 0)
        var v := aim_to - _head.global_position
        var horiz := Vector2(v.x, v.z).length()
        _head.rotation.x = lerp_angle(_head.rotation.x, atan2(v.y, horiz), minf(1.0, delta * TURN_SPEED * 2.0))

        # الاقتراب إذا كان بعيداً، التوقف عند مسافة الاشتباك.
        var move_dir := Vector3.ZERO
        if dist > ENGAGE_DISTANCE:
                move_dir = dir

        # إطلاق النار بمعدل عشوائي.
        if fire_cooldown <= 0.0:
                _fire_at(target)
        return move_dir


func _wander(delta: float) -> Vector3:
        _wander_timer -= delta
        var to_wp := _wander_target - global_position
        to_wp.y = 0.0
        if to_wp.length() < 2.0 or _wander_timer <= 0.0:
                _pick_wander_target()
                return Vector3.ZERO
        var dir := to_wp.normalized()
        rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), minf(1.0, delta * TURN_SPEED))
        _head.rotation.x = lerp_angle(_head.rotation.x, 0.0, minf(1.0, delta * TURN_SPEED))
        return dir


func _pick_wander_target() -> void:
        _wander_target = Vector3(randf_range(-WANDER_MARGIN, WANDER_MARGIN), 0.2, randf_range(-WANDER_MARGIN, WANDER_MARGIN))
        _wander_timer = randf_range(5.0, 10.0)


func _find_target() -> Node3D:
        var best: Node3D = null
        var best_dist := SIGHT_RANGE
        for node in get_tree().get_nodes_in_group("combatants"):
                if node == self:
                        continue
                if node.dead:
                        continue
                var dist: float = global_position.distance_to(node.global_position)
                if dist < best_dist and _has_los(node):
                        best = node
                        best_dist = dist
        return best


## خط النظر: الجدران (الطبقة 1) فقط تحجب الرؤية، الشخصيات لا تحجبها.
func _has_los(target: Node3D) -> bool:
        var space := get_world_3d().direct_space_state
        var from := _head.global_position
        var to := target.global_position + Vector3(0, 1.4, 0)
        var query := PhysicsRayQueryParameters3D.create(from, to, 1)
        query.exclude = [get_rid()]
        var hit := space.intersect_ray(query)
        return hit.is_empty() or hit["collider"] == target


func _fire_at(target: Node3D) -> void:
        fire_cooldown = randf_range(FIRE_COOLDOWN_MIN, FIRE_COOLDOWN_MAX)

        var from := _head.global_position
        var aim_to := target.global_position + Vector3(0, 1.25, 0)
        var dir := (aim_to - from).normalized()
        # تشتت التصويب: البوت يخطئ أحياناً عمداً.
        dir += Vector3(randf_range(-AIM_ERROR, AIM_ERROR), randf_range(-AIM_ERROR, AIM_ERROR), randf_range(-AIM_ERROR, AIM_ERROR))
        dir = dir.normalized()

        var space := get_world_3d().direct_space_state
        var query := PhysicsRayQueryParameters3D.create(from, from + dir * RAY_LENGTH, 1 | 2)
        query.exclude = [get_rid()]
        var hit := space.intersect_ray(query)
        if hit.is_empty():
                return
        var collider: Object = hit["collider"]
        if collider != null and collider != self and collider.has_method("take_damage"):
                collider.take_damage.rpc(DAMAGE, bot_id)


# ----------------------------------------------------------------------
# الضرر والموت والإحياء
# ----------------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func take_damage(amount: int, by_id: int) -> void:
        if dead:
                return
        health = maxi(0, health - amount)
        regen_timer = 0.0
        _flash_timer = 0.15
        _body_material.albedo_color = Color(0.95, 0.35, 0.3)

        # الاستدارة فوراً نحو من أطلق النار.
        var attacker := get_parent().get_node_or_null(str(by_id))
        if attacker != null:
                var d: Vector3 = attacker.global_position - global_position
                d.y = 0.0
                if d.length() > 0.1:
                        var nd := d.normalized()
                        rotation.y = atan2(-nd.x, -nd.z)

        if health <= 0:
                _die(by_id)


func _die(by_id: int) -> void:
        dead = true
        respawn_timer = RESPAWN_DELAY
        _body_mesh.visible = false
        NetworkManager.report_kill.rpc(by_id, bot_id)


func _respawn() -> void:
        var game := get_parent()
        if game != null and game.has_method("get_spawn_position"):
                global_position = game.get_spawn_position()
        velocity = Vector3.ZERO
        health = MAX_HEALTH
        dead = false
        _body_mesh.visible = true
        _pick_wander_target()
