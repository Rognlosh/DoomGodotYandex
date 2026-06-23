class_name RocketLauncher
extends Weapon
## Ракетомёт (слот 5): вместо хитскана запускает снаряд-ракету по форварду камеры.
## Поведение поверх Weapon — переопределён только _fire(). Кулдаун, расход патронов
## и звук (play_weapon по слоту) работают через базу.

@export_group("Ракета")
## Сцена снаряда — rocket.tscn.
@export var projectile_scene: PackedScene
## Вперёд от камеры в точке вылета, м (чтобы ракета не родилась внутри стрелка).
@export var muzzle_forward: float = 0.6
## Вниз от линии взгляда, м (визуально вылетает чуть из-под прицела).
@export var muzzle_down: float = 0.15


func _fire() -> void:
	if projectile_scene == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var cam_basis := camera.global_transform.basis
	var forward := -cam_basis.z
	var from := camera.global_position + forward * muzzle_forward - cam_basis.y * muzzle_down
	var owner_rid := _body.get_rid() if _body != null else RID()
	Projectile.launch(projectile_scene, camera, from, forward, owner_rid)
