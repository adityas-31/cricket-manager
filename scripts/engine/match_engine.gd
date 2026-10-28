class_name MatchEngine
extends RefCounted
## Runs a limited-overs match one delivery at a time: two innings, then super overs (ICC
## style: three batters, two wickets, one over each, the side that batted second batting
## first) until the tie is broken. The match screen and the tests drive it with bowl_ball().
##
## The manager's side (manager_team) can pick the next bowler, set the field, change who bats
## next, and is asked before using a DRS review: bowl_ball() then returns an event with
## review_pending, and resolve_review() finishes the delivery. Every other decision, and every
## decision in a match without a manager, is the captain's (CaptainAI).

const PITCHES := ["balanced", "flat", "green", "dusty"]
## Manager batting instructions and the intent offset each adds to the captain's call.
const BAT_APPROACHES := ["Defend", "Rotate", "Auto", "Attack", "All Out"]
const BAT_OFFSETS := [-0.6, -0.3, 0.0, 0.35, 0.7]
const BAT_AUTO := 2
## Manager bowling instructions; AUTO lets the captain decide each over.
const BOWL_APPROACHES := ["Defensive", "Balanced", "Attacking"]
const BOWL_AUTO := -1
const REVIEWS_PER_INNINGS := 2
const REVIEWS_PER_SUPER_OVER := 1
const SUPER_OVER_BALLS := 6
const SUPER_OVER_BATTERS := 3
const MAX_SUPER_OVERS := 5

var format: MatchFormat
var pitch := "balanced"
var teams: Array = []
var innings: Array = []
var toss_text := ""
var finished := false
var result_text := ""
var winner: CricketTeam = null
var rng := RandomNumberGenerator.new()
var states := {}  # CricketPlayer -> MatchDynamics.new_state()
var bat_approach := {}  # CricketTeam -> index into BAT_APPROACHES
var bowl_approach := {}  # CricketTeam -> index into BOWL_APPROACHES, or BOWL_AUTO
var super_overs := 0

## The side the human manages, or null for an all-AI match.
var manager_team: CricketTeam = null
var next_bowler := {}  # CricketTeam -> CricketPlayer picked for its next over
var field_choice := {}  # CricketTeam -> a Fields.PRESETS name, Fields.CUSTOM or Fields.AUTO
var custom_field := {}  # CricketTeam -> spots set by hand
## A delivery waiting on the manager's review decision: {result, meta, team}.
var pending_review := {}


func _init(home: CricketTeam, away: CricketTeam, fmt: MatchFormat, pitch_type := "balanced", seed := -1) -> void:
	format = fmt
	pitch = pitch_type
	teams = [home, away]
	for t: CricketTeam in teams:
		bat_approach[t] = t.default_bat_approach
		bowl_approach[t] = t.default_bowl_approach
		field_choice[t] = Fields.AUTO
		for p in t.players:
			states[p] = MatchDynamics.new_state()
	if seed >= 0:
		rng.seed = seed
	else:
		rng.randomize()

	var toss_winner: CricketTeam = teams[rng.randi_range(0, 1)]
	var bat_first := rng.randf() < (0.7 if pitch == "flat" else 0.4)
	toss_text = "%s won the toss and chose to %s" % [toss_winner.name, "bat" if bat_first else "bowl"]
	var first: CricketTeam = toss_winner if bat_first else other(toss_winner)
	innings.append(Innings.new(1, first, other(first), -1, format.overs * 6, [], false, REVIEWS_PER_INNINGS))


func current() -> Innings:
	return innings[-1]


func other(team: CricketTeam) -> CricketTeam:
	return teams[1] if team == teams[0] else teams[0]


## The two innings of the match proper (super overs excluded).
func main_innings() -> Array:
	return innings.filter(func(i): return not i.super_over)


## The intent a batter will play the next ball with: the captain's read of the situation,
## the manager's instruction, and frustration from pressure.
func batting_intent(inn: Innings, entry: Dictionary) -> float:
	var i := CaptainAI.intent(inn, format, entry)
	i += BAT_OFFSETS[bat_approach[inn.batting_team]]
	i += inn.pressure / 100.0 * 0.3
	return clampf(i, -1.0, 1.0)


## 0 defensive, 1 balanced, 2 attacking.
func bowling_approach(inn: Innings) -> int:
	var chosen: int = bowl_approach[inn.bowling_team]
	return chosen if chosen != BOWL_AUTO else CaptainAI.bowling_approach(inn, format)


# --- the manager's controls --------------------------------------------------------

## Who may bowl the next over: not the keeper, not whoever bowled the last one, and anyone
## still inside their over limit.
func eligible_bowlers(inn: Innings) -> Array:
	var out := []
	for p: CricketPlayer in inn.bowling_team.players:
		if p.is_keeper() or p == inn.last_over_bowler:
			continue
		if inn.super_over or inn.overs_bowled_by(p) < format.max_bowler_overs:
			out.append(p)
	return out


func set_next_bowler(team: CricketTeam, p: CricketPlayer) -> void:
	if p == null:
		next_bowler.erase(team)
	else:
		next_bowler[team] = p


## The name of the field the bowling side is using right now.
func field_name(inn: Innings) -> String:
	var chosen: String = field_choice.get(inn.bowling_team, Fields.AUTO)
	if chosen == Fields.AUTO:
		return Fields.auto_preset(bowling_approach(inn), inn.phase(format))
	return chosen


## The bowling side's field for the next ball, in the striker's frame, made legal for the
## fielding restrictions of this phase.
func current_field(inn: Innings) -> Array:
	var chosen := field_name(inn)
	var spots: Array = custom_field.get(inn.bowling_team, Fields.PRESETS.Balanced) if chosen == Fields.CUSTOM else Fields.PRESETS[chosen]
	return Fields.legalise(spots, inn.phase(format))


func set_field(team: CricketTeam, preset: String, spots: Array = []) -> void:
	field_choice[team] = preset
	if preset == Fields.CUSTOM:
		custom_field[team] = spots


# --- deliveries ---------------------------------------------------------------------

## Bowls the next delivery and returns everything that happened on it. If the manager has a
## review to decide, returns {review_pending: true, ...} and nothing more happens until
## resolve_review(). Returns {} once the match is over or while a review is pending.
func bowl_ball() -> Dictionary:
	if finished or not pending_review.is_empty():
		return {}
	var inn := current()
	if inn.bowler.is_empty():
		var picked: CricketPlayer = next_bowler.get(inn.bowling_team)
		next_bowler.erase(inn.bowling_team)
		if picked == null or not picked in eligible_bowlers(inn):
			picked = CaptainAI.choose_bowler(inn, format, pitch, states)
		inn.start_over(picked)

	var striker := inn.striker
	var bowler: CricketPlayer = inn.bowler.player
	var phase := inn.phase(format)
	var intent := batting_intent(inn, striker)
	states[striker.player].intent = intent
	var spots := current_field(inn)
	var r := DeliveryModel.bowl(rng, {
		"batter": striker.player,
		"batter_balls": striker.balls,
		"bowler": bowler,
		"intent": intent,
		"phase": phase,
		"pitch": pitch,
		"progress": float(inn.legal_balls) / inn.max_balls,
		"fielding": inn.bowling_team,
		"free_hit": inn.free_hit,
		"batter_state": states[striker.player],
		"bowler_state": states[bowler],
		"pressure": inn.pressure,
		"bowling_approach": bowling_approach(inn),
		"field": spots,
		"mixed_pair": striker.player.left_handed != inn.non_striker.player.left_handed,
	})
	var meta := {
		"innings": inn.number,
		"over_label": "%d.%d" % [inn.legal_balls / 6, inn.legal_balls % 6 + 1],
		"batter": striker.player,
		"bowler": bowler,
		"phase": phase,
		"free_hit": inn.free_hit,
		"field": spots,
		"super_over": inn.super_over,
	}

	var appeal: Dictionary = r.appeal
	if not appeal.is_empty():
		var deciding: CricketTeam = inn.batting_team if appeal.given_out else inn.bowling_team
		if inn.reviews[deciding] > 0:
			if deciding == manager_team:
				pending_review = {"result": r, "meta": meta, "team": deciding}
				var ask := meta.duplicate()
				ask.merge({"review_pending": true, "appeal": appeal, "team": deciding, "reviews_left": inn.reviews[deciding]})
				return ask
			if _captain_reviews(appeal):
				_review(r, deciding, inn)
	return _apply(r, meta)


## The manager's answer to a pending review: take it or not. Returns the finished delivery.
func resolve_review(take: bool) -> Dictionary:
	if pending_review.is_empty():
		return {}
	var pr := pending_review
	pending_review = {}
	if take:
		_review(pr.result, pr.team, current())
	return _apply(pr.result, pr.meta)


## AI captains review most bad decisions and a few good ones.
func _captain_reviews(appeal: Dictionary) -> bool:
	var wrong: bool = appeal.given_out != appeal.truly_out
	return rng.randf() < (0.65 if wrong else 0.12)


## Ball-tracking settles it: a wrong call is overturned (the review is kept), a right one
## costs the side a review.
func _review(r: Dictionary, team: CricketTeam, inn: Innings) -> void:
	var appeal: Dictionary = r.appeal
	var overturned: bool = appeal.given_out != appeal.truly_out
	if overturned and appeal.given_out:
		r.wicket = {}
	elif overturned:
		r.wicket = {"kind": "lbw"} if appeal.kind == "lbw" else {"kind": "caught", "fielder": appeal.keeper}
	if not overturned:
		inn.reviews[team] -= 1
	r.review = {"team": team, "overturned": overturned, "left": inn.reviews[team]}


func _apply(r: Dictionary, meta: Dictionary) -> Dictionary:
	var inn := current()
	var event := r.duplicate()
	event.merge(meta)
	event.merge(inn.record(r))
	event.commentary = Commentary.describe(event, rng)
	MatchDynamics.after_ball(self, inn, event)

	event.end_of_over = r.legal and inn.legal_balls % 6 == 0
	if event.end_of_over:
		inn.end_over()
		MatchDynamics.end_of_over(self, inn, meta.bowler)

	event.innings_complete = inn.is_complete()
	if event.innings_complete:
		_next_innings(inn)
	event.match_complete = finished
	event.score = inn.score_text()
	return event


## After an innings: the chase, a super over if the scores are level, or the result.
func _next_innings(inn: Innings) -> void:
	var n := inn.number + 1
	if inn.target < 0:  # the first innings of the match, or of a super over
		if inn.super_over:
			innings.append(Innings.new(n, inn.bowling_team, inn.batting_team, inn.runs + 1, SUPER_OVER_BALLS,
				super_over_lineup(inn.bowling_team), true, REVIEWS_PER_SUPER_OVER))
		else:
			innings.append(Innings.new(n, inn.bowling_team, inn.batting_team, inn.runs + 1, format.overs * 6,
				[], false, REVIEWS_PER_INNINGS))
			MatchDynamics.innings_break(self)
	elif inn.runs == inn.target - 1 and super_overs < MAX_SUPER_OVERS:
		super_overs += 1
		innings.append(Innings.new(n, inn.batting_team, inn.bowling_team, -1, SUPER_OVER_BALLS,
			super_over_lineup(inn.batting_team), true, REVIEWS_PER_SUPER_OVER))
	else:
		_finish()


## The three batters a side sends out for a super over: its biggest hitters.
func super_over_lineup(team: CricketTeam) -> Array:
	var hitters := team.players.duplicate()
	hitters.sort_custom(func(a, b): return a.batting_rating() + a.a("power") * 0.3 > b.batting_rating() + b.a("power") * 0.3)
	return hitters.slice(0, SUPER_OVER_BATTERS)


func _finish() -> void:
	finished = true
	var main := main_innings()
	var first: Innings = main[0]
	var second: Innings = main[1]
	if second.runs >= second.target:
		winner = second.batting_team
		var wkts := second.max_wickets - second.wickets
		result_text = "%s won by %s (%s left)" % [winner.name, _plural(wkts, "wicket"), _plural(second.balls_left(), "ball")]
		return
	if second.runs < second.target - 1:
		winner = first.batting_team
		result_text = "%s won by %s" % [winner.name, _plural(second.target - 1 - second.runs, "run")]
		return
	# Tied: the last super over decides, if there was one.
	var last := current()
	if not last.super_over:
		result_text = "Match tied"
	elif last.runs >= last.target:
		winner = last.batting_team
	elif last.runs < last.target - 1:
		winner = last.bowling_team
	else:
		result_text = "Match tied after %s" % _plural(super_overs, "super over")
	if winner:
		result_text = "Match tied; %s won the super over" % winner.name if super_overs == 1 else \
			"Match tied; %s won the %s super over" % [winner.name, Season.ordinal(super_overs)]


static func _plural(n: int, word: String) -> String:
	return "%d %s%s" % [n, word, "" if n == 1 else "s"]
