class_name EntityManager
extends Node3D
## Manages spawned traffic, pickups and projectiles.
## Handles spawning, movement, collision detection and entity lifecycle.

## Emitted when traffic collides with the unshielded player.
## main.gd handles the resulting crash.
signal player_crashed(victim: Node3D)

## Emitted when a pickup or other event requests a HUD notification.
signal toast_requested(message: String)

## Emitted when traffic passes close to the player or collides
## while the shield is active.
## The intensity drives the shield ripple effect in main.gd.
signal near_miss(intensity: float)

## Game controller providing access to race state and shared systems.
var host: RaceMain
var layout: TrackLayout
var segment_manager: TrackTopology
var entities: Array[Dictionary] = []
var spawn_cooldown := 1.2

## Forward speed of the SUPER SHOT shockwave relative to the player.
const WAVE_SPEED := 140.0

## Player-versus-traffic collision thresholds, measured between
## object centres. Smaller values allow slight visual overlap
## before a collision registers, making near misses more forgiving.
const CRASH_DX := 1.1
const CRASH_DZ := 2.3

## Available traffic colour schemes.
## Each entry provides the body, roof and accent colours expected
## by TrafficShip.
const TRAFFIC_PALETTE := [
	{ "id": "red", "name": "Red",
	  "body": "ff5c5c", "roof": "9a7ce0", "accent": "ff2d55" },
	{ "id": "blue", "name": "Blue",
	  "body": "8ba3d9", "roof": "b49df0", "accent": "00f5ff" },
	{ "id": "orange", "name": "Orange",
	  "body": "ffab5c", "roof": "7fb5e6", "accent": "ccff00" },
	{ "id": "white", "name": "White",
	  "body": "f1f3f5", "roof": "b2f2bb", "accent": "22d3ee" },
]

## Optional imported pickup models.
## Missing models fall back to procedural geometry.
## Per-model scale, rotation and lift values compensate for
## differences in the imported models and their origins.
const HEART_MODEL_PATH := "res://models/heart.glb"
const HEART_MODEL_SCALE := Vector3.ONE * 1.2
const HEART_MODEL_LIFT := 0.0
const GUN_MODEL_PATH := "res://models/ammo_box.glb"
const GUN_MODEL_SCALE := Vector3.ONE * 1.2
const GUN_MODEL_LIFT := 0.0
const SHIELD_MODEL_PATH := "res://models/shield.glb"
const SHIELD_MODEL_SCALE := Vector3.ONE * 3.3
const SHIELD_MODEL_LIFT := 0.3
const COIN_MODEL_PATH := "res://models/dollar.glb"
const COIN_MODEL_SCALE := Vector3.ONE * 0.7
const COIN_MODEL_LIFT := 0.0
## Rotation correction so the imported bill faces the player.
const COIN_MODEL_ROTATION := Vector3(PI / 2.0, 0.0, 0.0)

## Additional glow settings for imported pickup models.
## Texture brightness and coloured emission are controlled separately:
## brightness preserves the original materials, while glow adds
## a subtle colour accent.
const AMMO_GLOW := Color(0.5, 0.7, 0.8)
const AMMO_GLOW_STRENGTH := 0.05
const SHIELD_GLOW := Color("339af0")
const SHIELD_GLOW_STRENGTH := 0.2
const COIN_GLOW := Color("37b24d")
const COIN_GLOW_STRENGTH := 0.0
## Brightness multiplier applied to imported pickup textures.
## Values above 1.0 brighten the original albedo without replacing
## the imported material's appearance.
const IMPORT_BRIGHTNESS := 1.7
## Silhouette outline applied to imported pickup models.
## Its unlit appearance keeps pickups visible against different
## road and lighting conditions.
const OUTLINE_COLOR := Color(0.85, 0.92, 1.0)
const OUTLINE_THICKNESS := 1.06
## Point-light colour used by the life pickup.
const HEART_GLOW := Color("ff6b6b")

## Local light settings for pickup models.
## Each light uses a dedicated render layer so it illuminates only
## its own pickup, avoiding unwanted light spill onto the road.
## The light position follows the approximate direction of the
## world lighting.
const PICKUP_LIGHT_RANGE := 4.0
const PICKUP_LIGHT_ENERGY := 2.0
## Dedicated render layer shared by pickup meshes and their lights.
const PICKUP_LIGHT_LAYER := 20
## Local position of the pickup light, aligned with the world
## lighting direction.
const PICKUP_LIGHT_OFFSET := Vector3(-0.7, 2.0, 1.2)
var oncoming_lanes: Array = [0, 2]

## Debug mode: replaces random pickup placement with a regular
## column containing every pickup type.
## Controlled by the corresponding option in the main menu.
var debug_items := false
var debug_next_distance := 0.0
const DEBUG_ITEM_SPACING := 20.0
const DEBUG_ITEM_GAP := 3.2
var same_lanes: Array = [0, 1, 2]

# Traffic behaviour at lane closures.
const CLOSURE_LOOKAHEAD := 120.0
const CLOSURE_BRAKE_DURATION := 2.25
const CLOSURE_FADE_DURATION := 1.0
## Maximum road distance over which traffic fades out before
## reaching a lane closure. At higher speeds the fade duration
## shortens to keep the fade distance approximately constant.
const CLOSURE_FADE_DISTANCE := 60.0
const CLOSURE_STOP_MARGIN := 15.0
## Interval between lane-closure lookahead scans for each traffic ship.
## Avoids repeating the relatively expensive scan every frame.
const CLOSURE_SCAN_INTERVAL := 0.2

## Scales the braking lookahead relative to the estimated stopping
## distance. Braking begins early enough for the ship to slow down
## and fade out before reaching the lane closure.
const CLOSURE_BRAKE_LEAD := 0.8

## Traffic ships maintain a minimum distance from the vehicle ahead.
## Within CAR_FOLLOW_GAP, the follower matches the leader's movement.
## Within CAR_MIN_GAP, it also slows down to increase separation.
## Lane-closure braking takes priority over following behaviour.
const CAR_FOLLOW_GAP := 14.0
const CAR_MIN_GAP := 8.0


func set_segment_manager(manager: TrackTopology) -> void:
	segment_manager = manager

func configure(controller: RaceMain, road_layout: TrackLayout) -> void:
	host = controller
	layout = road_layout

## Updates the road layout, repositions existing entities and
## resets traffic spawning for the new lane configuration.
func set_layout(road_layout: TrackLayout) -> void:
	layout = road_layout
	for entity in entities:
		var lane_index := clampi(int(entity.get("lane", 0)), 0, layout.lane_count - 1)
		entity["lane"] = lane_index
		var node := entity.get("node") as Node3D
		if is_instance_valid(node):
			node.position.x = layout.get_lane_center(lane_index)
	reset_spawning()


func clear_entities() -> void:
	for entity in entities:
		# Destruction effects can leave entries whose nodes have already
		# been freed. Check validity before accessing or freeing them.
		var node = entity.get("node")
		if node != null and is_instance_valid(node):
			(node as Node3D).queue_free()

	entities.clear()

## Resets spawn timing and distributes traffic between available lanes.
## One edge lane is reserved for oncoming traffic; remaining lanes
## are used for same-direction traffic.
func reset_spawning() -> void:
	spawn_cooldown = 1.2
	debug_next_distance = 0.0
	var all_lanes := layout.get_all_lane_indices()
	if all_lanes.is_empty():
		oncoming_lanes = []
		same_lanes = []
		return
	var edge_candidates: Array[int] = [all_lanes.front()]
	if all_lanes.size() > 1:
		edge_candidates.append(all_lanes.back())
	var on_lane: int = edge_candidates[randi() % edge_candidates.size()]
	oncoming_lanes = [on_lane]
	same_lanes = all_lanes.filter(func(index: int): return index != on_lane)


func register_bullet(
	bullet: Node3D,
	lane_index: int,
	z_position: float
) -> void:
	entities.append({
		"type": "bullet",
		"lane": lane_index,
		"z": z_position,
		"node": bullet
	})


## Registers a SUPER SHOT shockwave.
## Stores its origin so the update logic can distinguish traffic
## ahead of the wave from traffic it has already passed.
func register_wave(wave: Node3D, z_position: float) -> void:
	entities.append({
		"type": "wave",
		"lane": -1,
		"z": z_position,
		"origin_z": z_position,
		"node": wave
	})


func _lane_blocked(lane_index: int, z0: float) -> bool:
	for entity in entities:
		if (
			entity.type == "car"
			and entity.lane == lane_index
			and absf(entity.z - z0) < 16.0
		):
			return true
	return false


func _lane_stays_open(lane_index: int, spawn_z: float) -> bool:
	if segment_manager == null:
		return true
	var player_distance: float = host.distance_travelled
	var spawn_distance := player_distance - spawn_z

	# Validate both the path to the spawn point and the road ahead.
	# Oncoming traffic travels toward the player, while same-direction
	# traffic moves away, so both portions of the path must be checked.
	var ahead: float = maxf(
		CLOSURE_LOOKAHEAD,
		float(host.world_speed) * 2.5 + 60.0
	)
	return (
		segment_manager.is_lane_open_between(
			lane_index, player_distance, spawn_distance
		)
		and segment_manager.is_lane_open_between(
			lane_index, spawn_distance, spawn_distance + ahead
		)
	)


func _get_lane_center(lane_index: int, relative_z: float) -> float:
	if segment_manager == null:
		return layout.get_lane_center(lane_index)

	var track_distance: float = host.distance_travelled - relative_z
	return segment_manager.get_lane_center_at(lane_index)


func _open_lanes_for_path(spawn_z: float) -> Array[int]:
	var result: Array[int] = []
	for lane_index in layout.get_all_lane_indices():
		if _lane_stays_open(lane_index, spawn_z):
			result.append(lane_index)
	return result


func _get_lane_closure_distance(entity: Dictionary) -> float:
	if segment_manager == null:
		return INF

	var car_speed: float = host.world_speed * (
		(1.0 + float(entity.rel)) if entity.oncoming else (1.0 - float(entity.rel))
	)

	var relative_track_speed: float = host.world_speed - car_speed

	if absf(relative_track_speed) < 0.01:
		return INF

	var current_distance: float = host.distance_travelled - float(entity.z)
	var direction := signf(relative_track_speed)

	# Scale the lookahead with speed so traffic has enough distance
	# to brake and fade out before reaching the closure.
	var lead_distance: float = (
		host.world_speed * CLOSURE_BRAKE_DURATION
		+ CLOSURE_FADE_DISTANCE
	)
	var lookahead := maxf(CLOSURE_LOOKAHEAD, lead_distance)
	var steps := 48
	var step_distance := lookahead / float(steps)

	for i in range(1, steps + 1):
		var test_distance := current_distance + direction * step_distance * float(i)

		if not segment_manager.get_available_lane_indices(test_distance).has(int(entity.lane)):
			return test_distance

	return INF


func _set_visual_transparency(node: Node, amount: float) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).transparency = clampf(amount, 0.0, 1.0)

	for child in node.get_children():
		_set_visual_transparency(child, amount)


## Plays the destruction effect for a traffic ship or other entity.
## Duplicates its materials before applying the emission flash,
## then fades the node out before freeing it.
##
## Callers must ensure the entity is excluded from active tracking
## before the next entity update.
func _vaporise(node: Node3D, glow_energy := 5.0) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var material := (mi as MeshInstance3D).get_active_material(0)
		if material is StandardMaterial3D:
			var hot := (material as StandardMaterial3D).duplicate()
			hot.emission_enabled = true
			hot.emission = Color(1.0, 0.8, 0.45)
			hot.emission_energy_multiplier = glow_energy
			(mi as MeshInstance3D).material_override = hot
	var tween: Tween = host.create_tween()
	# Hold the emission flash while the explosion plays, then
	# fade out the ship before freeing it.
	tween.tween_interval(0.1)
	tween.tween_method(
		_set_visual_transparency.bind(node),
		0.0, 1.0, 0.25
	)
	tween.tween_callback(node.queue_free)


## Run-end explosion hook: main.gd calls this when the LAST life
## is gone so the player ship — and, for a traffic hit, the ship
## that caused the crash — burn out with the game-over screen
## instead of just freezing in place. Same white-hot flash +
## transparency fade + blast shell as any kill; the tweens keep
## animating in the GAMEOVER state because only main's update
## loop stops, never the scene tree.
func explode(node: Node3D) -> void:
	if not is_instance_valid(node):
		return
	# Purge the victim's entity entry NOW: the vaporise tween
	# frees the node in 0.35 s, and a stale entry with a freed
	# node crashed clear_entities()/the shadow walk on the next
	# run ("Trying to cast a freed object").
	for i in range(entities.size() - 1, -1, -1):
		if entities[i].get("node") == node:
			entities.remove_at(i)
	_vaporise(node)
	_boom(node.global_position)

## Advances traffic and pickup spawning.
## Selects an available lane, creates traffic and places pickups
## along valid paths ahead of the player.
func spawn_step(delta: float) -> void:
	spawn_cooldown -= delta
	if spawn_cooldown > 0.0:
		return

	var gap := maxf(0.55, 1.4 - host.distance_travelled * 0.004)
	spawn_cooldown = gap * (0.8 + randf() * 0.6)

	# Increase spawn distance with speed to maintain a consistent
	# reaction time at higher speeds.
	var z0: float = (
		-150.0
		- randf() * 20.0
		- host.world_speed * 0.75
	)
	var is_oncoming := randf() < 0.42
	var lane_pool := oncoming_lanes if is_oncoming else same_lanes
	var open_lanes: Array = []

	for lane_candidate in lane_pool:
		if (
			not _lane_blocked(lane_candidate, z0)
			and _lane_stays_open(int(lane_candidate), z0)
		):
			open_lanes.append(lane_candidate)

	if open_lanes.is_empty():
		return

	var lane_index: int = open_lanes[randi() % open_lanes.size()]
	var nearby_cars := entities.filter(
		func(entity):
			return entity.type == "car" and absf(entity.z) < 25.0
	)

	var occupied_lanes := {}
	for entity in nearby_cars:
		occupied_lanes[entity.lane] = true

	if (
		occupied_lanes.size() >= mini(2, layout.lane_count)
		and not occupied_lanes.has(lane_index)
	):
		return

	# Select a random traffic colour scheme.
	var available_car_skins: Array = TRAFFIC_PALETTE
	var ship := TrafficShip.new(
		available_car_skins[randi() % available_car_skins.size()],
		is_oncoming,
		0.4 + randf() * 0.4
	)
	ship.position = Vector3(_get_lane_center(lane_index, z0), 0.1, z0)
	add_child(ship)

	entities.append({
		"type": "car",
		"lane": lane_index,
		"z": z0,
		"node": ship,
		"oncoming": is_oncoming,
		"rel": ship.rel,
		# Initial z-rate used by the car-following logic.
		# Updated from the ship's actual movement each frame.
		"z_rate": host.world_speed * (
			(1.0 + ship.rel) if is_oncoming else (1.0 - ship.rel)
		)
	})

	if debug_items:
		_spawn_debug_column()
	elif randf() < 0.85:
		var coin_lanes := _open_lanes_for_path(-180.0)
		if not coin_lanes.is_empty():
			var coin_lane: int = coin_lanes[randi() % coin_lanes.size()]
			var coin_count := 3 + randi() % 3
			for coin_index in coin_count:
				_spawn_coin(coin_lane, -165.0 - coin_index * 3.2)

	# Debug mode already places every pickup type, so skip random
	# powerup spawning.
	if not debug_items and randf() < 0.1:
		var power_roll := randf()
		var kind := "life" if power_roll < 0.45 else (
			"shield" if power_roll < 0.8 else "ammo"
		)
		# Place the powerup ahead of the coin run so the coins do not
		# obscure it from the player's view.
		var power_lanes := _open_lanes_for_path(-165.0)
		if not power_lanes.is_empty():
			var power_lane: int = power_lanes[randi() % power_lanes.size()]
			_spawn_power(kind, power_lane, -160.0)


## Spawns a column containing every pickup type at regular distance
## intervals. Uses the first available lane and skips the column
## when no suitable lane is open.
func _spawn_debug_column() -> void:
	if host.distance_travelled < debug_next_distance:
		return
	debug_next_distance = (
		host.distance_travelled + DEBUG_ITEM_SPACING
	)
	var open_lanes := _open_lanes_for_path(-170.0)
	if open_lanes.is_empty():
		return
	var lane_index: int = open_lanes[0]
	var z := -170.0
	for kind in ["life", "shield", "ammo", "coin"]:
		if kind == "coin":
			_spawn_coin(lane_index, z)
		else:
			_spawn_power(kind, lane_index, z)
		z -= DEBUG_ITEM_GAP


## Builds the coin model shared by world pickups and HUD icons.
## Uses the imported model when available, otherwise creates
## procedural coin geometry.
static func build_coin_model() -> Node3D:
	# Prefer the imported model, falling back to procedural geometry
	# when the asset is unavailable.
	var imported := _imported_pickup_model("coin")
	if imported != null:
		var model_root := Node3D.new()
		model_root.add_child(imported)
		return model_root

	var coin_material := PickupMaterials.coin()
	var coin_core_material := PickupMaterials.coin_core()
	var model_root := Node3D.new()

	Primitives.cyl(
		Vector2(0.42, 0.42), 0.1, coin_material,
		Vector3.ZERO, model_root, PI / 2
	)
	Primitives.cyl(
		Vector2(0.28, 0.28), 0.12, coin_core_material,
		Vector3(0, 0.02, 0), model_root, PI / 2
	)
	return model_root

## Spawns a coin pickup in the specified lane and at the given
## relative road position.
func _spawn_coin(lane_index: int, z: float) -> void:
	var pickup_model := build_coin_model()

	pickup_model.position = Vector3(_get_lane_center(lane_index, z), 0.8, z)
	# Position the blob shadow beneath the hovering pickup.
	var coin_blob := Primitives.shadow_blob(pickup_model, Vector2(1.3, 1.3), -0.625)
	# Store the shadow offset in world-aligned coordinates.
	# The pickup rotates, so update_ents counter-rotates this offset
	# to keep the shadow direction fixed.
	coin_blob.set_meta("offset", Vector3(0.22, -0.625, -0.38))
	Primitives.apply_shadow_mode(pickup_model, SaveManager.data.full_shadows)
	add_child(pickup_model)
	# Add the silhouette outline used by world pickups.
	_add_outline(pickup_model)
	_add_pickup_light(pickup_model, COIN_GLOW)
	entities.append({
		"type": "coin",
		"lane": lane_index,
		"z": z,
		"node": pickup_model,
		"blob": coin_blob
	})
	host.pickups_spawned += 1


## Builds a powerup model shared by world pickups and HUD icons.
## Uses the imported model when available, otherwise creates
## procedural geometry for the requested pickup type.
static func build_power_model(kind: String) -> Node3D:
	var model_root := Node3D.new()

	# Prefer the imported model for this pickup type.
	# Fall back to procedural geometry when the asset is unavailable.
	var imported := _imported_pickup_model(kind)
	if imported != null:
		model_root.add_child(imported)
		return model_root

	# Build the procedural fallback using the shared pickup materials.
	match kind:
		"life":
			var heart_material := PickupMaterials.heart()
			# Flat heart silhouette with rounded upper lobes and a tapered tip.
			Primitives.cyl(
				Vector2(0.34, 0.34), 0.55, heart_material,
				Vector3(-0.24, 0.38, 0), model_root, PI / 2
			)
			Primitives.cyl(
				Vector2(0.34, 0.34), 0.55, heart_material,
				Vector3(0.24, 0.38, 0), model_root, PI / 2
			)
			Primitives.box(
				Vector3(0.85, 0.6, 0.55),
				heart_material,
				Vector3(0, 0.12, 0),
				model_root
			)
			Primitives.box(
				Vector3(0.62, 0.62, 0.55),
				heart_material,
				Vector3(0, -0.18, 0),
				model_root,
				0.0,
				PI / 4
			)

		"shield":
			var shield_material := PickupMaterials.shield()
			var emblem_material := PickupMaterials.shield_emblem()
			# Flat shield silhouette with a pointed tip and bright emblem.
			# Main panel.
			Primitives.box(
				Vector3(0.95, 0.75, 0.08),
				shield_material,
				Vector3(0, 0.55, 0),
				model_root
			)
			# Pointed lower tip.
			Primitives.box(
				Vector3(0.68, 0.68, 0.07),
				shield_material,
				Vector3(0, 0.28, 0),
				model_root,
				0.0,
				PI / 4
			)
			# Emblem cross on the front face.
			Primitives.box(
				Vector3(0.18, 0.55, 0.10),
				emblem_material,
				Vector3(0, 0.55, 0.005),
				model_root
			)
			Primitives.box(
				Vector3(0.6, 0.18, 0.10),
				emblem_material,
				Vector3(0, 0.65, 0.005),
				model_root
			)

		"ammo":
			var gun_material := PickupMaterials.gun()
			var gun_dark_material := PickupMaterials.gun_dark()
			# Build a compact pistol silhouette with a slim barrel,
			# tilted grip and dark trigger guard.
			Primitives.box(
				Vector3(0.55, 0.34, 0.5),
				gun_material,
				Vector3(0, 0.22, 0.05),
				model_root
			)
			# Sight ridge on top.
			Primitives.box(
				Vector3(0.12, 0.1, 0.3),
				gun_material,
				Vector3(0, 0.44, -0.05),
				model_root
			)
			# Slim barrel with a slightly wider muzzle ring.
			Primitives.box(
				Vector3(0.16, 0.16, 0.85),
				gun_material,
				Vector3(0, 0.26, -0.55),
				model_root
			)
			Primitives.box(
				Vector3(0.24, 0.24, 0.12),
				gun_material,
				Vector3(0, 0.26, -1.0),
				model_root
			)
			# Tilted grip below the receiver, angled back.
			Primitives.box(
				Vector3(0.28, 0.52, 0.26),
				gun_material,
				Vector3(0, -0.1, 0.28),
				model_root,
				0.0,
				0.0,
				-0.35
			)
			# Dark trigger guard bridging receiver and grip.
			Primitives.box(
				Vector3(0.1, 0.22, 0.3),
				gun_dark_material,
				Vector3(0, -0.02, 0.02),
				model_root
			)

	return model_root


## Loads an imported pickup scene, returning null if the resource
## is missing or is not a PackedScene.
static func _pickup_scene(path: String) -> PackedScene:
	if not ResourceLoader.exists(path):
		push_warning("[EntityManager] missing pickup model: " + path)
		return null
	var scene := load(path)
	if scene is PackedScene:
		return scene
	push_warning("[EntityManager] not a PackedScene: " + path)
	return null


## Loads and configures an imported pickup model.
## Applies the shared neon material to life pickups, while other
## pickup types retain their imported materials with an added glow.
## Returns null when the model is unavailable so the caller can
## use the procedural fallback.
static func _imported_pickup_model(kind: String) -> Node3D:
	var path := ""
	var scale := Vector3.ONE
	var lift := 0.0
	var rotation := Vector3.ZERO
	match kind:
		"life":
			path = HEART_MODEL_PATH
			scale = HEART_MODEL_SCALE
			lift = HEART_MODEL_LIFT
		"ammo":
			path = GUN_MODEL_PATH
			scale = GUN_MODEL_SCALE
			lift = GUN_MODEL_LIFT
		"shield":
			path = SHIELD_MODEL_PATH
			scale = SHIELD_MODEL_SCALE
			lift = SHIELD_MODEL_LIFT
		"coin":
			path = COIN_MODEL_PATH
			scale = COIN_MODEL_SCALE
			lift = COIN_MODEL_LIFT
			# Orient the bill bundle so its face points toward the player.
			rotation = COIN_MODEL_ROTATION
		_:
			return null

	var scene := _pickup_scene(path)
	if scene == null:
		return null
	var model := scene.instantiate()
	model.name = "ImportedPickup"
	model.scale = scale
	model.position.y = lift
	model.rotation = rotation
	match kind:
		"life":
			_apply_pickup_material(model, PickupMaterials.heart())
		"ammo":
			_boost_imported_material(
				model, AMMO_GLOW, AMMO_GLOW_STRENGTH
			)
		"shield":
			# comes with its own material — glow boost only
			_boost_imported_material(
				model, SHIELD_GLOW, SHIELD_GLOW_STRENGTH
			)
		"coin":
			_boost_imported_material(
				model, COIN_GLOW, COIN_GLOW_STRENGTH
			)
		# Outlines are added by the world spawners, not by this shared
		# model builder, so HUD icons remain without an outline.
	return model


## Replaces the material on every mesh in an imported pickup model.
## Used for pickup types that adopt the shared neon material style.
static func _apply_pickup_material(root: Node3D, material: Material) -> void:
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_override = material


## Brightens an imported pickup while preserving its original textures.
##
## Each StandardMaterial3D is duplicated before modification so the
## imported resource remains unchanged. The albedo is brightened,
## metallic response is reduced, and a subtle additive emission
## provides the pickup's colour identity.
##
## ShaderMaterials are left unchanged.
static func _boost_imported_material(
	root: Node3D, color: Color, strength: float
) -> void:
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		var instance := mesh as MeshInstance3D
		for surface_index in instance.get_surface_override_material_count():
			var material := instance.get_active_material(surface_index)
			if material is StandardMaterial3D:
				var boosted := (material as StandardMaterial3D).duplicate()
				boosted.metallic = minf(boosted.metallic, 0.2)
				# Values above 1.0 brighten the original albedo texture.
				boosted.albedo_color = Color(
					IMPORT_BRIGHTNESS,
					IMPORT_BRIGHTNESS,
					IMPORT_BRIGHTNESS
				)
				boosted.emission_enabled = true
				boosted.emission_operator = (
					BaseMaterial3D.EMISSION_OP_ADD
				)
				boosted.emission = color
				boosted.emission_energy_multiplier = strength
				instance.set_surface_override_material(
					surface_index, boosted
				)


## Returns the light colour associated with a pickup type.
func _pickup_light_color(kind: String) -> Color:
	match kind:
		"life":
			return HEART_GLOW
		"ammo":
			return AMMO_GLOW
		"shield":
			return SHIELD_GLOW
	return Color.WHITE


func _add_pickup_light(parent: Node3D, color: Color) -> void:
	var light := OmniLight3D.new()
	light.name = "PickupLight"
	light.light_color = color
	light.omni_range = PICKUP_LIGHT_RANGE
	light.light_energy = PICKUP_LIGHT_ENERGY
	# Pickup lights do not cast shadows; the blob shadow handles this.
	light.shadow_enabled = false
	# Restrict this light to the pickup's dedicated render layer.
	# This prevents it from illuminating the surrounding road.
	var layer_bit := 1 << (PICKUP_LIGHT_LAYER - 1)
	light.light_cull_mask = layer_bit
	light.position = PICKUP_LIGHT_OFFSET
	parent.add_child(light)
	# Add all pickup meshes to the light's render layer.
	for mesh in parent.find_children("*", "MeshInstance3D", true, false):
		(mesh as GeometryInstance3D).layers |= layer_bit


## Adds an inverted-hull outline to every mesh in an imported model.
## Enlarged, front-face-culled copies render only beyond the original
## silhouettes, producing a consistent outline against the environment.
##
## Outline meshes are named "Outline" so Primitives.apply_shadow_mode()
## excludes them from real-time shadow casting.
static func _add_outline(root: Node3D) -> void:
	var material := Primitives.mat(OUTLINE_COLOR, 0.0, 1.0)
	material.shading_mode = (
		BaseMaterial3D.SHADING_MODE_UNSHADED
	)
	material.cull_mode = BaseMaterial3D.CULL_FRONT
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		var instance := mesh as MeshInstance3D
		if instance.mesh == null:
			continue
		var outline := MeshInstance3D.new()
		outline.name = "Outline"
		outline.mesh = instance.mesh
		outline.material_override = material
		outline.scale = Vector3.ONE * OUTLINE_THICKNESS
		outline.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		instance.add_child(outline)

## Spawns a powerup in the specified lane and at the given road position.
## Adds its shadow, outline and local light before registering it
## with the entity manager.
func _spawn_power(kind: String, lane_index: int, z: float) -> void:
	var pickup_model := build_power_model(kind)

	pickup_model.position = Vector3(_get_lane_center(lane_index, z), 0.9, z)
	# Place the blob shadow on the road beneath the hovering pickup.
	var power_blob := Primitives.shadow_blob(pickup_model, Vector2(1.6, 1.6), -0.725)
	# Store the sun-aligned shadow offset for counter-rotation in update_ents().
	power_blob.set_meta("offset", Vector3(0.25, -0.725, -0.44))
	Primitives.apply_shadow_mode(pickup_model, SaveManager.data.full_shadows)
	add_child(pickup_model)
	# Add the outline to world pickups; shared HUD models remain unoutlined.
	_add_outline(pickup_model)
	# Add a local light restricted to the pickup's own meshes.
	_add_pickup_light(pickup_model, _pickup_light_color(kind))
	entities.append({
		"type": kind,
		"lane": lane_index,
		"z": z,
		"node": pickup_model,
		"blob": power_blob
	})
	host.pickups_spawned += 1

## Updates all active traffic, projectiles and pickups.
## Handles movement, collisions, collection, destruction and cleanup.
func update_ents(delta: float) -> void:
	var keep: Array[Dictionary] = []

	for entity in entities:
		match entity.type:
			"car":
				if not is_instance_valid(entity.node):
					continue

				var car_speed: float = host.world_speed * (
					(1.0 + entity.rel) if entity.oncoming else (1.0 - entity.rel)
				)

				var closure_state: String = entity.get("closure_state", "driving")

				if closure_state == "driving":
					# Run the lane-closure scan periodically rather than every frame.
					var scan_timer: float = float(entity.get("closure_scan_timer", 0.0)) - delta
					var closure_distance := INF
					if scan_timer <= 0.0:
						scan_timer = CLOSURE_SCAN_INTERVAL
						closure_distance = _get_lane_closure_distance(entity)

						# If the car is already on a closed lane, begin fading immediately.
						# This catches closures missed by the periodic lookahead scan.
						if segment_manager != null:
							var car_track: float = (
								host.distance_travelled - float(entity.z)
							)
							if not segment_manager.get_available_lane_indices(
								car_track
							).has(int(entity.lane)):
								entity["closure_state"] = "fading"
								entity["closure_timer"] = 0.0
								closure_state = "fading"

					# Persist the timer every frame, including between scans.
					entity["closure_scan_timer"] = scan_timer

					if is_finite(closure_distance) and closure_state == "driving":
						# Begin braking only when the closure is within the stopping
						# distance. Detecting a closure alone must not trigger braking.
						var car_track: float = (
							host.distance_travelled - float(entity.z)
						)
						var relative_speed: float = absf(
							host.world_speed - car_speed
						)
						var remaining: float = absf(
							float(closure_distance) - car_track
						)
						var brake_start_distance: float = (
							relative_speed * CLOSURE_BRAKE_DURATION
							* CLOSURE_BRAKE_LEAD
							+ CLOSURE_STOP_MARGIN
						)

						if remaining <= brake_start_distance:
							entity["closure_state"] = "braking"
							entity["closure_timer"] = 0.0
							closure_state = "braking"

				match closure_state:
					"driving":
						# Follow the nearest car ahead in the same lane.
						# Traffic moves toward +z, so the leader has the larger z value.
						# Match its speed to maintain the gap; reduce speed further when
						# the minimum following distance is breached.
						var z_rate := car_speed
						var leader_gap := INF
						var leader_rate := 0.0

						for other_entity in entities:
							if (
								other_entity.type == "car"
								and other_entity.get("node") != entity.get("node")
								and int(other_entity.lane) == int(entity.lane)
							):
								var gap_z: float = float(other_entity.z) - float(entity.z)
								if gap_z > 0.25 and gap_z < leader_gap:
									leader_gap = gap_z
									leader_rate = float(
										other_entity.get("z_rate", host.world_speed)
									)

						if leader_gap < CAR_FOLLOW_GAP:
							z_rate = minf(z_rate, leader_rate)
							if leader_gap < CAR_MIN_GAP:
								# Too close: drop below the leader's
								# rate to slowly open the gap again.
								z_rate = minf(
									z_rate,
									maxf(0.0, leader_rate - 3.0)
								)

						entity.z += z_rate * delta
						entity["z_rate"] = z_rate

					"braking":
						entity["closure_timer"] += delta

						var progress := clampf(
							float(entity.closure_timer) / CLOSURE_BRAKE_DURATION,
							0.0,
							1.0
						)

						var smooth_progress := progress * progress * (3.0 - 2.0 * progress)

						var speed_factor := 1.0 - smooth_progress

						# Blend from the car's normal speed to the world scroll speed.
						# This makes the car stop relative to the road rather than the
						# player, allowing the player to drive past it.
						var brake_rate: float = (
							car_speed * speed_factor
							+ host.world_speed * (1.0 - speed_factor)
						)
						entity.z += brake_rate * delta
						entity["z_rate"] = brake_rate

						if progress >= 1.0:
							entity["closure_state"] = "fading"
							entity["closure_timer"] = 0.0
							closure_state = "fading"

					"fading":
						entity["closure_timer"] += delta

						# The car is stationary relative to the road, so it advances
						# at the world scroll speed while the player drives past.
						entity.z += host.world_speed * delta
						entity["z_rate"] = host.world_speed

						# Scale the fade duration with speed to keep the fade distance
						# approximately constant.
						var fade_duration := clampf(
							CLOSURE_FADE_DISTANCE
							/ maxf(host.world_speed, 1.0),
							0.1,
							CLOSURE_FADE_DURATION
						)
						var fade_progress := clampf(
							float(entity.closure_timer) / fade_duration,
							0.0,
							1.0
						)

						_set_visual_transparency(entity.node, fade_progress)

						if fade_progress >= 1.0:
							entity.node.queue_free()
							continue

				entity.node.position.z = entity.z

				# Detect the car's first pass across the player's longitudinal
				# position and measure the lateral clearance only once.
				if (
					not entity.get("passed", false)
					and entity.z > host.player.position.z
				):
					entity["passed"] = true
					var pass_dx := absf(
						_get_lane_center(int(entity.lane), float(entity.z))
						- host.player.position.x
					)
					if pass_dx < 2.6:
						near_miss.emit(1.0 - pass_dx / 2.6)

				# Only active traffic can collide with the player.
				if closure_state == "driving" or closure_state == "braking":
					var dx := absf(
						_get_lane_center(int(entity.lane), float(entity.z))
						- host.player.position.x
					)

					if (
						not entity.get("hitdone", false)
						and dx < CRASH_DX
						# Expand the collision window by the distance travelled this frame
						# so fast traffic cannot pass through the player between updates.
						and absf(entity.z - host.player.position.z)
						< CRASH_DZ + absf(car_speed) * delta
					):
						entity.hitdone = true

						if Time.get_ticks_msec() < host.shield_until:
							host.shake = 1.0
							# Ramming through traffic SURGES the dome.
							near_miss.emit(1.0)
							# A shielded collision surges the dome effect.
							AudioManager.play("crash")
							# The shield protects the player, but the colliding traffic ship
							# is still destroyed.
							_vaporise(entity.node)
							continue
						else:
							# Pass the colliding node to main.gd so it can also be destroyed
							# if this crash ends the run.
							player_crashed.emit(entity.node)
							return

				if entity.z > 25.0:
					entity.node.queue_free()
					continue

				keep.append(entity)

			"wave":
				# The SUPER SHOT wave expands forward from the player's position.
				# It destroys traffic between its advancing front and its origin,
				# but never affects cars behind the player.
				entity.z -= WAVE_SPEED * delta
				var origin_z: float = float(entity.get("origin_z", 0.0))
				var travelled: float = origin_z - entity.z
				entity.node.position.z = entity.z
				# Expand the shockwave as it travels, increasing its lateral reach.
				var grow := 1.0 + travelled * 0.12
				entity.node.scale = Vector3(3.0 * grow, 1.4 * grow, grow)

				# Collect traffic swept up by the wave before removing it from
				# the active entity list.
				var wiped: Array = []
				for other_entity in keep:
					if (
						other_entity.type == "car"
						and other_entity.z <= origin_z
						and other_entity.z >= entity.z
					):
						wiped.append(other_entity)

				# Award the same cash and destruction credit as a bullet kill.
				for victim in wiped:
					_vaporise(victim.node)
					keep.erase(victim)
					host.run_cash += 25
					host.cars_destroyed += 1
					SaveManager.data.cash += 25
					AudioManager.play("explode")
					_boom(Vector3(
						_get_lane_center(int(victim.lane), float(victim.z)),
						0.5,
						float(victim.z)
					))

				if entity.z < -220.0:
					entity.node.queue_free()
					continue

				keep.append(entity)

			"bullet":
				# Move forward relative to the player at the projectile's muzzle speed.
				entity.z -= 95.0 * delta
				entity.node.position.z = entity.z
				var hit_entity = null

				for other_entity in keep:
					if (
						other_entity.type == "car"
						and other_entity.lane == entity.lane
						# Expand the hit window by the distance travelled this frame
						# so fast bullets cannot pass through traffic between updates..
						and absf(other_entity.z - entity.z)
						< 2.4 + host.world_speed * delta
					):
						hit_entity = other_entity
						break

				if hit_entity:
					_vaporise(hit_entity.node)
					keep.erase(hit_entity)
					entity.node.queue_free()
					host.run_cash += 25
					host.cars_destroyed += 1
					SaveManager.data.cash += 25
					AudioManager.play("explode")
					_boom(Vector3(
						_get_lane_center(int(entity.lane), float(entity.z)),
						0.5,
						entity.z
					))
					continue

				if entity.z < -220.0:
					entity.node.queue_free()
					continue

				keep.append(entity)

			"coin", "ammo", "life", "shield":
				if not is_instance_valid(entity.node):
					continue

				# Pickups are stationary relative to the road, so they advance
				# at the full world scroll speed relative to the player.
				entity.z += host.world_speed * delta
				entity.node.position.z = entity.z

				entity.node.rotate_y(delta * 3.0)

				# Counter-rotate the shadow offset so its direction remains
				# fixed in world space while the pickup spins.
				var blob := entity.get("blob") as MeshInstance3D
				if blob != null:
					blob.position = (
						(blob.get_meta("offset") as Vector3)
						.rotated(Vector3.UP, -entity.node.rotation.y)
					)

				var dx := absf(
					_get_lane_center(int(entity.lane), float(entity.z))
					- host.player.position.x
				)

				# Expand the collection window by the distance travelled this frame
				# so fast pickups cannot pass the player between updates.
				if (
					dx < 1.2
					and absf(entity.z - host.player.position.z)
					< 1.8 + host.world_speed * delta
				):
					host.pickups_collected += 1
					match entity.type:
						"coin":
							host.run_cash += 10
							SaveManager.data.cash += 10
							AudioManager.play("coin")

						"ammo":
							host.ammo = mini(60, host.ammo + 15)
							AudioManager.play("power")
							toast_requested.emit(
								"🔫 Mini-gun loaded — press SPACE to fire!"
							)

						"life":
							host.lives = mini(
								RaceSession.MAX_LIVES,
								host.lives + 1
							)
							AudioManager.play("power")
							toast_requested.emit("❤ +1 life")

						"shield":
							# Apply the current Quantum Recycler upgrade level when the shield is collected.
							# This allows upgrades purchased during a run to affect later pickups.
							var shield_sec: float = (
								RaceSession.SHIELD_DURATION_SEC
								+ float(
									SaveManager.get_upgrade_level("recycler")
								) * RaceSession.UPGRADE_SHIELD_SEC_PER_TIER
							)
							host.shield_until = (
								Time.get_ticks_msec()
								+ int(shield_sec * 1000.0)
							)
							AudioManager.play("power")
							toast_requested.emit(
								"⛨ Shield %ds" % int(shield_sec)
							)

					entity.node.queue_free()
					continue

				if entity.z > 20.0:
					entity.node.queue_free()
					continue

				keep.append(entity)

	entities = keep


## Creates an expanding energy-shell explosion at the given position.
## The shell expands while its glow fades, then frees itself.
func _boom(pos: Vector3) -> void:
	var boom_shell := Primitives.energy_shell(
		self,
		Vector3.ONE * 0.5,
		Color(1.0, 0.57, 0.17, 0.4),
		0.06
	)
	boom_shell.position = pos
	var mat := boom_shell.material_override as ShaderMaterial
	mat.set_shader_parameter("intensity", 2.5)
	var tween: Tween = host.create_tween()
	tween.tween_property(boom_shell, "scale", Vector3(1.5, 1.5, 1.5), 0.35)
	# Fade the glow in parallel with the expansion.
	tween.parallel().tween_property(
		mat, "shader_parameter/intensity", 0.0, 0.35
	).set_ease(Tween.EASE_IN)
	tween.tween_callback(boom_shell.queue_free)
