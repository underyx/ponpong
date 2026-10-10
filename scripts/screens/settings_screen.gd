## The settings: master volume, fullscreen and screen shake, on a paper
## plate over a dimmed backdrop. Every change lands in the Settings statics
## and is applied at once, so the slider is heard and fullscreen is seen
## while the screen is still up; the Director writes the file when Back is
## pressed. Opened from the main menu or from Pause, and Back returns to
## whichever it was.
##
## args: {"return": "main_menu"|"pause"}
## actions: back. ui_cancel (Esc, B) presses back.
class_name SettingsScreen
extends UiScreen

const TITLE_SIZE := 56
const ROW_SIZE := 20
const SLIDER_WIDTH := 300
const SLIDER_STEP := 0.05
## Width of the setting names column, so the controls line up.
const NAME_WIDTH := 200
## Space between the slider and the ring drawn around it when it has focus.
const SLIDER_PAD := 6
const PERCENT_WIDTH := 64
const BACK_SIZE := Vector2(230, 52)
## The On/Off pill the toggles wear: the theme's own check icons are near
## invisible on paper, so Off read as a bare dot.
const PILL_SIZE := Vector2i(48, 26)
## Gap between the track's edge and the knob.
const PILL_KNOB_PAD := 4.0
const PILL_RIM := 2.0

var slider: HSlider
var percent_label: Label
var fullscreen_button: CheckButton
var shake_button: CheckButton
var back_button: Button

## The ring that shows the slider holds focus; a slider has no focus style
## of its own.
var _slider_frame: PanelContainer
var _frame_rest: StyleBoxEmpty
var _frame_focus: StyleBoxFlat


func setup(p_args: Dictionary) -> void:
	super(p_args)
	back_action = "back"
	add_child(UiKit.dim(0.5))
	var box := UiKit.vbox(12)
	box.add_child(UiKit.heading("SETTINGS", TITLE_SIZE))
	box.add_child(UiKit.rule())
	box.add_child(UiKit.spacer(6))
	var grid := GridContainer.new()
	grid.name = "Rows"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	grid.add_child(_name("Master volume"))
	grid.add_child(_volume_row())
	grid.add_child(_name("Fullscreen"))
	fullscreen_button = _toggle("Fullscreen", Settings.fullscreen, _on_fullscreen_toggled)
	grid.add_child(fullscreen_button)
	grid.add_child(_name("Screen shake"))
	shake_button = _toggle("ScreenShake", Settings.screen_shake, _on_shake_toggled)
	grid.add_child(shake_button)
	box.add_child(grid)
	box.add_child(UiKit.spacer(4))
	box.add_child(UiKit.caption("F11 flips fullscreen anywhere. Changes apply at once and Back saves them.", 13))
	box.add_child(UiKit.spacer(6))
	back_button = UiKit.button("Back", 20, BACK_SIZE)
	back_button.size_flags_horizontal = SIZE_SHRINK_CENTER
	_bind(back_button, "back")
	box.add_child(back_button)
	var panel := UiKit.panel()
	panel.add_child(box)
	add_child(UiKit.center(panel))


## The slider: a gamepad lands on the thing most worth adjusting.
func first_focus() -> Control:
	return slider


## Puts the controls back in step with the statics after something else
## changed them (F11 while this screen is up). Nothing is re-applied.
func refresh() -> void:
	slider.set_value_no_signal(Settings.master_volume)
	percent_label.text = Settings.percent(Settings.master_volume)
	fullscreen_button.set_pressed_no_signal(Settings.fullscreen)
	fullscreen_button.text = _on_off(Settings.fullscreen)
	shake_button.set_pressed_no_signal(Settings.screen_shake)
	shake_button.text = _on_off(Settings.screen_shake)


# --- rows ------------------------------------------------------------------------

func _name(text: String) -> Label:
	var l := UiKit.strong(text, ROW_SIZE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.custom_minimum_size = Vector2(NAME_WIDTH, 0)
	l.size_flags_vertical = SIZE_SHRINK_CENTER
	return l


## [ring( slider )] 80%
func _volume_row() -> HBoxContainer:
	var row := UiKit.hbox(12)
	slider = HSlider.new()
	slider.name = "Volume"
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = SLIDER_STEP
	slider.value = Settings.master_volume
	slider.custom_minimum_size = Vector2(SLIDER_WIDTH, 0)
	slider.size_flags_vertical = SIZE_SHRINK_CENTER
	slider.focus_mode = FOCUS_ALL
	var knob := _knob()
	slider.add_theme_icon_override("grabber", knob)
	slider.add_theme_icon_override("grabber_highlight", knob)
	slider.add_theme_icon_override("grabber_disabled", knob)
	slider.value_changed.connect(_on_volume_changed)
	slider.focus_entered.connect(_set_frame.bind(true))
	slider.focus_exited.connect(_set_frame.bind(false))
	_frame_rest = StyleBoxEmpty.new()
	_frame_rest.set_content_margin_all(SLIDER_PAD)
	_frame_focus = UiKit.focus_style(10, 0.0)
	_frame_focus.set_content_margin_all(SLIDER_PAD)
	_slider_frame = PanelContainer.new()
	_slider_frame.name = "VolumeFrame"
	_slider_frame.mouse_filter = MOUSE_FILTER_IGNORE
	_slider_frame.add_theme_stylebox_override("panel", _frame_rest)
	_slider_frame.add_child(slider)
	row.add_child(_slider_frame)
	percent_label = UiKit.display(Settings.percent(Settings.master_volume), ROW_SIZE, Palette.ORANGE)
	percent_label.name = "Percent"
	percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	percent_label.custom_minimum_size = Vector2(PERCENT_WIDTH, 0)
	percent_label.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(percent_label)
	return row


## A CheckButton reading On or Off, in the theme's print style, with the
## orange focus ring every other control wears.
func _toggle(p_name: String, on: bool, handler: Callable) -> CheckButton:
	var b := CheckButton.new()
	b.name = p_name
	b.button_pressed = on
	b.text = _on_off(on)
	b.focus_mode = FOCUS_ALL
	b.size_flags_horizontal = SIZE_SHRINK_BEGIN
	var on_icon := _pill(true)
	var off_icon := _pill(false)
	b.add_theme_icon_override("checked", on_icon)
	b.add_theme_icon_override("unchecked", off_icon)
	b.add_theme_icon_override("checked_disabled", on_icon)
	b.add_theme_icon_override("unchecked_disabled", off_icon)
	b.toggled.connect(handler)
	return b


## A rounded track with an ink rim and a knob: orange with a paper knob at
## the right for On, a dim track with an ink knob at the left for Off. Drawn
## pixel by pixel into an ImageTexture, so there is no asset to load.
static func _pill(on: bool) -> ImageTexture:
	var img := Image.create_empty(PILL_SIZE.x, PILL_SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := PILL_SIZE.y * 0.5
	var track := Palette.ORANGE if on else Palette.PAPER_DIM
	var knob := Palette.PAPER if on else Palette.INK
	var knob_x := PILL_SIZE.x - r if on else r
	for y in PILL_SIZE.y:
		for x in PILL_SIZE.x:
			var p := Vector2(x + 0.5, y + 0.5)
			# The track is a stadium: a point is inside when it is within r of
			# the centre line between the two end caps; the rim is its edge.
			var d := p.distance_to(Vector2(clampf(p.x, r, PILL_SIZE.x - r), r))
			if d <= r:
				img.set_pixel(x, y, Palette.INK if d > r - PILL_RIM else track)
			if p.distance_to(Vector2(knob_x, r)) <= r - PILL_KNOB_PAD:
				img.set_pixel(x, y, knob)
	return ImageTexture.create_from_image(img)


## The slider's knob: a paper disc with an ink rim.
static func _knob() -> ImageTexture:
	var size := 22
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(size * 0.5, size * 0.5)
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if d <= size * 0.5:
				img.set_pixel(x, y, Palette.INK if d > size * 0.5 - 3.0 else Palette.PAPER_BRIGHT)
	return ImageTexture.create_from_image(img)


static func _on_off(on: bool) -> String:
	return "On" if on else "Off"


# --- changes -------------------------------------------------------------------------

## The new level is applied and heard at once.
func _on_volume_changed(value: float) -> void:
	Settings.master_volume = clampf(value, 0.0, 1.0)
	percent_label.text = Settings.percent(Settings.master_volume)
	Settings.apply()
	Sfx.play("ui_move")


func _on_fullscreen_toggled(on: bool) -> void:
	Settings.fullscreen = on
	fullscreen_button.text = _on_off(on)
	Settings.apply()
	Sfx.play("ui_accept")


func _on_shake_toggled(on: bool) -> void:
	Settings.screen_shake = on
	shake_button.text = _on_off(on)
	Settings.apply()
	Sfx.play("ui_accept")


func _set_frame(focused: bool) -> void:
	_slider_frame.add_theme_stylebox_override("panel", _frame_focus if focused else _frame_rest)
