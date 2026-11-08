extends SceneTree
## Hit detection unit tests. Run: godot --headless --xr-mode off -s res://tests/test_hits.gd

const DT := 1.0 / 90.0
var failures := 0
var made: Array[Fighter] = []


func _init() -> void:
	test_straight_punch_lands_once()
	test_slow_contact_is_not_a_punch()
	test_guard_blocks()
	test_body_and_low_zones()
	test_back_of_head_is_behind()
	for f in made:
		f.free()
	print("ALL TESTS PASSED" if failures == 0 else "%d TEST(S) FAILED" % failures)
	quit(1 if failures else 0)


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


## Attacker at z=+0.7 facing -Z, defender at origin facing +Z, defender gloves out of the way.
func pair() -> Array[Fighter]:
	var a := Fighter.new().setup(Color.RED)
	var d := Fighter.new().setup(Color.BLUE)
	a.head = Transform3D(Basis(), Vector3(0, 1.7, 0.7))
	d.head = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 1.7, 0))
	d.gloves[0] = Vector3(-0.5, 1.0, 0)
	d.gloves[1] = Vector3(0.5, 1.0, 0)
	made.append_array([a, d])
	return [a, d]


## Moves attacker glove 0 from `from` to `to` at `speed` m/s; returns all hits on the defender.
func swing(a: Fighter, d: Fighter, from: Vector3, to: Vector3, speed: float) -> Array:
	var hits := []
	var steps := maxi(1, ceili(from.distance_to(to) / (speed * DT)))
	for s in steps + 1:
		a.gloves[0] = from.lerp(to, float(s) / steps)
		a.gloves[1] = Vector3(0.3, 1.0, 0.7)
		a.step(DT)
		d.step(DT)
		hits += a.punches_on(d)
	return hits


func test_straight_punch_lands_once() -> void:
	var p := pair()
	var hits := swing(p[0], p[1], Vector3(0, 1.7, 0.5), Vector3(0, 1.7, -0.05), 5.0)
	check(hits.size() == 1, "straight: one hit, got %d" % hits.size())
	if hits.size() == 1:
		check(hits[0].zone == "head" and not hits[0].blocked and not hits[0].behind, "straight: clean head shot")
		check(absf(hits[0].speed - 5.0) < 0.3, "straight: speed ~5 m/s, got %.2f" % hits[0].speed)


func test_slow_contact_is_not_a_punch() -> void:
	var p := pair()
	check(swing(p[0], p[1], Vector3(0, 1.7, 0.5), Vector3(0, 1.7, 0.0), 0.8).is_empty(), "slow push: no hit")


func test_guard_blocks() -> void:
	var p := pair()
	p[1].gloves[0] = Vector3(-0.04, 1.7, 0.2)  # glove in front of the face
	var hits := swing(p[0], p[1], Vector3(0, 1.7, 0.5), Vector3(0, 1.7, -0.05), 5.0)
	check(hits.size() == 1 and hits[0].blocked, "guard: blocked, got %s" % [hits])


func test_body_and_low_zones() -> void:
	var p := pair()
	var body := swing(p[0], p[1], Vector3(0, 1.25, 0.6), Vector3(0, 1.25, 0.0), 5.0)
	check(body.size() == 1 and body[0].zone == "body", "body shot, got %s" % [body])
	p = pair()
	var low := swing(p[0], p[1], Vector3(0, 0.85, 0.6), Vector3(0, 0.85, 0.0), 5.0)
	check(low.size() == 1 and low[0].zone == "low", "low blow, got %s" % [low])


func test_back_of_head_is_behind() -> void:
	var p := pair()
	# Glove comes from behind the defender (z < 0), travelling +Z, the way the defender faces.
	var hits := swing(p[0], p[1], Vector3(0, 1.7, -0.5), Vector3(0, 1.7, 0.0), 5.0)
	check(hits.size() == 1 and hits[0].behind, "rabbit punch flagged, got %s" % [hits])
