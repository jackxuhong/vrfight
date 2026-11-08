class_name BoxingMatch
extends RefCounted
## Pro boxing rules as plain logic (no nodes), so the host and the tests can both run it.
## Fighters are 0 (red) and 1 (blue). Feed it time and hits; it emits `event`s.
##
## - Rounds of `round_seconds` with `rest_seconds` between them. The clock stops during a count.
## - Three judges score each round on the 10-point must system: 10-9 to the round winner, 10-10 if
##   even, one point off per knockdown suffered and per foul deduction.
## - Health at 0 is a knockdown. The referee counts to 10; a boxer who recovers boxes on at eight
##   at the earliest (mandatory eight count). Not up by ten = KO. Three knockdowns in a round = TKO.
## - Low blows and rabbit punches score nothing and draw a warning; from the third warning on,
##   each one costs a point.
## - After the last round the judges' totals decide: unanimous, majority or split decision, or draw.

signal event(what: String, data: Dictionary)

enum State { PRE, ROUND, KNOCKDOWN, REST, OVER }

const JUDGES := 3
const PRE_SECONDS := 3.0
const MAX_HEALTH := 100.0
const HEAD_DAMAGE := 6.0  # per unit of punch power; tuned so 3-min rounds rarely end early
const BODY_DAMAGE := 4.0
const REST_HEAL := 25.0

var rounds := 3
var round_seconds := 180.0
var rest_seconds := 60.0

var state := State.PRE
var round_num := 0
var clock := PRE_SECONDS  # seconds left in the current phase
var health: Array[float] = [MAX_HEALTH, MAX_HEALTH]
var knockdowns: Array[int] = [0, 0]  # this round
var knockdowns_total: Array[int] = [0, 0]
var warnings: Array[int] = [0, 0]
var down := -1  # boxer being counted, or -1
var count := 0
var recovered := false
var cards := []  # cards[judge][round] = [red, blue]
var result := {}

var _count_t := 0.0
var _impressions := []  # per judge [red, blue]: how much of each boxer's work that judge saw
var _deductions: Array[int] = [0, 0]
var _rng := RandomNumberGenerator.new()


func _init(settings := {}) -> void:
	rounds = settings.get("rounds", rounds)
	round_seconds = settings.get("round_seconds", round_seconds)
	rest_seconds = settings.get("rest_seconds", rest_seconds)
	_rng.seed = 1  # judges differ from each other, but the same fight always scores the same
	for j in JUDGES:
		cards.append([])


func tick(dt: float) -> void:
	match state:
		State.PRE, State.REST:
			clock -= dt
			if clock <= 0.0:
				_start_round()
		State.ROUND:
			clock -= dt
			if clock <= 0.0:
				_end_round()
		State.KNOCKDOWN:
			_count_t += dt
			if _count_t >= 1.0:
				_count_t -= 1.0
				count += 1
				_emit("count", {"fighter": down, "count": count})
				if recovered and count >= 8:
					_resume()
				elif count >= 10:
					_finish(1 - down, "KO")


## zone: "head", "body" or "low" (below the belt). behind: landed on the back of the head.
## Returns true if it scored.
func register_hit(attacker: int, zone: String, power: float, blocked: bool, behind := false) -> bool:
	if state != State.ROUND:
		return false
	if zone == "low" or behind:
		_foul(attacker, "LOW BLOW" if zone == "low" else "RABBIT PUNCH")
		return false
	_emit("hit", {"attacker": attacker, "zone": zone, "power": power, "blocked": blocked})
	if blocked:
		return false
	var weight := 1.0 if zone == "head" else 0.7
	for j in JUDGES:
		_impressions[j][attacker] += power * weight * _rng.randf_range(0.7, 1.3)
	var target := 1 - attacker
	health[target] -= power * (HEAD_DAMAGE if zone == "head" else BODY_DAMAGE)
	if health[target] <= 0.0:
		_knockdown(target)
	return true


## The boxer on the canvas has shown the referee they can go on.
func recover(fighter: int) -> void:
	if state == State.KNOCKDOWN and fighter == down:
		recovered = true


func to_dict() -> Dictionary:
	return {"state": state, "round": round_num, "rounds": rounds, "clock": clock,
		"health": health, "down": down, "count": count}


func _start_round() -> void:
	round_num += 1
	state = State.ROUND
	clock = round_seconds
	knockdowns = [0, 0]
	_deductions = [0, 0]
	_impressions = []
	for j in JUDGES:
		_impressions.append([0.0, 0.0])
	_emit("round_start", {"round": round_num})


func _end_round() -> void:
	var this_round := []
	for j in JUDGES:
		var seen: Array = _impressions[j]
		var score := [10, 10]
		var total: float = seen[0] + seen[1]
		if total > 0.0 and absf(seen[0] - seen[1]) > 0.1 * total:
			score[0 if seen[0] < seen[1] else 1] = 9
		for f in 2:
			score[f] -= knockdowns[f]
		var top: int = maxi(score[0], score[1])
		for f in 2:
			score[f] += 10 - top - _deductions[f]
		cards[j].append(score)
		this_round.append(score)
	_emit("round_end", {"round": round_num, "cards": this_round})
	if round_num >= rounds:
		_decide()
		return
	state = State.REST
	clock = rest_seconds
	for f in 2:
		health[f] = minf(MAX_HEALTH, health[f] + REST_HEAL)


func _knockdown(f: int) -> void:
	knockdowns[f] += 1
	knockdowns_total[f] += 1
	_emit("knockdown", {"fighter": f, "total": knockdowns_total[f]})
	if knockdowns[f] >= 3:
		_finish(1 - f, "TKO")
		return
	state = State.KNOCKDOWN
	down = f
	count = 0
	recovered = false
	_count_t = 0.0
	health[f] = maxf(20.0, 60.0 - 15.0 * knockdowns_total[f])


func _resume() -> void:
	state = State.ROUND
	down = -1
	_emit("resume", {})


func _foul(f: int, kind: String) -> void:
	warnings[f] += 1
	var deduct := warnings[f] >= 3
	if deduct:
		_deductions[f] += 1
	_emit("foul", {"fighter": f, "kind": kind, "warnings": warnings[f], "deducted": deduct})


func _decide() -> void:
	var votes := [0, 0]
	var totals := []
	for j in JUDGES:
		var t := [0, 0]
		for r in cards[j]:
			t[0] += r[0]
			t[1] += r[1]
		totals.append(t)
		if t[0] != t[1]:
			votes[0 if t[0] > t[1] else 1] += 1
	if votes[0] < 2 and votes[1] < 2:
		_finish(-1, "DRAW", totals)
		return
	var w := 0 if votes[0] >= 2 else 1
	var draws: int = JUDGES - votes[0] - votes[1]
	_finish(w, "UD" if votes[w] == JUDGES else ("MD" if draws > 0 else "SD"), totals)


func _finish(winner: int, method: String, totals := []) -> void:
	state = State.OVER
	down = -1
	result = {"winner": winner, "method": method, "round": round_num, "totals": totals}
	_emit("match_over", result)


func _emit(what: String, data: Dictionary) -> void:
	event.emit(what, data)
