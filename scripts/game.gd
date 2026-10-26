extends Node3D
## Game — مشهد المباراة: بناء الساحة، توليد اللاعبين، وواجهة اللمس.
##
## كل شيء يُبنى برمجياً (بدون ملفات مشاهد معقدة) ليسهل قراءة الكود وتعديله،
## وتظل الساحة متطابقة على كل الأجهزة لأن التخطيط ثابت (Hardcoded).

const ARENA_HALF := 30.0
const WALL_HEIGHT := 5.0

## نقاط ظهور ثابتة (نفسها على كل الأجهزة — الاختيار عشوائي محلياً فقط).
const SPAWNS: Array[Vector3] = [
        Vector3(0, 0.2, 0),
        Vector3(24, 0.2, 24),
        Vector3(-24, 0.2, 24),
        Vector3(24, 0.2, -24),
        Vector3(-24, 0.2, -24),
        Vector3(0, 0.2, 26),
        Vector3(26, 0.2, 0),
        Vector3(-26, 0.2, 0),
]

## صناديق التغطية: [الموضع، الحجم] — ثابتة لضمان تطابق الساحة عند الجميع.
const COVERS: Array = [
        [Vector3(8, 1, 8), Vector3(4, 2, 4)],
        [Vector3(-8, 1, 8), Vector3(4, 2, 4)],
        [Vector3(8, 1, -8), Vector3(4, 2, 4)],
        [Vector3(-8, 1, -8), Vector3(4, 2, 4)],
        [Vector3(16, 1.5, 0), Vector3(3, 3, 8)],
        [Vector3(-16, 1.5, 0), Vector3(3, 3, 8)],
        [Vector3(0, 1.5, 16), Vector3(8, 3, 3)],
        [Vector3(0, 1.5, -16), Vector3(8, 3, 3)],
        [Vector3(20, 0.75, 12), Vector3(6, 1.5, 3)],
        [Vector3(-20, 0.75, -12), Vector3(6, 1.5, 3)],
        [Vector3(12, 0.75, -20), Vector3(3, 1.5, 6)],
        [Vector3(-12, 0.75, 20), Vector3(3, 1.5, 6)],
        [Vector3(0, 2.25, 0), Vector3(5, 4.5, 5)],
        [Vector3(22, 1, 22), Vector3(4, 2, 4)],
        [Vector3(-22, 1, -22), Vector3(4, 2, 4)],
]

var local_player: CharacterBody3D = null

# عناصر الواجهة.
var _look_area: Control
var _health_fill: ColorRect
var _health_label: Label
var _score_box: VBoxContainer
var _damage_flash: ColorRect
var _last_health := 100


func _ready() -> void:
        _build_environment()
        _build_arena()
        _spawn_players()
        _build_hud()
        NetworkManager.player_list_changed.connect(_refresh_scores)
        _refresh_scores()


func _process(_delta: float) -> void:
        if local_player == null:
                return
        var hp: int = local_player.health
        _health_fill.size.x = 380.0 * (float(hp) / 100.0)
        _health_label.text = "الصحة: %d" % hp
        if hp < _last_health:
                _damage_flash.color.a = 0.30
        _last_health = hp
        if _damage_flash.color.a > 0.0:
                _damage_flash.color.a = maxf(0.0, _damage_flash.color.a - _delta * 0.8)


## نقطة ظهور عشوائية للاعب المعاد إحياؤه.
func get_spawn_position() -> Vector3:
        return SPAWNS[randi() % SPAWNS.size()]


# ----------------------------------------------------------------------
# بناء البيئة والساحة
# ----------------------------------------------------------------------

func _build_environment() -> void:
        var sun := DirectionalLight3D.new()
        sun.rotation_degrees = Vector3(-52, 35, 0)
        sun.light_energy = 1.2
        sun.shadow_enabled = true
        add_child(sun)

        var env := Environment.new()
        var sky := Sky.new()
        var sky_mat := ProceduralSkyMaterial.new()
        sky_mat.sky_top_color = Color(0.22, 0.30, 0.42)
        sky_mat.sky_horizon_color = Color(0.62, 0.58, 0.50)
        sky_mat.ground_bottom_color = Color(0.12, 0.12, 0.10)
        sky_mat.ground_horizon_color = Color(0.55, 0.52, 0.45)
        sky.sky_material = sky_mat
        env.background_mode = Environment.BG_SKY
        env.sky = sky
        env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
        env.ambient_light_energy = 0.7
        env.fog_enabled = true
        env.fog_light_color = Color(0.55, 0.52, 0.45)
        env.fog_density = 0.004

        var we := WorldEnvironment.new()
        we.environment = env
        add_child(we)


func _static_box(pos: Vector3, box_size: Vector3, mat: StandardMaterial3D) -> void:
        var body := StaticBody3D.new()
        body.collision_layer = 1
        body.collision_mask = 0
        body.position = pos

        var shape := CollisionShape3D.new()
        var box := BoxShape3D.new()
        box.size = box_size
        shape.shape = box
        body.add_child(shape)

        var mesh := MeshInstance3D.new()
        var box_mesh := BoxMesh.new()
        box_mesh.size = box_size
        mesh.mesh = box_mesh
        mesh.material_override = mat
        body.add_child(mesh)

        add_child(body)


func _build_arena() -> void:
        var floor_mat := StandardMaterial3D.new()
        floor_mat.albedo_color = Color(0.32, 0.34, 0.28)
        floor_mat.roughness = 1.0
        _static_box(Vector3(0, -0.5, 0), Vector3(ARENA_HALF * 2, 1, ARENA_HALF * 2), floor_mat)

        var wall_mat := StandardMaterial3D.new()
        wall_mat.albedo_color = Color(0.42, 0.38, 0.32)
        wall_mat.roughness = 0.9
        var wall_size_n_s := Vector3(ARENA_HALF * 2 + 2, WALL_HEIGHT, 1)
        var wall_size_e_w := Vector3(1, WALL_HEIGHT, ARENA_HALF * 2 + 2)
        _static_box(Vector3(0, WALL_HEIGHT / 2, -ARENA_HALF - 0.5), wall_size_n_s, wall_mat)
        _static_box(Vector3(0, WALL_HEIGHT / 2, ARENA_HALF + 0.5), wall_size_n_s, wall_mat)
        _static_box(Vector3(-ARENA_HALF - 0.5, WALL_HEIGHT / 2, 0), wall_size_e_w, wall_mat)
        _static_box(Vector3(ARENA_HALF + 0.5, WALL_HEIGHT / 2, 0), wall_size_e_w, wall_mat)

        var cover_mat := StandardMaterial3D.new()
        cover_mat.albedo_color = Color(0.50, 0.42, 0.30)
        cover_mat.roughness = 0.85
        var cover_mat2 := StandardMaterial3D.new()
        cover_mat2.albedo_color = Color(0.36, 0.38, 0.40)
        cover_mat2.roughness = 0.85
        for i in COVERS.size():
                var c: Array = COVERS[i]
                _static_box(c[0], c[1], cover_mat if i % 2 == 0 else cover_mat2)


# ----------------------------------------------------------------------
# توليد اللاعبين
# ----------------------------------------------------------------------

func _spawn_players() -> void:
        var my_id := multiplayer.get_unique_id()
        var index := 0
        for id in NetworkManager.players.keys():
                var p := CharacterBody3D.new()
                p.name = str(id)
                p.set_multiplayer_authority(id)
                p.script = load("res://scripts/player.gd")
                p.display_name = str(NetworkManager.players[id]["name"])
                p.position = SPAWNS[index % SPAWNS.size()]
                add_child(p)
                if id == my_id:
                        local_player = p
                index += 1


# ----------------------------------------------------------------------
# واجهة اللمس (HUD) — تُبنى برمجياً بالكامل
# ----------------------------------------------------------------------

func _make_panel_style(bg: Color, radius: int = 10) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = bg
        sb.set_corner_radius_all(radius)
        return sb


func _build_hud() -> void:
        var canvas := CanvasLayer.new()
        add_child(canvas)
        var root := Control.new()
        root.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.mouse_filter = Control.MOUSE_FILTER_IGNORE
        canvas.add_child(root)

        # وميض الضرر الأحمر.
        _damage_flash = ColorRect.new()
        _damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
        _damage_flash.color = Color(0.8, 0.1, 0.1, 0.0)
        _damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
        root.add_child(_damage_flash)

        # منطقة النظر: كل الشاشة (خلف بقية العناصر)، السحب يحرّك الكاميرا.
        _look_area = Control.new()
        _look_area.set_anchors_preset(Control.PRESET_FULL_RECT)
        _look_area.gui_input.connect(_on_look_input)
        root.add_child(_look_area)

        # شعيرات التصويب.
        var crosshair := Label.new()
        crosshair.text = "+"
        crosshair.add_theme_font_size_override("font_size", 34)
        crosshair.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
        crosshair.set_anchors_preset(Control.PRESET_CENTER)
        crosshair.position = Vector2(-12, -24)
        crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
        root.add_child(crosshair)

        # شريط الصحة.
        var health_panel := PanelContainer.new()
        health_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.1, 0.09, 0.07, 0.75)))
        health_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
        health_panel.position = Vector2(-210, -86)
        health_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
        root.add_child(health_panel)
        var h_v := VBoxContainer.new()
        health_panel.add_child(h_v)
        _health_label = Label.new()
        _health_label.text = "الصحة: 100"
        _health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        h_v.add_child(_health_label)
        var bar_bg := ColorRect.new()
        bar_bg.color = Color(0.25, 0.22, 0.18)
        bar_bg.custom_minimum_size = Vector2(380, 14)
        h_v.add_child(bar_bg)
        _health_fill = ColorRect.new()
        _health_fill.color = Color(0.85, 0.55, 0.2)
        _health_fill.size = Vector2(380, 14)
        bar_bg.add_child(_health_fill)

        # لوحة النتائج (أعلى).
        var score_panel := PanelContainer.new()
        score_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.1, 0.09, 0.07, 0.75)))
        score_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
        score_panel.position = Vector2(-260, 14)
        score_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
        root.add_child(score_panel)
        _score_box = VBoxContainer.new()
        score_panel.add_child(_score_box)

        # عصا التحكم (أسفل اليسار).
        var joystick := Control.new()
        joystick.set_script(load("res://scripts/touch_joystick.gd"))
        joystick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
        joystick.position = Vector2(28, -268)
        root.add_child(joystick)
        if local_player != null:
                local_player._joystick = joystick

        # زر الإطلاق (أسفل اليمين).
        var fire_btn := Button.new()
        fire_btn.text = "إطلاق"
        fire_btn.add_theme_font_size_override("font_size", 26)
        fire_btn.add_theme_stylebox_override("normal", _make_panel_style(Color(0.62, 0.25, 0.12, 0.85), 40))
        fire_btn.add_theme_stylebox_override("pressed", _make_panel_style(Color(0.85, 0.35, 0.16, 0.95), 40))
        fire_btn.size = Vector2(110, 110)
        fire_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
        fire_btn.position = Vector2(-140, -140)
        fire_btn.button_down.connect(_on_fire_down)
        fire_btn.button_up.connect(_on_fire_up)
        root.add_child(fire_btn)

        # زر القفز (فوق زر الإطلاق).
        var jump_btn := Button.new()
        jump_btn.text = "قفز"
        jump_btn.add_theme_font_size_override("font_size", 20)
        jump_btn.add_theme_stylebox_override("normal", _make_panel_style(Color(0.16, 0.14, 0.11, 0.85), 40))
        jump_btn.add_theme_stylebox_override("pressed", _make_panel_style(Color(0.30, 0.26, 0.20, 0.95), 40))
        jump_btn.size = Vector2(90, 90)
        jump_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
        jump_btn.position = Vector2(-150, -255)
        jump_btn.button_down.connect(_on_jump_down)
        root.add_child(jump_btn)

        # زر الخروج (أعلى اليسار).
        var leave_btn := Button.new()
        leave_btn.text = "خروج"
        leave_btn.add_theme_font_size_override("font_size", 16)
        leave_btn.add_theme_stylebox_override("normal", _make_panel_style(Color(0.16, 0.14, 0.11, 0.85), 8))
        leave_btn.pressed.connect(_leave_match)
        root.add_child(leave_btn)

        # تلميح الكمبيوتر.
        if OS.has_feature("pc"):
                var hint := Label.new()
                hint.text = "WASD حركة | الماوس نظر (انقر للقفل، Esc للإلغاء) | زر أيسر إطلاق | مسافة قفز"
                hint.add_theme_font_size_override("font_size", 13)
                hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
                hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
                hint.position = Vector2(14, -26)
                root.add_child(hint)


func _on_fire_down() -> void:
        if local_player != null:
                local_player._fire_pressed = true


func _on_fire_up() -> void:
        if local_player != null:
                local_player._fire_pressed = false


func _on_jump_down() -> void:
        if local_player != null:
                local_player._jump_pressed = true


func _on_look_input(event: InputEvent) -> void:
        # أثناء قفل الماوس على الكمبيوتر نتجاهل السحب اللمسي (نظر الماوس يتكفل بالأمر).
        if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
                return
        if event is InputEventScreenDrag and local_player != null:
                local_player.add_look_delta(event.relative)


func _refresh_scores() -> void:
        if _score_box == null:
                return
        for child in _score_box.get_children():
                child.queue_free()
        var title := Label.new()
        title.text = "النتائج"
        title.add_theme_font_size_override("font_size", 14)
        title.add_theme_color_override("font_color", Color(0.85, 0.55, 0.2))
        _score_box.add_child(title)
        var sorted := NetworkManager.players.keys()
        sorted.sort_custom(func(a, b): return NetworkManager.players[a]["kills"] > NetworkManager.players[b]["kills"])
        for id in sorted:
                var row := Label.new()
                row.text = "%s — قتل: %d | موت: %d" % [NetworkManager.players[id]["name"], NetworkManager.players[id]["kills"], NetworkManager.players[id]["deaths"]]
                row.add_theme_font_size_override("font_size", 13)
                _score_box.add_child(row)


func _leave_match() -> void:
        NetworkManager.reset()
        get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
