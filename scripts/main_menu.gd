extends Control
## MainMenu — القائمة الرئيسية: استضافة غرفة أو الانضمام لغرفة عبر IP.
##
## تدفق اللعب المحلي:
##   1) المضيف يشغّل نقطة الاتصال (Hotspot) من إعدادات الهاتف.
##   2) المضيف يضغط "إنشاء غرفة" ويشارك عنوان IP الظاهر مع الأصدقاء.
##   3) الأصدقاء يتصلون بنفس شبكة الـ Hotspot ثم يدخلون الـ IP ويتصلون.
##   4) المضيف يضغط "ابدأ المباراة" فتنطلق المباراة عند الجميع فوراً.

var _name_input: LineEdit
var _ip_input: LineEdit
var _error_label: Label
var _home_panel: PanelContainer
var _lobby_panel: PanelContainer
var _lobby_title: Label
var _lobby_info: Label
var _lobby_list: VBoxContainer
var _start_btn: Button
var _connecting_label: Label


func _ready() -> void:
	_build_ui()
	NetworkManager.player_list_changed.connect(_refresh_lobby)
	NetworkManager.lobby_error.connect(_on_lobby_error)
	if NetworkManager.last_error != "":
		_error_label.text = NetworkManager.last_error
		NetworkManager.last_error = ""
	# استقبال بدء المباراة عبر مدير الشبكة (للمضيف والعميل معاً).
	if not NetworkManager.match_started.is_connected(_on_match_started):
		NetworkManager.match_started.connect(_on_match_started)


func _on_match_started() -> void:
	pass  # التبديل إلى مشهد اللعبة يتم داخل NetworkManager._load_match


func _player_name() -> String:
	var n := _name_input.text.strip_edges()
	if n.is_empty():
		n = "لاعب %d" % (randi() % 90 + 10)
	return n.substr(0, 16)


# ----------------------------------------------------------------------
# بناء الواجهة برمجياً
# ----------------------------------------------------------------------

func _make_style(bg: Color, radius: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	return sb


func _make_button(text: String, bg: Color, font_size: int = 20) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_stylebox_override("normal", _make_style(bg))
	b.add_theme_stylebox_override("hover", _make_style(bg.lightened(0.12)))
	b.add_theme_stylebox_override("pressed", _make_style(bg.darkened(0.15)))
	b.custom_minimum_size = Vector2(0, 52)
	return b


func _build_ui() -> void:
	# خلفية متدرجة داكنة.
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.09, 0.08, 0.07)
	add_child(bg)

	var layout := VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", 14)
	layout.custom_minimum_size = Vector2(0, 0)
	var margins := MarginContainer.new()
	margins.set_anchors_preset(Control.PRESET_FULL_RECT)
	margins.add_theme_constant_override("margin_left", 60)
	margins.add_theme_constant_override("margin_right", 60)
	margins.add_theme_constant_override("margin_top", 30)
	margins.add_theme_constant_override("margin_bottom", 30)
	add_child(margins)
	margins.add_child(layout)

	# العنوان.
	var title := Label.new()
	title.text = "ساحة المعركة — باتل محلية"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.85, 0.55, 0.2))
	layout.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "لعبة إطلاق نار 3D بدون إنترنت — عبر نقطة الاتصال أو أي شبكة محلية"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	subtitle.add_theme_font_size_override("font_size", 15)
	layout.add_child(subtitle)

	# لوحة الرئيسية.
	_home_panel = PanelContainer.new()
	_home_panel.add_theme_stylebox_override("panel", _make_style(Color(0.14, 0.125, 0.10, 0.97)))
	_home_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_home_panel.custom_minimum_size = Vector2(560, 0)
	layout.add_child(_home_panel)

	var home_v := VBoxContainer.new()
	home_v.add_theme_constant_override("separation", 12)
	_home_panel.add_child(home_v)

	_name_input = LineEdit.new()
	_name_input.placeholder_text = "اسم اللاعب"
	_name_input.max_length = 16
	_name_input.custom_minimum_size = Vector2(0, 48)
	home_v.add_child(_name_input)

	var host_btn := _make_button("إنشاء غرفة (أنا المضيف)", Color(0.62, 0.38, 0.10))
	host_btn.pressed.connect(_on_host_pressed)
	home_v.add_child(host_btn)

	var sep := HSeparator.new()
	home_v.add_child(sep)

	_ip_input = LineEdit.new()
	_ip_input.placeholder_text = "عنوان IP الخاص بالمضيف — مثال: 192.168.43.1"
	_ip_input.custom_minimum_size = Vector2(0, 48)
	home_v.add_child(_ip_input)

	var join_btn := _make_button("انضم إلى غرفة", Color(0.20, 0.32, 0.42))
	join_btn.pressed.connect(_on_join_pressed)
	home_v.add_child(join_btn)

	_error_label = Label.new()
	_error_label.add_theme_color_override("font_color", Color(0.9, 0.35, 0.3))
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(_error_label)

	# لوحة الغرفة (تظهر بعد الاستضافة أو الاتصال).
	_lobby_panel = PanelContainer.new()
	_lobby_panel.add_theme_stylebox_override("panel", _make_style(Color(0.14, 0.125, 0.10, 0.97)))
	_lobby_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_lobby_panel.custom_minimum_size = Vector2(560, 0)
	_lobby_panel.visible = false
	layout.add_child(_lobby_panel)

	var lobby_v := VBoxContainer.new()
	lobby_v.add_theme_constant_override("separation", 12)
	_lobby_panel.add_child(lobby_v)

	_lobby_title = Label.new()
	_lobby_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby_title.add_theme_font_size_override("font_size", 22)
	lobby_v.add_child(_lobby_title)

	_lobby_info = Label.new()
	_lobby_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby_info.add_theme_color_override("font_color", Color(0.85, 0.55, 0.2))
	_lobby_info.add_theme_font_size_override("font_size", 18)
	lobby_v.add_child(_lobby_info)

	_connecting_label = Label.new()
	_connecting_label.text = "جارٍ الاتصال..."
	_connecting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_connecting_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	lobby_v.add_child(_connecting_label)

	var players_title := Label.new()
	players_title.text = "اللاعبون في الغرفة:"
	players_title.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	lobby_v.add_child(players_title)

	_lobby_list = VBoxContainer.new()
	lobby_v.add_child(_lobby_list)

	_start_btn = _make_button("ابدأ المباراة", Color(0.62, 0.38, 0.10))
	_start_btn.pressed.connect(_on_start_pressed)
	lobby_v.add_child(_start_btn)

	var cancel_btn := _make_button("إلغاء والعودة", Color(0.25, 0.14, 0.12), 16)
	cancel_btn.pressed.connect(_on_cancel_pressed)
	lobby_v.add_child(cancel_btn)


# ----------------------------------------------------------------------
# منطق الأزرار
# ----------------------------------------------------------------------

func _on_host_pressed() -> void:
	_error_label.text = ""
	if NetworkManager.host_game(_player_name()):
		_home_panel.visible = false
		_lobby_panel.visible = true
		_connecting_label.visible = false
		_start_btn.visible = true
		_lobby_title.text = "غرفة المضيف جاهزة"
		_lobby_info.text = "شارك هذا العنوان مع أصدقائك:\n%s" % NetworkManager.get_local_ip()
		_refresh_lobby()


func _on_join_pressed() -> void:
	_error_label.text = ""
	var ip := _ip_input.text.strip_edges()
	if ip.is_empty():
		_error_label.text = "أدخل عنوان IP الخاص بالمضيف أولاً"
		return
	if NetworkManager.join_game(_player_name(), ip):
		_home_panel.visible = false
		_lobby_panel.visible = true
		_connecting_label.visible = true
		_start_btn.visible = false
		_lobby_title.text = "في انتظار بدء المضيف..."
		_lobby_info.text = "متصل بـ: %s" % ip
		_refresh_lobby()


func _on_start_pressed() -> void:
	if NetworkManager.is_host:
		NetworkManager.start_match()


func _on_cancel_pressed() -> void:
	NetworkManager.reset()
	_lobby_panel.visible = false
	_home_panel.visible = true
	_error_label.text = ""


func _on_lobby_error(message: String) -> void:
	_error_label.text = message
	_lobby_panel.visible = false
	_home_panel.visible = true


func _refresh_lobby() -> void:
	if _lobby_list == null or not _lobby_panel.visible:
		return
	for child in _lobby_list.get_children():
		child.queue_free()
	var count := NetworkManager.players.size()
	var players_title := Label.new()
	players_title.text = "%d / %d متصلين" % [count, NetworkManager.MAX_PLAYERS]
	players_title.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	_lobby_list.add_child(players_title)
	for id in NetworkManager.players:
		var row := Label.new()
		var tag := " (المضيف)" if id == 1 else ""
		row.text = "• %s%s" % [NetworkManager.players[id]["name"], tag]
		row.add_theme_font_size_override("font_size", 16)
		_lobby_list.add_child(row)
	if NetworkManager.is_host:
		_start_btn.disabled = count < NetworkManager.MIN_PLAYERS_TO_START
		_start_btn.text = "ابدأ المباراة" if count >= NetworkManager.MIN_PLAYERS_TO_START else "انتظر اتصال لاعب آخر (%d/%d)" % [count, NetworkManager.MIN_PLAYERS_TO_START]
