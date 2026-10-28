extends SceneTree
## Plays a whole season headlessly (the club's matches simmed too), then checks the table,
## play-offs, champion and a save/load round-trip. Uses its own save file.
##
## Run: godot --headless --path . --script res://tests/season_test.gd

const SAVE := "user://test_career.json"

var _failures := 0


func _init() -> void:
	Season.save_path = SAVE
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	var s := Season.new_career(0)
	var n := s.teams.size()
	var league_games := n * (n - 1)
	_check(s.fixtures.size() == league_games, "%d league fixtures scheduled (got %d)" % [league_games, s.fixtures.size()])
	_check(s.user_match_pending() or n % 2 == 1, "club plays on day one")
	_test_transfers(s)

	# Track who plays: injured players must never be picked, and the AI should rotate.
	var used := {}
	var injured_picks := 0
	var bad_xis := 0
	var injuries_seen := {}
	var engine_starts := func(f: Dictionary) -> MatchEngine:
		var e: MatchEngine = s.start_match(f)
		for t: CricketTeam in e.teams:
			if t.players.size() != 11 or not t.players.any(func(p): return p.is_keeper()):
				bad_xis += 1
			for p in t.players:
				used[p] = true
				if s.is_injured(p):
					injured_picks += 1
		return e
	var guard := 0
	while not s.is_over() and guard < 200:
		guard += 1
		for f in s.fixtures_on(s.day):
			if f.result.is_empty():
				var e: MatchEngine = engine_starts.call(f)
				while not e.finished:
					e.bowl_ball()
				s.record(f, e)
		for p in s.injuries:
			injuries_seen[p] = true
		if s.day == 30:
			var shown := s.club.squad.filter(func(p): return p.bowling_rating() >= 12 or p.batting_rating() >= 13)
			print("Day 30 condition: %s" % ", ".join(shown.map(func(p): return "%s %d%%" % [p.surname(), s.condition[p]])))
		if not s.advance() and not s.is_over():
			_check(false, "advance stalled on day %d" % s.day)
			break
	_check(injured_picks == 0, "no injured player was picked (%d were)" % injured_picks)
	_check(bad_xis == 0, "every XI had 11 players and a keeper (%d didn't)" % bad_xis)
	print("Players used: %d of %d in squads; injuries this season: %d" % [used.size(), s.stats.size(), injuries_seen.size()])
	_check(used.size() > n * 11, "clubs rotated beyond their first XI")
	_check(injuries_seen.size() > 0, "injuries happened")

	var rows := s.table()
	var points := 0
	for r in rows:
		points += r.pts
		print("%-24s P%2d W%2d L%2d T%d  %2d pts  NRR %+.3f  %s" % [r.team.name, r.p, r.w, r.l, r.t, r.pts, r.nrr, "".join(r.form.slice(-5))])
	_check(rows.all(func(r): return r.p == 2 * (n - 1)), "every team played %d league games" % (2 * (n - 1)))
	_check(points == league_games * 2, "points add up to 2 per league match (got %d)" % points)
	_check(n < 4 or s.fixtures.filter(func(f): return f.stage == "Semi-final").size() == 2, "two semi-finals")
	print("Club balance at season end: %s (wage bill %s a year)" % [Transfers.money(s.balance[s.club]),
		Transfers.money(Transfers.wage_bill(s.club, s))])
	_check(s.champion != null, "a champion was crowned")
	print("Champion: %s on %s" % [s.champion.name if s.champion else "none", s.date_text()])
	for key in ["runs", "wickets", "rating"]:
		var top: CricketPlayer = s.leaders(key, 1)[0]
		print("Top %s: %s (%s) runs %d, wkts %d, avg rating %.2f" % [key, top.name, s.team_of(top).short_name,
			s.stats[top].runs, s.stats[top].wickets, s.average_rating(top)])
	print("News items: %d, latest: %s" % [s.news.size(), s.news[-1].title])

	s.club.players.reverse()
	s.club.bat_roles[s.club.players[0]] = "Pinch Hitter"
	s.save()
	var loaded := Season.load_from(SAVE)
	_check(loaded != null, "save loads")
	if loaded:
		_check(loaded.day == s.day and loaded.champion.name == s.champion.name, "day and champion survive")
		var a := s.table().map(func(r): return [r.team.name, r.pts, snappedf(r.nrr, 0.001)])
		var b := loaded.table().map(func(r): return [r.team.name, r.pts, snappedf(r.nrr, 0.001)])
		_check(a == b, "table survives save/load")
		_check(loaded.club.players[0].id == s.club.players[0].id, "batting order survives")
		_check(Tactics.bat_role(loaded.club, loaded.club.players[0]) == "Pinch Hitter", "roles survive")
		var top: CricketPlayer = s.leaders("runs", 1)[0]
		var top_loaded: CricketPlayer = loaded.leaders("runs", 1)[0]
		_check(top.id == top_loaded.id and int(s.stats[top].runs) == int(loaded.stats[top_loaded].runs), "stats survive")
		var squads_a := s.teams.map(func(t): return t.squad.map(func(p): return p.id))
		var squads_b := loaded.teams.map(func(t): return t.squad.map(func(p): return p.id))
		_check(squads_a == squads_b, "squads (after transfers) survive")
		_check(is_equal_approx(loaded.balance[loaded.club], s.balance[s.club]), "balance survives")
		var someone: CricketPlayer = s.club.squad[0]
		_check(int(loaded.contracts[loaded.club.squad[0]].wage) == int(s.contracts[someone].wage), "contracts survive")

	_test_next_season(s)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("FAILURES: %d" % _failures if _failures else "ALL CHECKS PASSED")
	quit(1 if _failures else 0)


## Rolls into the next season, checks what changed, plays it out, and round-trips the save.
func _test_next_season(s: Season) -> void:
	var ages := {}
	for p in s.all_players():
		ages[p] = p.age
	var first_year := s.year
	var balance_before: float = s.balance[s.club]
	_check(s.start_next_season(), "next season starts")
	_check(s.year == first_year + 1 and s.day == 0 and not s.is_over() and not s.fixtures.is_empty(), "calendar rolled over")
	_check(s.history.size() == 1, "season recorded in history")
	var survivors := ages.keys().filter(func(p): return p in s.all_players())
	_check(survivors.all(func(p): return p.age == ages[p] + 1), "everyone aged a year")
	var youth := s.all_players().filter(func(p): return not ages.has(p))
	_check(youth.size() >= 1 and youth.all(func(p): return p.age <= 19), "youth intake arrived")
	_check(s.teams.all(func(t): return t.squad.size() >= 12 and t.squad.size() <= Transfers.SQUAD_MAX), "squads within limits")
	_check(s.teams.all(func(t): return t.players.size() == 11), "every club has an XI")
	_check(s.balance[s.club] > balance_before, "prize money paid")
	var h: Dictionary = s.history[0]
	print("Season %d: champions %s, club %s, POTS %s, bat %s, ball %s, young %s" % [h.year, h.champion,
		Season.ordinal(h.club_finish), h.player_of_season, h.top_runs, h.top_wickets, h.young_player])
	print("Retired or released: %d players; free agents now %d; youth: %s" % [ages.size() - survivors.size() + s.free_agents.size(),
		s.free_agents.size(), ", ".join(youth.map(func(p): return "%s (%d)" % [p.name, p.age]))])
	print("Season %d starts %s; news: %s" % [s.year, s.date_text(), s.news.slice(-4).map(func(n): return n.title)])

	var guard := 0
	while not s.is_over() and guard < 200:
		guard += 1
		for f in s.fixtures_on(s.day):
			if f.result.is_empty():
				var e := s.start_match(f)
				while not e.finished:
					e.bowl_ball()
				s.record(f, e)
		if not s.advance() and not s.is_over():
			_check(false, "season 2 stalled on day %d" % s.day)
			break
	_check(s.champion != null, "season 2 finished with a champion")
	print("Season %d champion: %s" % [s.year, s.champion.name if s.champion else "none"])

	s.save()
	var loaded := Season.load_from(SAVE)
	_check(loaded != null and loaded.year == s.year and loaded.history.size() == 1, "season 2 save loads")
	if loaded:
		var p: CricketPlayer = s.club.squad[0]
		var q: CricketPlayer = loaded.club.squad[0]
		_check(q.id == p.id and q.age == p.age and is_equal_approx(q.a("technique"), p.a("technique")), "developed attributes and ages survive")
		_check(loaded.all_players().size() == s.all_players().size() and loaded.free_agents.size() == s.free_agents.size(), "free agents survive")


## Buy a player, sell one through an AI bid, renew a contract, and check the money moves.
func _test_transfers(s: Season) -> void:
	var club := s.club
	var start_balance: float = s.balance[club]
	var target: CricketPlayer = null
	for t: CricketTeam in s.teams:
		if t != club:
			var bench := t.reserves()
			bench.sort_custom(func(a, b): return Transfers.value(a, s) < Transfers.value(b, s))
			target = bench[0]
			break
	var seller := s.team_of(target)
	var ask := Transfers.asking_price(target, s)
	var low := Transfers.respond(target, int(ask * 0.5), s)
	var fair := Transfers.respond(target, ask, s)
	_check(low.result == "reject" and fair.result == "accept", "bids: half the asking price rejected, asking price accepted")
	var wage := Transfers.wage_demand(target, s, true)
	var blocker := Transfers.blockers(target, club, ask, wage, s)
	_check(blocker == "", "can afford a reserve (%s)" % blocker)
	Transfers.complete(target, club, ask, wage, Transfers.demand_years(target), s)
	_check(target in club.squad and not target in seller.squad, "player moved clubs")
	_check(is_equal_approx(s.balance[club], start_balance - ask), "fee paid")
	print("Bought %s from %s for %s (value %s, wage %s)" % [target.name, seller.short_name, Transfers.money(ask),
		Transfers.money(Transfers.value(target, s)), Transfers.money(wage)])

	var sold: CricketPlayer = club.reserves()[0]
	s.listed[sold] = true
	var buyer: CricketTeam = s.teams.filter(func(t): return t != club and t.squad.size() < Transfers.SQUAD_MAX)[0]
	var offer := {"player": sold, "from": buyer, "fee": Transfers.value(sold, s), "day": s.day, "status": "pending"}
	s.offers.append(offer)
	var err := Transfers.accept_offer(offer, s)
	_check(err == "" and sold in buyer.squad and not s.listed.has(sold), "AI bid accepted (%s)" % err)

	var renewed: CricketPlayer = club.players[0]
	err = Transfers.renew(renewed, s)
	_check(err == "" and Transfers.contract_years(renewed, s) >= 1, "contract renewed (%s)" % err)
	var tiny := Transfers.respond(club.players[0], 1, s)
	_check(tiny.result == "reject", "a £1 bid is rejected")


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: " + what)
