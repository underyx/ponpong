## The online lobby: host a room and read the code to a friend, or type the
## code they read to you. While waiting it shows the code large and the
## relay's status; after a match it shows the result. Everything goes to the
## Director as actions: host, join {code}, cancel, back.
class_name OnlineScreen
extends UiScreen

const TITLE_SIZE := 56
const CODE_SIZE := 96
const STATUS_SIZE := 18
const CODE_FIELD_WIDTH := 180

var _host: Button
var _join: Button
var _code_field: LineEdit
var _status: Label
var _back: Button
var _copy: Button
var _link := ""


## args: {"mode": "menu" | "waiting" | "result", "status": String,
##        "code": String and "link": String (waiting), "won": bool, "score": [me, them] (result)}
func setup(p_args: Dictionary) -> void:
	super(p_args)
	back_action = "back"
	add_child(UiKit.dim(0.5))
	var box := UiKit.vbox(10)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var mode := String(args.get("mode", "menu"))
	match mode:
		"waiting":
			_build_waiting(box)
		"result":
			_build_result(box)
		_:
			_build_menu(box)
	var panel := UiKit.panel(Vector2(520, 0))
	panel.add_child(box)
	add_child(UiKit.center(panel))


func first_focus() -> Control:
	if _host != null:
		return _host
	return _back


func set_status(text: String) -> void:
	if _status != null:
		_status.text = text


func _build_menu(box: VBoxContainer) -> void:
	box.add_child(UiKit.heading("PLAY ONLINE", TITLE_SIZE))
	box.add_child(UiKit.rule())
	box.add_child(UiKit.text("Same table, two browsers. One of you hosts and reads the code out, the other joins with it."))
	box.add_child(UiKit.spacer(6))
	_host = UiKit.button("Host a Game")
	_host.size_flags_horizontal = SIZE_SHRINK_CENTER
	_bind(_host, "host")
	box.add_child(_host)
	var row := UiKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_code_field = LineEdit.new()
	_code_field.name = "Code"
	_code_field.placeholder_text = "CODE"
	_code_field.max_length = OnlineRoom.CODE_LENGTH
	_code_field.custom_minimum_size = Vector2(CODE_FIELD_WIDTH, UiKit.BUTTON_SIZE.y)
	_code_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_field.add_theme_font_override("font", Palette.display)
	_code_field.add_theme_font_size_override("font_size", 26)
	_code_field.text = String(args.get("code", ""))
	_code_field.text_changed.connect(_on_code_changed)
	_code_field.text_submitted.connect(func(_t: String) -> void: _on_join_pressed())
	row.add_child(_code_field)
	_join = UiKit.button("Join", 22, Vector2(140, UiKit.BUTTON_SIZE.y))
	_join.pressed.connect(_on_join_pressed)
	row.add_child(_join)
	box.add_child(row)
	_status = UiKit.text(String(args.get("status", "")), STATUS_SIZE)
	_status.name = "Status"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	box.add_child(UiKit.spacer(2))
	_back = UiKit.button("Back")
	_back.size_flags_horizontal = SIZE_SHRINK_CENTER
	_bind(_back, "back")
	box.add_child(_back)


func _build_waiting(box: VBoxContainer) -> void:
	var is_host := bool(args.get("host", true))
	box.add_child(UiKit.heading("ROOM CODE" if is_host else "JOINING", TITLE_SIZE))
	box.add_child(UiKit.rule())
	var code := UiKit.heading(String(args.get("code", "")), CODE_SIZE, Palette.ORANGE)
	code.name = "CodeLabel"
	box.add_child(code)
	if is_host:
		box.add_child(UiKit.text("Read this to your friend. The match starts when they join."))
		_link = String(args.get("link", ""))
		if not _link.is_empty():
			var link_label := UiKit.caption("or send them this link: " + _link)
			link_label.name = "Link"
			link_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			link_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
			box.add_child(link_label)
			_copy = UiKit.button("Copy Link", 18, Vector2(180, 40))
			_copy.size_flags_horizontal = SIZE_SHRINK_CENTER
			_copy.pressed.connect(_on_copy_pressed)
			box.add_child(_copy)
	_status = UiKit.text(String(args.get("status", "")), STATUS_SIZE)
	_status.name = "Status"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	box.add_child(UiKit.spacer(2))
	_back = UiKit.button("Cancel")
	_back.size_flags_horizontal = SIZE_SHRINK_CENTER
	_bind(_back, "cancel")
	box.add_child(_back)
	back_action = "cancel"


func _build_result(box: VBoxContainer) -> void:
	var won := bool(args.get("won", false))
	var score: Array = args.get("score", [0, 0])
	box.add_child(UiKit.heading("YOU WIN" if won else "YOU LOSE", TITLE_SIZE, Palette.ORANGE if won else Palette.INK))
	box.add_child(UiKit.rule())
	box.add_child(UiKit.text("%d to %d against your friend." % [int(score[0]), int(score[1])]))
	_status = UiKit.text(String(args.get("status", "")), STATUS_SIZE)
	_status.name = "Status"
	box.add_child(_status)
	box.add_child(UiKit.spacer(2))
	_back = UiKit.button("Back")
	_back.size_flags_horizontal = SIZE_SHRINK_CENTER
	_bind(_back, "back")
	box.add_child(_back)


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(_link)
	_copy.text = "Copied"


func _on_code_changed(text: String) -> void:
	var upper := text.to_upper()
	if upper != text:
		var caret := _code_field.caret_column
		_code_field.text = upper
		_code_field.caret_column = caret


func _on_join_pressed() -> void:
	var text := _code_field.text.strip_edges().to_upper()
	if not OnlineRoom.is_valid_code(text):
		set_status("A room code is %d letters or digits." % OnlineRoom.CODE_LENGTH)
		return
	press("join", {"code": text})
