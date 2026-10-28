class_name Innings
extends RefCounted
## Score and scorecard for one innings. MatchEngine feeds it one delivery at a time via record().

var number := 1
var batting_team: CricketTeam
var bowling_team: CricketTeam
var target := -1  # runs needed to win, or -1 when batting first
## The batting order. For a normal innings this is the team's XI array itself, so reordering
## the team mid-innings changes who comes in next; a super over gets its own three.
var lineup: Array = []
var max_balls := 120
var max_wickets := 10
var super_over := false
var reviews := {}  # CricketTeam -> unsuccessful reviews left this innings

var runs := 0
var wickets := 0
var legal_balls := 0
var wides := 0
var no_balls := 0
var dots := 0
var fours := 0
var sixes := 0

var batters: Array = []  # batting card entries, in order of arrival
var bowlers: Array = []  # bowling card entries, in order of first over
var fall_of_wickets: Array = []  # {runs, balls, wicket, player, kind, fielder, bowler}
var drops: Array = []  # fielders who dropped a catch
var striker: Dictionary
var non_striker: Dictionary
var bowler: Dictionary = {}  # current over's bowling entry; empty between overs
var last_over_bowler: CricketPlayer = null
var this_over: Array = []  # symbols for the current (or just finished) over
var free_hit := false
var pressure := 0.0  # on the batting side, 0-100; see MatchDynamics

var _over_conceded := 0


func _init(innings_number: int, batting: CricketTeam, bowling: CricketTeam, target_runs: int,
		balls := 120, batters: Array = [], is_super_over := false, review_count := 2) -> void:
	number = innings_number
	batting_team = batting
	bowling_team = bowling
	target = target_runs
	max_balls = balls
	lineup = batters if not batters.is_empty() else batting.players
	max_wickets = lineup.size() - 1
	super_over = is_super_over
	reviews = {batting: review_count, bowling: review_count}
	striker = _arrive(lineup[0])
	non_striker = _arrive(lineup[1])


## "powerplay", "middle" or "death"; a super over is all death.
func phase(fmt: MatchFormat) -> String:
	return "death" if super_over else fmt.phase(mini(legal_balls / 6, fmt.overs - 1))


func is_complete() -> bool:
	return wickets >= max_wickets or legal_balls >= max_balls or (target > 0 and runs >= target)


static func overs_text(balls: int) -> String:
	return str(balls / 6) if balls % 6 == 0 else "%d.%d" % [balls / 6, balls % 6]


func score_text() -> String:
	return "%d/%d" % [runs, wickets] if wickets < max_wickets else str(runs)


func run_rate() -> float:
	return runs * 6.0 / maxi(legal_balls, 1)


func balls_left(_fmt: MatchFormat = null) -> int:
	return max_balls - legal_balls


func runs_needed() -> int:
	return target - runs


func extras() -> int:
	return wides + no_balls


func overs_bowled_by(p: CricketPlayer) -> int:
	for e in bowlers:
		if e.player == p:
			return ceili(e.balls / 6.0)
	return 0


## Players still to come in, in the current batting order.
func yet_to_bat() -> Array:
	var batted := batters.map(func(e): return e.player)
	return lineup.filter(func(p): return not p in batted)


## Sends p in next: moves them ahead of everyone else still waiting in the lineup.
func promote(p: CricketPlayer) -> void:
	var waiting := yet_to_bat()
	if not p in waiting or waiting[0] == p:
		return
	lineup.erase(p)
	lineup.insert(lineup.find(waiting[0]), p)


func partnership() -> Dictionary:
	var last: Dictionary = fall_of_wickets[-1] if not fall_of_wickets.is_empty() else {"runs": 0, "balls": 0}
	return {"runs": runs - last.runs, "balls": legal_balls - last.balls}


func start_over(p: CricketPlayer) -> void:
	bowler = _bowling_entry(p)
	this_over = []
	_over_conceded = 0


func end_over() -> void:
	if _over_conceded == 0:
		bowler.maidens += 1
	last_over_bowler = bowler.player
	bowler = {}
	_swap_strike()


## Applies one delivery from DeliveryModel.bowl().
## Returns {symbol, out, incoming}; out and incoming are batting entries when a wicket fell.
func record(r: Dictionary) -> Dictionary:
	var batter_runs: int = r.runs
	var total: int = batter_runs + int(r.extra_runs)
	runs += total
	bowler.runs += total
	_over_conceded += total

	if r.extra == "wd":
		wides += int(r.extra_runs)
		bowler.wides += 1
		this_over.append("wd")
		return {"symbol": "wd"}

	if r.extra == "nb":
		no_balls += 1
		bowler.no_balls += 1
	else:
		legal_balls += 1
		bowler.balls += 1
		if total == 0:
			dots += 1
	free_hit = r.extra == "nb"

	striker.balls += 1  # a no-ball still counts as a ball faced
	striker.runs += batter_runs
	if r.boundary and batter_runs == 4:
		striker.fours += 1
		fours += 1
	elif r.boundary and batter_runs == 6:
		striker.sixes += 1
		sixes += 1

	if r.dropped != null:
		drops.append(r.dropped)

	var info := {}
	var symbol := "•" if batter_runs == 0 else str(batter_runs)
	if r.extra == "nb":
		symbol = "nb" if batter_runs == 0 else "nb+%d" % batter_runs

	var wk: Dictionary = r.wicket
	if not wk.is_empty():
		symbol = "W"
		var out: Dictionary = non_striker if wk.get("non_striker", false) else striker
		out.out = true
		out.how_out = _how_out(wk, bowler.player)
		if wk.kind != "run out":
			bowler.wickets += 1
		wickets += 1
		fall_of_wickets.append({"runs": runs, "balls": legal_balls, "wicket": wickets, "player": out.player,
			"kind": wk.kind, "fielder": wk.get("fielder"), "bowler": bowler.player})
		info.out = out
		var incoming := _bring_in_next()
		if not incoming.is_empty():
			if is_same(out, striker):
				striker = incoming
			else:
				non_striker = incoming
			info.incoming = incoming
	elif batter_runs % 2 == 1:
		_swap_strike()

	this_over.append(symbol)
	info.symbol = symbol
	return info


func _arrive(p: CricketPlayer) -> Dictionary:
	var entry := {"player": p, "runs": 0, "balls": 0, "fours": 0, "sixes": 0, "out": false, "how_out": "not out"}
	batters.append(entry)
	return entry


func _bring_in_next() -> Dictionary:
	var waiting := yet_to_bat()
	return {} if waiting.is_empty() else _arrive(waiting[0])


func _bowling_entry(p: CricketPlayer) -> Dictionary:
	for e in bowlers:
		if e.player == p:
			return e
	var entry := {"player": p, "balls": 0, "runs": 0, "wickets": 0, "maidens": 0, "wides": 0, "no_balls": 0}
	bowlers.append(entry)
	return entry


func _swap_strike() -> void:
	var s := striker
	striker = non_striker
	non_striker = s


func _how_out(wk: Dictionary, by: CricketPlayer) -> String:
	var fielder: CricketPlayer = wk.get("fielder")
	match wk.kind:
		"caught":
			if fielder == by:
				return "c & b %s" % by.surname()
			var mark := "†" if fielder.is_keeper() else ""
			return "c %s%s b %s" % [mark, fielder.surname(), by.surname()]
		"stumped":
			return "st †%s b %s" % [fielder.surname(), by.surname()]
		"run out":
			return "run out (%s)" % fielder.surname()
		"lbw":
			return "lbw b %s" % by.surname()
	return "b %s" % by.surname()
