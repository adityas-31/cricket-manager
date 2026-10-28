class_name Selection
extends RefCounted
## Picking a playing XI from the squad: the assistant's best XI (used by AI clubs every match,
## which rests tired players on its own), covering injuries in the manager's XI, and the
## warnings the Selection screen shows.

const BOWLING_OPTIONS := 5
## A player counts as a bowling option at this bowling rating or above.
const BOWLER_RATING := 10.0
## Below this condition a player is flagged as tired.
const TIRED := 70.0


static func is_bowling_option(p: CricketPlayer) -> bool:
	return p.bowling_rating() >= BOWLER_RATING and not p.is_keeper()


## How strong a pick a player is today, on a skill scale: tiredness and form adjust it.
static func value(p: CricketPlayer, season: Season, skill: float) -> float:
	var tired := MatchDynamics.fatigue(season.condition[p])
	return skill * (1.0 - 0.35 * tired) + (season.form[p] - 50.0) / 50.0 * 0.6


static func available(team: CricketTeam, season: Season) -> Array:
	return team.squad.filter(func(p): return not season.is_injured(p))


## The assistant's XI: the best keeper, five bowling options, then the best batters,
## batting in order of batting quality.
static func auto_select(team: CricketTeam, season: Season) -> void:
	var pool := available(team, season)
	var xi := []
	var keepers := pool.filter(func(p): return p.is_keeper())
	if keepers.is_empty():
		keepers = pool.duplicate()
	keepers.sort_custom(func(a, b): return a.a("keeping") + a.batting_rating() > b.a("keeping") + b.batting_rating())
	if not keepers.is_empty():
		xi.append(keepers[0])

	var bowlers := pool.filter(func(p): return not p in xi and is_bowling_option(p))
	bowlers.sort_custom(func(a, b): return value(a, season, a.bowling_rating()) > value(b, season, b.bowling_rating()))
	xi.append_array(bowlers.slice(0, BOWLING_OPTIONS))

	var rest := pool.filter(func(p): return not p in xi)
	rest.sort_custom(func(a, b): return value(a, season, a.batting_rating()) > value(b, season, b.batting_rating()))
	xi.append_array(rest.slice(0, CricketTeam.XI_SIZE - xi.size()))

	xi.sort_custom(func(a, b): return a.batting_rating() > b.batting_rating())
	team.players = xi
	Tactics.suggest_batting(team)


## Keeps the manager's XI legal before a match: injured players are swapped for the best
## available reserve of the same kind (keeper, bowler or batter) in the same batting slot,
## and gaps are filled. Returns a line per change.
static func ensure_valid(team: CricketTeam, season: Season) -> Array:
	var changes := []
	for i in team.players.size():
		var out: CricketPlayer = team.players[i]
		if not season.is_injured(out):
			continue
		var cover := _best_cover(team, season, out)
		if cover == null:
			continue
		team.players[i] = cover
		changes.append("%s replaces the injured %s" % [cover.name, out.name])
	team.players = team.players.filter(func(p): return not season.is_injured(p))
	while team.players.size() < CricketTeam.XI_SIZE:
		var pool := available(team, season).filter(func(p): return not p in team.players)
		if pool.is_empty():
			break
		pool.sort_custom(func(a, b): return _overall(a, season) > _overall(b, season))
		team.players.append(pool[0])
		changes.append("%s comes into the XI" % pool[0].name)
	return changes


## Problems with an XI the manager should know about before a match.
static func issues(team: CricketTeam, season: Season) -> Array:
	var out := []
	if team.players.size() != CricketTeam.XI_SIZE:
		out.append("The XI has %d players; pick %d" % [team.players.size(), CricketTeam.XI_SIZE])
	if not team.players.any(func(p): return p.is_keeper()):
		out.append("No specialist wicketkeeper selected")
	var options := team.players.filter(func(p): return is_bowling_option(p)).size()
	if options < BOWLING_OPTIONS:
		out.append("Only %d bowling options (need %d for 20 overs)" % [options, BOWLING_OPTIONS])
	for p: CricketPlayer in team.players:
		if season.is_injured(p):
			out.append("%s is injured (%d days)" % [p.name, season.injury_days(p)])
		elif season.condition[p] < TIRED:
			out.append("%s is tired (%d%% condition)" % [p.name, roundi(season.condition[p])])
	return out


static func _best_cover(team: CricketTeam, season: Season, out: CricketPlayer) -> CricketPlayer:
	var pool := available(team, season).filter(func(p): return not p in team.players)
	if pool.is_empty():
		return null
	var same := pool.filter(func(p): return _kind(p) == _kind(out))
	if not same.is_empty():
		pool = same
	pool.sort_custom(func(a, b): return _overall(a, season) > _overall(b, season))
	return pool[0]


static func _kind(p: CricketPlayer) -> String:
	if p.is_keeper():
		return "keeper"
	return "bowler" if is_bowling_option(p) else "batter"


static func _overall(p: CricketPlayer, season: Season) -> float:
	return value(p, season, maxf(p.batting_rating(), p.bowling_rating()))
