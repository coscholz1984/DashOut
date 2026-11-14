
class_name RaceSession
extends RefCounted
## Owns the mutable state and rules of the current race session.
## Tracks run progress, speed, lives, resources, scoring and run economy.

enum Mode { MENU, RUNNING, PAUSED, GAMEOVER, SUMMARY }

## Emitted when the run economy awards a cash bonus.
## main.gd forwards the notification to the HUD toast display.
signal cash_toast(message: String)

## Base speed model: throttle controls acceleration from MIN_SPEED
## toward MAX_SPEED, with acceleration tapering near the upper limit.
const MIN_SPEED := 12.0           # Minimum speed at zero throttle (m/s).
const SPEED_PER_THROTTLE := 25.0  # Speed gained per throttle unit (m/s).
const MAX_SPEED := 110.0          # Normal maximum speed (m/s).
## Throttle value corresponding to MAX_SPEED, derived automatically
## from the other speed constants.
const MAX_THROTTLE := (MAX_SPEED - MIN_SPEED) / SPEED_PER_THROTTLE
## Controls how strongly acceleration decreases near MAX_SPEED.
const ACCEL_TAPER := 0.999

## Overdrive allows speed to exceed the normal throttle limit.
## The bonus grows while accelerating at the normal speed cap,
## but is lost when acceleration is released or the player crashes.
## Overdrive speed contributes to the high score.
const OVERDRIVE_RATE := 0.0278 * 2.5  # Overdrive gain per second (m/s).

## Soft upper bound for overdrive speed, keeping speed-dependent
## world calculations within a practical range.
const OVERDRIVE_MAX_SPEED := 1388.9  # m/s (~5000 km/h)
## Maximum overdrive bonus above the normal speed limit.
const OVERDRIVE_MAX_BONUS := OVERDRIVE_MAX_SPEED - MAX_SPEED

## Current overdrive bonus in m/s, added to the normal speed limit.
var overdrive_speed := 0.0

## Lives available during a run. Crashes consume lives, while
## life pickups can restore them up to MAX_LIVES.
## Lives are reset for each run and are not persisted.
const START_LIVES := 3
const MAX_LIVES := 9

## Starting ammunition before applying the Ammo Depot upgrade.
const START_AMMO := 15

## Base shield pickup duration before applying the upgrade bonus.
const SHIELD_DURATION_SEC := 3.0

## Additional effect granted by each upgrade tier.
## Applied using the corresponding upgrade level in SaveManager.
const UPGRADE_LIVES_PER_TIER := 1
const UPGRADE_AMMO_PER_TIER := 5
const UPGRADE_SHIELD_SEC_PER_TIER := 2.0

## Multipliers used by compute_score() for the different run achievements.
const SCORE_PER_KMH := 15.0            # Maximum speed reached.
const SCORE_PER_CASH := 2.0            # Cash earned during the run.
const SCORE_PER_COLLECTION_PCT := 25.0 # Percentage of pickups collected.
const SCORE_PER_KILL := 100.0          # Traffic ships destroyed by weapons.

var mode: int = Mode.MENU
var distance_travelled := 0.0
var world_speed := 0.0
var speed_kmh := 0
var throttle := 1.0
var lane := 1
var lives := 3
var run_cash := 0
var ammo := 0
var next_milestone := 500.0
var speed_level := 0
var fire_cooldown := 0.0
var shake := 0.0
var shield_until_msec := 0

## Per-run statistics used to calculate and record achievements.
var max_speed_kmh := 0
var pickups_spawned := 0
var pickups_collected := 0
var cars_destroyed := 0
var continues_used := 0


func begin_run() -> void:
	mode = Mode.RUNNING
	distance_travelled = 0.0
	world_speed = 0.0
	speed_kmh = 0
	throttle = 1.0
	lane = 1
	overdrive_speed = 0.0
	# Apply the starting bonuses from owned upgrades.
	lives = START_LIVES + (
		SaveManager.get_upgrade_level("hull") * UPGRADE_LIVES_PER_TIER
	)
	ammo = START_AMMO + (
		SaveManager.get_upgrade_level("ammo_depot") * UPGRADE_AMMO_PER_TIER
	)
	run_cash = 0
	next_milestone = 500.0
	speed_level = 0
	fire_cooldown = 0.0
	shake = 0.0
	shield_until_msec = 0
	max_speed_kmh = 0
	pickups_spawned = 0
	pickups_collected = 0
	cars_destroyed = 0
	continues_used = 0


## Share of spawned pickups the player caught, in whole percent.
func collection_pct() -> int:
	if pickups_spawned <= 0:
		return 0
	return roundi(
		100.0 * float(pickups_collected) / float(pickups_spawned)
	)


## Calculates the total run score from distance, top speed, cash,
## pickup collection rate and destroyed traffic.
## Lost lives do not directly reduce the score.
func compute_score() -> int:
	var score := (
		distance_travelled
		+ float(max_speed_kmh) * SCORE_PER_KMH
		+ float(run_cash) * SCORE_PER_CASH
		+ float(collection_pct()) * SCORE_PER_COLLECTION_PCT
		+ float(cars_destroyed) * SCORE_PER_KILL
	)
	return maxi(0, roundi(score))


## Processes distance milestones and speed-level bonuses.
## Rewards are added to both the run total and persistent cash.
## Notifications are emitted through cash_toast for the HUD.
func step_economy() -> void:
	if distance_travelled >= next_milestone:
		var bonus := 50 + int(next_milestone / 500.0) * 25
		run_cash += bonus
		SaveManager.data.cash += bonus
		cash_toast.emit("🏁 %d m survived! +💵 %d" % [next_milestone, bonus])
		next_milestone += 500.0

	var level := int((speed_kmh - 90) / 30)
	if level > speed_level and speed_kmh > 90:
		speed_level = level
		var bonus := level * 40
		run_cash += bonus
		SaveManager.data.cash += bonus
		cash_toast.emit("⚡ %d km/h! +💵 %d" % [speed_kmh, bonus])
