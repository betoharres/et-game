extends Node

signal appearance_changed(profile : Dictionary)

const SAVE_PATH : String = "user://character_appearance.cfg"
const SAVE_SECTION : String = "appearance"
const PROFILE_VERSION : int = 1
const FEATURE_KEYS : PackedStringArray = [
	"head_size",
	"belly_size",
	"leg_length",
	"arm_length",
	"shoulder_width",
	"overall_height",
	"eye_size",
]
const DEFAULT_PROFILE : Dictionary = {
	"head_size": 0.5,
	"belly_size": 0.5,
	"leg_length": 0.5,
	"arm_length": 0.5,
	"shoulder_width": 0.5,
	"overall_height": 0.5,
	"eye_size": 0.5,
}

var _profile : Dictionary = DEFAULT_PROFILE.duplicate(true)


func _ready() -> void:
	load_profile()


func get_profile() -> Dictionary:
	return _profile.duplicate(true)


func set_profile(profile : Dictionary, persist : bool = true) -> void:
	_profile = sanitize_profile(profile)
	appearance_changed.emit(get_profile())
	if persist:
		save_profile()


func reset_profile(persist : bool = true) -> void:
	set_profile(DEFAULT_PROFILE, persist)


func sanitize_profile(profile : Dictionary) -> Dictionary:
	var sanitized : Dictionary = {}
	for key : String in FEATURE_KEYS:
		var raw_value : Variant = profile.get(key, DEFAULT_PROFILE[key])
		var value : float = float(raw_value) if raw_value is float or raw_value is int else 0.5
		sanitized[key] = clampf(value, 0.0, 1.0)
	return sanitized


func save_profile() -> void:
	var config : ConfigFile = ConfigFile.new()
	config.set_value(SAVE_SECTION, "version", PROFILE_VERSION)
	for key : String in FEATURE_KEYS:
		config.set_value(SAVE_SECTION, key, _profile[key])
	var error : Error = config.save(SAVE_PATH)
	if error != OK:
		push_warning("Could not save the character appearance profile: %s" % error_string(error))


func load_profile() -> void:
	var config : ConfigFile = ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		_profile = DEFAULT_PROFILE.duplicate(true)
		return

	var loaded : Dictionary = {}
	for key : String in FEATURE_KEYS:
		loaded[key] = config.get_value(SAVE_SECTION, key, DEFAULT_PROFILE[key])
	_profile = sanitize_profile(loaded)


## Stable, JSON-safe packet that can be sent by a future multiplayer layer.
## No peer IDs or transport assumptions live in the appearance system.
func make_replication_payload(profile : Dictionary = {}) -> Dictionary:
	var source : Dictionary = _profile if profile.is_empty() else profile
	return {
		"version": PROFILE_VERSION,
		"features": sanitize_profile(source),
	}


func profile_from_replication_payload(payload : Dictionary) -> Dictionary:
	var features : Variant = payload.get("features", payload)
	if features is Dictionary:
		return sanitize_profile(features as Dictionary)
	return DEFAULT_PROFILE.duplicate(true)
