
extends Node
## Autoload that manages persistent game data, customization catalogs
## and purchases.

const SAVE_PATH := "user://dash-racer-save.json"

## Fixed Standard paint used by all ship models.
## The dictionary retains the skin-shaped structure expected by
## TrafficShip and other ship-building code.
const DEFAULT_SHIP_SKIN := {
	"id": "original", "name": "Standard",
	"body": "ffffff", "roof": "ffffff", "accent": "00f5ff"
}
## Default colours for the three independently customizable ship effects.
const EFFECT_COLORS := {
	"effect_flame": "4080ff",
	"effect_shot": "7326ff",
	"effect_overdrive": "a855f7"
}
## Available player ship hulls.
## Each entry defines the model identifier, display name, price and description.
## Hull geometry comes from the equipped model; paint and effect colours
## are managed separately.
const SHIP_MODELS := [
	{
		"id": "slim",
		"name": "Slimline",
		"price": 0,
		"desc": "The lean beginner racer — external model with its own materials"
	},
	{
		"id": "dispatcher",
		"name": "Dispatcher",
		"price": 65000,
		"desc": "Imported Dispatcher cruiser — external model with its own materials"
	},
	{
		"id": "striker",
		"name": "Striker",
		"price": 80000,
		"desc": "The ultimate interceptor — external model with its own materials"
	},
	{
		"id": "argon",
		"name": "Argon",
		"price": 160000,
		"desc": "Argon X7 — external model with its own materials"
	},
]
## Available track themes and their world colour palettes.
## Each entry defines its purchase price and the colours used by
## WorldTheme, Scenery and RoadMesh.
const TRACK_SKINS := [
	{
		"id": "day",
		"name": "Neon Day",
		"price": 0,
		"road": "3b3f46",
		"line": "00f5ff",
		"grass2": "ccff00",
		"sky": "87ceeb",
		"fog": "a8d8ea",
		"ground": "17202d",
		"accent": "6bffda"
	},
	{
		"id": "sunset",
		"name": "Neon Sunset",
		"price": 4000,
		"road": "2b2b34",
		"line": "ff7edb",
		"grass2": "332344",
		"sky": "ff7e5f",
		"fog": "ff9a76",
		"ground": "211923",
		"accent": "ffb347"
	},
	{
		"id": "night",
		"name": "Midnight City",
		"price": 9000,
		"road": "505060",
		"line": "4dd4ff",
		"grass2": "0a0a10",
		"sky": "0a0a14",
		"fog": "14142a",
		"ground": "080b14",
		"accent": "b66dff"
	},
	{
		"id": "candy",
		"name": "Candy Land",
		"price": 15000,
		"road": "ffb3c6",
		"line": "ffffff",
		"grass2": "8fd694",
		"sky": "ffd6ec",
		"fog": "ffc2e0",
		"ground": "33283c",
		"accent": "ff6eb4"
	},
	{
		"id": "toxic",
		"name": "Toxic Wasteland",
		"price": 24000,
		"road": "2b321e",
		"line": "d0ff4d",
		"grass2": "1e3b1e",
		"sky": "55a630",
		"fog": "95d5b2",
		"ground": "0f2417",
		"accent": "ffd43b"
	},
	{
		"id": "arctic",
		"name": "Arctic Circuit",
		"price": 35000,
		"road": "86929c",
		"line": "e7f5ff",
		"grass2": "cde8f5",
		"sky": "a5d8ff",
		"fog": "c9e5f7",
		"ground": "182b33",
		"accent": "22d3ee"
	},
	{
		"id": "inferno",
		"name": "Inferno Highway",
		"price": 50000,
		"road": "26120e",
		"line": "ff922b",
		"grass2": "2b1206",
		"sky": "842029",
		"fog": "e8590c",
		"ground": "1a0c08",
		"accent": "ffd43b"
	},
	{
		"id": "void",
		"name": "Void Sector",
		"price": 75000,
		"road": "0b0b12",
		"line": "b197fc",
		"grass2": "05050a",
		"sky": "05050d",
		"fog": "140a2e",
		"ground": "020208",
		"accent": "e599f7"
	},
]

## Purchasable gameplay upgrades, each with up to three tiers.
## The tiers array stores the price of each successive purchase.
## Upgrade effects are applied by RaceSession and EntityManager
## according to the owned level.
const UPGRADES := [
	{
		"id": "hull",
		"name": "Self-Healing Hull",
		"tiers": [4000, 12000, 30000],
		"desc": "+1 life per tier at the start of every run"
	},
	{
		"id": "ammo_depot",
		"name": "Ammo Depot",
		"tiers": [2000, 7000, 18000],
		"desc": "+5 ammo per tier at the start of every run"
	},
	{
		"id": "recycler",
		"name": "Quantum Recycler",
		"tiers": [5000, 16000, 40000],
		"desc": "+2 s shield duration per tier"
	},
]

## Returns the factory-default save state.
## Used both for initial data and for resetting all progress.
static func default_data() -> Dictionary:
	return {
		"cash": 0, "best": 0, "muted": false,
		"player_name": "PLAYER", "highscores": [],
		"track_skin": "day",
		"owned_tracks": ["day"],
		"effect_flame": "4080ff",
		"effect_shot": "7326ff",
		"effect_overdrive": "a855f7",
		"ship_model": "slim", "owned_models": ["slim"],
		"upgrade_levels": {},
		"fullscreen": false,
		"full_shadows": false,
		"engine_hum": true,
		"debug_items": false,
		"music_volume": 100,
		"sfx_volume": 100,
		"resolution": "1280x720"
	}

var data := default_data()

## Resets all persistent data to its factory defaults.
func reset_all() -> void:
	data = default_data()
	persist()

## Maximum number of high score entries kept.
const HIGHSCORE_LENGTH := 10

func _ready() -> void:
	_load()

func car_skin() -> Dictionary:
	return DEFAULT_SHIP_SKIN.duplicate()

## Returns the selected effect colour.
## Invalid or unknown values fall back to the configured default.
func effect_color(key: String) -> Color:
	var hex := str(data.get(key, ""))
	if Color.html_is_valid(hex):
		return Color.html(hex)
	return Color.html(str(EFFECT_COLORS.get(key, "ffffff")))

## Updates a customizable effect colour and immediately saves the change.
func set_effect_color(key: String, color: Color) -> void:
	if not EFFECT_COLORS.has(key):
		return
	data[key] = color.to_html(false)
	persist()

## Returns the equipped track theme, falling back to the default theme
## if the saved identifier is unknown.
func track_skin() -> Dictionary:
	for skin in TRACK_SKINS:
		if skin.id == data.track_skin: return skin
	return TRACK_SKINS[0]

## Writes the current save data to the user save file.
func persist() -> void:
	var save_file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if save_file: save_file.store_string(JSON.stringify(data))

## Adds a completed run to the high score list.
## Returns its 1-based placement, or 0 if it falls outside the
## maximum number of retained entries.
## A unique timestamp token identifies the entry even when scores
## are identical.
func add_score(entry: Dictionary) -> int:
	var scores: Array = data.highscores
	var token := Time.get_ticks_msec()
	entry["ts"] = token
	entry["date"] = Time.get_date_string_from_system()
	scores.append(entry)
	scores.sort_custom(
		func(a, b): return int(a.score) > int(b.score)
	)

	var placement := 0
	for i in range(scores.size()):
		if int(scores[i].get("ts", -1)) == token:
			placement = i + 1
			break

	while scores.size() > HIGHSCORE_LENGTH:
		scores.remove_at(scores.size() - 1)

	if placement > HIGHSCORE_LENGTH:
		return 0

	persist()
	return placement


## Checks whether a score would qualify for the high score list
## without modifying the saved entries.
func would_make_list(score: int) -> bool:
	var scores: Array = data.highscores
	if scores.size() < HIGHSCORE_LENGTH:
		return true
	return score > int(scores[scores.size() - 1].score)

## Loads the saved data and validates it against the current catalogs.
## Invalid references and unsupported values are replaced with safe defaults.
## Also migrates fields from older save formats.
func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH): return
	var save_file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not save_file: return
	var parsed = JSON.parse_string(save_file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY: return
	# JSON.parse_string() returns numbers as floats, so integer fields
	# must be converted explicitly before assigning them to save data.
	const INT_FIELDS := ["cash", "best", "music_volume", "sfx_volume"]
	for field in data.keys():
		if not parsed.has(field):
			continue
		if INT_FIELDS.has(field):
			data[field] = int(parsed[field])
		elif typeof(parsed[field]) == typeof(data[field]):
			data[field] = parsed[field]
	
	# Discard unknown track identifiers and always retain the free default.
	data.owned_tracks = data.owned_tracks.filter(func(id): return TRACK_SKINS.any(func(skin): return skin.id == id))
	if not data.owned_tracks.has("day"): data.owned_tracks.append("day")

	# Discard unknown model identifiers and always retain the free default.
	# Fall back to Slimline if the equipped model is no longer available.
	data.owned_models = data.owned_models.filter(func(id): return SHIP_MODELS.any(func(model): return model.id == id))
	if not data.owned_models.has("slim"): data.owned_models.append("slim")
	if SHIP_MODELS.all(func(model): return model.id != data.ship_model):
		# Legacy saves with a removed procedural hull id fall
		# back to the Slimline beginner ship (catalog index 0).
		data.ship_model = "slim"

	# Keep only known upgrades and clamp saved levels to their valid ranges.
	var clean_levels := {}
	for upgrade_id in data.upgrade_levels.keys():
		for upgrade in UPGRADES:
			if upgrade.id == upgrade_id:
				clean_levels[upgrade_id] = clampi(
					int(data.upgrade_levels[upgrade_id]), 0, upgrade.tiers.size()
				)
				break
	data.upgrade_levels = clean_levels

	# Migrate the previous single-purchase upgrade format to tier 1.
	if parsed.has("owned_upgrades"):
		for upgrade_id in parsed.owned_upgrades:
			for upgrade in UPGRADES:
				if upgrade.id == upgrade_id and not data.upgrade_levels.has(upgrade_id):
					data.upgrade_levels[upgrade_id] = 1

## Purchases and equips a track theme.
## Returns false if the theme is unknown, already owned or unaffordable.
func buy_track(id: String) -> bool:
	var skin: Dictionary = {}
	for track in TRACK_SKINS:
		if track.id == id: skin = track
	if skin.is_empty() or data.owned_tracks.has(id): return false
	if data.cash < skin.price: return false
	data.cash -= skin.price
	data.owned_tracks.append(id)
	data.track_skin = id
	persist()
	return true


## Returns the equipped ship model's catalog entry.
## Falls back to the default model if the saved identifier is unknown.
func ship_model() -> Dictionary:
	for model in SHIP_MODELS:
		if model.id == data.ship_model: return model
	return SHIP_MODELS[0]


## Builds the ship configuration passed to PlayerShip.
## The equipped model determines the hull geometry; paint and effect
## colours are managed separately.
func player_ship_skin() -> Dictionary:
	return {"model": str(data.ship_model)}


## Purchases and equips a ship model immediately.
## Returns false if the model is unknown, already owned or unaffordable.
func buy_model(id: String) -> bool:
	var model: Dictionary = {}
	for candidate in SHIP_MODELS:
		if candidate.id == id: model = candidate
	if model.is_empty() or data.owned_models.has(id): return false
	if data.cash < int(model.price): return false
	data.cash -= int(model.price)
	data.owned_models.append(id)
	data.ship_model = id
	persist()
	return true

## Owned tier level of a gameplay upgrade (0 = not bought yet).
func get_upgrade_level(id: String) -> int:
	return int(data.upgrade_levels.get(id, 0))


## Maximum tier level of a gameplay upgrade (tiers array size).
func get_upgrade_max_level(id: String) -> int:
	for upgrade in UPGRADES:
		if upgrade.id == id:
			return upgrade.tiers.size()
	return 0


## Purchases the next tier of an upgrade if it is available and affordable.
## Returns false for unknown, maxed-out or unaffordable upgrades.
func buy_upgrade(id: String) -> bool:
	var item: Dictionary = {}
	for upgrade in UPGRADES:
		if upgrade.id == id: item = upgrade
	if item.is_empty():
		return false
	var level := get_upgrade_level(id)
	if level >= item.tiers.size():
		return false
	var price: int = item.tiers[level]
	if data.cash < price:
		return false
	data.cash -= price
	data.upgrade_levels[id] = level + 1
	persist()
	return true
