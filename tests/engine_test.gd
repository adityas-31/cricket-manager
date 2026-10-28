extends SceneTree
## Engine rules: super overs settle ties, DRS overturns bad calls, the manager's bowler and
## batting-order choices are used, custom fields obey restrictions, and handedness matchups
## favour the bowler who moves the ball away.
##
## Run: godot --headless --path . --script res://tests/engine_test.gd

var _failures := 0


func _init() -> void:
	var teams := CricketTeam.load_all("res://data/teams.json")
	_test_super_overs(teams)
	_test_reviews(teams)
	_test_manager_choices(teams)
	_test_fields()
	_test_matchups(teams)
	print("FAILURES: %d" % _failures if _failures else "ALL CHECKS PASSED")
	quit(1 if _failures else 0)


func _test_super_overs(teams: Array) -> void:
	var found := 0
	var seed := 0
	while found < 3 and seed < 4000:
		var e := MatchEngine.new(teams[seed % 2], teams[(seed + 1) % 2], MatchFormat.t20(), "balanced", seed)
		seed += 1
		while not e.finished:
			e.bowl_ball()
		if e.super_overs == 0:
			_check(e.result_text != "Match tied", "a tie always goes to a super over")
			continue
		found += 1
		var main := e.main_innings()
		var so: Array = e.innings.filter(func(i): return i.super_over)
		_check(main[1].runs == main[1].target - 1, "main match was tied")
		_check(so.size() == 2 * e.super_overs, "super overs come in pairs")
		_check(so[0].batting_team == main[1].batting_team, "the side batting second bats first in the super over")
		_check(so.all(func(i): return i.lineup.size() == 3 and i.legal_balls <= 6 and i.wickets <= 2), "three batters, six balls, two wickets")
		_check(e.winner != null and e.result_text.contains("super over"), "super over decided it: %s" % e.result_text)
		print("Super over (seed %d): %s; SO scores %s" % [seed - 1, e.result_text,
			", ".join(so.map(func(i): return "%s %s" % [i.batting_team.short_name, i.score_text()]))])
	_check(found > 0, "found tied matches to test (%d)" % found)


func _test_reviews(teams: Array) -> void:
	var reviews := 0
	var overturned := 0
	for seed in 60:
		var e := MatchEngine.new(teams[0], teams[1], MatchFormat.t20(), "balanced", 9000 + seed)
		e.manager_team = teams[0]
		var guard := 0
		while not e.finished and guard < 1000:
			guard += 1
			var ev := e.bowl_ball()
			if ev.has("review_pending"):
				_check(ev.team == teams[0] and ev.reviews_left > 0, "only the manager's side is asked, with reviews left")
				ev = e.resolve_review(true)
			if ev.has("review"):
				reviews += 1
				if ev.review.overturned:
					overturned += 1
				_check(ev.commentary.contains("review"), "commentary covers the review")
		for inn: Innings in e.innings:
			_check(inn.reviews.values().all(func(r): return r >= 0), "reviews never go negative")
	print("Reviews in 60 matches: %d, overturned %d" % [reviews, overturned])
	_check(reviews > 0 and overturned > 0, "reviews happen and some succeed")


func _test_manager_choices(teams: Array) -> void:
	var e := MatchEngine.new(teams[0], teams[1], MatchFormat.t20(), "balanced", 77)
	var inn := e.current()
	e.manager_team = inn.bowling_team
	var pick: CricketPlayer = e.eligible_bowlers(inn)[-1]
	e.set_next_bowler(inn.bowling_team, pick)
	e.bowl_ball()
	_check(inn.bowlers[0].player == pick, "the manager's bowler opens (%s)" % pick.surname())
	var waiting := inn.yet_to_bat()
	inn.promote(waiting[-1])
	_check(inn.yet_to_bat()[0] == waiting[-1], "promoted batter is next in")
	while inn.wickets == 0 and not e.finished:
		var ev := e.bowl_ball()
		if ev.has("review_pending"):
			e.resolve_review(false)
	_check(inn.batters[2].player == waiting[-1], "promoted batter came in at the first wicket")


func _test_fields() -> void:
	for name in Fields.PRESETS:
		var outside := Fields.outside_count(Fields.PRESETS[name])
		_check(outside <= 5, "%s preset has %d outside the circle" % [name, outside])
		var pp := Fields.legalise(Fields.PRESETS[name], "powerplay")
		_check(Fields.outside_count(pp) <= 2, "%s is made powerplay-legal" % name)
	var all_out := []
	for i in 9:
		all_out.append([i * 40.0 - 160.0, 65.0])
	_check(Fields.outside_count(Fields.legalise(all_out, "middle")) == 5, "nine boundary riders cut to five")
	_check(not Fields.outside_ring([150, 19]), "first slip is inside the circle")
	var back := Fields.spot_at(Fields.position([55.0, 25.0]))
	_check(absf(back[0] - 55.0) < 0.01 and absf(back[1] - 25.0) < 0.01, "spot_at inverts position")


func _test_matchups(teams: Array) -> void:
	# Same off-spinner, same batter, only the batting hand changes.
	var bowler := CricketPlayer.from_dict({"id": 1, "name": "Off Spinner", "role": "bowler", "style": "off_spin",
		"attributes": {"accuracy": 13, "movement": 13, "variation": 12}})
	var runs := {}
	for hand in ["right", "left"]:
		var batter := CricketPlayer.from_dict({"id": 2, "name": "Batter", "bats": hand, "role": "batter",
			"attributes": {"technique": 13, "timing": 13, "power": 12, "vs_spin": 12}})
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var total := 0
		for i in 20000:
			var r := DeliveryModel.bowl(rng, {"batter": batter, "batter_balls": 20, "bowler": bowler, "intent": 0.0,
				"phase": "middle", "pitch": "balanced", "progress": 0.5, "fielding": teams[0], "free_hit": false})
			total += r.runs + r.extra_runs
		runs[hand] = total * 6.0 / 20000.0
	print("Off-spinner economy: v right-hander %.2f, v left-hander %.2f" % [runs.right, runs.left])
	_check(runs.left < runs.right, "off-spin turning away from the left-hander is harder to score off")


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: " + what)
