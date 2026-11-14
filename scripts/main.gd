class_name RaceMain
extends Node3D
## Coordinates the race world and delegates state, entities and UI to components.


# PLAYER POSITION -------------------------------------------------------------
## Player position along the road. Other world objects use this as their
## reference point.
const PLAYER_Z := -1.0

## Default hover height, adjusted individually for some ship models.
const PLAYER_HOVER_Y := 0.45


# SUPER SHOT ------------------------------------------------------------------
## Hold duration required to charge a super shot.
const SUPER_HOLD_SEC := 3.0

## Ammo consumed when releasing a charged super shot.
const SUPER_AMMO_COST := 9

## Delay before showing the charge indicator after SPACE is pressed.
const SUPER_BAR_DELAY := 0.15


# LANE SELECTION --------------------------------------------------------------
## Distance ahead of the player used when checking lane availability.
const LANE_SELECT_LOOKAHEAD := 18.0


# EDGE BONUS ------------------------------------------------------------------
## Bonus awarded for performing a risky lane change.
const EDGE_BONUS := 15

## Minimum speed required to qualify for the edge bonus.
const EDGE_SPEED := 22.0

## Maximum distance to a closing lane's end for a risky lane change.
const EDGE_LANE_END := 18.0

## Maximum distance to nearby traffic for a risky lane change.
const EDGE_TRAFFIC_Z := 7.0

## Minimum time between consecutive edge bonuses.
const EDGE_COOLDOWN := 1.5

## Time without a crash required to confirm a pending bonus.
const EDGE_CONFIRM_SEC := 1.0

## Remaining cooldown before another edge bonus can be earned.
var edge_cooldown := 0.0

## Remaining confirmation time for a pending edge bonus.
var edge_pending := 0.0


# RACE CONFIGURATION ----------------------------------------------------------
@export var road_config: TrackConfig = TrackConfig.new()

var road_layout: TrackLayout
var segment_manager: TrackTopology


# COMPONENTS ------------------------------------------------------------------
var session := RaceSession.new()
var entity_manager: EntityManager
var race_hud: RaceHUD
var garage_ui: GarageUI
var menu_ui: MenuUI
var display_manager: DisplayManager


# DEBUG -----------------------------------------------------------------------
var _debug_performance_timer := 0.0


# INPUT STATE -----------------------------------------------------------------
## Tracks the current SPACE hold duration for super shots.
var space_held := false
var space_hold_time := 0.0

func _debug_performance_monitor(delta: float) -> void:
	_debug_performance_timer += delta

	if _debug_performance_timer < 10.0:
		return

	_debug_performance_timer = 0.0

	print(
		"[PERFORMANCE] Nodes: ",
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		" | Orphan nodes: ",
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		" | Objects: ",
		Performance.get_monitor(Performance.OBJECT_COUNT),
		" | FPS: ",
		Engine.get_frames_per_second()
	)

var state: int:
	get:
		return session.mode
	set(value):
		session.mode = value

var distance_travelled: float:
	get:
		return session.distance_travelled
	set(value):
		session.distance_travelled = value

var world_speed: float:
	get:
		return session.world_speed
	set(value):
		session.world_speed = value

var speed_kmh: int:
	get:
		return session.speed_kmh
	set(value):
		session.speed_kmh = value

var throttle: float:
	get:
		return session.throttle
	set(value):
		session.throttle = value

var overdrive_speed: float:
	get:
		return session.overdrive_speed
	set(value):
		session.overdrive_speed = value

var lane: int:
	get:
		return session.lane
	set(value):
		session.lane = value

var lives: int:
	get:
		return session.lives
	set(value):
		session.lives = value

var run_cash: int:
	get:
		return session.run_cash
	set(value):
		session.run_cash = value

var ammo: int:
	get:
		return session.ammo
	set(value):
		session.ammo = value

var next_milestone: float:
	get:
		return session.next_milestone
	set(value):
		session.next_milestone = value

var speed_level: int:
	get:
		return session.speed_level
	set(value):
		session.speed_level = value

var fire_cooldown: float:
	get:
		return session.fire_cooldown
	set(value):
		session.fire_cooldown = value

var shake: float:
	get:
		return session.shake
	set(value):
		session.shake = value

var shield_until: int:
	get:
		return session.shield_until_msec
	set(value):
		session.shield_until_msec = value

var max_speed_kmh: int:
	get:
		return session.max_speed_kmh
	set(value):
		session.max_speed_kmh = value

var pickups_spawned: int:
	get:
		return session.pickups_spawned
	set(value):
		session.pickups_spawned = value

var pickups_collected: int:
	get:
		return session.pickups_collected
	set(value):
		session.pickups_collected = value

var cars_destroyed: int:
	get:
		return session.cars_destroyed
	set(value):
		session.cars_destroyed = value

var continues_used: int:
	get:
		return session.continues_used
	set(value):
		session.continues_used = value

var run_score_recorded := false
var last_run_placement := 0
var world_visuals: Node3D
var road: RoadMesh
var scenery: Scenery
var player: PlayerShip
var camera: Camera3D
var camera_pivot: Node3D

var shield_dome: MeshInstance3D

## Shield-dome ripple strength (0..1), fed by crashes, shielded
## rams and near-miss flybys; decays in _process and drives the
## dome shader's pulsing surge via Primitives.set_shell_ripple.
var shield_ripple := 0.0

## Initializes the race world, gameplay components, UI and audio.
func _ready() -> void:
	if road_config == null:
		road_config = TrackConfig.new()
	road_config.validate_config()
	road_layout = TrackLayout.new(road_config)
	segment_manager = TrackTopology.new()
	segment_manager.configure(road_layout)
	entity_manager = EntityManager.new()
	entity_manager.configure(self, road_layout)
	entity_manager.set_segment_manager(segment_manager)
	entity_manager.debug_items = SaveManager.data.debug_items
	add_child(entity_manager)

	# Forward entity events to the appropriate handlers.
	entity_manager.player_crashed.connect(_crash)
	entity_manager.toast_requested.connect(_toast)
	entity_manager.near_miss.connect(_on_near_miss)

	# Forward session notifications to the HUD.
	session.cash_toast.connect(_toast)

	_build_world()
	_build_ui()
	_spawn_player()
	_refresh_menu()
	_apply_shadow_mode()

	# Apply saved audio settings and start the menu music.
	AudioManager.set_muted(SaveManager.data.muted)
	AudioManager.set_engine_enabled(SaveManager.data.engine_hum)
	AudioManager.play_menu_theme()

	# DisplayManager owns the window (fullscreen, resolution); its _ready
	# applies the persisted window state, replacing the old direct call.
	display_manager = DisplayManager.new()
	add_child(display_manager)


## Creates the visual elements of the race world.
func _build_world() -> void:
	# Get the currently equipped track.
	var track: Dictionary = SaveManager.track_skin()

	# Remove the previous world before creating a replacement.
	# This avoids temporarily having two WorldEnvironment nodes
	# in the active 3D world.
	if is_instance_valid(world_visuals):
		remove_child(world_visuals)
		world_visuals.free()

	# ---------------------------------------------------------
	# World root.
	# ---------------------------------------------------------
	world_visuals = Node3D.new()
	world_visuals.name = "WorldVisuals"
	add_child(world_visuals)

	# ---------------------------------------------------------
	# Road.
	# ---------------------------------------------------------
	road = RoadMesh.new()
	road.configure(road_layout, segment_manager)
	road.name = "RaceRoad"
	road.position.z = 0.0
	world_visuals.add_child(road)

	# ---------------------------------------------------------
	# Scenery.
	# ---------------------------------------------------------
	scenery = Scenery.new()
	scenery.name = "RaceScenery"
	world_visuals.add_child(scenery)
	scenery.build(track, road_layout)

	# ---------------------------------------------------------
	# Shared World environment.
	# ---------------------------------------------------------
	WorldTheme.build(world_visuals, track)

	# ---------------------------------------------------------
	# Shield dome.
	#
	# Keep it separate from WorldVisuals, as in the existing
	# project, so rebuilding the world doesn't delete it.
	# ---------------------------------------------------------
	if is_instance_valid(shield_dome):
		shield_dome.queue_free()
		shield_dome = null

	# The shield dome is an ENERGY SHELL (Primitives.energy_shell):
	# a blueish additive fresnel bubble — nearly invisible
	# head-on, glowing at the silhouette, with a breathing
	# wobble — pulsed through its intensity uniform while active
	# (see the shield block in _process).
	shield_dome = Primitives.energy_shell(
		self,
		Vector3(1.7, 1.05, 2.7),
		Color(0.2, 0.8, 1.0, 0.5),
		0.05
	)
	shield_dome.position = Vector3(0.0, PLAYER_HOVER_Y, PLAYER_Z - 0.25)

	shield_dome.visible = false


## Applies a new road configuration and updates dependent components.
## Rebuilds are immediate; animated transitions are not handled here.
func apply_road_config(new_config: TrackConfig) -> void:
	if new_config == null:
		return
	new_config.validate_config()
	road_config = new_config
	road_layout = TrackLayout.new(road_config)
	segment_manager.configure(road_layout)
	if is_instance_valid(road):
		road.set_road_configuration(road_layout, segment_manager)
	if is_instance_valid(scenery):
		scenery.build(SaveManager.track_skin(), road_layout)
	if is_instance_valid(entity_manager):
		entity_manager.set_layout(road_layout)
		entity_manager.set_segment_manager(segment_manager)
	lane = clampi(lane, 0, road_layout.lane_count - 1)
	if is_instance_valid(player):
		player.target_x = road_layout.get_lane_center(lane)
	if is_instance_valid(camera_pivot):
		camera_pivot.position.x = road_layout.road_center
	if is_instance_valid(camera):
		camera.look_at(Vector3(road_layout.road_center, 0, -30), Vector3.UP)
	if is_instance_valid(garage_ui):
		garage_ui.configure_road_layout(road_layout)
		garage_ui.refresh()


func _build_ui() -> void:
	race_hud = RaceHUD.new()
	add_child(race_hud)

	menu_ui = MenuUI.new()
	add_child(menu_ui)

	menu_ui.start_requested.connect(_on_start_button_pressed)
	menu_ui.resume_requested.connect(_resume_run)
	menu_ui.garage_requested.connect(_toggle_garage)
	menu_ui.menu_requested.connect(_show_run_summary)
	menu_ui.fullscreen_requested.connect(_toggle_fullscreen)
	menu_ui.full_shadows_requested.connect(_toggle_full_shadows)
	menu_ui.engine_hum_requested.connect(_toggle_engine_hum)
	menu_ui.debug_items_requested.connect(_toggle_debug_items)
	menu_ui.resolution_selected.connect(_on_resolution_selected)
	menu_ui.quit_requested.connect(_on_quit)
	menu_ui.quit_race_requested.connect(_show_run_summary)
	menu_ui.reset_requested.connect(_on_debug_reset)
	menu_ui.summary_menu_requested.connect(_on_menu)
	menu_ui.summary_play_again_requested.connect(_play_again)

	garage_ui = GarageUI.new()
	garage_ui.configure_road_layout(road_layout)
	garage_ui.close_requested.connect(_on_garage_close_requested)
	garage_ui.visible = false

	menu_ui.add_menu_overlay(garage_ui)

	garage_ui.track_selected.connect(_on_track_skin)
	garage_ui.model_selected.connect(_on_model_selected)
	garage_ui.upgrade_selected.connect(_on_upgrade_selected)


func _on_garage_close_requested() -> void:
	garage_ui.visible = false

	if is_instance_valid(race_hud):
		race_hud.visible = state == RaceSession.Mode.RUNNING


## Creates the equipped ship while preserving its position when replacing it.
func _spawn_player() -> void:
	# Preserve the current position when replacing the ship during a run.
	var keep_x := NAN
	var keep_target := NAN
	if is_instance_valid(player):
		keep_x = player.position.x
		keep_target = player.target_x
	
	# The previous ship may still be awaiting its destruction tween
	# when a new run starts.
	if is_instance_valid(player):
		player.queue_free()

	player = PlayerShip.new(SaveManager.player_ship_skin())
	add_child(player)
	var start_x := road_layout.get_lane_center(road_layout.get_center_lane_index())
	# Set player position
	if is_nan(keep_x):
		# First spawn of a session: start on the center lane.
		player.position = Vector3(start_x, PLAYER_HOVER_Y, PLAYER_Z)
		player.target_x = start_x
	else:
		# Mid-run replacement: keep the lane the player is in.
		player.position = Vector3(keep_x, PLAYER_HOVER_Y, PLAYER_Z)
		player.target_x = keep_target

	# Keep an active shield dome on the new hull right away: while
	# paused, the per-frame follow in _process (RUNNING branch)
	# does not run, so the dome would linger at its old spot until
	# the race resumes.
	if is_instance_valid(shield_dome) and shield_dome.visible:
		shield_dome.position = player.position + Vector3(0.0, 0.0, -0.25)

	if camera:
		camera.queue_free()
	if camera_pivot:
		camera_pivot.queue_free()

	camera_pivot = Node3D.new()
	add_child(camera_pivot)
	camera_pivot.position = Vector3(road_layout.road_center, 6, 9)

	camera = Camera3D.new()
	camera_pivot.add_child(camera)
	camera.make_current()
	camera.fov = 70
	camera.look_at(Vector3(road_layout.road_center, 0, -30), Vector3.UP)


func _toggle_garage() -> void:
	if state == RaceSession.Mode.RUNNING:
		AudioManager.stop_engine()

	var opening := not garage_ui.visible
	garage_ui.visible = opening

	if opening:
		garage_ui.refresh()

	if is_instance_valid(race_hud):
		race_hud.visible = not opening


func _toggle_fullscreen() -> void:
	# All window-mode logic (mode switch, resolution restore, centring)
	# lives in DisplayManager.
	display_manager.toggle_fullscreen()
	_sync_fs_label()


## Toggles real-time shadows for ships and pickups.
## SaveManager.default_data() once the engine fix lands.
func _toggle_full_shadows() -> void:
	SaveManager.data.full_shadows = not SaveManager.data.full_shadows
	SaveManager.persist()
	_apply_shadow_mode()


## Toggles the engine sound and updates the audio state immediately.
func _toggle_engine_hum() -> void:
	SaveManager.data.engine_hum = not SaveManager.data.engine_hum
	SaveManager.persist()

	AudioManager.set_engine_enabled(SaveManager.data.engine_hum)
	menu_ui.set_engine_hum(SaveManager.data.engine_hum)

	if (
		SaveManager.data.engine_hum
		and state == RaceSession.Mode.RUNNING
	):
		AudioManager.start_engine()


## Toggles the fixed pickup-spawning pattern used for debugging.
func _toggle_debug_items() -> void:
	SaveManager.data.debug_items = not SaveManager.data.debug_items
	SaveManager.persist()

	if is_instance_valid(entity_manager):
		entity_manager.debug_items = SaveManager.data.debug_items
	menu_ui.set_debug_items(SaveManager.data.debug_items)


## Applies the selected shadow mode to the player and active entities.
## Newly spawned entities configure their shadows when created.
func _apply_shadow_mode() -> void:
	var full: bool = SaveManager.data.full_shadows

	if is_instance_valid(player):
		Primitives.apply_shadow_mode(player, full)

	if is_instance_valid(entity_manager):
		for e in entity_manager.entities:
			# Freed-safe: vaporised ships linger in the list until
			# explode() purges them — never cast a freed object.
			var node = e.get("node")
			if node != null and is_instance_valid(node):
				Primitives.apply_shadow_mode(node, full)

	if is_instance_valid(menu_ui):
		menu_ui.set_full_shadows(full)


func _on_resolution_selected(resolution: String) -> void:
	display_manager.apply_resolution(resolution)


# Persist/save settings before closing the game.
func _on_quit() -> void:
	SaveManager.persist()
	get_tree().quit()


## Restores default save data and rebuilds components that depend on it.
func _on_debug_reset() -> void:
	if state == RaceSession.Mode.RUNNING:
		return

	SaveManager.reset_all()

	# Audio state back to defaults (mute off, default volumes;
	# refresh_options re-applies the volume sliders).
	AudioManager.set_muted(SaveManager.data.muted)
	AudioManager.set_engine_enabled(SaveManager.data.engine_hum)

	# Debug item placement back to default (off).
	if is_instance_valid(entity_manager):
		entity_manager.debug_items = SaveManager.data.debug_items

	# Window back to the default mode/size.
	if is_instance_valid(display_manager):
		display_manager.set_fullscreen(SaveManager.data.fullscreen)

	# Options widgets (name, sliders, resolution, fullscreen label).
	menu_ui.refresh_options()

	# Selection state and garage preview back to the default skins.
	garage_ui.focused_item_id = ""
	garage_ui.refresh()

	# Player ship rebuilt from the default skin.
	_spawn_player()

	# World and scenery rebuilt from the default theme.
	_build_world()

	_refresh_menu()


func _sync_fs_label() -> void:
	var fullscreen := (
		DisplayServer.window_get_mode()
		== DisplayServer.WINDOW_MODE_FULLSCREEN
	)

	menu_ui.set_fullscreen(fullscreen)


func _on_track_skin(skin: Dictionary) -> void:
	garage_ui.focused_item_id = skin.id

	if SaveManager.data.owned_tracks.has(skin.id):
		SaveManager.data.track_skin = skin.id
		SaveManager.persist()
	elif SaveManager.buy_track(skin.id):
		AudioManager.play("buy")

	_build_world()
	garage_ui.refresh()


## Equips the selected ship model, purchasing it if necessary.
func _on_model_selected(model: Dictionary) -> void:
	garage_ui.focused_item_id = model.id

	if SaveManager.data.owned_models.has(model.id):
		SaveManager.data.ship_model = model.id
		SaveManager.persist()
	elif SaveManager.buy_model(model.id):
		AudioManager.play("buy")

	_spawn_player()
	garage_ui.refresh()


## Attempts to purchase the selected upgrade.
func _on_upgrade_selected(upgrade: Dictionary) -> void:
	if SaveManager.buy_upgrade(str(upgrade.id)):
		AudioManager.play("buy")

	garage_ui.refresh()


## Ends the current run and returns to the main menu.
func _on_menu() -> void:
	# Leaving the race for the menu ends the run — record it.
	_record_run_score()

	AudioManager.stop_engine()
	# Back outside the race: the ambient menu theme crossfades
	# in over the race breakbeat.
	AudioManager.play_menu_theme()
	_reset_super_charge()
	shield_until = 0

	if shield_dome:
		shield_dome.visible = false

	SaveManager.data.best = maxi(
		SaveManager.data.best,
		int(distance_travelled)
	)
	SaveManager.persist()

	state = RaceSession.Mode.MENU
	_refresh_menu()


## Initializes and starts a new race.
func _on_start(from_menu: bool = true) -> void:
	if from_menu:
		SaveManager.persist()

	AudioManager.start_music()
	AudioManager.start_engine()

	entity_manager.clear_entities()
	scenery.restore_layout()
	segment_manager.reset()
	road.update_scroll(0.0, true)
	entity_manager.set_segment_manager(segment_manager)
	# Record the previous run before resetting the session.
	_record_run_score()

	session.begin_run()
	run_score_recorded = false
	# Clear any leftover shield countdown from the previous run.
	race_hud.reset_shield_countdown()
	lane = road_layout.get_center_lane_index()
	var start_x := road_layout.get_lane_center(lane)
	# A run-end explosion frees the old ship 0.35 s after the last
	# life is lost; starting a fresh run after that must respawn it
	# before touching position/target_x (freed object).
	if not is_instance_valid(player):
		_spawn_player()
	player.position.x = start_x
	player.target_x = start_x
	entity_manager.reset_spawning()

	state = RaceSession.Mode.RUNNING
	_refresh_menu()


## Handles keyboard input for menus and active gameplay.
func _unhandled_key_input(event: InputEvent) -> void:
	if menu_ui.is_options_open() or menu_ui.is_scores_open():
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				menu_ui.close_options()
				menu_ui.close_scores()
				get_viewport().set_input_as_handled()
				return

	if not event is InputEventKey:
		return

	var keycode := (event as InputEventKey).keycode

	# SPACE RELEASE resolves the hold: the SUPER SHOT when the
	# charge threshold was reached, a normal shot for a quick tap.
	if keycode == KEY_SPACE and not event.pressed and not event.echo:
		_on_space_released()
		return

	if not event.pressed or event.echo:
		return

	if keycode == KEY_ESCAPE:
		if garage_ui and garage_ui.visible:
			_on_garage_close_requested()
			menu_ui.focus_garage_button()
			return

		if state == RaceSession.Mode.RUNNING:
			_pause_run()
			return

		if state == RaceSession.Mode.PAUSED:
			_resume_run()
			return

		if state == RaceSession.Mode.GAMEOVER:
			_show_run_summary()
			return

		if state == RaceSession.Mode.SUMMARY:
			_on_menu()
			return

	if keycode == KEY_F:
		_toggle_fullscreen()
		return

	if state != RaceSession.Mode.RUNNING:
		return

	if keycode == KEY_LEFT or keycode == KEY_A:
		_move_lane(-1)

	if keycode == KEY_RIGHT or keycode == KEY_D:
		_move_lane(1)

	if keycode == KEY_SPACE:
		_on_space_pressed()


## Attempts to move one lane in the requested direction.
func _move_lane(direction: int) -> void:
	# Check lane availability ahead of the player to account for
	# upcoming road transitions.
	var available := segment_manager.get_available_lane_indices(
		distance_travelled + LANE_SELECT_LOOKAHEAD
	)
	if available.is_empty():
		return

	var current_index := available.find(lane)
	if current_index < 0:
		# If the current lane has closed, use the nearest available lane
		# as the reference for the next movement.
		var nearest_lane: int = available[0]
		var nearest_distance := INF
		for candidate in available:
			var dx := absf(segment_manager.get_lane_center(candidate) - player.position.x)
			if dx < nearest_distance:
				nearest_distance = dx
				nearest_lane = candidate
		current_index = available.find(nearest_lane)

	var target_index := clampi(current_index + direction, 0, available.size() - 1)
	var old_lane := lane
	lane = available[target_index]
	player.target_x = segment_manager.get_lane_center(lane)
	_check_edge_bonus(old_lane)


## Checks whether a lane change qualifies for the edge bonus.
## The bonus is confirmed only if the player survives the grace period.
func _check_edge_bonus(old_lane: int) -> void:
	if edge_cooldown > 0.0 or world_speed < EDGE_SPEED:
		return

	var risky := false

	# Check whether the old lane is about to close.
	var probe := distance_travelled
	for _step in range(24):
		probe += 2.0
		if not segment_manager.get_available_lane_indices(probe).has(old_lane):
			if probe - distance_travelled <= EDGE_LANE_END:
				risky = true
			break

	# Check for nearby traffic.
	if not risky:
		for entity in entity_manager.entities:
			if (
				entity.type == "car"
				and absf(entity.z - player.position.z) < EDGE_TRAFFIC_Z
			):
				risky = true
				break

	if not risky:
		return

	# Delay payment until the player survives the confirmation period.
	# i.e. no bonus if you collide shortly after
	if edge_pending <= 0.0:
		edge_pending = EDGE_CONFIRM_SEC


## Fires a normal projectile if ammunition and cooldown allow it.
func _fire() -> void:
	if fire_cooldown > 0.0:
		return

	if ammo <= 0:
		AudioManager.play("hit")
		_toast("⚡ No ammo — grab a 🔫 pickup!")
		return

	ammo -= 1
	fire_cooldown = 0.25
	var bz := player.position.z - 1.0

	# Purple plasma bolt (primitives.gd) instead of the plain
	# yellow emissive sphere — same family as the super-shot ball.
	# Shot colour from the free EFFECTS customization (garage).
	var bullet := Primitives.plasma_bullet(
		self,
		Vector3(segment_manager.get_lane_center(lane), 0.5, bz),
		SaveManager.effect_color("effect_shot")
	)

	entity_manager.register_bullet(bullet, lane, bz)
	# Gunfire reaction: a bright pulse washes over the hull plating.
	player.fx_flash = 1.0
	AudioManager.play("shoot")


## Begins charging a super shot.
func _on_space_pressed() -> void:
	space_held = true
	space_hold_time = 0.0


## Fires a super shot if fully charged; otherwise fires a normal shot.
func _on_space_released() -> void:
	if not space_held:
		return

	var held := space_hold_time
	_reset_super_charge()

	if state != RaceSession.Mode.RUNNING:
		return

	if held >= SUPER_HOLD_SEC:
		if ammo >= SUPER_AMMO_COST:
			_super_fire()
			return
		AudioManager.play("hit")
		_toast(
			"⚡ SUPER needs %d ammo — grab a 🔫 pickup!"
			% SUPER_AMMO_COST
		)

	_fire()


## Resets the charge state and hides the HUD indicator.
func _reset_super_charge() -> void:
	space_held = false
	space_hold_time = 0.0
	race_hud.show_super_charge(-1.0)


## Fires a super shot that destroys traffic ahead of the player.
func _super_fire() -> void:
	ammo -= SUPER_AMMO_COST
	var wave_z := player.position.z - 1.0

	# The shockwave itself is a slightly transparent bluish PLASMA
	# ball (Primitives.plasma_wave): semi-opaque churning interior,
	# bright cyan rim, additive glow. Born at the size the "wave"
	# update branch uses at travelled == 0, so no pop on frame one.
	var wave := Primitives.plasma_wave(self, Vector3(player.position.x, 0.5, wave_z))

	entity_manager.register_wave(wave, wave_z)
	# The super shot's reaction pulse on the hull plating.
	player.fx_flash = 1.0
	AudioManager.play("supershot")
	_toast("⚡ SUPER SHOT!")

## Selects the nearest lane that is expected to remain open.
func _get_safe_resume_lane() -> int:
	var candidates: Array[int] = []

	# Prefer lanes that remain open over the lookahead distance.
	for lane_index in road_layout.get_all_lane_indices():
		if segment_manager.is_lane_open_between(
			lane_index,
			distance_travelled,
			distance_travelled + 120.0
		):
			candidates.append(lane_index)

	# Fall back to currently available lanes if none meet that condition.
	if candidates.is_empty():
		candidates = segment_manager.get_available_lane_indices(
			distance_travelled
		)

	if candidates.is_empty():
		return road_layout.get_center_lane_index()

	# Select the lane closest to the player's current horizontal position.
	var best_lane: int = candidates[0]
	var best_distance := INF

	for candidate in candidates:
		var dx := absf(
			segment_manager.get_lane_center(candidate)
			- player.position.x
		)

		if dx < best_distance:
			best_distance = dx
			best_lane = candidate

	return best_lane


## Updates the active race, including movement, effects, entities and HUD.
func _process(delta: float) -> void:
	# Keep diagnostic logging out of release builds.
	if OS.is_debug_build():
		_debug_performance_monitor(delta)

	if state != RaceSession.Mode.RUNNING:
		_update_exhaust_only(delta)
		return

	# Update charge progress and play the ready sound when fully charged.
	if space_held:
		var was_ready := space_hold_time >= SUPER_HOLD_SEC
		space_hold_time += delta
		if not was_ready and space_hold_time >= SUPER_HOLD_SEC:
			# Charge complete: its own bell-chime ping ("superready"),
			# NOT the powerup pickup sound the old code reused here.
			AudioManager.play("superready")
		var fraction: float = -1.0
		if space_hold_time >= SUPER_BAR_DELAY:
			fraction = space_hold_time / SUPER_HOLD_SEC
		race_hud.show_super_charge(fraction)

	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		# Reduce acceleration near the normal speed cap.
		var speed_fraction: float = (
			world_speed / RaceSession.MAX_SPEED
		)
		# Clamp the rate to zero so overdrive cannot produce negative acceleration.
		var accel_rate: float = maxf(
			0.0,
			0.6 * (
				1.0 - RaceSession.ACCEL_TAPER * speed_fraction
			)
		)
		throttle = minf(
			RaceSession.MAX_THROTTLE,
			throttle + delta * accel_rate
		)

		# Build the overdrive bonus while maximum throttle is maintained.
		if throttle >= RaceSession.MAX_THROTTLE:
			if overdrive_speed <= 0.0:
				_toast("⚡ OVERDRIVE — hold to push the record!")
			overdrive_speed = minf(
				overdrive_speed + RaceSession.OVERDRIVE_RATE * delta,
				RaceSession.OVERDRIVE_MAX_BONUS
			)
	elif Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		throttle = maxf(0.0, throttle - delta * 1.2)
		# Braking immediately removes the overdrive bonus.
		_drop_overdrive()
	else:
		# Coast toward the minimum throttle while retaining the current speed.
		# Releasing acceleration also removes the overdrive bonus.
		throttle = maxf(0.45, throttle - delta * 0.15)
		_drop_overdrive()

	var target := (
		RaceSession.MIN_SPEED
		+ throttle * RaceSession.SPEED_PER_THROTTLE
		+ overdrive_speed
	)
	world_speed += (target - world_speed) * minf(1.0, delta * 1.5)
	speed_kmh = int(world_speed * 3.6)
	max_speed_kmh = maxi(max_speed_kmh, speed_kmh)
	distance_travelled += world_speed * delta
	fire_cooldown = maxf(0.0, fire_cooldown - delta)
	# Edge-bonus cooldown (see _check_edge_bonus).
	edge_cooldown = maxf(0.0, edge_cooldown - delta)
	# Award the pending bonus if the player survives the confirmation period.
	if edge_pending > 0.0:
		edge_pending -= delta
		if edge_pending <= 0.0:
			edge_cooldown = EDGE_COOLDOWN
			run_cash += EDGE_BONUS
			SaveManager.data.cash += EDGE_BONUS
			_toast("⚡ Living on the edge! +💵 %d" % EDGE_BONUS)

	# Generate enough track to maintain approximately eight seconds of visibility.
	segment_manager.ensure_generated_through(
		distance_travelled + maxf(240.0, world_speed * 8.0)
	)

	road.update_scroll(distance_travelled)
	scenery.position.z = 0.0
	scenery.update_scroll(distance_travelled)
	# The static ground plane's texture must stream with the
	# world: same travelled distance as the road chunks.
	WorldTheme.update_ground_scroll(distance_travelled)

	# Blend the overdrive effect according to the current bonus.
	player.fx_overdrive = lerpf(
		player.fx_overdrive,
		1.0 if overdrive_speed > 0.0 else 0.0,
		minf(1.0, delta * 4.0)
	)
	player.update_craft(delta, speed_kmh, world_speed)

	# Increase speed-line intensity as the player approaches overdrive.
	race_hud.set_speed_lines(
		clampf((world_speed / RaceSession.MAX_SPEED - 0.8) / 0.2, 0.0, 1.0),
		player.fx_overdrive
	)

	# Decay the shield ripple effect.
	shield_ripple = maxf(0.0, shield_ripple - delta * 1.5)
	if is_instance_valid(shield_dome):
		Primitives.set_shell_ripple(shield_dome, shield_ripple)

	# Off-road movement remains lethal, even while shielded.
	# Check both the current road boundary and the lookahead boundary:
	# this allows early lane changes during widening transitions without
	# allowing the player to remain outside the road.
	if (
		not segment_manager.is_position_on_road(
			distance_travelled,
			player.position.x,
			0.15
		)
		and not segment_manager.is_position_on_road(
			distance_travelled + LANE_SELECT_LOOKAHEAD,
			player.position.x,
			0.15
		)
	):
		_crash()
		return

	if shake > 0.0:
		shake -= delta * 6.0
		camera_pivot.position.x = (randf() * 2.0 - 1.0) * shake * 0.15
		camera_pivot.position.y = 6.0 + (
			randf() * 2.0 - 1.0
		) * shake * 0.08
	else:
		camera_pivot.position.x = lerpf(
			camera_pivot.position.x, 0.0, minf(1.0, delta * 8.0)
		)
		camera_pivot.position.y = lerpf(
			camera_pivot.position.y, 6.0, minf(1.0, delta * 8.0)
		)

	if is_instance_valid(shield_dome) and is_instance_valid(player):
		var now_ms := Time.get_ticks_msec()
		var shield_on := now_ms < shield_until

		shield_dome.visible = shield_on

		# Keep the shield centered on the player ship.
		shield_dome.position = (
			player.position + Vector3(0, 0.0, -0.25)
		)

		if shield_on:
			var remaining := (
				float(shield_until - now_ms) / 1000.0
			)

			# Pulse the shield normally and flash it as it approaches expiration.
			if remaining < 1.0:
				Primitives.set_shell_energy(
					shield_dome,
					0.5 if int(remaining * 8.0) % 2 == 0
					else 0.1
				)
			else:
				Primitives.set_shell_energy(
					shield_dome,
					0.35 + 0.1 * sin(
						now_ms / 1000.0 * 6.0
					)
				)

	AudioManager.set_engine_speed(speed_kmh)
	entity_manager.spawn_step(delta)
	entity_manager.update_ents(delta)
	session.step_economy()

	# Update the remaining shield duration for the HUD.
	var shield_left := maxf(
		0.0,
		(shield_until - Time.get_ticks_msec()) / 1000.0
	)
	race_hud.update_stats(
		distance_travelled,
		speed_kmh,
		run_cash,
		lives,
		shield_left > 0.0,
		ammo,
		overdrive_speed,
		shield_left
	)


## Updates ship exhaust and visual effects while the race is inactive.
func _update_exhaust_only(delta: float) -> void:
	# The player may already have been freed by the run-end explosion.
	if is_instance_valid(player):
		# Fade out overdrive and update the ship's idle effects.
		player.fx_overdrive = lerpf(
			player.fx_overdrive, 0.0, minf(1.0, delta * 4.0)
		)
		player.update_craft(delta, 0.0, 0.0, false)
	# Hide speed lines outside active gameplay.
	if is_instance_valid(race_hud):
		race_hud.set_speed_lines(0.0)


## Removes the overdrive bonus and adjusts the current speed immediately.
func _drop_overdrive(velocity_fraction := 1.0) -> void:
	overdrive_speed = 0.0
	world_speed = minf(
		world_speed,
		(
			RaceSession.MIN_SPEED
			+ throttle * RaceSession.SPEED_PER_THROTTLE
		) * velocity_fraction
	)


## Handles a player crash, including recovery or ending the run.
func _crash(victim: Node3D = null) -> void:
	_reset_super_charge()
	# A crash cancels any pending edge bonus.
	edge_pending = 0.0
	shield_ripple = 1.0
	shield_until = 0

	if is_instance_valid(shield_dome):
		shield_dome.visible = false

	AudioManager.play("crash")

	# Each crash costs one life. The run continues while lives remain.
	lives -= 1
	# Still tracked for the high score entry's "continues" field
	# (now the count of lives lost mid-run); it no longer docks
	# any score.
	continues_used += 1

	# A crash forfeits the overdrive bonus — record attempts must
	# survive the whole push, and a clean run is rewarded by the
	# overdrive it keeps alive instead of score arithmetic.
	_drop_overdrive(0.9)

	if lives > 0:
		# Recover in a safe lane and grant temporary protection against traffic.
		# Road-boundary violations remain lethal during recovery.
		shake = 1.0
		lane = _get_safe_resume_lane()
		var safe_x := segment_manager.get_lane_center(lane)
		player.position.x = safe_x
		player.target_x = safe_x
		shield_until = Time.get_ticks_msec() + 4000
		return

	# Final life lost: end the run and play the crash effects.
	entity_manager.explode(player)
	if victim != null and is_instance_valid(victim):
		entity_manager.explode(victim)
		AudioManager.play("explode")

	# Persist the distance
	# best and hand over to the end-of-run screen, which shows
	# the final score (recorded once the player leaves it).
	AudioManager.stop_engine()

	SaveManager.data.best = maxi(
		SaveManager.data.best,
		int(distance_travelled)
	)
	SaveManager.persist()

	state = RaceSession.Mode.GAMEOVER
	_refresh_menu()


## Records the completed run in the high-score table, at most once.
func _record_run_score() -> void:
	# Do not record a score if no race has been started.
	if run_score_recorded:
		return
	if state == RaceSession.Mode.MENU:
		return
	run_score_recorded = true

	last_run_placement = SaveManager.add_score({
		"name": str(SaveManager.data.player_name),
		"score": session.compute_score(),
		"distance": int(distance_travelled),
		"top_speed": max_speed_kmh,
		"cash": run_cash,
		"collection_pct": session.collection_pct(),
		"kills": cars_destroyed,
		"continues": continues_used
	})


func _pause_run() -> void:
	if state != RaceSession.Mode.RUNNING:
		return

	state = RaceSession.Mode.PAUSED
	AudioManager.stop_engine()
	_reset_super_charge()
	_refresh_menu()


func _resume_run() -> void:
	if state != RaceSession.Mode.PAUSED:
		return

	state = RaceSession.Mode.RUNNING
	AudioManager.start_engine()
	_refresh_menu()


func _on_start_button_pressed() -> void:
	if state == RaceSession.Mode.PAUSED:
		_restart_race()
	elif state == RaceSession.Mode.MENU:
		_on_start(false)


## Ends the current run and opens the summary screen.
func _restart_race() -> void:
	if state != RaceSession.Mode.PAUSED:
		return

	# A restart ends the current run: record its score and show
	# the summary.
	_show_run_summary()


## Records the current run and displays its final statistics.
func _show_run_summary() -> void:
	_record_run_score()
	_reset_super_charge()
	state = RaceSession.Mode.SUMMARY
	_refresh_menu()


func _play_again() -> void:
	if state != RaceSession.Mode.SUMMARY:
		return
	_on_start(false)


func _toast(msg: String) -> void:
	race_hud.show_toast(msg)


## Updates the shield ripple effect after a near miss or
## a shielded traffic collision.
func _on_near_miss(intensity: float) -> void:
	shield_ripple = maxf(shield_ripple, clampf(intensity, 0.0, 1.0))


## Updates menu and HUD visibility according to the current race state.
func _refresh_menu() -> void:
	match state:
		RaceSession.Mode.MENU:
			# Main menu
			menu_ui.show_menu(false)
			race_hud.visible = false

		RaceSession.Mode.PAUSED:
			# Pause menu
			menu_ui.show_menu(true)
			race_hud.visible = false

		RaceSession.Mode.RUNNING:
			# Active race
			menu_ui.hide_all()
			race_hud.visible = true

		RaceSession.Mode.GAMEOVER:
			 # Game-over screen
			menu_ui.show_game_over(
				int(distance_travelled),
				run_cash,
				SaveManager.data.best,
				session.compute_score(),
				SaveManager.would_make_list(
					session.compute_score()
				)
			)
			race_hud.visible = false

		RaceSession.Mode.SUMMARY:
			# Run summary
			menu_ui.show_run_summary(
				str(SaveManager.data.player_name),
				session.compute_score(),
				{
					"distance": int(distance_travelled),
					"top_speed": max_speed_kmh,
					"cash": run_cash,
					"collection_pct": session.collection_pct(),
					"kills": cars_destroyed
				},
				last_run_placement
			)
			race_hud.visible = false
