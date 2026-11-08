class_name Fighter
extends Node3D
## A boxer reduced to what boxing needs: a head and two gloves in world space. A driver (VR rig,
## desktop rig, bot, dummy or the network) writes `head` and `gloves` every tick; this node draws
## them, tracks glove speed, and finds the punches that land on the other boxer.
## Glove 0 is the left hand, 1 the right.

const HEAD_R := 0.13
const BODY_R := 0.17
const GLOVE_R := 0.065
const MIN_GAP := 0.45     # closest two heads may get, on the floor plane (m)
const MIN_SPEED := 1.6    # m/s; slower contact is a push, not a punch
const MAX_POWER := 1.5
const BLOCK_DIST := 0.13  # attacking glove this close to a defending glove = blocked (gloves touch)
const COOLDOWN := 0.3     # s before the same glove can land again

var head := Transform3D(Basis(), Vector3(0, 1.7, 0))
var gloves: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var glove_vel: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]

var _prev: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _touching: Array[bool] = [false, false]
var _cooldown: Array[float] = [0.0, 0.0]
var _fresh := true
var _head_mesh: MeshInstance3D
var _torso_mesh: MeshInstance3D
var _glove_meshes: Array[MeshInstance3D] = []


func setup(kit: Color) -> Fighter:
	_head_mesh = Arena.make(Arena.sphere(HEAD_R), Color(0.87, 0.68, 0.55))
	add_child(_head_mesh)
	var torso := CapsuleMesh.new()
	torso.radius = BODY_R
	torso.height = 0.62
	_torso_mesh = Arena.make(torso, kit.darkened(0.35))
	add_child(_torso_mesh)
	for i in 2:
		var g := Arena.make(Arena.sphere(GLOVE_R + 0.01), kit)
		add_child(g)
		_glove_meshes.append(g)
	return self


## Hide your own head and torso so you don't see the inside of them.
func set_body_visible(on: bool) -> void:
	_head_mesh.visible = on
	_torso_mesh.visible = on


## Call once per physics tick after the driver has written the pose.
func step(dt: float) -> void:
	for i in 2:
		glove_vel[i] = Vector3.ZERO if _fresh else (gloves[i] - _prev[i]) / dt
		_prev[i] = gloves[i]
		_cooldown[i] = maxf(0.0, _cooldown[i] - dt)
		_glove_meshes[i].position = gloves[i]
	_fresh = false
	_head_mesh.transform = head
	_torso_mesh.position = body_center()
	_torso_mesh.basis = Basis(Vector3.UP, yaw())


func forward() -> Vector3:
	var f := -head.basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD


func yaw() -> float:
	var f := forward()
	return atan2(-f.x, -f.z)


func body_top() -> Vector3:
	return head.origin + Vector3(0, -0.3, 0) - forward() * 0.04


func body_bottom() -> Vector3:
	return head.origin + Vector3(0, -0.62, 0) - forward() * 0.04


func body_center() -> Vector3:
	return (body_top() + body_bottom()) * 0.5


func below_belt() -> Vector3:
	return head.origin + Vector3(0, -0.85, 0)


## Which zone a sphere at `p` with radius `r` touches: "head", "body", "low" or "".
func zone_at(p: Vector3, r: float) -> String:
	if p.distance_to(head.origin) < HEAD_R + r:
		return "head"
	if p.distance_to(Geometry3D.get_closest_point_to_segment(p, body_top(), body_bottom())) < BODY_R + r:
		return "body"
	if p.distance_to(below_belt()) < BODY_R + r:
		return "low"
	return ""


## Punches from this boxer that landed on `other` this tick:
## [{hand, zone, speed, power, blocked, behind, point}]. A glove lands when it enters a zone
## fast enough while moving into it.
func punches_on(other: Fighter) -> Array:
	var hits := []
	for i in 2:
		var g := gloves[i]
		var zone := other.zone_at(g, GLOVE_R)
		var entering := zone != "" and not _touching[i]
		_touching[i] = zone != ""
		if not entering or _cooldown[i] > 0.0:
			continue
		var v := glove_vel[i]
		var aim := other.head.origin
		if zone == "body":
			aim = other.body_center()
		elif zone == "low":
			aim = other.below_belt()
		if v.length() < MIN_SPEED or v.dot(aim - g) <= 0.0:
			continue
		_cooldown[i] = COOLDOWN
		var blocked := false
		for og in other.gloves:
			blocked = blocked or g.distance_to(og) < BLOCK_DIST
		hits.append({
			"hand": i, "zone": zone, "speed": v.length(), "point": g, "blocked": blocked,
			"power": clampf(v.length() / 7.0, 0.1, MAX_POWER),
			# moving the same way the defender faces = it came from behind
			"behind": zone == "head" and v.normalized().dot(other.forward()) > 0.5,
		})
	return hits
