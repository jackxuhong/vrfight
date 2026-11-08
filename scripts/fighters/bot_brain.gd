class_name BotBrain
extends RefCounted
## Drives a Fighter like a boxer: footwork to its favourite range, a guard, combos, and blocking or
## slipping incoming punches. `skill` (0..1) scales reaction, accuracy and work rate.

const RANGE := 0.75  # head-to-head distance it likes to fight at (m)
const COMBOS := [["jab"], ["jab", "cross"], ["jab", "cross", "hook"], ["cross", "hook"],
	["jab", "body"], ["body", "upper"], ["hook", "body"]]

var me: Fighter
var foe: Fighter
var skill: float
var pos := Vector3.ZERO  # feet, on the canvas
var down := false
var recover_at := 10  # the count it will get up at

var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _right := Vector3.RIGHT
var _next_attack := 1.5
var _queue := []
var _punch := {}
var _cover := 0.0
var _slip := 0.0
var _slip_dir := 1.0
var _circle := 0.0
var _circle_t := 0.0
var _threat_seen := false


func _init(fighter: Fighter, opponent: Fighter, bot_skill: float) -> void:
	me = fighter
	foe = opponent
	skill = clampf(bot_skill, 0.0, 1.0)
	_rng.randomize()


func on_knockdown(total_knockdowns: int) -> void:
	down = true
	_punch = {}
	_queue = []
	# The more often it has been dropped, the likelier it stays down.
	recover_at = 10 if _rng.randf() < 0.2 * total_knockdowns else _rng.randi_range(4, 9)


## `active`: a round is on, so move and punch; otherwise just hold the guard.
func update(dt: float, active: bool) -> void:
	_t += dt
	var to_foe := foe.head.origin - pos
	to_foe.y = 0.0
	var dist := to_foe.length()
	var fwd := to_foe / dist if dist > 0.01 else Vector3.FORWARD
	_right = Vector3(-fwd.z, 0.0, fwd.x)
	var facing := Basis(Vector3.UP, atan2(-fwd.x, -fwd.z))
	if down:
		me.head = Transform3D(facing, pos + Vector3(0, 0.5, 0))
		me.gloves[0] = pos - _right * 0.3 + Vector3(0, 0.1, 0)
		me.gloves[1] = pos + _right * 0.3 + Vector3(0, 0.1, 0)
		return
	if active:
		_footwork(dt, fwd, dist)
	_cover = maxf(0.0, _cover - dt)
	_slip = maxf(0.0, _slip - dt)
	var h := pos + Vector3(0, 1.68 + sin(_t * 4.0) * 0.015, 0)
	if _slip > 0.0:
		h += _right * _slip_dir * 0.16 * sin(PI * _slip / 0.35)
	me.head = Transform3D(facing, h)
	_defend(h)
	var guard := _guard(h, fwd)
	if active:
		_attack(dt, dist)
	else:
		_punch = {}
	for i in 2:
		if not _punch.is_empty() and _punch.hand == i:
			me.gloves[i] = _punch_pos(guard[i])
		else:
			me.gloves[i] = me.gloves[i].lerp(guard[i], 1.0 - exp(-18.0 * dt))


func _footwork(dt: float, fwd: Vector3, dist: float) -> void:
	_circle_t -= dt
	if _circle_t <= 0.0:
		_circle = [-1.0, 0.0, 1.0][_rng.randi() % 3]
		_circle_t = _rng.randf_range(0.8, 2.5)
	var approach := 0.0
	if dist > RANGE + 0.1:
		approach = 1.0
	elif dist < RANGE - 0.15:
		approach = -1.0
	pos += (fwd * approach * 1.2 + _right * _circle * 0.5) * dt
	var lim := Arena.HALF - 0.35
	pos.x = clampf(pos.x, -lim, lim)
	pos.z = clampf(pos.z, -lim, lim)
	var gap := pos - foe.head.origin
	gap.y = 0.0
	if gap.length() < Fighter.MIN_GAP:
		pos += gap.normalized() * (Fighter.MIN_GAP - gap.length())


func _guard(h: Vector3, fwd: Vector3) -> Array[Vector3]:
	var tight := _cover > 0.0
	var reach := 0.17 if tight else 0.23
	var width := 0.07 if tight else 0.11
	var drop := Vector3(0, -0.03 if tight else -0.08, 0)
	return [h + fwd * reach - _right * width + drop, h + fwd * reach + _right * width + drop]


func _defend(h: Vector3) -> void:
	var threat := false
	for i in 2:
		var v := foe.glove_vel[i]
		var g := foe.gloves[i]
		threat = threat or (v.length() > 2.0 and g.distance_to(h) < 0.7 and v.dot(h - g) > 0.0)
	if not threat:
		_threat_seen = false
		return
	if _threat_seen:
		return
	_threat_seen = true  # react once per incoming punch
	var r := _rng.randf()
	if r < skill * 0.45:
		_cover = 0.5
	elif r < skill * 0.75:
		_slip = 0.35
		_slip_dir = -1.0 if _rng.randf() < 0.5 else 1.0


func _attack(dt: float, dist: float) -> void:
	_next_attack -= dt
	if not _punch.is_empty():
		_punch.t += dt
		if _punch.t > _punch.out + _punch.back:
			_punch = {}
		return
	if _queue.is_empty() and _next_attack <= 0.0 and dist < RANGE + 0.25:
		_queue = COMBOS[_rng.randi() % COMBOS.size()].duplicate()
		_next_attack = _rng.randf_range(1.2, 2.6) * (1.8 - skill)
	if not _queue.is_empty():
		_start_punch(_queue.pop_front())


func _start_punch(kind: String) -> void:
	var hand := 0 if kind == "jab" else (1 if kind == "cross" else _rng.randi() % 2)
	var aim := foe.body_center() if kind == "body" else foe.head.origin
	aim += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 0.08 * (1.0 - skill)
	var from := me.gloves[hand]
	var to := aim + (aim - from).normalized() * 0.12  # punch through the target
	var ctrl := (from + to) * 0.5
	if kind == "hook":
		ctrl += _right * (-0.35 if hand == 0 else 0.35)
	elif kind == "upper":
		ctrl += Vector3(0, -0.3, 0)
	_punch = {"hand": hand, "t": 0.0, "out": 0.15 + 0.08 * (1.0 - skill), "back": 0.22,
		"from": from, "ctrl": ctrl, "to": to}


func _punch_pos(guard: Vector3) -> Vector3:
	var p := _punch
	if p.t < p.out:
		var s: float = p.t / p.out
		var a: Vector3 = p.from.lerp(p.ctrl, s)
		return a.lerp(p.ctrl.lerp(p.to, s), s)  # quadratic curve: straight, hook or uppercut
	return p.to.lerp(guard, (p.t - p.out) / p.back)
