extends CharacterBody3D
## Player — كائن اللاعب (FPS) مع مزامنة شبكية كاملة.
##
## نموذج الصلاحية (Authority Model):
##   كل لاعب يملك عقدته الخاصة على جهازه (الجهاز صاحب الصلاحية يتحرك ويطلق النار)
##   ويرسل حالته للآخرين عبر RPC غير موثوق (unreliable) بسرعة الإطارات.
##   الضرر: من أطلق النار يرسل طلب ضرر لجهاز الضحية، وجهاز الضحية (الصاحب
##   للصلاحية على صحته) يطبقه ويعلن النتيجة — نموذج مبسط مناسب لـ 2-4 أصدقاء.

const SPEED := 6.5
const AIR_SPEED := 4.0
const JUMP_VELOCITY := 8.5
const GRAVITY := 22.0
const MOUSE_SENS := 0.0025
const TOUCH_SENS := 0.0045
const MAX_HEALTH := 100
const FIRE_COOLDOWN := 0.18
const DAMAGE := 20
const REGEN_DELAY := 5.0
const REGEN_RATE := 12.0
const RESPAWN_DELAY := 3.0
const RAY_LENGTH := 120.0

var health := MAX_HEALTH
var display_name := "لاعب"
var dead := false
var fire_cooldown := 0.0
var regen_timer := 0.0
var respawn_timer := 0.0

# مدخلات اللمس (يضبطها مشهد اللعبة).
var _joystick: Node = null
var _fire_pressed := false
var _jump_pressed := false

# حالة الشبكة للاعبين البعيدين (تنعيم الحركة).
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_pitch := 0.0
var _net_moving := false
var _has_net_state := false

var _camera: Camera3D
var _head: Node3D
var _body_mesh: MeshInstance3D
var _nameplate: Label3D
var _cam_pitch := 0.0
var _body_material: StandardMaterial3D
var _flash_timer := 0.0


func _ready() -> void:
        _build_body()
        _net_pos = global_position
        if not is_multiplayer_authority():
                set_process_unhandled_input(false)


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
        _body_material.albedo_color = Color(0.85, 0.55, 0.2) if is_multiplayer_authority() else Color(0.2, 0.45, 0.8)
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

        _camera = Camera3D.new()
        _camera.fov = 75.0
        _camera.near = 0.05
        _head.add_child(_camera)
        if is_multiplayer_authority():
                _camera.current = true
                _body_mesh.visible = false  # لا نرى جسمنا من منظور الأول
        else:
                _nameplate = Label3D.new()
                _nameplate.text = display_name
                _nameplate.font = load("res://fonts/Cairo.ttf")
                _nameplate.font_size = 40
                _nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
                _nameplate.no_depth_test = true
                _nameplate.position = Vector3(0, 2.2, 0)
                _nameplate.modulate = Color(1, 1, 1, 0.9)
                add_child(_nameplate)


# ----------------------------------------------------------------------
# الجهاز صاحب الصلاحية: المدخلات والحركة والإطلاق
# ----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
        if is_multiplayer_authority():
                _process_authority(delta)
        else:
                _process_remote(delta)


func _process_authority(delta: float) -> void:
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

        # الجاذبية.
        if not is_on_floor():
                velocity.y -= GRAVITY * delta

        # اتجاه الحركة: لوحة المفاتيح + عصا اللمس. (الأمام هو -Z، لذا W تسحب نحو -1)
        var input_vec := Vector2.ZERO
        if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
                input_vec.y -= 1.0
        if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
                input_vec.y += 1.0
        if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
                input_vec.x -= 1.0
        if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
                input_vec.x += 1.0
        if _joystick != null:
                input_vec += _joystick.output
        input_vec = input_vec.limit_length(1.0)

        var dir := (transform.basis * Vector3(input_vec.x, 0, input_vec.y)).normalized()
        var speed := SPEED if is_on_floor() else AIR_SPEED
        if dir != Vector3.ZERO:
                velocity.x = dir.x * speed
                velocity.z = dir.z * speed
        else:
                velocity.x = move_toward(velocity.x, 0, SPEED * delta)
                velocity.z = move_toward(velocity.z, 0, SPEED * delta)

        # القفز.
        var wants_jump := Input.is_physical_key_pressed(KEY_SPACE) or _jump_pressed
        if wants_jump and is_on_floor():
                velocity.y = JUMP_VELOCITY
        _jump_pressed = false

        move_and_slide()

        # إطلاق النار.
        var wants_fire := _fire_pressed or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
        if wants_fire:
                _try_fire()

        # مزامنة الحالة مع بقية الأجهزة كل إطار فيزيائي.
        _net_sync.rpc(global_position, rotation.y, _cam_pitch, velocity.length() > 0.5)


func _process_remote(delta: float) -> void:
        if not _has_net_state:
                return
        # تنعيم حركة اللاعبين البعيدين.
        global_position = global_position.lerp(_net_pos, minf(1.0, delta * 14.0))
        rotation.y = lerp_angle(rotation.y, _net_yaw, minf(1.0, delta * 14.0))
        _head.rotation.x = lerp_angle(_head.rotation.x, _net_pitch, minf(1.0, delta * 14.0))
        if _flash_timer > 0.0:
                _flash_timer -= delta
                if _flash_timer <= 0.0:
                        _body_material.albedo_color = Color(0.2, 0.45, 0.8)


func _unhandled_input(event: InputEvent) -> void:
        if dead:
                return
        # قفل الفأرة على الكمبيوتر للتجربة (غير مفعّل على الهاتف).
        if event is InputEventMouseButton and event.pressed and OS.has_feature("pc"):
                if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
                        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
        # نظر الماوس أثناء القفل.
        elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
                rotation.y -= event.relative.x * MOUSE_SENS
                _cam_pitch = clampf(_cam_pitch - event.relative.y * MOUSE_SENS, -1.4, 1.4)
                _head.rotation.x = _cam_pitch
        # زر Esc يحرر الفأرة.
        elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
                Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## تستدعيه منطقة اللمس في واجهة اللعبة عند سحب الإصبع على يمين الشاشة.
func add_look_delta(px: Vector2) -> void:
        if dead:
                return
        rotation.y -= px.x * TOUCH_SENS
        _cam_pitch = clampf(_cam_pitch - px.y * TOUCH_SENS, -1.4, 1.4)
        _head.rotation.x = _cam_pitch


func _try_fire() -> void:
        if fire_cooldown > 0.0 or dead:
                return
        fire_cooldown = FIRE_COOLDOWN

        var space := get_world_3d().direct_space_state
        var from := _camera.global_position
        var dir := -_camera.global_transform.basis.z
        var query := PhysicsRayQueryParameters3D.create(from, from + dir * RAY_LENGTH, 1 | 2)
        query.exclude = [get_rid()]
        var hit := space.intersect_ray(query)
        if hit.is_empty():
                return

        var collider: Object = hit["collider"]
        if collider != null and collider.has_method("take_damage"):
                # نجتاز معرّف الجهاز المطلق ليعرف الضحية من قتله لاحقاً.
                collider.take_damage.rpc(DAMAGE, multiplayer.get_unique_id())


# ----------------------------------------------------------------------
# الضرر والموت والإحياء (تُنفذ على جهاز الضحية)
# ----------------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func take_damage(amount: int, by_id: int) -> void:
        if not is_multiplayer_authority() or dead:
                return
        health = maxi(0, health - amount)
        regen_timer = 0.0
        _sync_health.rpc(health, false)
        if health <= 0:
                _die(by_id)


func _die(by_id: int) -> void:
        dead = true
        respawn_timer = RESPAWN_DELAY
        _sync_health.rpc(0, true)
        NetworkManager.report_kill.rpc(by_id, multiplayer.get_unique_id())


func _respawn() -> void:
        var game := get_parent()
        if game != null and game.has_method("get_spawn_position"):
                global_position = game.get_spawn_position()
        velocity = Vector3.ZERO
        health = MAX_HEALTH
        dead = false
        _sync_health.rpc(health, false)


## مزامنة الصحة والحالة للآخرين (لومض الضرر وإخفاء الجثة).
@rpc("authority", "call_remote", "reliable")
func _sync_health(h: int, is_dead: bool) -> void:
        if is_dead:
                _body_mesh.visible = false
        else:
                _body_mesh.visible = true
                _body_material.albedo_color = Color(0.9, 0.25, 0.2)
                _flash_timer = 0.15


# ----------------------------------------------------------------------
# مزامنة الحالة عبر الشبكة
# ----------------------------------------------------------------------

@rpc("authority", "call_remote", "unreliable_ordered")
func _net_sync(pos: Vector3, yaw: float, pitch: float, moving: bool) -> void:
        _net_pos = pos
        _net_yaw = yaw
        _net_pitch = pitch
        _net_moving = moving
        _has_net_state = true
