
class_name GarageUI
extends Control
## Manages the garage interface, including item selection,
## upgrades, customization and the live 3D preview.
## Emits selection signals; main.gd handles purchases and equips.

signal track_selected(skin: Dictionary)
signal model_selected(model: Dictionary)
signal upgrade_selected(upgrade: Dictionary)
signal close_requested

var cash_label: Label
var equipped_label: Label
var tabs: TabContainer
## Colour pickers in the EFFECTS tab, keyed by their SaveManager
## field names ("effect_flame", "effect_shot", "effect_overdrive").
var effect_pickers: Dictionary = {}
var track_grid: GridContainer
var model_grid: GridContainer
var upgrade_grid: GridContainer

var preview_viewport: SubViewport
var preview_theme_root: Node3D
var preview_root: Node3D
var preview_ship: PlayerShip
## Blob shadow of the preview ship. Its offset is counter-rotated
## in _process() to keep the shadow direction fixed in world space.
var preview_blob: Node3D
var road_layout: TrackLayout
var focused_item_id := ""
var _preview_rotation := 0.0

## Temporary preview overrides for unowned skins.
## Empty IDs show the currently equipped skin; these overrides
## never modify SaveManager data.
var preview_track_id := ""
var preview_model_id := ""


# =============================================================
# LIFECYCLE
# =============================================================

func configure_road_layout(shared_layout: TrackLayout) -> void:
	road_layout = shared_layout


func _ready() -> void:
	if road_layout == null:
		road_layout = TrackLayout.new(TrackConfig.new())
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	refresh()


func _process(delta: float) -> void:
	if not visible or not is_instance_valid(preview_ship):
		return

	_preview_rotation += delta * 0.45
	preview_ship.rotation.y = _preview_rotation
	preview_ship.update_craft(delta, 0.0, 0.0)

	# Counter-rotate the shadow offset so the ship's rotation
	# does not change its direction in world space.
	if preview_blob != null and is_instance_valid(preview_blob):
		preview_blob.position = (
			(preview_blob.get_meta("offset") as Vector3)
			.rotated(Vector3.UP, -preview_ship.rotation.y)
		)


# =============================================================
# GARAGE UI
# =============================================================

func _build_ui() -> void:
	var background := ColorRect.new()
	background.name = "GarageBackground"
	background.color = Color(0.025, 0.035, 0.065, 0.98)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)

	# ---------------------------------------------------------
	# Header.
	# ---------------------------------------------------------
	var header := HBoxContainer.new()
	layout.add_child(header)

	var title_stack := VBoxContainer.new()
	var garage_title := _label("DASHOUT // GARAGE", 42)
	garage_title.add_theme_font_override("font", _title_font())
	garage_title.add_theme_color_override(
		"font_color", Color(0.95, 1.0, 1.0)
	)
	garage_title.add_theme_color_override(
		"font_outline_color", Color("22d3ee")
	)
	garage_title.add_theme_constant_override("outline_size", 6)
	garage_title.add_theme_color_override(
		"font_shadow_color", Color("22d3ee")
	)
	garage_title.add_theme_constant_override("shadow_offset_x", 2)
	garage_title.add_theme_constant_override("shadow_offset_y", 2)
	title_stack.add_child(garage_title)

	cash_label = _label("Credits: 0", 16)
	title_stack.add_child(cash_label)
	header.add_child(title_stack)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var exit_button := Button.new()
	exit_button.text = "EXIT  [ESC]"
	exit_button.custom_minimum_size = Vector2(120, 42)
	exit_button.pressed.connect(_on_close_pressed)
	header.add_child(exit_button)

	# ---------------------------------------------------------
	# Main columns.
	# ---------------------------------------------------------
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 18)
	layout.add_child(columns)

	# Left column: item selection, customization and upgrades.
	var left_panel := PanelContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 1.15
	columns.add_child(left_panel)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 12)
	left_panel.add_child(left)

	equipped_label = _label("", 14)
	left.add_child(equipped_label)

	tabs = TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(tabs)

	# Free customization of exhaust, plasma-shot and overdrive colours.
	# Changes are saved immediately and reflected in the live preview.
	var effect_scroll := ScrollContainer.new()
	effect_scroll.name = "EFFECTS"
	effect_scroll.horizontal_scroll_mode = (
		ScrollContainer.SCROLL_MODE_DISABLED
	)
	effect_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	effect_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var effect_column := VBoxContainer.new()
	effect_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	effect_column.add_theme_constant_override("separation", 12)
	effect_scroll.add_child(effect_column)

	for entry in [
		["effect_flame", "EXHAUST FLAME"],
		["effect_shot", "PLASMA SHOT"],
		["effect_overdrive", "OVERDRIVE GLOW"],
	]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var caption := _label(str(entry[1]), 14)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(caption)

		var picker := ColorPickerButton.new()
		picker.custom_minimum_size = Vector2(64, 32)
		picker.color = SaveManager.effect_color(str(entry[0]))
		picker.color_changed.connect(
			_on_effect_color_changed.bind(str(entry[0]))
		)
		effect_pickers[str(entry[0])] = picker
		row.add_child(picker)

		effect_column.add_child(row)

	var effect_hint := _label(
		"Free customization — applies to your ship immediately.",
		12
	)
	effect_hint.add_theme_color_override(
		"font_color", Color(0.8, 0.85, 0.95)
	)
	effect_column.add_child(effect_hint)

	# Hull model selection is independent of the ship's paint and effects.
	var model_scroll := ScrollContainer.new()
	model_scroll.name = "SHIP MODELS"
	model_scroll.horizontal_scroll_mode = (
		ScrollContainer.SCROLL_MODE_DISABLED
	)
	model_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	model_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var model_column := VBoxContainer.new()
	model_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	model_column.add_theme_constant_override("separation", 12)
	model_scroll.add_child(model_column)

	model_grid = GridContainer.new()
	model_grid.columns = 2
	model_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	model_grid.add_theme_constant_override("h_separation", 10)
	model_grid.add_theme_constant_override("v_separation", 10)
	model_column.add_child(model_grid)

	# --- scenery skins page.
	var track_scroll := ScrollContainer.new()
	track_scroll.name = "SCENERY SKINS"
	track_scroll.horizontal_scroll_mode = (
		ScrollContainer.SCROLL_MODE_DISABLED
	)
	track_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var track_column := VBoxContainer.new()
	track_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track_column.add_theme_constant_override("separation", 12)
	track_scroll.add_child(track_column)

	track_grid = GridContainer.new()
	track_grid.columns = 2
	track_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track_grid.add_theme_constant_override("h_separation", 10)
	track_grid.add_theme_constant_override("v_separation", 10)
	track_column.add_child(track_grid)

	# Tiered gameplay upgrades. Each purchase increases the corresponding
	# effect; the gameplay systems apply the bonuses during a race.
	var upgrades_scroll := ScrollContainer.new()
	upgrades_scroll.name = "UPGRADES"
	upgrades_scroll.horizontal_scroll_mode = (
		ScrollContainer.SCROLL_MODE_DISABLED
	)
	upgrades_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upgrades_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var upgrades_column := VBoxContainer.new()
	upgrades_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upgrades_column.add_theme_constant_override("separation", 12)
	upgrades_scroll.add_child(upgrades_column)

	upgrade_grid = GridContainer.new()
	upgrade_grid.columns = 1
	upgrade_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upgrade_grid.add_theme_constant_override("h_separation", 10)
	upgrade_grid.add_theme_constant_override("v_separation", 10)
	upgrades_column.add_child(upgrade_grid)

	# Tab order is determined by the order in which pages are added.
	tabs.add_child(model_scroll)
	tabs.add_child(effect_scroll)
	tabs.add_child(upgrades_scroll)
	tabs.add_child(track_scroll)

	# Right: live preview.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 0.85
	right.add_theme_constant_override("separation", 8)
	columns.add_child(right)

	right.add_child(_label("LIVE PREVIEW", 18))

	var preview_frame := PanelContainer.new()
	preview_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_frame.custom_minimum_size = Vector2(240, 320)

	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.035, 0.055, 0.09, 1.0)
	frame_style.border_color = Color(0.1, 0.8, 1.0, 0.55)
	frame_style.set_border_width_all(1)
	frame_style.set_corner_radius_all(4)
	preview_frame.add_theme_stylebox_override("panel", frame_style)
	right.add_child(preview_frame)

	# ---------------------------------------------------------
	# Dedicated 3D preview viewport.
	# ---------------------------------------------------------
	preview_viewport = SubViewport.new()
	preview_viewport.name = "GaragePreviewViewport"
	preview_viewport.own_world_3d = true
	preview_viewport.transparent_bg = false
	preview_viewport.size = Vector2i(480, 720)
	preview_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS
	)

	var viewport_container := SubViewportContainer.new()
	viewport_container.name = "GaragePreviewContainer"
	viewport_container.stretch = true
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_container.add_child(preview_viewport)
	preview_frame.add_child(viewport_container)

	_build_preview_world()


# =============================================================
# PREVIEW WORLD INITIALIZATION
# =============================================================

func _build_preview_world() -> void:
	# Keep the environment separate so it can be rebuilt without
	# removing the camera or preview objects.
	preview_theme_root = Node3D.new()
	preview_theme_root.name = "PreviewThemeRoot"
	preview_viewport.add_child(preview_theme_root)

	_refresh_preview_theme()

	# The ship, road and scenery live under a separate root.
	preview_root = Node3D.new()
	preview_root.name = "PreviewRoot"
	preview_viewport.add_child(preview_root)

	var camera := Camera3D.new()
	camera.name = "PreviewCamera"
	camera.position = Vector3(road_layout.road_center, 3.4, 7.5)
	camera.fov = 48.0
	preview_viewport.add_child(camera)

	camera.look_at(
		Vector3(road_layout.road_center, 0.8, -2.5),
		Vector3.UP
	)
	camera.make_current()


func _refresh_preview_theme() -> void:
	if not is_instance_valid(preview_theme_root):
		return

	# Clear the previous environment before rebuilding it.
	for child in preview_theme_root.get_children():
		preview_theme_root.remove_child(child)
		child.queue_free()

	# Use the preview override when set, otherwise the equipped theme.
	var track: Dictionary = _preview_track_skin()

	WorldTheme.build(preview_theme_root, track)


# =============================================================
# PREVIEW CONTENT
# =============================================================

func _build_preview() -> void:
	if not is_instance_valid(preview_root):
		return

	# Clear only the preview objects, not its environment or camera.
	for child in preview_root.get_children():
		preview_root.remove_child(child)
		child.queue_free()

	# Use the preview override when set, otherwise the equipped theme.
	var track: Dictionary = _preview_track_skin()

	# Use the same theme for scenery and environment.
	var scenery := Scenery.new()
	scenery.name = "PreviewScenery"
	scenery.build(track, road_layout)
	scenery.position = Vector3(0.0, 0.0, -5.0)
	preview_root.add_child(scenery)
	scenery.update_scroll(0.0)

	# Road preview.
	var road := RoadMesh.new()
	road.configure(road_layout)
	road.name = "PreviewRoad"
	road.position = Vector3(0.0, -0.12, 0.0)
	road.scale = Vector3(0.7, 0.7, 0.7)
	preview_root.add_child(road)

	# Build the preview ship using the selected model and equipped paint.
	preview_ship = PlayerShip.new(
		_preview_ship_skin(),
		true
	)
	preview_ship.name = "PreviewCraft"
	preview_ship.position = Vector3(road_layout.road_center, 0.2, 0.0)
	preview_ship.scale = Vector3(0.8, 0.8, 0.8)
	preview_root.add_child(preview_ship)
	preview_ship.rotation.y = _preview_rotation

	# The preview uses a different hover height and scale from the race
	# ship, so its blob shadow needs a separate vertical offset.
	# Store the complete base offset for world-space counter-rotation
	# in _process().
	var blob := preview_ship.find_child(
		"BlobShadow", true, false
	)
	if blob is Node3D:
		preview_blob = blob
		(blob as Node3D).position = Vector3(0.22, -0.22, -0.38)
		(blob as Node3D).set_meta(
			"offset", Vector3(0.22, -0.22, -0.38)
		)


# =============================================================
# PREVIEW OVERRIDES
# =============================================================

## Returns the preview track override, or the equipped track if
## no preview override is active.
func _preview_track_skin() -> Dictionary:
	if preview_track_id != "":
		for skin in SaveManager.TRACK_SKINS:
			if skin.id == preview_track_id:
				return skin
	return SaveManager.track_skin()


## Builds the preview ship skin using the default paint and the
## selected model ID. PlayerShip reads the model from the "model" key.
func _preview_ship_skin() -> Dictionary:
	var ship_skin: Dictionary = (
		SaveManager.DEFAULT_SHIP_SKIN.duplicate()
	)
	ship_skin["model"] = (
		preview_model_id
		if preview_model_id != ""
		else str(SaveManager.data.ship_model)
	)
	return ship_skin


## Toggles a temporary preview override for an unowned item.
## Selecting the same item again restores the equipped appearance.
func _toggle_preview(kind: String, item: Dictionary) -> void:
	focused_item_id = str(item.id)
	var id := str(item.id)
	match kind:
		"track":
			preview_track_id = "" if preview_track_id == id else id
		"model":
			preview_model_id = "" if preview_model_id == id else id
	refresh()


# =============================================================
# REFRESH
# =============================================================

func refresh() -> void:
	if not is_instance_valid(model_grid):
		return

	cash_label.text = "Credits: %d" % SaveManager.data.cash

	var track_skin: Dictionary = SaveManager.track_skin()

	equipped_label.text = "MODEL: %s  |  SCENERY: %s" % [
		str(SaveManager.ship_model().name),
		str(track_skin.name)
	]

	# Hull model cards.
	_clear_grid(model_grid)
	for model in SaveManager.SHIP_MODELS:
		model_grid.add_child(_make_model_card(model))

	_clear_grid(track_grid)
	for skin in SaveManager.TRACK_SKINS:
		track_grid.add_child(_make_card("track", skin))

	# Gameplay upgrades.
	if is_instance_valid(upgrade_grid):
		_clear_grid(upgrade_grid)
		for upgrade in SaveManager.UPGRADES:
			upgrade_grid.add_child(_make_upgrade_card(upgrade))

	# Rebuild both parts of the preview: the environment and its objects.
	# Changing the selected track does not automatically update the theme.
	_refresh_preview_theme()
	_build_preview()

	_restore_focus()


# =============================================================
# SELECTION CARDS
# =============================================================

func _make_card(kind: String, item: Dictionary) -> PanelContainer:
	var selected: bool = (
		kind == "track"
		and item.id == SaveManager.data.track_skin
	)

	var owned: bool = (
		SaveManager.data.owned_tracks.has(item.id)
	)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = (
		Color(0.08, 0.24, 0.19, 0.9)
		if selected
		else Color(0.08, 0.10, 0.16, 0.9)
	)
	style.border_color = (
		Color("51cf5e")
		if selected
		else Color(0.25, 0.35, 0.48, 0.8)
	)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	card.add_child(column)

	var colors: Array = [item.road, item.grass2, item.line]

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 5)

	for color_code in colors:
		var rect := ColorRect.new()
		rect.color = Color(str(color_code))
		rect.custom_minimum_size = Vector2(26, 18)
		rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(rect)

	column.add_child(row)

	var name_label := _label(str(item.name), 14)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_label)

	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 32)
	button.set_meta("item_id", str(item.id))

	if selected:
		button.text = "EQUIPPED"
		button.disabled = true
	elif owned:
		button.text = "EQUIP"
	else:
		button.text = "BUY · %d" % int(item.price)
		button.disabled = SaveManager.data.cash < int(item.price)

	button.pressed.connect(_select_item.bind(kind, item))
	column.add_child(button)

	# Unowned skins can be previewed without purchasing them.
	# Owned skins can be equipped directly.
	if not owned:
		var preview_button := Button.new()
		preview_button.custom_minimum_size = Vector2(0, 26)
		preview_button.set_meta("item_id", str(item.id))
		var previewing: bool = (
			preview_track_id == str(item.id)
		)
		preview_button.text = (
			"STOP PREVIEW" if previewing else "PREVIEW"
		)
		preview_button.pressed.connect(
			_toggle_preview.bind(kind, item)
		)
		column.add_child(preview_button)

	return card


## Saves a customization colour and rebuilds the live preview.
func _on_effect_color_changed(color: Color, key: String) -> void:
	SaveManager.set_effect_color(key, color)
	_build_preview()


func _select_item(kind: String, item: Dictionary) -> void:
	focused_item_id = str(item.id)

	# A real selection clears any temporary preview override.
	match kind:
		"track":
			preview_track_id = ""
			track_selected.emit(item)
		"model":
			preview_model_id = ""
			model_selected.emit(item)


## Creates a ship model card with its description and purchase options.
func _make_model_card(model: Dictionary) -> PanelContainer:
	var selected: bool = (
		model.id == SaveManager.data.ship_model
	)
	var owned: bool = (
		SaveManager.data.owned_models.has(model.id)
	)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = (
		Color(0.08, 0.24, 0.19, 0.9)
		if selected
		else Color(0.08, 0.10, 0.16, 0.9)
	)
	style.border_color = (
		Color("51cf5e")
		if selected
		else Color(0.25, 0.35, 0.48, 0.8)
	)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	card.add_child(column)

	var name_label := _label(str(model.name), 14)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_label)

	var desc_label := _label(str(model.desc), 12)
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.add_theme_color_override(
		"font_color",
		Color(0.8, 0.85, 0.95)
	)
	column.add_child(desc_label)

	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 32)
	button.set_meta("item_id", str(model.id))

	if selected:
		button.text = "EQUIPPED"
		button.disabled = true
	elif owned:
		button.text = "EQUIP"
	else:
		button.text = "BUY · %d" % int(model.price)
		button.disabled = SaveManager.data.cash < int(model.price)

	button.pressed.connect(_select_item.bind("model", model))
	column.add_child(button)

	# Allow unowned models to be previewed with the equipped paint.
	if not owned:
		var preview_button := Button.new()
		preview_button.custom_minimum_size = Vector2(0, 26)
		preview_button.set_meta("item_id", str(model.id))
		preview_button.text = (
			"STOP PREVIEW" if preview_model_id == str(model.id)
			else "PREVIEW"
		)
		preview_button.pressed.connect(
			_toggle_preview.bind("model", model)
		)
		column.add_child(preview_button)

	return card


## Creates an upgrade card showing its current tier, effect
## and the purchase option for the next tier.
func _make_upgrade_card(item: Dictionary) -> PanelContainer:
	var id := str(item.id)
	var level: int = SaveManager.get_upgrade_level(id)
	var max_level: int = SaveManager.get_upgrade_max_level(id)
	var maxed := level >= max_level
	var price := 0
	if not maxed:
		price = int(item.tiers[level])

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = (
		Color(0.08, 0.16, 0.26, 0.9)
		if level > 0
		else Color(0.08, 0.10, 0.16, 0.9)
	)
	style.border_color = (
		Color("51cf5e")
		if level > 0
		else Color(0.25, 0.35, 0.48, 0.8)
	)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	card.add_child(column)

	var name_label := _label(str(item.name), 15)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_label)

	var tier_label := _label("TIER %d / %d" % [level, max_level], 12)
	tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tier_label.add_theme_color_override("font_color", Color("51cf5e"))
	column.add_child(tier_label)

	var desc_label := _label(str(item.desc), 12)
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	column.add_child(desc_label)

	# Show the actual effect at the currently owned tier.
	var effect_label := _label(_upgrade_effect_text(id, level), 12)
	effect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	effect_label.add_theme_color_override("font_color", Color(0.9, 0.93, 0.98))
	column.add_child(effect_label)

	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 32)
	button.set_meta("item_id", str(item.id))

	if maxed:
		button.text = "MAXED"
		button.disabled = true
	else:
		button.text = "BUY · %d" % price
		button.disabled = SaveManager.data.cash < price

	button.pressed.connect(func():
		focused_item_id = str(item.id)
		upgrade_selected.emit(item)
	)
	column.add_child(button)

	return card


## Returns the current gameplay effect of an upgrade at the given tier.
func _upgrade_effect_text(id: String, level: int) -> String:
	match id:
		"hull":
			return "Start lives: %d (+%d)" % [
				RaceSession.START_LIVES
					+ level * RaceSession.UPGRADE_LIVES_PER_TIER,
				level * RaceSession.UPGRADE_LIVES_PER_TIER
			]
		"ammo_depot":
			return "Start ammo: %d (+%d)" % [
				RaceSession.START_AMMO
					+ level * RaceSession.UPGRADE_AMMO_PER_TIER,
				level * RaceSession.UPGRADE_AMMO_PER_TIER
			]
		"recycler":
			var shield_sec: float = (
				RaceSession.SHIELD_DURATION_SEC
				+ float(level)
				* RaceSession.UPGRADE_SHIELD_SEC_PER_TIER
			)
			return "Shield: %ds (+%ds)" % [
				int(shield_sec),
				int(float(level)
					* RaceSession.UPGRADE_SHIELD_SEC_PER_TIER)
			]
	return ""


func _restore_focus() -> void:
	# Restore focus to the previously selected item on the active tab.
	# Hidden tabs are skipped because their controls cannot take focus.
	for grid in [model_grid, track_grid, upgrade_grid]:
		if not is_instance_valid(grid) or not grid.is_visible_in_tree():
			continue
		for card in grid.get_children():
			var column := (card as PanelContainer).get_child(0)
			for control in column.get_children():
				if (
					control is Button
					and str(control.get_meta("item_id", ""))
					== focused_item_id
					and not control.disabled
				):
					control.grab_focus()
					return


func _clear_grid(grid: GridContainer) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()


func _on_close_pressed() -> void:
	close_requested.emit()
	

func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color.WHITE)
	return label


## Creates the faux-bold font variation used by the garage title.
func _title_font() -> FontVariation:
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.variation_embolden = 0.4
	font.variation_transform = Transform2D(
		Vector2(1.0, 0.0),
		Vector2(0.0, 1.0),
		Vector2.ZERO
	)
	return font
