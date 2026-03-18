extends Node

const NONE := 0
const KNIFE := 1
const GLOCK := 2
const USP := 3
const AK47 := 4
const M4A1 := 5
const AWP := 6

const WEAPONS := {
	1: preload("res://examples/multiplayer-fps/scripts/data/weapons/knife.tres"),
	2: preload("res://examples/multiplayer-fps/scripts/data/weapons/glock.tres"),
	3: preload("res://examples/multiplayer-fps/scripts/data/weapons/usp.tres"),
	4: preload("res://examples/multiplayer-fps/scripts/data/weapons/ak47.tres"),
	5: preload("res://examples/multiplayer-fps/scripts/data/weapons/m4a1.tres"),
	6: preload("res://examples/multiplayer-fps/scripts/data/weapons/awp.tres"),
}

static func get_weapon(id: int) -> WeaponData:
	return WEAPONS.get(id, null)

static func get_default_pistol(team: int) -> int:
	return GLOCK if team == 0 else USP
