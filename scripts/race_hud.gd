
class_name RaceHUD
extends CanvasLayer
## Builds and updates the in-race HUD.
## Receives gameplay state from main.gd and displays race statistics,
## speed, overdrive, pickups, notifications and temporary effects.

const NEON := Color("22d3ee")
const NEON_HOT := Color("ff5df2")
const LIFE := Color("ff5d7a")
## Maximum overdrive bonus represented by the full strip, in m/s.
## The display range is independent of the normal speed gauge.
const OD_DISPLAY_MAX := 50.0
## Shared width of the speed and overdrive bars.
const BAR_WIDTH := 260.0

## Dimensions of each bottom-row stat panel.
const PANEL_WIDTH := 132.0
const PANEL_HEIGHT := 84.0
## Pixel size of the rotating pickup-model viewports.
const ICON_SIZE := Vector2(44, 44)

var distance_label: Label
var cash_label: Label
var ammo_label: Label
var toast_label: Label
var toast_remaining := 0.0
## Controls for the SUPER SHOT charge readout.
var charge_root: VBoxContainer
var charge_caption: Label
var charge_bar: ColorRect
var charge_fill: ColorRect
## Speed gauge and label
var speed_num_label: Label
var speed_fill: ColorRect
var od_root: Control
var od_fill: ColorRect
var od_label: Label

## One bar per MAX_LIVES slot; filled bars show the lives left.
var life_bars: Array[ColorRect] = []
## The rotating pickup models shown in the stat panels, plus the
## shield icon container (only visible while a shield is up).
var shield_icon: Control
## Shield expiry countdown caption ("⛨ SHIELD OFF IN 3" →
## "⛨ SHIELD OFF!"), a big centered readout above the charge bar.
var shield_count_label: Label
## Whether the shield was active during the previous update.
## Detects the transition to inactive so the expiry flash fires once.
var shield_last_active := false
## Remaining duration of the "SHIELD OFF!" flash.
var shield_off_flash := 0.0

var coin_model: Node3D
var ammo_model: Node3D
var shield_model: Node3D

## Faux-italic variation used throughout the HUD.
var _hud_font: FontVariation

## Full-screen additive speed-line overlay.
## Radial streaks travel outward from the screen centre, while
## the central viewing area remains clear.
##
## main.gd controls the intensity and overdrive tint according
## to the current speed.
const SPEED_LINES_SHADER: Shader = preload("res://shaders/speed_lines.gdshader")

var speed_lines: ColorRect
var speed_lines_mat: ShaderMaterial


func _ready() -> void:
	_hud_font = _make_font(0.18)
	# Build the overlay first so all HUD panels render above it.
	_build_speed_lines()
	_build_stat_panels()
	_build_speed_gauge()
	_build_toast()
	_build_charge_bar()
	_build_shield_countdown()


## Creates the full-screen additive speed-line overlay.
func _build_speed_lines() -> void:
	speed_lines = ColorRect.new()
	speed_lines.name = "SpeedLines"
	speed_lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	speed_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speed_lines_mat = ShaderMaterial.new()
	speed_lines_mat.shader = SPEED_LINES_SHADER
	speed_lines.material = speed_lines_mat
	add_child(speed_lines)


## Updates the speed-line intensity and overdrive colour blend.
## Both parameters are clamped to the range 0..1.
func set_speed_lines(t: float, od: float = 0.0) -> void:
	if speed_lines_mat != null:
		speed_lines_mat.set_shader_parameter(
			"intensity", clampf(t, 0.0, 1.0)
		)
		speed_lines_mat.set_shader_parameter(
			"overdrive", clampf(od, 0.0, 1.0)
		)


# ------------------------------------------------------------
# Layout
# ------------------------------------------------------------

## Creates a stat panel with a fixed-height caption area and a
## vertically centred content area.
##
## Returns the content container so callers can add their own
## values and icons without affecting caption alignment.
func _stat_panel(row: HBoxContainer, caption: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	panel.add_theme_stylebox_override("panel", _neon_panel())
	row.add_child(panel)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)

	var top_pad := Control.new()
	top_pad.custom_minimum_size = Vector2(0, 7)
	column.add_child(top_pad)

	var caption_label := _label(caption, 13)
	caption_label.add_theme_color_override("font_color", NEON)
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(caption_label)

	# Let the content fill the remaining space below the caption.
	var content := VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(content)

	return content


func _build_stat_panels() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	row.offset_left = 14
	# Derive the row height from PANEL_HEIGHT so the panel dimensions
	# remain controlled by the shared constant.
	row.offset_top = -(PANEL_HEIGHT + 14.0)
	row.offset_bottom = -14
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	# DISTANCE
	var distance_column := _stat_panel(row, "DISTANCE")
	distance_label = _label("0 m", 20)
	distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	distance_column.add_child(distance_label)

	# CREDITS
	var cash_column := _stat_panel(row, "CREDITS")
	var cash_row := _icon_row(cash_column)
	coin_model = EntityManager.build_coin_model()

	cash_row.add_child(_item_viewport(coin_model, ICON_SIZE, 0.0, 0.65))
	var cash_value := _stat_value_label("0", 20)
	cash_label = cash_value.get_child(0) as Label
	cash_row.add_child(cash_value)

	# AMMO
	var ammo_column := _stat_panel(row, "AMMO")
	var ammo_row := _icon_row(ammo_column)
	ammo_model = EntityManager.build_power_model("ammo")
	ammo_row.add_child(_item_viewport(ammo_model, ICON_SIZE, -0.2, 0.7))
	var ammo_value := _stat_value_label("0", 20)
	ammo_label = ammo_value.get_child(0) as Label
	ammo_row.add_child(ammo_value)

	# HULL
	var hull_column := _stat_panel(row, "HULL")
	var hull_row := _icon_row(hull_column)
	var bars := HBoxContainer.new()
	bars.alignment = BoxContainer.ALIGNMENT_CENTER
	bars.add_theme_constant_override("separation", 2)
	bars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hull_row.add_child(bars)
	# One bar per life slot; filled bars represent remaining lives.
	for life_index in range(RaceSession.MAX_LIVES):
		var bar := ColorRect.new()
		bar.custom_minimum_size = Vector2(4, 30)
		bar.color = LIFE
		bars.add_child(bar)
		life_bars.append(bar)
	shield_model = EntityManager.build_power_model("shield")
	shield_icon = _item_viewport(shield_model, Vector2(36, 36), 0.0, 0.61)
	shield_icon.visible = false
	hull_row.add_child(shield_icon)


## Content row inside a stat panel: icon + value, horizontally
## centered.
func _icon_row(column: VBoxContainer) -> HBoxContainer:
	var icon_row := HBoxContainer.new()
	icon_row.alignment = BoxContainer.ALIGNMENT_CENTER
	icon_row.add_theme_constant_override("separation", 6)
	column.add_child(icon_row)
	return icon_row


## Vertical adjustment applied to stat values beside their icons.
const STAT_LABEL_NUDGE := 4

## Wraps a stat label so it can be shifted vertically inside a
## container without changing the row's overall alignment.
func _stat_value_label(text: String, size: int) -> MarginContainer:
	var label := _label(text, size)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nudge := MarginContainer.new()
	nudge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nudge.add_theme_constant_override("margin_top", -STAT_LABEL_NUDGE)
	nudge.add_child(label)
	return nudge


## Creates a transparent SubViewport displaying a rotating 3D pickup.
## Each viewport has its own 3D world, camera and directional light.
##
## lift and zoom compensate for differences in the imported models'
## origins and dimensions, keeping each icon framed consistently.
func _item_viewport(
	model: Node3D,
	size_px := ICON_SIZE,
	lift := 0.0,
	zoom := 1.0
) -> SubViewportContainer:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.size = Vector2i(size_px)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var camera := Camera3D.new()
	camera.fov = 30
	camera.position = Vector3(0.0, 0.0, 2.2)
	camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	camera.make_current()
	viewport.add_child(camera)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-45, -30, 0)
	key_light.light_energy = 1.2
	viewport.add_child(key_light)

	# Apply the per-model framing adjustments before adding it to the viewport.
	model.position.y += lift
	model.scale *= zoom
	viewport.add_child(model)

	var container := SubViewportContainer.new()
	container.custom_minimum_size = size_px
	container.stretch = true
	container.add_child(viewport)
	return container


func _build_speed_gauge() -> void:
	# Bottom-right speed/velocity panel
	var gauge := PanelContainer.new()
	gauge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	gauge.offset_left = -330
	gauge.offset_top = -(PANEL_HEIGHT + 14.0)
	gauge.offset_right = -14
	# Bottom band needs a custom lift?
	gauge.offset_bottom = -7
	gauge.add_theme_stylebox_override("panel", _neon_panel())
	add_child(gauge)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	# Align the gauge content with the bottom of the stat panels.
	# The overdrive strip grows upward when it becomes visible.
	column.alignment = BoxContainer.ALIGNMENT_END
	gauge.add_child(column)

	# OVERDRIVE — hidden until an overdrive bonus is active.
	# Its caption pulses while the bonus is available.
	od_root = Control.new()
	od_root.custom_minimum_size = Vector2(BAR_WIDTH, 18)
	column.add_child(od_root)

	od_label = _label("⚡ OVERDRIVE", 12)
	od_label.add_theme_color_override("font_color", NEON_HOT)
	od_root.add_child(od_label)

	var od_track := ColorRect.new()
	od_track.color = Color(NEON_HOT, 0.15)
	od_track.position = Vector2(0, 14)
	od_track.size = Vector2(BAR_WIDTH, 4)
	od_root.add_child(od_track)

	od_fill = ColorRect.new()
	od_fill.color = NEON_HOT
	od_fill.position = Vector2(0, 14)
	od_fill.size = Vector2(0, 4)
	od_root.add_child(od_fill)

	# Speed value and unit, independently positioned within the row.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)

	speed_num_label = _label("0", 24)
	speed_num_label.add_theme_color_override("font_color", NEON)
	row.add_child(_offset_slot(speed_num_label, -3.0))

	var unit := _label("km/h", 16)
	row.add_child(_offset_slot(unit, -1.0))

	# Main speed bar, with quarter ticks for a techy read.
	var bar_root := Control.new()
	bar_root.custom_minimum_size = Vector2(BAR_WIDTH, 12)
	column.add_child(bar_root)

	var track := ColorRect.new()
	track.color = Color(NEON, 0.12)
	track.position = Vector2(0, 1 - 10)
	track.size = Vector2(BAR_WIDTH, 10)
	bar_root.add_child(track)

	for i in range(1, 4):
		var tick := ColorRect.new()
		tick.color = Color(0.02, 0.06, 0.10, 0.9)
		tick.position = Vector2(BAR_WIDTH * float(i) / 4.0, 1 - 10)
		tick.size = Vector2(1, 10)
		bar_root.add_child(tick)

	speed_fill = ColorRect.new()
	speed_fill.color = NEON
	speed_fill.position = Vector2(0, 1 - 10)
	speed_fill.size = Vector2(0, 10)
	bar_root.add_child(speed_fill)

	od_root.visible = false


func _build_toast() -> void:
	toast_label = _label("", 22)
	toast_label.visible = false
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_label.offset_top = 84
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_stylebox_override("normal", _neon_pill())
	toast_label.add_theme_color_override(
		"font_outline_color",
		Color(0, 0, 0, 0.5)
	)
	toast_label.add_theme_constant_override("outline_size", 2)
	add_child(toast_label)


# ------------------------------------------------------------
# Per-frame updates
# ------------------------------------------------------------

## Updates the HUD with the current race statistics and player state.
## Handles life bars, shield status, speed and overdrive display.
func update_stats(
	distance_m: float,
	speed: int,
	cash: int,
	lives: int,
	shield: bool,
	ammo: int,
	overdrive_bonus: float = 0.0,
	shield_remaining := -1.0
) -> void:
	distance_label.text = "%d m" % int(distance_m)
	cash_label.text = str(cash)
	ammo_label.text = str(ammo)

	# Fill one bar for each remaining life and dim the unused slots.
	var lives_shown := mini(lives, life_bars.size())
	for life_index in range(life_bars.size()):
		var bar := life_bars[life_index]
		if life_index < lives_shown:
			bar.color = LIFE
		else:
			bar.color = Color(LIFE, 0.16)

	# Show the shield model only while the shield is active.
	shield_icon.visible = shield

	# Show a countdown during the final three seconds of the shield.
	# When it expires, display a temporary "SHIELD OFF!" flash.
	if shield:
		shield_last_active = true
		if shield_remaining >= 0.0 and int(ceil(shield_remaining)) <= 3:
			shield_count_label.visible = true
			shield_count_label.text = "⛨ SHIELD OFF IN %d" % int(
				ceil(shield_remaining)
			)
			shield_count_label.add_theme_color_override(
				"font_color", NEON
			)
		else:
			# Hide the countdown while the shield has sufficient time remaining.
			shield_count_label.visible = false
	else:
		if shield_last_active:
			# Detect the shield expiry transition and start the warning flash.
			shield_last_active = false
			shield_off_flash = 1.2
			shield_count_label.visible = true
			shield_count_label.text = "⛨ SHIELD OFF!"
			shield_count_label.add_theme_color_override(
				"font_color", NEON_HOT
			)
		elif shield_off_flash <= 0.0:
			shield_count_label.visible = false

	speed_num_label.text = str(speed)

	# Normal speed bar, scaled against the regular maximum speed.
	var cap_kmh := RaceSession.MAX_SPEED * 3.6
	speed_fill.size.x = BAR_WIDTH * clampf(speed / cap_kmh, 0.0, 1.0)

	# Display the overdrive bonus separately from normal speed.
	# Highlight the speed readout while overdrive is active.
	var od_active := overdrive_bonus > 0.0
	od_root.visible = od_active
	if od_active:
		od_fill.size.x = BAR_WIDTH * clampf(
			overdrive_bonus / OD_DISPLAY_MAX, 0.0, 1.0
		)
		speed_num_label.add_theme_color_override(
			"font_color", NEON_HOT
		)
	else:
		speed_num_label.add_theme_color_override(
			"font_color", NEON
		)


## Builds the SUPER SHOT charge indicator at the bottom of the screen.
## The fill and caption change colour when the shot becomes ready.
func _build_charge_bar() -> void:
	charge_root = VBoxContainer.new()
	charge_root.alignment = BoxContainer.ALIGNMENT_CENTER
	charge_root.add_theme_constant_override("separation", 5)
	charge_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	charge_root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	charge_root.grow_vertical = Control.GROW_DIRECTION_BEGIN
	charge_root.offset_bottom = -16.0
	charge_root.visible = false
	add_child(charge_root)

	charge_caption = _label("", 20)
	charge_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER 
	charge_caption.add_theme_color_override("font_color", NEON)
	charge_root.add_child(charge_caption)

	charge_bar = ColorRect.new()
	charge_bar.color = Color(0.02, 0.05, 0.08, 0.85)
	charge_bar.custom_minimum_size = Vector2(440, 18)
	charge_root.add_child(charge_bar)

	# Adjust the right offset to represent the current charge fraction.
	charge_fill = ColorRect.new()
	charge_fill.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	charge_fill.offset_left = 2.0
	charge_fill.offset_top = 2.0
	charge_fill.offset_bottom = -2.0
	charge_fill.offset_right = 2.0
	charge_fill.color = NEON
	charge_bar.add_child(charge_fill)


## Builds the shield expiry countdown above the SUPER SHOT charge bar.
## Displays a final countdown followed by a temporary expiry warning.
func _build_shield_countdown() -> void:
	shield_count_label = _label("", 26)
	shield_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shield_count_label.add_theme_color_override("font_color", NEON)
	# Keep the countdown readable against the moving game world.
	shield_count_label.add_theme_color_override(
		"font_outline_color", Color(0.0, 0.05, 0.08, 0.85)
	)
	shield_count_label.add_theme_constant_override("outline_size", 6)
	shield_count_label.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_BOTTOM
	)
	shield_count_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	shield_count_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Place the countdown above the charge indicator to avoid overlap.
	shield_count_label.offset_bottom = -78.0
	shield_count_label.visible = false
	add_child(shield_count_label)


## fraction < 0 hides the readout; 0..1 fills the bar; >= 1 = READY.
func show_super_charge(fraction: float) -> void:
	charge_root.visible = fraction >= 0.0
	if fraction < 0.0:
		return
	var t := clampf(fraction, 0.0, 1.0)
	var is_ready := t >= 1.0
	charge_fill.offset_right = 2.0 + 436.0 * t
	charge_fill.color = NEON_HOT if is_ready else NEON
	charge_caption.text = (
		"⚡ SUPER SHOT READY — RELEASE TO FIRE!"
		if is_ready
		else "SUPER SHOT CHARGING..."
	)
	charge_caption.add_theme_color_override(
		"font_color", NEON_HOT if is_ready else NEON
	)


func show_toast(message: String, duration: float = 1.8) -> void:
	toast_label.text = message + "  " # two empty spaces, quick-fix the non-centered placement
	toast_label.visible = true
	toast_remaining = duration

## Updates time-dependent HUD effects and animations.
func _process(delta: float) -> void:
	# Keep the radial overlay circular when the viewport is resized.
	if speed_lines_mat != null:
		var vs := get_viewport().get_visible_rect().size
		speed_lines_mat.set_shader_parameter(
			"aspect", vs.x / maxf(1.0, vs.y)
		)
	if toast_remaining > 0.0:
		toast_remaining = maxf(0.0, toast_remaining - delta)
		if toast_remaining == 0.0:
			toast_label.visible = false

	# Rotate the 3D pickup icons continuously.
	for model in [coin_model, ammo_model, shield_model]:
		if is_instance_valid(model):
			model.rotate_y(delta * 3.0)

	# Hide the expiry flash when its timer runs out, unless a new
	# shield has become active.
	if shield_off_flash > 0.0:
		shield_off_flash = maxf(0.0, shield_off_flash - delta)
		if shield_off_flash == 0.0 and not shield_last_active:
			shield_count_label.visible = false

	# Pulse the overdrive caption while the bonus is active.
	if od_root != null and od_root.visible:
		od_label.modulate.a = 0.65 + 0.35 * sin(
			Time.get_ticks_msec() / 1000.0 * 6.0
		)


## Clears the shield countdown and expiry flash.
## Called at the start of a new run to prevent stale HUD state
## from carrying over from the previous run.
func reset_shield_countdown() -> void:
	shield_last_active = false
	shield_off_flash = 0.0
	if shield_count_label != null:
		shield_count_label.visible = false


# ------------------------------------------------------------
# Styling helpers
# ------------------------------------------------------------

func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_font_override("font", _hud_font)
	label.add_theme_color_override("font_color", Color.WHITE)
	return label


## Wraps a label to apply pixel offsets inside a container row.
##
## Containers control their children's positions, so ordinary
## Control offsets cannot be used. Positive margins shift the label,
## while matching negative margins preserve the wrapper's size.
func _offset_slot(label: Label, nudge: float, x := 0.0) -> Control:
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_top", int(nudge))
	wrap.add_theme_constant_override("margin_bottom", -int(nudge))
	wrap.add_theme_constant_override("margin_left", int(x))
	wrap.add_theme_constant_override("margin_right", -int(x))
	wrap.add_child(label)
	return wrap


func _neon_pill() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.01, 0.03, 0.06, 0.74)
	style.border_color = Color(NEON, 0.45)
	style.set_border_width_all(1)
	style.shadow_color = Color(NEON, 0.25)
	style.shadow_size = 8
	style.set_corner_radius_all(4)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


func _neon_panel() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.01, 0.03, 0.06, 0.74)
	style.border_color = Color(NEON, 0.5)
	style.set_border_width_all(1)
	style.shadow_color = Color(NEON, 0.3)
	style.shadow_size = 14
	style.set_corner_radius_all(4)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 6
	style.content_margin_bottom = 8
	return style

## Creates a FontVariation with the specified italic-style shear.
func _make_font(shear: float) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.variation_transform = Transform2D(
		Vector2(1.0, shear),
		Vector2(0.0, 1.0),
		Vector2.ZERO
	)
	return font
