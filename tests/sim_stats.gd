extends SceneTree
## Simulates many matches headlessly and prints averages to calibrate DeliveryModel against
## real cricket (T20 first innings ~160-175, ~6-7 wickets, ~35-40% dots, ~13-16 boundaries).
##
## Run: godot --headless --path . --script res://tests/sim_stats.gd

const MATCHES := 400


func _init() -> void:
	var teams := CricketTeam.load_all("res://data/teams.json")
	for fmt: MatchFormat in [MatchFormat.t20(), MatchFormat.odi()]:
		print("\n== %s, %d matches ==" % [fmt.name, MATCHES])
		var by_pitch := {}
		var s := {"runs": 0.0, "wkts": 0.0, "balls": 0.0, "dots": 0.0, "fours": 0.0, "sixes": 0.0, "extras": 0.0,
			"part_timer_overs": 0.0, "bat_first_wins": 0.0, "ties": 0.0, "chase_runs": 0.0}
		for i in MATCHES:
			var pitch: String = MatchEngine.PITCHES[i % MatchEngine.PITCHES.size()]
			var e := MatchEngine.new(teams[i % 2], teams[(i + 1) % 2], fmt, pitch, i)
			while not e.finished:
				e.bowl_ball()
			var first: Innings = e.innings[0]
			s.runs += first.runs
			s.wkts += first.wickets
			s.balls += first.legal_balls
			s.dots += first.dots
			s.fours += first.fours
			s.sixes += first.sixes
			s.extras += first.extras()
			s.chase_runs += e.innings[1].runs
			for b in first.bowlers:
				if b.player.role == CricketPlayer.Role.BATTER:
					s.part_timer_overs += b.balls / 6.0
			if e.winner == first.batting_team:
				s.bat_first_wins += 1
			elif e.winner == null:
				s.ties += 1
			by_pitch[pitch] = by_pitch.get(pitch, 0.0) + first.runs
		var n := float(MATCHES)
		print("1st inns: %.1f/%.1f in %.1f overs  (chase avg %.1f)" % [s.runs / n, s.wkts / n, s.balls / n / 6.0, s.chase_runs / n])
		print("dots %.1f%%  4s %.1f  6s %.1f  extras %.1f  run rate %.2f" % [
			100.0 * s.dots / s.balls, s.fours / n, s.sixes / n, s.extras / n, s.runs * 6.0 / s.balls])
		print("part-timer overs %.2f  bat-first wins %.0f%%  ties %d" % [s.part_timer_overs / n, 100.0 * s.bat_first_wins / n, s.ties])
		var per_pitch := []
		for p in by_pitch:
			per_pitch.append("%s %.0f" % [p, by_pitch[p] / (n / by_pitch.size())])
		print("1st inns by pitch: " + ", ".join(per_pitch))

		# What each manager batting instruction does to a first innings.
		var by_approach := []
		for a in MatchEngine.BAT_APPROACHES.size():
			var runs := 0.0
			var wkts := 0.0
			for i in 150:
				var e := MatchEngine.new(teams[0], teams[1], fmt, "balanced", 10000 + i)
				for t in e.teams:
					e.bat_approach[t] = a
				while e.innings.size() == 1:
					e.bowl_ball()
				runs += e.innings[0].runs
				wkts += e.innings[0].wickets
			by_approach.append("%s %.0f/%.1f" % [MatchEngine.BAT_APPROACHES[a], runs / 150.0, wkts / 150.0])
		print("batting approach: " + ", ".join(by_approach))

		# The suggested bowling plan against leaving every bowler on Auto.
		var by_plan := []
		for plan in ["Auto", "Suggested"]:
			var runs := 0.0
			var wkts := 0.0
			for t: CricketTeam in teams:
				t.bowl_roles.clear()
				if plan == "Suggested":
					Tactics.suggest_bowling(t)
			for i in 150:
				var e := MatchEngine.new(teams[i % 2], teams[(i + 1) % 2], fmt, "balanced", 20000 + i)
				while e.innings.size() == 1:
					e.bowl_ball()
				runs += e.innings[0].runs
				wkts += e.innings[0].wickets
			by_plan.append("%s %.0f/%.1f" % [plan, runs / 150.0, wkts / 150.0])
		for t: CricketTeam in teams:
			t.bowl_roles.clear()
		print("bowling plan: " + ", ".join(by_plan))
	quit()
