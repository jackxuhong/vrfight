extends SceneTree
## Rules unit tests. Run: godot --headless -s res://tests/test_rules.gd

var failures := 0


func _init() -> void:
	test_decision()
	test_even_fight_is_draw()
	test_ko()
	test_recovery_waits_for_eight()
	test_tko_three_knockdowns()
	test_knockdown_round_scores_10_8()
	test_fouls_warn_then_deduct()
	test_rabbit_punch_is_foul()
	test_blocked_and_out_of_round_hits_dont_score()
	print("ALL TESTS PASSED" if failures == 0 else "%d TEST(S) FAILED" % failures)
	quit(1 if failures else 0)


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func new_match(rounds := 2) -> BoxingMatch:
	var m := BoxingMatch.new({"rounds": rounds, "round_seconds": 10.0, "rest_seconds": 2.0})
	run(m, BoxingMatch.PRE_SECONDS + 0.05)
	return m


func run(m: BoxingMatch, seconds: float) -> void:
	var t := 0.0
	while t < seconds and m.state != BoxingMatch.State.OVER:
		m.tick(0.1)
		t += 0.1


func until_round(m: BoxingMatch, n: int) -> void:
	while m.round_num < n and m.state != BoxingMatch.State.OVER:
		m.tick(0.1)


func test_decision() -> void:
	var m := new_match(2)
	for r in 2:
		until_round(m, r + 1)
		for i in 10:
			m.register_hit(0, "head", 0.5, false)
		run(m, 11.0)
	check(m.state == BoxingMatch.State.OVER, "decision: match over")
	check(m.result.winner == 0 and m.result.method == "UD", "decision: red by UD, got %s" % m.result)
	check(m.cards[0] == [[10, 9], [10, 9]], "decision: 10-9 rounds, got %s" % [m.cards[0]])
	check(m.result.totals[0] == [20, 18], "decision: totals 20-18")


func test_even_fight_is_draw() -> void:
	var m := new_match(1)
	run(m, 11.0)
	check(m.result.method == "DRAW" and m.result.winner == -1, "even: draw, got %s" % m.result)


func test_ko() -> void:
	var m := new_match()
	while m.state == BoxingMatch.State.ROUND:
		m.register_hit(0, "head", 1.0, false)
	check(m.state == BoxingMatch.State.KNOCKDOWN and m.down == 1, "ko: blue down")
	run(m, 10.5)
	check(m.result.winner == 0 and m.result.method == "KO", "ko: red by KO, got %s" % m.result)


func test_recovery_waits_for_eight() -> void:
	var m := new_match()
	while m.state == BoxingMatch.State.ROUND:
		m.register_hit(1, "head", 1.0, false)
	m.recover(1)  # wrong boxer: ignored
	check(not m.recovered, "recovery: only the downed boxer can recover")
	m.recover(0)
	run(m, 7.5)
	check(m.state == BoxingMatch.State.KNOCKDOWN, "recovery: still counting before eight")
	run(m, 1.0)
	check(m.state == BoxingMatch.State.ROUND, "recovery: boxing resumes at eight")


func test_tko_three_knockdowns() -> void:
	var m := new_match()
	for k in 3:
		while m.state == BoxingMatch.State.ROUND:
			m.register_hit(0, "body", 1.5, false)
		if m.state == BoxingMatch.State.KNOCKDOWN:
			m.recover(1)
			run(m, 8.5)
	check(m.result.get("method") == "TKO" and m.result.winner == 0, "tko: red by TKO, got %s" % m.result)


func test_knockdown_round_scores_10_8() -> void:
	var m := new_match(1)
	while m.state == BoxingMatch.State.ROUND:
		m.register_hit(0, "head", 1.0, false)
	m.recover(1)
	run(m, 20.0)
	check(m.cards[0][0] == [10, 8], "10-8: got %s" % [m.cards[0][0]])


func test_fouls_warn_then_deduct() -> void:
	var m := new_match(1)
	for i in 3:
		check(not m.register_hit(0, "low", 1.0, false), "fouls: low blow does not score")
	check(m.warnings[0] == 3, "fouls: three warnings")
	check(m.health[1] == BoxingMatch.MAX_HEALTH, "fouls: no damage from fouls")
	run(m, 11.0)
	check(m.cards[0][0] == [9, 10], "fouls: one point deducted, got %s" % [m.cards[0][0]])


func test_rabbit_punch_is_foul() -> void:
	var m := new_match()
	check(not m.register_hit(1, "head", 1.0, false, true), "rabbit: does not score")
	check(m.warnings[1] == 1, "rabbit: warning")


func test_blocked_and_out_of_round_hits_dont_score() -> void:
	var m := BoxingMatch.new({"rounds": 1, "round_seconds": 10.0})
	check(not m.register_hit(0, "head", 1.0, false), "pre-fight hit ignored")
	run(m, BoxingMatch.PRE_SECONDS + 0.05)
	check(not m.register_hit(0, "head", 1.0, true), "blocked hit does not score")
	check(m.health[1] == BoxingMatch.MAX_HEALTH, "blocked hit does no damage")
