extends Resource
class_name WeaponData

enum FireMode { SEMI, AUTO, MELEE }

@export var weapon_id: int = 0
@export var weapon_name: String = ""
@export var slot: int = 0
@export var damage: int = 0
@export var fire_rate: float = 0.0
@export var fire_mode: FireMode = FireMode.SEMI
@export var magazine_size: int = 0
@export var reserve_size: int = 0
@export var move_speed: float = 5.0
@export var recoil_per_shot: float = 0.0
@export var recoil_recovery: float = 10.0
@export var kill_reward: int = 300
@export var armor_penetration: float = 0.0
@export var price: int = 0
@export var team: int = -1  # -1=all, 0=T, 1=CT
@export var max_distance: float = 1000.0
@export var reload_time: float = 2.0
