
class_name MenuUI
extends Node
## Builds and manages the game's menu panels, including the main and
## pause menus, options, high scores, help, game over and run summary.
## Emits signals for main.gd to handle; persistent settings are
## managed through SaveManager.

## Shared minimum width of the main menu, options and high-scores
## panels, so the three windows read as one consistent size.
const PANEL_WIDTH := 420.0
## Wider layout for the two-column HOW TO PLAY panel.
const HELP_WIDTH := 900.0

## Animated neon shader for the front layer of the DashOut title.
## Uses SCREEN_UV for a horizontal light sweep across the label,
## with a subtle pulse and flicker.
const TITLE_SHADER := "
shader_type canvas_item;
uniform float sweep_speed = 0.35;
uniform float band_width = 0.16;
uniform vec3 sweep_color = vec3(0.133, 0.827, 0.933); // #22d3ee
uniform vec3 base_tint = vec3(0.95, 1.0, 1.0);
void fragment() {
\tvec4 glyph = texture(TEXTURE, UV);
\tfloat sweep = fract(TIME * sweep_speed);
\tfloat d = abs(SCREEN_UV.x - sweep);
\tfloat band = smoothstep(band_width, 0.0, d);
\t// Keep the front layer consistently brighter than the dark
\t// back layer to preserve the title's extruded appearance.
\tfloat pulse = 0.92 + 0.08 * sin(TIME * 2.2);
\tfloat flicker = step(0.985, fract(sin(floor(TIME * 14.0)) * 43758.5453));
\tvec3 rgb = glyph.rgb * base_tint * pulse * (1.0 - 0.15 * flicker);
\t// Blend the travelling highlight into the glyph colour.
\trgb = mix(rgb, sweep_color, band * glyph.a * 0.9);
\tCOLOR = vec4(rgb, glyph.a);
}"

## Creates the ShaderMaterial used by the animated title label.
static func title_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = TITLE_SHADER
	mat.shader = shader
	return mat

# ------------------------------------------------------------
# Signals
# ------------------------------------------------------------

## Requests forwarded to main.gd for handling game state and actions.
signal start_requested
signal resume_requested
signal garage_requested
signal menu_requested
signal fullscreen_requested
signal full_shadows_requested
signal engine_hum_requested
signal debug_items_requested
signal resolution_selected(resolution: String)
signal quit_requested
signal quit_race_requested
signal reset_requested
signal summary_menu_requested
signal summary_play_again_requested


# ------------------------------------------------------------
# UI nodes
# ------------------------------------------------------------

var menu_layer: CanvasLayer
var go_layer: CanvasLayer

var main_menu_panel: PanelContainer
var options_panel: PanelContainer

var menu_title: Label
## Lit front layer of the two-layer title, carrying the sweep shader.
var menu_title_front: Label
var game_over_label: Label

var menu_start_btn: Button
var menu_resume_btn: Button
var menu_garage_btn: Button
var fs_btn: Button
var full_shadows_btn: Button
var engine_hum_btn: Button
var debug_items_btn: Button
var options_btn: Button
var quit_race_btn: Button

var go_menu_btn: Button

var music_slider: HSlider
var sfx_slider: HSlider

var music_value_label: Label
var sfx_value_label: Label

var resolution_select: OptionButton
var options_back_btn: Button

var name_edit: LineEdit
var scores_btn: Button
var scores_panel: PanelContainer
var scores_list: VBoxContainer
var scores_back_btn: Button

var help_btn: Button
var help_panel: PanelContainer
var help_back_btn: Button

var debug_reset_btn: Button

var summary_panel: PanelContainer
var summary_title_label: Label
var summary_stats_label: Label
var summary_bank_label: Label
var summary_place_label: Label
var summary_menu_btn: Button
var summary_play_btn: Button

## Faux-bold font variation used by the title.
var _title_font: FontVariation

## Faux-italic font variation used by buttons.
var _button_font: FontVariation


# ------------------------------------------------------------
# Initialization
# ------------------------------------------------------------

func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	menu_layer = CanvasLayer.new()
	add_child(menu_layer)

	# Create shared font variations from the default font.
	_title_font = _make_variation(0.4, 0.0)
	_button_font = _make_variation(0.0, 0.22)

	# --------------------------------------------------------
	# Main menu panel
	# --------------------------------------------------------

	main_menu_panel = PanelContainer.new()
	main_menu_panel.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER
	)
	main_menu_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	main_menu_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	main_menu_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)

	var panel_style := _create_panel_style()

	main_menu_panel.add_theme_stylebox_override(
		"panel",
		panel_style
	)

	menu_layer.add_child(main_menu_panel)

	var menu_container := VBoxContainer.new()
	menu_container.add_theme_constant_override(
		"separation",
		20
	)
	main_menu_panel.add_child(menu_container)

	# Build the title from two overlapping labels. The dark rear
	# layer creates the extrusion effect; the bright front layer
	# carries the animated neon shader.
	menu_title = _label("DashOut", 44)
	menu_title.add_theme_font_override("font", _title_font)
	menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Keep the rear layer dark to create contrast with the front.
	menu_title.add_theme_color_override(
		"font_color", Color(0.10, 0.14, 0.20)
	)
	menu_title.add_theme_color_override(
		"font_outline_color", Color(0.05, 0.30, 0.38)
	)
	menu_title.add_theme_constant_override("outline_size", 6)

	# Bright neon styling for the front layer.
	menu_title_front = _label("DashOut", 44)
	menu_title_front.add_theme_font_override("font", _title_font)
	menu_title_front.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_title_front.add_theme_color_override(
		"font_color", Color(0.95, 1.0, 1.0)
	)
	menu_title_front.add_theme_color_override(
		"font_outline_color", Color("22d3ee")
	)
	menu_title_front.add_theme_constant_override("outline_size", 6)
	menu_title_front.add_theme_color_override(
		"font_shadow_color", Color("22d3ee")
	)
	menu_title_front.add_theme_constant_override("shadow_offset_x", 2)
	menu_title_front.add_theme_constant_override("shadow_offset_y", 2)
	# Apply the animated shader only to the front layer.
	# The rear layer retains its static dark appearance.
	menu_title_front.material = title_material()
	# Draw the front layer above its parent and offset it slightly
	# to create the appearance of extruded lettering.
	menu_title_front.position = Vector2(-4, -4)
	menu_title.add_child(menu_title_front)
	menu_container.add_child(menu_title)

	# Resume
	menu_resume_btn = Button.new()
	menu_resume_btn.text = "RESUME RACE"
	menu_resume_btn.custom_minimum_size = Vector2(200, 0)
	menu_resume_btn.visible = false
	menu_resume_btn.pressed.connect(_on_resume_pressed)
	menu_container.add_child(menu_resume_btn)

	# Start / Restart
	menu_start_btn = Button.new()
	menu_start_btn.text = "START RACE"
	menu_start_btn.custom_minimum_size = Vector2(200, 0)
	menu_start_btn.pressed.connect(_on_start_pressed)
	menu_container.add_child(menu_start_btn)

	# Garage
	menu_garage_btn = Button.new()
	menu_garage_btn.text = "GARAGE"
	menu_garage_btn.custom_minimum_size = Vector2(200, 0)
	menu_garage_btn.pressed.connect(_on_garage_pressed)
	menu_container.add_child(menu_garage_btn)

	# Quit (pause menu only): end the run and return to the menu.
	quit_race_btn = Button.new()
	quit_race_btn.text = "QUIT RACE"
	quit_race_btn.custom_minimum_size = Vector2(200, 0)
	quit_race_btn.visible = false
	quit_race_btn.pressed.connect(_on_quit_race_pressed)
	menu_container.add_child(quit_race_btn)

	# Options
	options_btn = Button.new()
	options_btn.text = "OPTIONS"
	options_btn.custom_minimum_size = Vector2(200, 0)
	options_btn.pressed.connect(_open_options)
	menu_container.add_child(options_btn)

	# Scores
	scores_btn = Button.new()
	scores_btn.text = "SCORES"
	scores_btn.custom_minimum_size = Vector2(200, 0)
	scores_btn.pressed.connect(_open_scores)
	menu_container.add_child(scores_btn)

	# Help — the "HOW TO PLAY" panel with the game mechanics.
	help_btn = Button.new()
	help_btn.text = "HOW TO PLAY"
	help_btn.custom_minimum_size = Vector2(200, 0)
	help_btn.pressed.connect(_open_help)
	menu_container.add_child(help_btn)

	# Quit
	var quit_btn := Button.new()
	quit_btn.text = "QUIT"
	quit_btn.custom_minimum_size = Vector2(200, 0)
	quit_btn.pressed.connect(_on_quit_pressed)
	menu_container.add_child(quit_btn)

	# DEBUG: reset the whole save to initial conditions.
	debug_reset_btn = Button.new()
	debug_reset_btn.text = "RESET DATA"
	debug_reset_btn.custom_minimum_size = Vector2(200, 0)
	debug_reset_btn.visible = false
	debug_reset_btn.pressed.connect(_on_debug_reset_pressed)
	menu_container.add_child(debug_reset_btn)

	# --------------------------------------------------------
	# Options panel
	# --------------------------------------------------------

	options_panel = PanelContainer.new()
	options_panel.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER
	)
	options_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	options_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	options_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)

	options_panel.add_theme_stylebox_override(
		"panel",
		panel_style.duplicate()
	)

	options_panel.visible = false
	menu_layer.add_child(options_panel)

	var options_container := VBoxContainer.new()
	options_container.add_theme_constant_override(
		"separation",
		14
	)
	options_panel.add_child(options_container)

	# Options title
	var options_title := _neon_title("OPTIONS", 28)
	options_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	options_container.add_child(options_title)

	# --------------------------------------------------------
	# Music volume
	# --------------------------------------------------------

	music_value_label = _label(
		"MUSIC VOLUME: 100%",
		16
	)
	options_container.add_child(music_value_label)

	music_slider = HSlider.new()
	music_slider.custom_minimum_size = Vector2(260, 24)
	music_slider.min_value = 0
	music_slider.max_value = 100
	music_slider.step = 1
	music_slider.value = SaveManager.data.music_volume
	music_slider.value_changed.connect(
		_on_music_volume_changed
	)
	options_container.add_child(music_slider)

	# --------------------------------------------------------
	# SFX volume
	# --------------------------------------------------------

	sfx_value_label = _label(
		"SFX VOLUME: 100%",
		16
	)
	options_container.add_child(sfx_value_label)

	sfx_slider = HSlider.new()
	sfx_slider.custom_minimum_size = Vector2(260, 24)
	sfx_slider.min_value = 0
	sfx_slider.max_value = 100
	sfx_slider.step = 1
	sfx_slider.value = SaveManager.data.sfx_volume
	sfx_slider.value_changed.connect(
		_on_sfx_volume_changed
	)
	options_container.add_child(sfx_slider)

	# --------------------------------------------------------
	# Player name (used for the high score list)
	# --------------------------------------------------------

	var name_label := _label("PLAYER NAME", 16)
	options_container.add_child(name_label)

	name_edit = LineEdit.new()
	name_edit.text = str(SaveManager.data.player_name)
	name_edit.max_length = 12
	name_edit.custom_minimum_size = Vector2(260, 0)
	name_edit.text_changed.connect(_on_name_changed)
	options_container.add_child(name_edit)

	# --------------------------------------------------------
	# Resolution
	# --------------------------------------------------------

	var resolution_label := _label("RESOLUTION", 16)
	options_container.add_child(resolution_label)

	resolution_select = OptionButton.new()
	resolution_select.custom_minimum_size = Vector2(260, 0)

	var resolutions := [
		"940x580",
		"1280x720",
		"1600x900",
		"1920x1080",
		"2560x1440"
	]

	var selected_resolution := 0

	for i in resolutions.size():
		resolution_select.add_item(resolutions[i])

		if resolutions[i] == SaveManager.data.resolution:
			selected_resolution = i

	resolution_select.select(selected_resolution)

	resolution_select.item_selected.connect(
		_on_resolution_selected
	)

	options_container.add_child(resolution_select)

	# --------------------------------------------------------
	# Fullscreen
	# --------------------------------------------------------

	fs_btn = Button.new()
	fs_btn.custom_minimum_size = Vector2(260, 0)
	fs_btn.pressed.connect(_on_fullscreen_pressed)
	options_container.add_child(fs_btn)

	# --------------------------------------------------------
	# Shadow settings
	# --------------------------------------------------------

	# The world sun always casts shadows for buildings and scenery.
	# Full shadows additionally enables real shadows for ships and
	# pickups, replacing their blob-shadow fallback.
	full_shadows_btn = Button.new()
	full_shadows_btn.custom_minimum_size = Vector2(260, 0)
	full_shadows_btn.pressed.connect(_on_full_shadows_pressed)
	options_container.add_child(full_shadows_btn)

	# Allow the player to toggle the background engine hum.
	engine_hum_btn = Button.new()
	engine_hum_btn.custom_minimum_size = Vector2(260, 0)
	engine_hum_btn.pressed.connect(_on_engine_hum_pressed)
	options_container.add_child(engine_hum_btn)

	# Toggle debug pickup placement for testing pickup models.
	debug_items_btn = Button.new()
	debug_items_btn.custom_minimum_size = Vector2(260, 0)
	debug_items_btn.pressed.connect(_on_debug_items_pressed)
	options_container.add_child(debug_items_btn)

	# --------------------------------------------------------
	# Back button
	# --------------------------------------------------------

	options_back_btn = Button.new()
	options_back_btn.text = "BACK"
	options_back_btn.custom_minimum_size = Vector2(200, 0)
	options_back_btn.pressed.connect(_close_options)
	options_container.add_child(options_back_btn)

	# Apply saved audio settings.
	AudioManager.set_music_volume(
		int(SaveManager.data.music_volume)
	)

	AudioManager.set_sfx_volume(
		int(SaveManager.data.sfx_volume)
	)

	# --------------------------------------------------------
	# High scores panel
	# --------------------------------------------------------

	scores_panel = PanelContainer.new()
	scores_panel.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER
	)
	scores_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	scores_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	scores_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)

	scores_panel.add_theme_stylebox_override(
		"panel",
		panel_style.duplicate()
	)

	scores_panel.visible = false
	menu_layer.add_child(scores_panel)

	var scores_container := VBoxContainer.new()
	scores_container.add_theme_constant_override(
		"separation",
		10
	)
	scores_panel.add_child(scores_container)

	var scores_title := _neon_title("HIGH SCORES", 28)
	scores_container.add_child(scores_title)

	scores_list = VBoxContainer.new()
	scores_container.add_child(scores_list)

	scores_back_btn = Button.new()
	scores_back_btn.text = "BACK"
	scores_back_btn.custom_minimum_size = Vector2(200, 0)
	scores_back_btn.pressed.connect(_close_scores)
	scores_container.add_child(scores_back_btn)

	# --------------------------------------------------------
	# Help panel — the game mechanics, WIDE two-column layout
	# --------------------------------------------------------

	help_panel = PanelContainer.new()
	help_panel.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER
	)
	help_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	# Use a wide layout to accommodate the two help-text columns.
	help_panel.custom_minimum_size = Vector2(HELP_WIDTH, 0)

	help_panel.add_theme_stylebox_override(
		"panel",
		panel_style.duplicate()
	)

	help_panel.visible = false
	menu_layer.add_child(help_panel)

	var help_container := VBoxContainer.new()
	help_container.add_theme_constant_override(
		"separation",
		10
	)
	help_panel.add_child(help_container)

	var help_title := _neon_title("HOW TO PLAY", 28)
	help_container.add_child(help_title)

	# Split the instructions into two rich-text columns.
	# BBCode provides styled section headings without separate labels.
	var help_columns := HBoxContainer.new()
	help_columns.add_theme_constant_override(
		"separation",
		28
	)
	help_container.add_child(help_columns)

	var _make_help_col := func(bb: String) -> RichTextLabel:
		var col := RichTextLabel.new()
		col.bbcode_enabled = true
		col.fit_content = true
		col.scroll_active = false
		col.custom_minimum_size = Vector2(
			(HELP_WIDTH - 60) / 2.0, 0
		)
		col.add_theme_color_override(
			"default_color", Color(0.85, 0.95, 1.0)
		)
		col.text = bb
		return col

	# Specify the return type explicitly because Callable.call()
	# returns Variant and strict typing treats inferred Variants as errors.
	var help_left: RichTextLabel = _make_help_col.call(
		"""[color=#22d3ee][b]FLYING[/b][/color]
LEFT / RIGHT (or A / D) flip lanes. UP / DOWN (or W / S) accelerate and brake. At the ~396 km/h cap, KEEP holding UP to push into [color=#ff5df2]OVERDRIVE[/color] — the speed creeps up and up… until you hit something.

[color=#22d3ee][b]GUNS[/b][/color]
TAP SPACE to fire a single plasma bolt. HOLD SPACE to charge the [color=#ff5df2]SUPER SHOT[/color] — release to send a wave that wipes out all traffic ahead.

[color=#22d3ee][b]CRASHES[/b][/color]
Hitting traffic or a closing lane end costs one HULL BAR. Lose them all and the run is over — in flames. After a crash you get a short recovery shield against traffic.

[color=#22d3ee][b]SHIELDS[/b][/color]
The ⛨ pickup wraps your ship in an energy dome: While active, the dome protects you from traffic collisions and lets you ram traffic ships. Road-boundary violations remain lethal."""
	)
	help_columns.add_child(help_left)

	var help_right: RichTextLabel = _make_help_col.call(
		"""[color=#22d3ee][b]PICKUPS[/b][/color]
💵 credits · ❤ +1 hull bar (up to 9) · 🔫 gun + ammo · ⛨ shield.

[color=#22d3ee][b]RISK PAYS[/b][/color]
Changing lanes just before your lane closes or squeezing past nearby traffic can earn bonus credits. The bonus is paid only if you survive the confirmation period.

[color=#22d3ee][b]EARN & UPGRADE[/b][/color]
Distance milestones, speed levels, pickups and kills all pay credits. Spend them in the GARAGE on ship models, scenery skins and tiered upgrades — more start lives, more ammo, longer shields. Effect colours (exhaust, shot, overdrive) are free customization on the EFFECTS tab.

[color=#22d3ee][b]THE GOAL[/b][/color]
Buy every upgrade, then see how far you can break the speed record!"""
	)
	help_columns.add_child(help_right)

	help_back_btn = Button.new()
	help_back_btn.text = "BACK"
	help_back_btn.custom_minimum_size = Vector2(200, 0)
	help_back_btn.pressed.connect(_close_help)
	help_container.add_child(help_back_btn)

	# --------------------------------------------------------
	# Game-over panel
	# --------------------------------------------------------

	go_layer = CanvasLayer.new()
	add_child(go_layer)
	go_layer.visible = false

	var game_over_panel := PanelContainer.new()
	game_over_panel.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER
	)
	game_over_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	game_over_panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	game_over_panel.add_theme_stylebox_override(
		"panel",
		panel_style.duplicate()
	)

	go_layer.add_child(game_over_panel)

	var game_over_container := VBoxContainer.new()
	game_over_container.add_theme_constant_override(
		"separation",
		16
	)
	game_over_panel.add_child(game_over_container)

	game_over_label = _label("0 m", 24)
	game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_container.add_child(game_over_label)

	# Back to menu
	go_menu_btn = Button.new()
	go_menu_btn.text = "BACK TO MENU"
	go_menu_btn.custom_minimum_size = Vector2(200, 0)
	go_menu_btn.pressed.connect(_on_menu_pressed)
	game_over_container.add_child(go_menu_btn)

	# --------------------------------------------------------
	# Run summary panel (shown before returning to the menu)
	# --------------------------------------------------------

	summary_panel = PanelContainer.new()
	summary_panel.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER
	)
	summary_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	summary_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	summary_panel.add_theme_stylebox_override(
		"panel",
		panel_style.duplicate()
	)
	summary_panel.visible = false
	menu_layer.add_child(summary_panel)

	var summary_container := VBoxContainer.new()
	summary_container.add_theme_constant_override(
		"separation",
		14
	)
	summary_panel.add_child(summary_container)

	summary_title_label = _label("", 26)
	summary_title_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	summary_container.add_child(summary_title_label)

	summary_stats_label = _label("", 17)
	summary_stats_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	summary_container.add_child(summary_stats_label)

	summary_bank_label = _label("", 16)
	summary_bank_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	summary_container.add_child(summary_bank_label)

	summary_place_label = _label("", 18)
	summary_place_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	summary_container.add_child(summary_place_label)

	var summary_buttons := HBoxContainer.new()
	summary_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	summary_buttons.add_theme_constant_override(
		"separation",
		12
	)
	summary_container.add_child(summary_buttons)

	summary_play_btn = Button.new()
	summary_play_btn.text = "PLAY AGAIN"
	summary_play_btn.custom_minimum_size = Vector2(180, 0)
	summary_play_btn.pressed.connect(_on_summary_play_pressed)
	summary_buttons.add_child(summary_play_btn)

	summary_menu_btn = Button.new()
	summary_menu_btn.text = "RETURN TO MAIN MENU"
	summary_menu_btn.custom_minimum_size = Vector2(220, 0)
	summary_menu_btn.pressed.connect(_on_summary_menu_pressed)
	summary_buttons.add_child(summary_menu_btn)

	# Initial fullscreen label.
	set_fullscreen(
		DisplayServer.window_get_mode()
		== DisplayServer.WINDOW_MODE_FULLSCREEN
	)
	# Initial shadow-mode label.
	set_full_shadows(SaveManager.data.full_shadows)
	# Initial engine-hum label.
	set_engine_hum(SaveManager.data.engine_hum)
	# Initial debug-items label.
	set_debug_items(SaveManager.data.debug_items)

	# Apply shared font and interaction colours to every button
	# in the menu tree, including buttons in nested panels.
	for node in find_children("*", "Button", true, false):
		var button := node as Button
		button.add_theme_font_override("font", _button_font)
		button.add_theme_color_override(
			"font_hover_color", Color("22d3ee")
		)
		button.add_theme_color_override(
			"font_pressed_color", Color("ff5df2")
		)


# ------------------------------------------------------------
# Styling and labels
# ------------------------------------------------------------

func _create_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()

	# Mostly-opaque dark blue panel: the race behind stays visible,
	# but the text always reads clearly.
	style.bg_color = Color(0.02, 0.04, 0.08, 0.75)
	# Thin neon border plus a soft cyan glow around the panel
	# (StyleBoxFlat shadow = glow outside the box).
	style.border_color = Color("22d3ee", 0.5)
	style.set_border_width_all(1)
	style.shadow_color = Color("22d3ee", 0.3)
	style.shadow_size = 14
	style.set_corner_radius_all(4)

	style.content_margin_left = 34
	style.content_margin_right = 34
	style.content_margin_top = 34
	style.content_margin_bottom = 34

	return style


## Creates a FontVariation using the default font, with optional
## emboldening and italic-style shear.
func _make_variation(embolden: float, shear: float) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.variation_embolden = embolden
	font.variation_transform = Transform2D(
		Vector2(1.0, shear),
		Vector2(0.0, 1.0),
		Vector2.ZERO
	)
	return font


## Creates a centred neon-styled title label using the shared
## title font, cyan outline and matching drop shadow.
func _neon_title(text: String, size: int) -> Label:
	var label_node := _label(text, size)
	label_node.add_theme_font_override("font", _title_font)
	label_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_node.add_theme_color_override(
		"font_color", Color(0.95, 1.0, 1.0)
	)
	label_node.add_theme_color_override(
		"font_outline_color", Color("22d3ee")
	)
	label_node.add_theme_constant_override("outline_size", 6)
	label_node.add_theme_color_override(
		"font_shadow_color", Color("22d3ee")
	)
	label_node.add_theme_constant_override("shadow_offset_x", 2)
	label_node.add_theme_constant_override("shadow_offset_y", 2)
	return label_node


func _label(text: String, size: int) -> Label:
	var label_node := Label.new()

	label_node.text = text
	label_node.add_theme_font_size_override(
		"font_size",
		size
	)
	label_node.add_theme_color_override(
		"font_color",
		Color(1, 1, 1)
	)

	return label_node


# ------------------------------------------------------------
# Public interface
# ------------------------------------------------------------

func show_menu(is_paused: bool) -> void:
	menu_layer.visible = true
	go_layer.visible = false

	main_menu_panel.visible = true
	options_panel.visible = false
	scores_panel.visible = false
	help_panel.visible = false
	summary_panel.visible = false

	if is_paused:
		menu_title.text = "RACE PAUSED"
		menu_title_front.text = menu_title.text
		menu_title_front.position = Vector2(-14, -4)
		# The huge display size is for the game title only; the
		# pause headline keeps its original size.
		menu_title.add_theme_font_size_override("font_size", 44)
		menu_title_front.add_theme_font_size_override(
			"font_size", 44
		)

		menu_resume_btn.visible = true
		quit_race_btn.visible = true
		debug_reset_btn.visible = false

		menu_start_btn.visible = true
		menu_start_btn.text = "RESTART RACE"

		menu_resume_btn.grab_focus()

	else:
		menu_title.text = "DashOut"
		menu_title_front.text = menu_title.text
		menu_title_front.position = Vector2(-4, -4)
		# Display size for the game title on the main menu only.
		# The panel simply grows if the wider word needs more
		# room than PANEL_WIDTH.
		menu_title.add_theme_font_size_override("font_size", 88)
		menu_title_front.add_theme_font_size_override(
			"font_size", 88
		)

		menu_resume_btn.visible = false
		quit_race_btn.visible = false
		debug_reset_btn.visible = true

		menu_start_btn.visible = true
		menu_start_btn.text = "START RACE"

		menu_start_btn.grab_focus()

	_sync_fullscreen_label()


func show_game_over(
	distance: int,
	run_cash: int,
	best: int,
	score: int,
	is_record: bool
) -> void:
	menu_layer.visible = false
	go_layer.visible = true

	game_over_label.text = "%d m · +💵 %d · best %d m · score %d%s" % [
		distance,
		run_cash,
		best,
		score,
		"\n🏆 NEW RECORD!" if is_record else ""
	]

	go_menu_btn.grab_focus()


func hide_all() -> void:
	menu_layer.visible = false
	go_layer.visible = false


func set_fullscreen(enabled: bool) -> void:
	fs_btn.text = "FULLSCREEN: %s" % (
		"ON" if enabled else "OFF"
	)


func set_full_shadows(enabled: bool) -> void:
	full_shadows_btn.text = "FULL SHADOWS: %s" % (
		"ON" if enabled else "OFF"
	)


func set_engine_hum(enabled: bool) -> void:
	engine_hum_btn.text = "ENGINE HUM: %s" % (
		"ON" if enabled else "OFF"
	)


func set_debug_items(enabled: bool) -> void:
	debug_items_btn.text = "DEBUG ITEMS: %s" % (
		"ON" if enabled else "OFF"
	)


func is_options_open() -> bool:
	return (
		is_instance_valid(options_panel)
		and options_panel.visible
	)


func close_options() -> void:
	if not is_instance_valid(options_panel):
		return

	options_panel.visible = false
	main_menu_panel.visible = true

	# Persist the audio settings once, when the player leaves the panel.
	SaveManager.persist()

	if is_instance_valid(options_btn):
		options_btn.grab_focus()


func is_scores_open() -> bool:
	return (
		is_instance_valid(scores_panel)
		and scores_panel.visible
	)


func close_scores() -> void:
	if not is_instance_valid(scores_panel):
		return

	scores_panel.visible = false
	main_menu_panel.visible = true

	if is_instance_valid(scores_btn):
		scores_btn.grab_focus()


func _open_help() -> void:
	main_menu_panel.visible = false
	help_panel.visible = true
	help_back_btn.grab_focus()


func _close_help() -> void:
	help_panel.visible = false
	main_menu_panel.visible = true
	help_btn.grab_focus()


func refresh_scores() -> void:
	if not is_instance_valid(scores_list):
		return

	for child in scores_list.get_children():
		child.queue_free()

	var scores: Array = SaveManager.data.highscores

	if scores.is_empty():
		var empty_note := _label(
			"No records yet — go set one!",
			16
		)
		empty_note.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_CENTER
		)
		scores_list.add_child(empty_note)
		return

	for i in scores.size():
		var entry: Dictionary = scores[i]
		var row := (
			"%2d. %-12s %6d pts · %5d m · %3d km/h · 💵%4d · 🎯%3d%%"
			% [
				i + 1,
				str(entry.get("name", "PLAYER")),
				int(entry.get("score", 0)),
				int(entry.get("distance", 0)),
				int(entry.get("top_speed", 0)),
				int(entry.get("cash", 0)),
				int(entry.get("collection_pct", 0))
			]
		)
		var row_label := _label(row, 16)
		scores_list.add_child(row_label)


func add_menu_overlay(node: Control) -> void:
	# Allows main.gd to add GarageUI to the same CanvasLayer
	# as the main menu.
	menu_layer.add_child(node)


func focus_garage_button() -> void:
	if is_instance_valid(menu_garage_btn):
		menu_garage_btn.grab_focus()


# ------------------------------------------------------------
# Main menu button callbacks
# ------------------------------------------------------------

func _on_start_pressed() -> void:
	start_requested.emit()


func _on_resume_pressed() -> void:
	resume_requested.emit()


func _on_garage_pressed() -> void:
	garage_requested.emit()


func _on_fullscreen_pressed() -> void:
	fullscreen_requested.emit()


func _on_full_shadows_pressed() -> void:
	full_shadows_requested.emit()


func _on_engine_hum_pressed() -> void:
	engine_hum_requested.emit()


func _on_debug_items_pressed() -> void:
	debug_items_requested.emit()


func _on_quit_pressed() -> void:
	quit_requested.emit()


func _on_quit_race_pressed() -> void:
	quit_race_requested.emit()


func _on_debug_reset_pressed() -> void:
	reset_requested.emit()


func _on_summary_menu_pressed() -> void:
	summary_menu_requested.emit()


func _on_summary_play_pressed() -> void:
	summary_play_again_requested.emit()


## End-of-run summary: congratulation, total score, run stats and
## high score placement, plus RETURN TO MAIN MENU / PLAY AGAIN.
func show_run_summary(
	player_name: String,
	score: int,
	details: Dictionary,
	placement: int
) -> void:
	menu_layer.visible = true
	go_layer.visible = false
	main_menu_panel.visible = false
	options_panel.visible = false
	scores_panel.visible = false
	help_panel.visible = false
	summary_panel.visible = true

	if placement == 1:
		summary_title_label.text = (
			"Legendary run, %s! 🏆" % player_name
		)
	elif placement > 0:
		summary_title_label.text = "Great run, %s!" % player_name
	else:
		summary_title_label.text = "Good effort, %s!" % player_name

	summary_stats_label.text = (
		"SCORE: %d\n%d m · %d km/h · 💵%d · 🎯%d%% · 🔫%d"
		% [
			score,
			int(details.get("distance", 0)),
			int(details.get("top_speed", 0)),
			int(details.get("cash", 0)),
			int(details.get("collection_pct", 0)),
			int(details.get("kills", 0))
		]
	)

	summary_bank_label.text = (
		"💵 %d credits earned added to your account — current total: %d"
		% [
			int(details.get("cash", 0)),
			int(SaveManager.data.cash)
		]
	)

	if placement > 0:
		summary_place_label.text = (
			"🏆 You placed #%d on the high score list!" % placement
		)
	else:
		summary_place_label.text = (
			"Not quite enough for the high score list this time."
		)

	summary_menu_btn.grab_focus()


func _on_menu_pressed() -> void:
	menu_requested.emit()


# ------------------------------------------------------------
# Options panel
# ------------------------------------------------------------

func _open_options() -> void:
	main_menu_panel.visible = false
	options_panel.visible = true

	# The label must reflect the current mode, even if fullscreen
	# was toggled while the options panel was closed (e.g. via F11).
	_sync_fullscreen_label()

	options_back_btn.grab_focus()


func _close_options() -> void:
	close_options()


func _open_scores() -> void:
	main_menu_panel.visible = false
	scores_panel.visible = true
	refresh_scores()
	scores_back_btn.grab_focus()


func _close_scores() -> void:
	close_scores()


func _on_name_changed(new_text: String) -> void:
	# Stored immediately so a crash right after renaming still
	# credits the run to the new name; close_options() persists.
	SaveManager.data.player_name = new_text.strip_edges()


## Refreshes the name field from SaveManager.
## Ensures the displayed value reflects resets or other data changes.
func refresh_player_name() -> void:
	if is_instance_valid(name_edit):
		name_edit.text = str(SaveManager.data.player_name)


## Refreshes all options widgets from the current SaveManager data.
## Also reapplies settings whose UI controls trigger runtime updates
## when their values change.
func refresh_options() -> void:
	refresh_player_name()

	if is_instance_valid(music_slider):
		music_slider.value = int(SaveManager.data.music_volume)
	if is_instance_valid(sfx_slider):
		sfx_slider.value = int(SaveManager.data.sfx_volume)

	if is_instance_valid(music_value_label):
		music_value_label.text = (
			"MUSIC VOLUME: %d%%" % int(SaveManager.data.music_volume)
		)
	if is_instance_valid(sfx_value_label):
		sfx_value_label.text = (
			"SFX VOLUME: %d%%" % int(SaveManager.data.sfx_volume)
		)

	# Resolution dropdown.
	if is_instance_valid(resolution_select):
		var resolutions := [
			"940x580",
			"1280x720",
			"1600x900",
			"1920x1080",
			"2560x1440"
		]
		for i in resolutions.size():
			if resolutions[i] == str(SaveManager.data.resolution):
				resolution_select.select(i)
				break

	# Fullscreen button label.
	_sync_fullscreen_label()

	# Shadow-mode button label.
	set_full_shadows(SaveManager.data.full_shadows)

	# Engine-hum button label.
	set_engine_hum(SaveManager.data.engine_hum)

	# Debug-items button label.
	set_debug_items(SaveManager.data.debug_items)


func _on_music_volume_changed(value: float) -> void:
	var volume := roundi(value)

	music_value_label.text = "MUSIC VOLUME: %d%%" % volume

	# Update the active volume immediately; persistence is handled
	# when the options panel closes.
	SaveManager.data.music_volume = volume

	AudioManager.set_music_volume(volume)


func _on_sfx_volume_changed(value: float) -> void:
	var volume := roundi(value)

	sfx_value_label.text = "SFX VOLUME: %d%%" % volume

	SaveManager.data.sfx_volume = volume

	AudioManager.set_sfx_volume(volume)


func _on_resolution_selected(index: int) -> void:
	# Delegate window changes to main.gd through the selection signal.
	resolution_selected.emit(resolution_select.get_item_text(index))


# ------------------------------------------------------------
# Fullscreen label
# ------------------------------------------------------------

func _sync_fullscreen_label() -> void:
	var fullscreen := (
		DisplayServer.window_get_mode()
		== DisplayServer.WINDOW_MODE_FULLSCREEN
	)

	set_fullscreen(fullscreen)
