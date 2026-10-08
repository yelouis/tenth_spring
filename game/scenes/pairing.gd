extends Control

# PC Pairing Screen (Item 3a / §B3)
# Displays "Recruit your scout", live QR code, expiration countdown, and recruitment status.

@onready var title_label: Label = $CenterContainer/VBoxContainer/TitleLabel
@onready var qr_rect: TextureRect = $CenterContainer/VBoxContainer/QrRect
@onready var countdown_label: Label = $CenterContainer/VBoxContainer/CountdownLabel
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel

var _t_expire: int = 0

func _ready() -> void:
	SyncServer.peer_paired.connect(_on_peer_paired)
	refresh_code()

func refresh_code() -> void:
	var now = int(Time.get_unix_time_from_system())
	_t_expire = now + PairingCodes.EXPIRATION_SECONDS
	var code = SyncServer.pairing_codes.new_code(now)
	var addrs = PairingCodes.filter_addrs(IP.get_local_addresses())
	var payload = PairingCodes.qr_payload(SyncServer.get_identity(), addrs, SyncServer.get_port(), code)
	var matrix = QrCode.encode_text(payload)
	var tex = QrCode.render_to_texture(matrix, 4)
	if qr_rect != null and tex != null:
		qr_rect.texture = tex
	if status_label != null:
		status_label.text = ""
	_update_countdown(now)

func _process(_delta: float) -> void:
	var now = int(Time.get_unix_time_from_system())
	_update_countdown(now)

func _update_countdown(now: int) -> void:
	if countdown_label == null:
		return
	var remaining = _t_expire - now
	if remaining <= 0:
		countdown_label.text = "Code expired"
	else:
		var mins = remaining / 60
		var secs = remaining % 60
		countdown_label.text = "Code expires in %d:%02d" % [mins, secs]

func _on_peer_paired(_phone_id: String) -> void:
	if status_label != null:
		status_label.text = "Scout recruited."
