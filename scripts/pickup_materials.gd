
class_name PickupMaterials
extends Object
## Provides shared glow materials for the different pickup components.
## Materials use Primitives.glow_mat() for consistent lighting and
## appearance across the game.

## Creates a pickup material with the specified base, glow and rim properties.
static func _mat(base: Color, metal: float, rough: float,
		glow: Color, glow_energy: float,
		rim: Color, rim_energy: float
) -> Material:
	return Primitives.glow_mat(
		base, metal, rough, glow, glow_energy, rim, rim_energy
	)


## ❤ life pickup — hot red with a strong rim glow.
static func heart() -> Material:
	return _mat(
		Color("ff6b6b"), 0.5, 0.1,
		Color("ff6b6b"), 1.0,
		Color("ff4d6d"), 1.0
	)


## 🛡 shield pickup — cool blue with a bright cyan rim.
static func shield() -> Material:
	return _mat(
		Color("339af0"), 0.5, 0.1,
		Color("339af0"), 0.9,
		Color("a5d8ff"), 1.0
	)


## The bright emblem cross on the shield front — near-white,
## glowing a touch stronger than the panel behind it.
static func shield_emblem() -> Material:
	return _mat(
		Color("e7f5ff"), 0.35, 0.12,
		Color("a5d8ff"), 1.2,
		Color("ffffff"), 0.8
	)


## 🔫 ammo pickup — warm orange body.
static func gun() -> Material:
	return _mat(
		Color("ff922b"), 0.6, 0.12,
		Color("ff922b"), 0.8,
		Color("ffa94d"), 0.9
	)


## The gun's dark parts (trigger guard) — low glow, subtle rim.
static func gun_dark() -> Material:
	return _mat(
		Color("7a4a12"), 0.65, 0.3,
		Color(0, 0, 0, 0), 0.0,
		Color("e8590c"), 0.3
	)


## 🪙 coin — gold, metallic nearly maxed, roughness at the floor of
## what still reads as metal, and stronger glow/rim so the polish 
## flashes as it spins under the sun.
static func coin() -> Material:
	return _mat(
		Color("ffd43b"), 0.95, 0.03,
		Color("ffd43b"), 0.7,
		Color("fff3bf"), 1.1
	)


## The coin's inner core disc.
static func coin_core() -> Material:
	return _mat(
		Color("fcc419"), 0.92, 0.05,
		Color("fcc419"), 0.55,
		Color("fff3bf"), 0.9
	)
