## The player's settings: master volume, fullscreen and screen shake, as
## statics any script can read. They live in a ConfigFile under user://, are
## read once at boot by the Director (load_and_apply) and written whenever
## the Settings screen is left or F11 is pressed. apply() pushes the values
## into the engine: the Master bus and the window mode. Nothing here is a
## node; the Settings screen edits the statics and calls apply() live.
##
## `path` is where the file lives. Tests point it at a file of their own
## before the Director boots, so a headless check never touches the player's
## settings, the way Director.save_path does for the run.
class_name Settings
extends RefCounted

const DEFAULT_PATH := "user://settings.cfg"
const SECTION := "settings"
const DEFAULT_MASTER_VOLUME := 0.8
const DEFAULT_FULLSCREEN := false
const DEFAULT_SCREEN_SHAKE := true
## Below this the Master bus is muted outright rather than set to a very
## quiet level, so "0%" really is silence.
const MUTE_BELOW := 0.001
## What linear_to_db gets at the bottom of the slider; it is never asked
## for the -inf dB of a true zero.
const MIN_LINEAR := 0.0001

## 0..1, linear; the Master bus volume.
static var master_volume := DEFAULT_MASTER_VOLUME
static var fullscreen := DEFAULT_FULLSCREEN
## Off, the camera rig never shakes, whatever the match asks for.
static var screen_shake := DEFAULT_SCREEN_SHAKE
## The file the statics are read from and written to.
static var path := DEFAULT_PATH


## Reads the file at `path` into the statics. A missing or unreadable file
## leaves the defaults in place and returns false; that is the first launch,
## not an error. Values out of range are clamped; values of the wrong type
## (a hand edit, another program's file) fall back to the defaults, and the
## file still counts as read, so the next save() rewrites it clean.
static func load() -> bool:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return false
	master_volume = clampf(_number(cf.get_value(SECTION, "master_volume", master_volume), DEFAULT_MASTER_VOLUME), 0.0, 1.0)
	fullscreen = _flag(cf.get_value(SECTION, "fullscreen", fullscreen), DEFAULT_FULLSCREEN)
	screen_shake = _flag(cf.get_value(SECTION, "screen_shake", screen_shake), DEFAULT_SCREEN_SHAKE)
	return true


## A float from a file value; anything that is not a finite number is
## `fallback`. float() on a String or an Array would raise, and a string
## such as "loud" would otherwise read as 0.0 and mute the game.
static func _number(value: Variant, fallback: float) -> float:
	var t := typeof(value)
	if t != TYPE_FLOAT and t != TYPE_INT:
		return fallback
	var f := float(value)
	return fallback if is_nan(f) else f


## A bool from a file value; bools and ints count, anything else is `fallback`.
static func _flag(value: Variant, fallback: bool) -> bool:
	var t := typeof(value)
	return bool(value) if t == TYPE_BOOL or t == TYPE_INT else fallback


## Writes the statics to the file at `path`. False, with a warning, when the
## file cannot be written; the settings still hold for this session.
static func save() -> bool:
	var cf := ConfigFile.new()
	cf.set_value(SECTION, "master_volume", master_volume)
	cf.set_value(SECTION, "fullscreen", fullscreen)
	cf.set_value(SECTION, "screen_shake", screen_shake)
	var err := cf.save(path)
	if err != OK:
		push_warning("Settings: cannot write %s (%s)" % [path, error_string(err)])
		return false
	return true


## Pushes the statics into the engine: the Master bus gets the volume (and
## is muted at zero), the window goes fullscreen or back. The window is left
## alone under the headless driver, which has none. Screen shake needs no
## push: the camera rig reads the static every frame.
static func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, MIN_LINEAR)))
	AudioServer.set_bus_mute(0, master_volume <= MUTE_BELOW)
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.window_get_mode()
	var is_fullscreen := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	# Only a real change touches the window, so a maximised window is not
	# shrunk back to its default size every time the settings are applied.
	if is_fullscreen != fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


## Boot: read the file, then apply whatever that left in the statics.
static func load_and_apply() -> void:
	Settings.load()
	apply()


## Back to the defaults, without touching the file or the engine.
static func reset() -> void:
	master_volume = DEFAULT_MASTER_VOLUME
	fullscreen = DEFAULT_FULLSCREEN
	screen_shake = DEFAULT_SCREEN_SHAKE


## "80%" for the volume label.
static func percent(volume: float) -> String:
	return "%d%%" % roundi(clampf(volume, 0.0, 1.0) * 100.0)
