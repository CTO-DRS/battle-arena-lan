extends Node
## NetworkManager — العقدة المركزية لإدارة الاتصال المحلي (Autoload)
##
## الفكرة المعمارية:
##   جهاز المضيف (Host) يعمل كخادم ENet على المنفذ 7777 داخل شبكة نقطة الاتصال (Hotspot).
##   بقية اللاعبين يتصلون بعنوان IP الخاص بالمضيف عبر نفس الشبكة المحلية.
##   لا يوجد أي إنترنت مطلوب — هذه بنية Client/Host كلاسيكية شبيهة بما تستخدمه
##   ألعاب مثل Mini Militia في وضع نقطة الاتصال.

signal player_list_changed
signal lobby_error(message: String)
signal match_started

const PORT := 7777
const MAX_PLAYERS := 4
const MIN_PLAYERS_TO_START := 2

var players := {}            # peer_id (int) -> {"name": String, "kills": int, "deaths": int}
var my_name := "لاعب"
var is_host := false
var in_match := false
var last_error := ""


func _ready() -> void:
        multiplayer.peer_connected.connect(_on_peer_connected)
        multiplayer.peer_disconnected.connect(_on_peer_disconnected)
        multiplayer.connected_to_server.connect(_on_connected_to_server)
        multiplayer.connection_failed.connect(_on_connection_failed)
        multiplayer.server_disconnected.connect(_on_server_disconnected)


## إعادة تهيئة كاملة لحالة الشبكة (تُستدعى قبل استضافة أو انضمام جديد، وعند الخروج).
func reset() -> void:
        if multiplayer.multiplayer_peer != null:
                multiplayer.multiplayer_peer.close()
        multiplayer.multiplayer_peer = null
        players.clear()
        is_host = false
        in_match = false


## المضيف: فتح غرفة على شبكة محلية.
func host_game(player_name: String) -> bool:
        reset()
        my_name = player_name
        var peer := ENetMultiplayerPeer.new()
        if peer.create_server(PORT, MAX_PLAYERS) != OK:
                last_error = "تعذر فتح المنفذ %d — أغلق التطبيق وأعد المحاولة" % PORT
                lobby_error.emit(last_error)
                return false
        multiplayer.multiplayer_peer = peer
        is_host = true
        players[1] = _make_entry(player_name)
        player_list_changed.emit()
        return true


## العميل: الاتصال بغرفة المضيف عبر عنوان IP.
func join_game(player_name: String, ip: String) -> bool:
        reset()
        my_name = player_name
        var peer := ENetMultiplayerPeer.new()
        if peer.create_client(ip, PORT) != OK:
                last_error = "عنوان IP غير صالح"
                lobby_error.emit(last_error)
                return false
        multiplayer.multiplayer_peer = peer
        is_host = false
        return true


## المضيف فقط: إطلاق المباراة على كل الأجهزة المتصلة.
func start_match() -> void:
        if multiplayer.is_server():
                _load_match.rpc()


## جلب عنوان IP المحلي لجهاز المضيف ليشاركه مع الأصدقاء.
func get_local_ip() -> String:
        for addr in IP.get_local_addresses():
                if addr.begins_with("192.168.") or addr.begins_with("10."):
                        return addr
                if addr.begins_with("172.") and not addr.begins_with("172.17."):
                        return addr
        return "127.0.0.1"


func _make_entry(pname: String) -> Dictionary:
        return {"name": pname, "kills": 0, "deaths": 0}


# ----------------------------------------------------------------------
# أحداث الاتصال
# ----------------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
        # الخادم فقط من يدير القبول: منع الانضمام المتأخر بعد بدء المباراة أو عند الامتلاء.
        if not multiplayer.is_server():
                return
        if in_match or players.size() >= MAX_PLAYERS:
                multiplayer.multiplayer_peer.disconnect_peer(id)


func _on_peer_disconnected(id: int) -> void:
        if players.has(id):
                players.erase(id)
                player_list_changed.emit()


func _on_connected_to_server() -> void:
        # العميل يعلن عن نفسه للمضيف فور نجاح الاتصال.
        _submit_player_info.rpc_id(1, my_name)


func _on_connection_failed() -> void:
        reset()
        last_error = "فشل الاتصال — تأكد من العنوان وأن المضيف أنشأ الغرفة"
        lobby_error.emit(last_error)


func _on_server_disconnected() -> void:
        reset()
        last_error = "انقطع الاتصال بالمضيف"
        lobby_error.emit(last_error)
        if get_tree().current_scene and get_tree().current_scene.name != "MainMenu":
                get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# ----------------------------------------------------------------------
# استدعاءات عن بعد (RPCs)
# ----------------------------------------------------------------------

## العميل -> المضيف: تقديم اسم اللاعب للانضمام إلى القائمة.
@rpc("any_peer", "call_remote", "reliable")
func _submit_player_info(pname: String) -> void:
        if not multiplayer.is_server() or in_match:
                return
        var id := multiplayer.get_remote_sender_id()
        if not players.has(id) and players.size() < MAX_PLAYERS:
                players[id] = _make_entry(pname)
                _sync_player_list.rpc(players)
                player_list_changed.emit()


## المضيف -> الجميع: مزامنة قائمة اللاعبين (والنتائج أثناء المباراة).
@rpc("authority", "call_remote", "reliable")
func _sync_player_list(list: Dictionary) -> void:
        players = list
        player_list_changed.emit()


## المضيف -> الجميع (ويشمله المضيف): تحميل مشهد المباراة.
@rpc("authority", "call_local", "reliable")
func _load_match() -> void:
        in_match = true
        get_tree().change_scene_to_file("res://scenes/game.tscn")
        match_started.emit()


## أي جهاز -> الجميع: تسجيل قتل في لوحة النتائج.
## يرسلها جهاز الضحية لأنه صاحب صلاحية (Authority) على صحته.
@rpc("any_peer", "call_local", "reliable")
func report_kill(killer_id: int, victim_id: int) -> void:
        if players.has(killer_id):
                players[killer_id]["kills"] += 1
        if players.has(victim_id):
                players[victim_id]["deaths"] += 1
        player_list_changed.emit()
