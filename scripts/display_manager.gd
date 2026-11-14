class_name DisplayManager
extends Node
## Manages window mode, resolution, positioning and render-surface updates.
## Settings are persisted by SaveManager; this node only applies them.
## Created in main.gd and not registered as an autoload.

func _ready() -> void:
	# Apply the persisted window state on startup.
	set_fullscreen(SaveManager.data.fullscreen)


func toggle_fullscreen() -> void:
	set_fullscreen(
		DisplayServer.window_get_mode()
		!= DisplayServer.WINDOW_MODE_FULLSCREEN
	)


## Applies the requested window mode and persists the setting.
func set_fullscreen(enabled: bool) -> void:
	SaveManager.data.fullscreen = enabled
	SaveManager.persist()

	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var target := _resolution_vector(SaveManager.data.resolution)
		if target.x > 0:
			DisplayServer.window_set_size(target)
			_center_window()
			_refresh_render_surface(target)


## Applies and persists the selected resolution.
func apply_resolution(resolution: String) -> void:
	SaveManager.data.resolution = resolution
	SaveManager.persist()

	if SaveManager.data.fullscreen:
		# The selected resolution takes effect when leaving fullscreen.
		return

	var target := _resolution_vector(resolution)
	if target.x > 0:
		DisplayServer.window_set_size(target)
		_center_window()
		_refresh_render_surface(target)


func _resolution_vector(resolution: String) -> Vector2i:
	var parts := str(resolution).split("x")
	if parts.size() == 2:
		return Vector2i(int(parts[0]), int(parts[1]))
	return Vector2i.ZERO


## Centres the window on the currently selected screen.
func _center_window() -> void:
	var screen := DisplayServer.window_get_current_screen()
	var screen_size := DisplayServer.screen_get_size(screen)
	var window_size := DisplayServer.window_get_size()
	DisplayServer.window_set_position(
		DisplayServer.screen_get_position(screen)
		+ (screen_size - window_size) / 2
	)


## Forces the render surface to update after a window resize.
##
## Some platforms or drivers do not correctly resize the render surface
## after changing the window size or mode. Temporarily increasing the
## window size and restoring it triggers a resize event that refreshes it.
## bug (godotengine/godot#105747)
##
## Uses the intended target size rather than reading back the current
## window size, which may not yet reflect the previous resize request.
func _refresh_render_surface(target: Vector2i) -> void:
	await get_tree().process_frame
	# Fullscreen mode already refreshes the render surface.
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		return
	# Fall back to the current size if the target is invalid or too small.
	if target.x <= 4 or target.y <= 4:
		target = DisplayServer.window_get_size()
	DisplayServer.window_set_size(target + Vector2i(2, 2))
	await get_tree().process_frame
	DisplayServer.window_set_size(target)
	_center_window()
