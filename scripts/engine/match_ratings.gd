class_name MatchRatings
extends RefCounted
## FM-style player ratings (3.0-10.0, 6.0 = did nothing wrong) from a finished match.

const BASE := 6.0


## Returns {CricketPlayer: rating} for every player in both XIs.
static func compute(engine: MatchEngine) -> Dictionary:
	var r := {}
	for t: CricketTeam in engine.teams:
		for p in t.players:
			r[p] = BASE
	var par_sr := engine.format.par_rate * 100.0 / 6.0  # a par strike rate for the format
	var par_econ := engine.format.par_rate

	for inn: Innings in engine.main_innings():  # super overs don't count, as in official stats
		for e in inn.batters:
			var score: float = e.runs / 20.0
			if e.balls >= 8:
				score += (e.runs * 100.0 / e.balls - par_sr) / 120.0
			if e.out and e.runs == 0:
				score -= 0.5
			r[e.player] += score
		for b in inn.bowlers:
			var score: float = b.wickets * 0.55
			if b.balls >= 6:
				var econ: float = b.runs * 6.0 / b.balls
				score += (par_econ - econ) * 0.1 * b.balls / 24.0
			r[b.player] += score
		for f in inn.fall_of_wickets:
			if f.fielder != null and f.kind in ["caught", "stumped", "run out"]:
				r[f.fielder] += 0.3
		for d in inn.drops:
			r[d] -= 0.4

	if engine.winner:
		for p in engine.winner.players:
			r[p] += 0.2
	for p in r:
		r[p] = snappedf(clampf(r[p], 3.0, 10.0), 0.1)
	return r


## Player of the match: best rating, from the winning side when there is one.
static func player_of_match(engine: MatchEngine, ratings: Dictionary) -> CricketPlayer:
	var pool: Array = engine.winner.players if engine.winner else ratings.keys()
	var best: CricketPlayer = null
	for p in pool:
		if best == null or ratings[p] > ratings[best]:
			best = p
	return best
