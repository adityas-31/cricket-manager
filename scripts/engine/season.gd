class_name Season
extends RefCounted
## A league season, FM-style: a calendar of fixtures (double round-robin, then semi-finals
## and a final), results, the table (points, then net run rate), player form, condition and
## season stats, news, and saving. The app holds one Season; Continue calls advance().

const TEAMS_PATH := "res://data/teams.json"
const SAVE_VERSION := 4
const COMPETITION := "Premier T20 League"
const FIRST_YEAR := 2026
## Every season opens on this day of the year (a Saturday in early April).
const SEASON_START := {"month": 4, "day": 4}
const DAYS_BETWEEN_ROUNDS := 3
const PLAYOFF_GAP := 4
## Tuned so batters and spinners are fresh for every game three days later, while a fast
## bowler who plays every match slides toward tiredness after about five: workload management.
const RECOVERY_PER_DAY := 5.0
## Condition every player in an XI loses to the physical load of a match day (travel,
## warm-up, fielding), on top of what they spent during the match itself.
const MATCH_LOAD := 12.0
const INJURY_BASE := 0.012  # per player per match
const INJURY_PER_FATIGUE := 0.05  # extra at full fatigue at the end of a match
const INJURY_DAYS := [3, 4, 5, 6, 7, 7, 10, 12, 14, 21, 28]
const INJURY_TYPES := ["hamstring strain", "side strain", "sore back", "ankle knock", "finger injury",
	"groin strain", "calf tightness", "shoulder strain"]
const WIN_POINTS := 2
const TIE_POINTS := 1
## Prize money for champion, runner-up and the two beaten semi-finalists; the rest of the
## league gets PRIZE_REST, less 15k a place.
const PRIZE_MONEY := [1000000, 600000, 350000, 350000]
const PRIZE_REST := 200000
## AI clubs re-sign out-of-contract players ranked this high in their squad (if under 34).
const KEEP_RANK := 13
## AI clubs top up from free agency to this many players between seasons.
const AI_SQUAD_TARGET := 15
const WEEKDAYS := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

## Tests point this elsewhere so they never touch a real career.
static var save_path := "user://career.json"

var teams: Array = []
var club: CricketTeam
var format := MatchFormat.t20()
var year := FIRST_YEAR
var day := 0  # days since this season opened
var free_agents: Array = []  # players without a club
var next_player_id := 1  # for youth players, above every id in the database
var history: Array = []  # one summary per finished season, see _season_summary()
var credits: Array = []  # data sources to credit (from teams.json's "credits"), shown on Home
var fixtures: Array = []  # {id, day, home, away, stage, round, result}
var news: Array = []  # {day, title, body}, oldest first
var form := {}  # CricketPlayer -> 0-100, 50 = average
var condition := {}  # CricketPlayer -> 0-100
var stats := {}  # CricketPlayer -> season totals, see _blank_stats()
var injuries := {}  # CricketPlayer -> day they are fit again
var contracts := {}  # CricketPlayer -> {wage (per year), until (last season, a year)}
var balance := {}  # CricketTeam -> money in the bank
var wage_budget := {}  # CricketTeam -> most the board lets it spend on wages a year
var ledger: Array = []  # the club's money in and out: {day, text, amount}
var offers: Array = []  # AI bids for the club's players: {player, from, fee, day, status}
var listed := {}  # the club's transfer-listed players -> true
var champion: CricketTeam = null
var training_template := "Balanced"  # the club's default week, a Training.TEMPLATES name
var training_plan := {}  # day -> [morning, afternoon] sessions set by hand (see Training)
var training_focus := {}  # CricketPlayer -> their own focus (Training.INDIVIDUAL), if not the team's
var last_training := {}  # the latest Training.run report, for the Training screen
var match_prep := 0  # Match prep sessions since the club's last match (Training.MAX_PREP at most)
## Lines describing selection changes made at the last start_match() for the club.
var last_selection_changes: Array = []
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


static func new_career(club_index: int) -> Season:
	var s := Season.new()
	s.teams = CricketTeam.load_all(TEAMS_PATH)
	s.credits = CricketTeam.load_credits(TEAMS_PATH)
	s.club = s.teams[clampi(club_index, 0, s.teams.size() - 1)]
	s._init_players()
	for p: CricketPlayer in s.all_players():
		s.next_player_id = maxi(s.next_player_id, p.id + 1)
	Transfers.setup(s)
	for t: CricketTeam in s.teams:
		Selection.auto_select(t, s)
	s._schedule_league()
	var first := s.next_user_fixture()
	s.add_news("Welcome to %s" % s.club.name,
		"The board expects a top-four finish in the %s. The season opens on %s against %s." % [
			COMPETITION, s.date_text(first.day), s.opponent(first).name])
	return s


## Loads the saved career, or starts a new one with the first team if there is none.
static func load_or_new() -> Season:
	if FileAccess.file_exists(save_path):
		var loaded := load_from(save_path)
		if loaded:
			return loaded
		push_warning("Save at %s is incompatible; starting a new career" % save_path)
	var s := new_career(0)
	s.save()
	return s


# --- calendar --------------------------------------------------------------------

## The date of day d (default today) of the given season (default this one).
func date_text(d := -1, season_year := -1) -> String:
	var start := {"year": year if season_year < 0 else season_year, "month": SEASON_START.month, "day": SEASON_START.day, "hour": 12, "minute": 0, "second": 0}
	var unix := Time.get_unix_time_from_datetime_dict(start) + (day if d < 0 else d) * 86400
	var dt := Time.get_datetime_dict_from_unix_time(unix)
	return "%s %d %s %d" % [WEEKDAYS[dt.weekday], dt.day, MONTHS[dt.month - 1], dt.year]


func fixtures_on(d: int) -> Array:
	return fixtures.filter(func(f): return f.day == d)


func involves(f: Dictionary, team: CricketTeam) -> bool:
	return f.home == team or f.away == team


func opponent(f: Dictionary, team: CricketTeam = null) -> CricketTeam:
	var me := club if team == null else team
	return f.away if f.home == me else f.home


func stage_text(f: Dictionary) -> String:
	return "Round %d" % f.round if f.stage == "League" else f.stage


func user_fixture_today() -> Dictionary:
	for f in fixtures_on(day):
		if involves(f, club):
			return f
	return {}


func user_match_pending() -> bool:
	var f := user_fixture_today()
	return not f.is_empty() and f.result.is_empty()


func next_user_fixture() -> Dictionary:
	for f in fixtures:
		if involves(f, club) and f.result.is_empty():
			return f
	return {}


func last_user_result() -> Dictionary:
	var played := fixtures.filter(func(f): return involves(f, club) and not f.result.is_empty())
	return played[-1] if not played.is_empty() else {}


func is_over() -> bool:
	return champion != null


func is_injured(p: CricketPlayer) -> bool:
	return injuries.get(p, -1) > day


func injury_days(p: CricketPlayer) -> int:
	return maxi(injuries.get(p, day) - day, 0)


## Plays the rest of today's fixtures, then moves to the next day that has fixtures.
## Returns false if the club still has to play today, or the season is over.
func advance() -> bool:
	if user_match_pending():
		return false
	for f in fixtures_on(day):
		if f.result.is_empty():
			play_ai(f)
	var next := -1
	for f in fixtures:
		if f.result.is_empty() and (next < 0 or f.day < next):
			next = f.day
	if next < 0:
		save()
		return false
	for p in condition:
		if not p in club.squad:  # the club's squad recovers through training, below
			condition[p] = minf(condition[p] + RECOVERY_PER_DAY * (next - day), 100.0)
	var was := day
	day = next
	_pay_wages(day / 7 - was / 7)
	Transfers.expire_offers(self)
	Transfers.make_ai_offers(self, day - was)
	var deadline := Transfers.deadline_day(self)
	if was <= deadline and day > deadline:
		add_news("Transfer window closed", "No more signings or sales until the end of the season.")
	for p: CricketPlayer in injuries.keys():
		if injuries[p] > was and injuries[p] <= day:
			injuries.erase(p)
			if p in club.squad:
				add_news("%s is fit again" % p.name, "Back in full training and available for selection.")
	last_training = Training.run(self, was, day)
	for d: int in training_plan.keys():
		if d <= day:
			training_plan.erase(d)
	var report := Training.summary(last_training, self)
	if report != "":
		add_news("Training report", report)
		var gains: Dictionary = last_training.gains
		GameLog.event("training", {"days": last_training.days.map(func(x): return x.sessions), "template": training_template,
			"individual": training_focus.size(), "injured": last_training.injured.map(func(x): return x.name),
			"prep": last_training.prep, "gain": snappedf(gains.values().reduce(func(a, b): return a + b, 0.0), 0.01)})
	save()
	return true


# --- matches ---------------------------------------------------------------------

## A match engine for a fixture. AI clubs (and the club, if the assistant picks) choose
## their XI first; the club's own XI is kept legal. Players carry condition and form in.
func start_match(f: Dictionary) -> MatchEngine:
	last_selection_changes = []
	for t: CricketTeam in [f.home, f.away]:
		if t != club or t.assistant_selects:
			Selection.auto_select(t, self)
		else:
			last_selection_changes = Selection.ensure_valid(t, self)
			if not last_selection_changes.is_empty():
				add_news("Team changes v %s" % opponent(f).name, ". ".join(last_selection_changes) + ".")
	var e := MatchEngine.new(f.home, f.away, format, f.home.home_pitch)
	for t: CricketTeam in e.teams:
		for p in t.players:
			e.states[p].condition = condition[p]
			e.states[p].confidence = 50.0 + (form[p] - 50.0) * 0.5
			if t == club:
				e.states[p].confidence += match_prep * Training.PREP_CONFIDENCE
	if involves(f, club):
		match_prep = 0
	return e


func play_ai(f: Dictionary) -> void:
	var e := start_match(f)
	while not e.finished:
		e.bowl_ball()
	record(f, e)


## Stores a finished match: result, table data, ratings, form, condition, stats and news.
func record(f: Dictionary, e: MatchEngine) -> void:
	if not f.result.is_empty() or not e.finished:
		return
	var ratings := MatchRatings.compute(e)
	var winner: CricketTeam = e.winner
	var text := e.result_text
	if winner == null and f.stage != "League":
		winner = f.home  # knockout ties go to the higher seed, who hosts
		text += "; %s go through as the higher seed" % f.home.name
	var innings := []
	for inn: Innings in e.main_innings():  # super overs stay out of stats and NRR
		innings.append({"team": inn.batting_team, "runs": inn.runs, "wickets": inn.wickets,
			"balls": inn.legal_balls, "all_out": inn.wickets >= inn.max_wickets})
	f.result = {"winner": winner, "text": text, "innings": innings,
		"potm": MatchRatings.player_of_match(e, ratings), "ratings": ratings}
	_update_players(e, ratings)
	_gate_receipts(f)
	if involves(f, club):
		_report(f)
	GameLog.event("result", {"date": date_text(f.day), "stage": stage_text(f), "home": f.home.name, "away": f.away.name,
		"result": text, "score": score_line(f), "ours": involves(f, club), "super_overs": e.super_overs})
	_update_playoffs()


func _update_players(e: MatchEngine, ratings: Dictionary) -> void:
	for p: CricketPlayer in ratings:
		var r: float = ratings[p]
		form[p] = form[p] * 0.65 + clampf((r - 3.0) / 7.0 * 100.0, 0.0, 100.0) * 0.35
		condition[p] = maxf(e.states[p].condition - MATCH_LOAD, 0.0)
		stats[p].apps += 1
		stats[p].rating_sum += r
		_roll_injury(p)

	for inn: Innings in e.main_innings():  # super overs stay out of stats and NRR
		for b in inn.batters:
			var s: Dictionary = stats[b.player]
			s.inns += 1
			s.runs += b.runs
			s.balls += b.balls
			s.fours += b.fours
			s.sixes += b.sixes
			if not b.out:
				s.not_outs += 1
			if b.runs > s.hs or (b.runs == s.hs and not b.out):
				s.hs = b.runs
				s.hs_not_out = not b.out
			if b.runs >= 100:
				s.hundreds += 1
			elif b.runs >= 50:
				s.fifties += 1
			if b.player in club.squad and b.runs >= 50:
				add_news("%s %s" % [b.player.name, "hits a century" if b.runs >= 100 else "makes a fifty"],
					"%d off %d balls against %s." % [b.runs, b.balls, inn.bowling_team.name])
		for b in inn.bowlers:
			var s: Dictionary = stats[b.player]
			s.bowl_balls += b.balls
			s.bowl_runs += b.runs
			s.wickets += b.wickets
			if b.wickets > s.best_w or (b.wickets == s.best_w and b.runs < s.best_r):
				s.best_w = b.wickets
				s.best_r = b.runs
			if b.player in club.squad and b.wickets >= 4:
				add_news("%s takes %d wickets" % [b.player.name, b.wickets],
					"Figures of %d-%d against %s." % [b.wickets, b.runs, inn.batting_team.name])
		for f in inn.fall_of_wickets:
			if f.fielder != null and f.kind in ["caught", "stumped"]:
				stats[f.fielder].catches += 1


## Home sides take the gate (more the higher they sit in the table); both play-off sides get one.
func _gate_receipts(f: Dictionary) -> void:
	var takers: Array = [f.home] if f.stage == "League" else [f.home, f.away]
	for t: CricketTeam in takers:
		var gate: int = Transfers.PLAYOFF_GATE if f.stage != "League" else \
			Transfers.GATE_BASE + Transfers.GATE_PER_PLACE * (teams.size() + 1 - position(t))
		balance[t] += gate
		if t == club:
			log_money(gate, "Gate receipts v %s" % opponent(f).name)


func _pay_wages(weeks: int) -> void:
	for i in weeks:
		for t: CricketTeam in teams:
			var weekly := Transfers.wage_bill(t, self) / 52.0
			balance[t] -= weekly
			if t == club:
				log_money(-weekly, "Weekly wages")


func log_money(amount: float, text: String) -> void:
	ledger.append({"day": day, "text": text, "amount": amount})


## Tired players break down more often.
func _roll_injury(p: CricketPlayer) -> void:
	var chance := INJURY_BASE + MatchDynamics.fatigue(condition[p]) * INJURY_PER_FATIGUE
	if rng.randf() >= chance:
		return
	injure(p)


## Puts a player out for a random spell. where: "" for a match, or e.g. "in training".
func injure(p: CricketPlayer, where := "") -> void:
	var days: int = INJURY_DAYS[rng.randi_range(0, INJURY_DAYS.size() - 1)]
	injuries[p] = day + days
	if p in club.squad:
		add_news("%s injured%s" % [p.name, " " + where if where != "" else ""], "Out for about %d days with a %s." % [
			days, INJURY_TYPES[rng.randi_range(0, INJURY_TYPES.size() - 1)]])
		GameLog.event("injury", {"player": p.name, "days": days, "condition": roundi(condition[p]), "where": where})


func _report(f: Dictionary) -> void:
	var res: Dictionary = f.result
	var other := opponent(f)
	var verb := "Defeat to"
	if res.winner == club:
		verb = "Victory over"
	elif res.winner == null:
		verb = "Tie with"
	var potm: CricketPlayer = res.potm
	add_news("%s %s" % [verb, other.name], "%s. %s. Player of the match: %s (%.1f)." % [
		score_line(f), res.text, potm.name, res.ratings[potm]])


func score_line(f: Dictionary) -> String:
	var parts := []
	for inn in f.result.get("innings", []):
		var score := str(inn.runs) if inn.all_out else "%d/%d" % [inn.runs, inn.wickets]
		parts.append("%s %s (%s)" % [inn.team.short_name, score, Innings.overs_text(inn.balls)])
	return "  ·  ".join(parts)


func _update_playoffs() -> void:
	var league := fixtures.filter(func(f): return f.stage == "League")
	if league.any(func(f): return f.result.is_empty()):
		return
	var semis := fixtures.filter(func(f): return f.stage == "Semi-final")
	if semis.is_empty() and teams.size() < 4:
		if champion == null:  # too few teams for play-offs: top of the table wins
			champion = table()[0].team
			add_news("%s are champions!" % champion.name, "%s top the %s." % [champion.name, COMPETITION])
		return
	if semis.is_empty():
		var top := table().slice(0, 4).map(func(r): return r.team)
		var d: int = league.map(func(f): return f.day).max() + PLAYOFF_GAP
		_add_fixture(d, top[0], top[3], "Semi-final", 0)
		_add_fixture(d, top[1], top[2], "Semi-final", 0)
		add_news("Play-offs set", "%s v %s and %s v %s in the semi-finals on %s." % [
			top[0].name, top[3].name, top[1].name, top[2].name, date_text(d)])
		return
	if semis.any(func(f): return f.result.is_empty()):
		return
	var finals := fixtures.filter(func(f): return f.stage == "Final")
	if finals.is_empty():
		var a: CricketTeam = semis[0].result.winner
		var b: CricketTeam = semis[1].result.winner
		if position(b) < position(a):
			var swap := a
			a = b
			b = swap
		var d: int = semis[0].day + DAYS_BETWEEN_ROUNDS
		_add_fixture(d, a, b, "Final", 0)
		add_news("Final: %s v %s" % [a.name, b.name], "The %s final is on %s." % [COMPETITION, date_text(d)])
		return
	if champion == null and not finals[0].result.is_empty():
		champion = finals[0].result.winner
		add_news("%s are champions!" % champion.name, "%s win the %s. %s" % [
			champion.name, COMPETITION, finals[0].result.text])


# --- table and stats ---------------------------------------------------------------

## League table rows {team, p, w, l, t, pts, nrr, form}, sorted by points then net run rate.
func table() -> Array:
	var rows := {}
	for t in teams:
		rows[t] = {"team": t, "p": 0, "w": 0, "l": 0, "t": 0, "pts": 0, "rf": 0, "bf": 0, "ra": 0, "ba": 0, "form": []}
	for f in fixtures:
		if f.stage != "League" or f.result.is_empty():
			continue
		var res: Dictionary = f.result
		for side in [f.home, f.away]:
			var row: Dictionary = rows[side]
			row.p += 1
			if res.winner == null:
				row.t += 1
				row.pts += TIE_POINTS
				row.form.append("T")
			elif res.winner == side:
				row.w += 1
				row.pts += WIN_POINTS
				row.form.append("W")
			else:
				row.l += 1
				row.form.append("L")
		for inn in res.innings:
			# Net run rate counts an all-out side as having faced its full quota.
			var balls: int = format.overs * 6 if inn.all_out else inn.balls
			var bowling: CricketTeam = f.home if inn.team == f.away else f.away
			rows[inn.team].rf += inn.runs
			rows[inn.team].bf += balls
			rows[bowling].ra += inn.runs
			rows[bowling].ba += balls
	var list := rows.values()
	for row in list:
		row.nrr = row.rf * 6.0 / maxi(row.bf, 1) - row.ra * 6.0 / maxi(row.ba, 1)
	list.sort_custom(func(a, b): return a.pts > b.pts if a.pts != b.pts else a.nrr > b.nrr)
	return list


func position(team: CricketTeam) -> int:
	var rows := table()
	for i in rows.size():
		if rows[i].team == team:
			return i + 1
	return 0


## The player's club, or null for a free agent.
func team_of(p: CricketPlayer) -> CricketTeam:
	for t in teams:
		if p in t.squad:
			return t
	return null


func all_players() -> Array:
	var out := free_agents.duplicate()
	for t: CricketTeam in teams:
		out.append_array(t.squad)
	return out


func average_rating(p: CricketPlayer) -> float:
	var s: Dictionary = stats[p]
	return s.rating_sum / s.apps if s.apps > 0 else 0.0


func batting_average(p: CricketPlayer) -> float:
	var s: Dictionary = stats[p]
	return s.runs / maxf(s.inns - s.not_outs, 1.0)


## Top n players by "runs", "wickets" or "rating" (rating needs 3+ appearances).
func leaders(key: String, n := 10) -> Array:
	var players := stats.keys()
	if key == "rating":
		players = players.filter(func(p): return stats[p].apps >= 3)
		players.sort_custom(func(a, b): return average_rating(a) > average_rating(b))
	else:
		players = players.filter(func(p): return stats[p][key] > 0)
		players.sort_custom(func(a, b): return stats[a][key] > stats[b][key])
	return players.slice(0, n)


func add_news(title: String, body: String) -> void:
	news.append({"year": year, "day": day, "title": title, "body": body})


func news_date(n: Dictionary) -> String:
	return date_text(int(n.day), int(n.get("year", year)))


# --- setup ---------------------------------------------------------------------------

func _init_players() -> void:
	for p in all_players():
		form[p] = 50.0
		condition[p] = 100.0
		stats[p] = _blank_stats()


static func _blank_stats() -> Dictionary:
	return {"apps": 0, "rating_sum": 0.0, "inns": 0, "runs": 0, "balls": 0, "not_outs": 0, "hs": 0,
		"hs_not_out": false, "fifties": 0, "hundreds": 0, "fours": 0, "sixes": 0,
		"bowl_balls": 0, "bowl_runs": 0, "wickets": 0, "best_w": 0, "best_r": 0, "catches": 0}


## Double round-robin by the circle method: every team plays every other home and away.
## With an odd number of teams one side sits out each round (a bye, index -1).
func _schedule_league() -> void:
	var order := range(teams.size())
	if order.size() % 2 == 1:
		order.append(-1)
	var n := order.size()
	var rounds := []
	for r in n - 1:
		var pairs := []
		for i in n / 2:
			var a: int = order[i]
			var b: int = order[n - 1 - i]
			if a < 0 or b < 0:
				continue
			pairs.append([a, b] if (r + i) % 2 == 0 else [b, a])
		rounds.append(pairs)
		order.insert(1, order.pop_back())
	for leg in 2:
		for r in rounds.size():
			var round_no := leg * rounds.size() + r
			for pair in rounds[r]:
				_add_fixture(round_no * DAYS_BETWEEN_ROUNDS, teams[pair[leg]], teams[pair[1 - leg]], "League", round_no + 1)


func _add_fixture(d: int, home: CricketTeam, away: CricketTeam, stage: String, round_no: int) -> void:
	fixtures.append({"id": fixtures.size(), "day": d, "home": home, "away": away, "stage": stage,
		"round": round_no, "result": {}})


# --- between seasons ---------------------------------------------------------------------

## Wraps up a finished season (prize money, awards, board review, contracts, retirements,
## development, youth intake, AI signings) and starts the next. False if it isn't over yet.
func start_next_season() -> bool:
	if not is_over():
		return false
	var standings := final_standings()
	_award_prizes(standings)
	var summary := _season_summary(standings)
	history.append(summary)
	GameLog.event("season_review", summary)
	add_news("Season %d review" % year, "%s are champions. %s finished %s. Player of the season: %s. Most runs: %s. Most wickets: %s. Young player: %s." % [
		summary.champion, club.name, ordinal(summary.club_finish), summary.player_of_season,
		summary.top_runs, summary.top_wickets, summary.young_player])
	_board_review(standings)
	_expire_contracts()
	_retire_and_develop()
	_youth_intake()
	_sign_free_agents()
	_reset_for(year + 1)
	var first := next_user_fixture()
	if not first.is_empty():
		add_news("Season %d begins" % year, "The %s opens on %s against %s. The transfer window is open until %s." % [
			COMPETITION, date_text(first.day), opponent(first).name, date_text(Transfers.deadline_day(self))])
	save()
	return true


## Every club in finishing order: champion, runner-up, beaten semi-finalists (by league
## position), then the rest of the table.
func final_standings() -> Array:
	var order := table().map(func(r): return r.team)
	var finals := fixtures.filter(func(f): return f.stage == "Final" and not f.result.is_empty())
	if finals.is_empty():
		return order
	var f: Dictionary = finals[0]
	var top := [champion, f.away if f.result.winner == f.home else f.home]
	var beaten := []
	for sf in fixtures.filter(func(x): return x.stage == "Semi-final"):
		beaten.append(sf.away if sf.result.winner == sf.home else sf.home)
	beaten.sort_custom(func(a, b): return order.find(a) < order.find(b))
	top.append_array(beaten)
	for t in order:
		if not t in top:
			top.append(t)
	return top


static func ordinal(n: int) -> String:
	if n % 100 in [11, 12, 13]:
		return "%dth" % n
	return "%d%s" % [n, {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")]


func _award_prizes(standings: Array) -> void:
	for i in standings.size():
		var prize: int = PRIZE_MONEY[i] if i < PRIZE_MONEY.size() else \
			maxi(PRIZE_REST - 15000 * (i - PRIZE_MONEY.size()), 50000)
		balance[standings[i]] += prize
		if standings[i] == club:
			log_money(prize, "Prize money (%s place)" % ordinal(i + 1))


func _season_summary(standings: Array) -> Dictionary:
	var games := 2 * (teams.size() - 1)
	var regulars := stats.keys().filter(func(p): return stats[p].apps >= maxi(games / 2, 1))
	regulars.sort_custom(func(a, b): return average_rating(a) > average_rating(b))
	var young := regulars.filter(func(p): return p.age <= 23)
	var runs := leaders("runs", 1)
	var wickets := leaders("wickets", 1)
	return {
		"year": year,
		"champion": champion.name,
		"runner_up": standings[1].name if standings.size() > 1 else "",
		"club": club.name,
		"club_finish": standings.find(club) + 1,
		"player_of_season": "%s, %.2f" % [_who(regulars[0]), average_rating(regulars[0])] if not regulars.is_empty() else "-",
		"top_runs": "%s, %d" % [_who(runs[0]), stats[runs[0]].runs] if not runs.is_empty() else "-",
		"top_wickets": "%s, %d" % [_who(wickets[0]), stats[wickets[0]].wickets] if not wickets.is_empty() else "-",
		"young_player": "%s, %.2f" % [_who(young[0]), average_rating(young[0])] if not young.is_empty() else "-",
	}


func _who(p: CricketPlayer) -> String:
	var t := team_of(p)
	return "%s (%s)" % [p.name, t.short_name if t else "FA"]


## The board judges the finish against where the squad's strength said the club should
## finish, and raises the wage budget for doing better.
func _board_review(standings: Array) -> void:
	var by_strength := teams.duplicate()
	by_strength.sort_custom(func(a, b): return _xi_strength(a) > _xi_strength(b))
	var expected := by_strength.find(club) + 1
	var finish := standings.find(club) + 1
	var verdict := "disappointed"
	var rise := 0.0
	if finish <= expected - 2:
		verdict = "delighted"
		rise = 0.15
	elif finish <= expected:
		verdict = "pleased"
		rise = 0.08
	elif finish <= expected + 2:
		verdict = "satisfied"
		rise = 0.03
	wage_budget[club] = int(wage_budget[club] * (1.0 + rise))
	for t: CricketTeam in teams:
		if t != club:
			wage_budget[t] = int(wage_budget[t] * 1.05)
	add_news("Board review", "The board expected %s and you finished %s. They are %s.%s" % [
		ordinal(expected), ordinal(finish), verdict,
		" The wage budget rises to %s." % Transfers.money(wage_budget[club]) if rise > 0.0 else ""])


func _xi_strength(t: CricketTeam) -> float:
	var abilities := t.squad.map(func(p): return Transfers.ability(p))
	abilities.sort()
	abilities.reverse()
	var total := 0.0
	for a in abilities.slice(0, CricketTeam.XI_SIZE):
		total += a
	return total


## Contracts ending this season: AI clubs keep the players they rate (and who aren't too
## old); everyone else, and the club's unrenewed players, become free agents.
func _expire_contracts() -> void:
	var left := []
	for t: CricketTeam in teams:
		var ranked := t.squad.duplicate()
		ranked.sort_custom(func(a, b): return Transfers.ability(a) > Transfers.ability(b))
		for p: CricketPlayer in t.squad.duplicate():
			if int(contracts[p].until) > year:
				continue
			if t != club and ranked.find(p) < KEEP_RANK and p.age < 34:
				contracts[p] = {"wage": Transfers.wage_demand(p, self), "until": year + Transfers.demand_years(p)}
				continue
			_remove_player(p)
			free_agents.append(p)
			if t == club:
				left.append(p.name)
	if not left.is_empty():
		add_news("Contracts expired", "%s left the club on free transfers." % ", ".join(left))


func _retire_and_develop() -> void:
	var averages := {}
	for p in all_players():
		averages[p] = average_rating(p) if stats.has(p) else 0.0
	var retired := []
	for p: CricketPlayer in all_players():
		if Development.retires(p, rng):
			if p in club.squad or Transfers.ability(p) >= 14.0:
				retired.append(_who(p))
			_remove_player(p)
			continue
		Development.age_player(p, averages[p], rng)
	if not retired.is_empty():
		add_news("Retirements", "%s retired at the end of the season." % ", ".join(retired))


func _youth_intake() -> void:
	var names := Development.load_names()
	for t: CricketTeam in teams:
		if t.squad.size() < Transfers.SQUAD_MAX:
			_academy_player(t, names, "Youth intake")


## Promotes a youngster from a club's academy into its squad.
func _academy_player(t: CricketTeam, names: Dictionary, headline: String) -> void:
	var p := Development.youth_player(next_player_id, rng, names, t.name)
	next_player_id += 1
	t.squad.append(p)
	contracts[p] = {"wage": 20000, "until": year + 3}
	if t == club:
		add_news("%s: %s" % [headline, p.name], "A %d-year-old %s joins from the academy." % [
			p.age, str(CricketPlayer.Role.keys()[p.role]).capitalize().to_lower()])


## AI clubs top their squads up from free agency, best first; the club only gets help if
## it couldn't field an XI.
func _sign_free_agents() -> void:
	for t: CricketTeam in teams:
		var target := AI_SQUAD_TARGET if t != club else CricketTeam.XI_SIZE + 1
		while t.squad.size() < target and not free_agents.is_empty():
			free_agents.sort_custom(func(a, b): return Transfers.ability(a) > Transfers.ability(b))
			var p: CricketPlayer = free_agents[0]
			Transfers.complete(p, t, 0, Transfers.wage_demand(p, self), Transfers.demand_years(p), self)
			if t == club:
				add_news("The board signs %s" % p.name, "With the squad too small to field an XI, the board brought in a free agent.")
	# An ageing squad can lose more players than free agency can replace (an imported
	# database full of veterans, say): academies make up the numbers.
	var names := Development.load_names()
	for t: CricketTeam in teams:
		while t.squad.size() < Transfers.SQUAD_MIN:
			_academy_player(t, names, "Academy call-up")


func _remove_player(p: CricketPlayer) -> void:
	var t := team_of(p)
	if t:
		t.squad.erase(p)
		t.players.erase(p)
		t.bat_roles.erase(p)
		t.bowl_roles.erase(p)
	free_agents.erase(p)
	contracts.erase(p)
	injuries.erase(p)
	listed.erase(p)
	training_focus.erase(p)


func _reset_for(new_year: int) -> void:
	year = new_year
	day = 0
	fixtures = []
	champion = null
	offers = []
	listed = {}
	ledger = []
	injuries = {}
	training_plan = {}
	match_prep = 0
	var everyone := all_players()
	var new_form := {}
	condition = {}
	stats = {}
	for p in everyone:
		new_form[p] = 50.0 + (form.get(p, 50.0) - 50.0) * 0.5
		condition[p] = 100.0
		stats[p] = _blank_stats()
	form = new_form
	for p in everyone:
		if not contracts.has(p) and team_of(p) != null:
			contracts[p] = {"wage": Transfers.wage_demand(p, self), "until": year + 1}
	_schedule_league()
	for t: CricketTeam in teams:
		if t == club and not t.assistant_selects:
			t.players = t.players.filter(func(p): return p in t.squad)
			Selection.ensure_valid(t, self)
		else:
			Selection.auto_select(t, self)


# --- saving --------------------------------------------------------------------------

## Saves are self-contained: they carry every player (ages and attributes change between
## seasons) and every club, so editing teams.json only affects new careers.
func save() -> void:
	var data := {
		"version": SAVE_VERSION,
		"year": year,
		"club": teams.find(club),
		"day": day,
		"champion": teams.find(champion) if champion else -1,
		"next_player_id": next_player_id,
		"news": news,
		"history": history,
		"credits": credits,
		"people": all_players().map(func(p): return p.to_dict()),
		"free_agents": free_agents.map(func(p): return p.id),
		"teams": [],
		"players": {},
		"fixtures": [],
	}
	for t: CricketTeam in teams:
		data.teams.append({
			"name": t.name,
			"short": t.short_name,
			"colour": "#" + t.colour.to_html(false),
			"pitch": t.home_pitch,
			"squad": t.squad.map(func(p): return p.id),
			"balance": balance[t],
			"wage_budget": wage_budget[t],
			"order": t.players.map(func(p): return p.id),
			"bat_roles": _roles_by_id(t.bat_roles),
			"bowl_roles": _roles_by_id(t.bowl_roles),
			"bat_approach": t.default_bat_approach,
			"bowl_approach": t.default_bowl_approach,
			"assistant_selects": t.assistant_selects,
		})
	data.injuries = {}
	for p: CricketPlayer in injuries:
		data.injuries[str(p.id)] = injuries[p]
	data.contracts = {}
	for p: CricketPlayer in contracts:
		data.contracts[str(p.id)] = contracts[p]
	data.ledger = ledger
	data.offers = offers.map(func(o): return {"player": o.player.id, "from": teams.find(o.from), "fee": o.fee,
		"day": o.day, "status": o.status})
	data.listed = listed.keys().map(func(p): return p.id)
	data.training_template = training_template
	data.training_plan = {}
	for d: int in training_plan:
		data.training_plan[str(d)] = training_plan[d]
	data.match_prep = match_prep
	data.training_focus = {}
	for p: CricketPlayer in training_focus:
		data.training_focus[str(p.id)] = training_focus[p]
	for p: CricketPlayer in stats:
		data.players[str(p.id)] = {"form": form[p], "condition": condition[p], "stats": stats[p]}
	for f in fixtures:
		var fd := {"day": f.day, "home": teams.find(f.home), "away": teams.find(f.away), "stage": f.stage,
			"round": f.round, "result": {}}
		if not f.result.is_empty():
			var res: Dictionary = f.result
			var ratings := {}
			for p in res.ratings:
				ratings[str(p.id)] = res.ratings[p]
			fd.result = {
				"winner": teams.find(res.winner) if res.winner else -1,
				"text": res.text,
				"innings": res.innings.map(func(i): return {"team": teams.find(i.team), "runs": i.runs,
					"wickets": i.wickets, "balls": i.balls, "all_out": i.all_out}),
				"potm": res.potm.id,
				"ratings": ratings,
			}
		data.fixtures.append(fd)
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not save career to %s" % save_path)
		return
	file.store_string(JSON.stringify(data, "\t"))


## Rebuilds a career from a save, or null if it's from an older version of the game.
static func load_from(path: String) -> Season:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != SAVE_VERSION:
		return null
	var s := Season.new()
	var by_id := {}
	for pd in data.people:
		var p := CricketPlayer.from_dict(pd)
		by_id[p.id] = p
	var players_for := func(ids: Array) -> Array:
		return ids.filter(func(id): return by_id.has(int(id))).map(func(id): return by_id[int(id)])

	for td in data.teams:
		var t := CricketTeam.from_dict({"name": td.name, "short": td.short, "colour": td.colour, "pitch": td.pitch})
		t.squad = players_for.call(td.squad)
		t.players = players_for.call(td.order).filter(func(p): return p in t.squad)
		t.bat_roles = _roles_from_ids(td.bat_roles, by_id)
		t.bowl_roles = _roles_from_ids(td.bowl_roles, by_id)
		t.default_bat_approach = int(td.bat_approach)
		t.default_bowl_approach = int(td.bowl_approach)
		t.assistant_selects = bool(td.assistant_selects)
		s.teams.append(t)
		s.balance[t] = float(td.balance)
		s.wage_budget[t] = int(td.wage_budget)
	s.free_agents = players_for.call(data.free_agents)
	s._init_players()

	for key in data.injuries:
		s.injuries[by_id[int(key)]] = int(data.injuries[key])
	for key in data.contracts:
		s.contracts[by_id[int(key)]] = {"wage": int(data.contracts[key].wage), "until": int(data.contracts[key].until)}
	s.ledger = data.ledger
	for od in data.offers:
		s.offers.append({"player": by_id[int(od.player)], "from": s.teams[int(od.from)], "fee": int(od.fee),
			"day": int(od.day), "status": od.status})
	for id in data.listed:
		s.listed[by_id[int(id)]] = true
	if Training.TEMPLATES.has(data.get("training_template")):
		s.training_template = data.training_template
	var plan: Dictionary = data.get("training_plan", {})
	for key in plan:
		var sessions: Array = plan[key]
		if sessions.size() == 2 and sessions.all(func(x): return Training.SESSIONS.has(x)):
			s.training_plan[int(key)] = sessions
	s.match_prep = int(data.get("match_prep", 0))
	var focus: Dictionary = data.get("training_focus", {})
	for key in focus:
		if by_id.has(int(key)) and focus[key] in Training.INDIVIDUAL:
			s.training_focus[by_id[int(key)]] = focus[key]
	for key in data.players:
		var p: CricketPlayer = by_id.get(int(key))
		if p == null:
			continue
		var pd: Dictionary = data.players[key]
		s.form[p] = float(pd.form)
		s.condition[p] = float(pd.condition)
		for stat in pd.stats:
			s.stats[p][stat] = pd.stats[stat]

	for fd in data.fixtures:
		s._add_fixture(int(fd.day), s.teams[int(fd.home)], s.teams[int(fd.away)], fd.stage, int(fd.round))
		var rd: Dictionary = fd.result
		if rd.is_empty():
			continue
		var ratings := {}
		for key in rd.ratings:
			ratings[by_id[int(key)]] = float(rd.ratings[key])
		s.fixtures[-1].result = {
			"winner": s.teams[int(rd.winner)] if int(rd.winner) >= 0 else null,
			"text": rd.text,
			"innings": rd.innings.map(func(i): return {"team": s.teams[int(i.team)], "runs": int(i.runs),
				"wickets": int(i.wickets), "balls": int(i.balls), "all_out": i.all_out}),
			"potm": by_id.get(int(rd.potm)),
			"ratings": ratings,
		}

	s.year = int(data.year)
	s.club = s.teams[int(data.club)]
	s.day = int(data.day)
	s.champion = s.teams[int(data.champion)] if int(data.champion) >= 0 else null
	s.next_player_id = int(data.next_player_id)
	s.news = data.news
	s.history = data.history
	s.credits = data.get("credits", [])
	return s


static func _roles_by_id(roles: Dictionary) -> Dictionary:
	var out := {}
	for p in roles:
		out[str(p.id)] = roles[p]
	return out


static func _roles_from_ids(roles: Dictionary, by_id: Dictionary) -> Dictionary:
	var out := {}
	for key in roles:
		if by_id.has(int(key)):
			out[by_id[int(key)]] = roles[key]
	return out
