extends Control

## game/scenes/dialogue_box.gd — Compact Bottom Pokemon-Style Dialogue Box (Item 73)
## Contract: docs/implementation_plan_travel_and_time.md §(h)

signal advanced(page_index: int)
signal closed()

var _lines: Array[String] = []
var _page_index: int = 0
var _speaker: String = ""
var _extra_line: String = ""
var _extra_color: Color = Color.WHITE

@onready var speaker_label: Label = $BoxPanel/Margin/VBox/SpeakerLabel
@onready var body_label: Label = $BoxPanel/Margin/VBox/BodyLabel
@onready var extra_label: Label = $BoxPanel/Margin/VBox/Footer/ExtraLabel
@onready var prompt_label: Label = $BoxPanel/Margin/VBox/Footer/PromptLabel

func open_lines(lines: Array, speaker: String = "", extra_line: String = "", extra_color: Color = Color.WHITE) -> void:
	_lines.clear()
	for lv in lines:
		var s := str(lv).strip_edges()
		if not s.is_empty():
			_lines.append(s)
	if _lines.is_empty():
		close()
		return
	_page_index = 0
	_speaker = speaker.strip_edges()
	_extra_line = extra_line.strip_edges()
	_extra_color = extra_color
	visible = true
	_refresh_view()

func advance_or_close() -> bool:
	if not visible:
		return false
	if _page_index + 1 < _lines.size():
		_page_index += 1
		_refresh_view()
		advanced.emit(_page_index)
		return true
	close()
	return false

func close() -> void:
	if not visible and _lines.is_empty():
		return
	visible = false
	_lines.clear()
	_page_index = 0
	closed.emit()

func is_open() -> bool:
	return visible

func current_text() -> String:
	if _page_index >= 0 and _page_index < _lines.size():
		return _lines[_page_index]
	return ""

func current_speaker() -> String:
	return _speaker

func current_extra_text() -> String:
	return _extra_line

func current_extra_color() -> Color:
	return _extra_color

func get_all_lines() -> Array[String]:
	return _lines.duplicate()

func _refresh_view() -> void:
	if speaker_label != null:
		speaker_label.text = _speaker
		speaker_label.visible = not _speaker.is_empty()
	if body_label != null:
		body_label.text = current_text()
	var is_last := (_page_index + 1 >= _lines.size())
	if extra_label != null:
		extra_label.text = _extra_line
		extra_label.add_theme_color_override("font_color", _extra_color)
		extra_label.visible = is_last and not _extra_line.is_empty()
	if prompt_label != null:
		prompt_label.text = "▼ [Enter]" if not is_last else "■ [Enter]"

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			if ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER or ke.keycode == KEY_SPACE or ke.keycode == KEY_Z:
				advance_or_close()
				get_viewport().set_input_as_handled()
			elif ke.keycode == KEY_ESCAPE or ke.keycode == KEY_X:
				close()
				get_viewport().set_input_as_handled()
