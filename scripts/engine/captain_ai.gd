class_name CaptainAI
extends RefCounted
## On-field decisions: how hard to bat, and who bowls the next over.


## Batting intent from -1 (survive) to 1 (all-out attack).
static func intent(inn: Innings, fmt: MatchFormat, batter_entry: Dictionary) -> float:
	var batter: CricketPlayer = batter_entry.player
	var phase := inn.phase(fmt)
	var i: float = fmt.phase_intent.get(phase, 0.0)
	i += (batter.a("aggression") - 10.0) * 0.04
	i += Tactics.intent_offset(inn.batting_team, batter, phase)
	if batter_entry.balls >= 15:
		i += 0.1
	if phase != "death":
		if inn.wickets >= 6:
			i -= 0.25
		if inn.wickets >= 8:
			i -= 0.2
	if inn.target > 0:
		var balls_left := maxi(inn.balls_left(fmt), 1)
		var required := inn.runs_needed() * 6.0 / balls_left
		i += clampf((required - fmt.par_rate) * 0.1, -0.6, 0.6)
	return clampf(i, -1.0, 1.0)


## Attack with a ring field in the powerplay and when defending a big total, protect the
## boundary at the death, balanced otherwise. 0 defensive, 1 balanced, 2 attacking.
static func bowling_approach(inn: Innings, fmt: MatchFormat) -> int:
	match inn.phase(fmt):
		"powerplay":
			return 2
		"death":
			return 0
	if inn.target > 0 and inn.runs_needed() > inn.balls_left(fmt) / 6.0 * (fmt.par_rate + 1.5):
		return 2
	return 1


## Picks the bowler for the next over: no back-to-back overs, quotas respected,
## seamers at the start and end, spin through the middle, the best death bowlers saved,
## and tired bowlers rested.
static func choose_bowler(inn: Innings, fmt: MatchFormat, pitch: String, states: Dictionary) -> CricketPlayer:
	var phase := inn.phase(fmt)
	var best: CricketPlayer = null
	var best_score := -INF
	for p: CricketPlayer in inn.bowling_team.players:
		if p == inn.last_over_bowler or p.is_keeper():
			continue
		var used := inn.overs_bowled_by(p)
		if used >= fmt.max_bowler_overs:
			continue
		var spinner := p.is_spinner()
		var score := p.bowling_rating()
		if phase == "middle":
			score += 1.5 if spinner else 0.0
		else:
			score += 0.0 if spinner else 1.5
		if pitch == "dusty" and spinner:
			score += 1.0
		elif pitch == "green" and not spinner:
			score += 1.0
		if phase != "death" and not spinner and p.a("variation") >= 13.0 and fmt.max_bowler_overs - used <= 2:
			score -= 2.5
		score -= used * 0.3
		score -= MatchDynamics.fatigue(states[p].condition) * 4.0
		score += _plan_bonus(Tactics.bowl_role(inn.bowling_team, p), phase, fmt.max_bowler_overs - used)
		if score > best_score:
			best_score = score
			best = p
	return best


## How much the manager's bowling plan pulls a bowler towards (or away from) this over.
static func _plan_bonus(role: String, phase: String, overs_left: int) -> float:
	match role:
		"Auto":
			return 0.0
		"Do Not Bowl":
			return -100.0  # still a last resort if nobody else can bowl
	var planned: String = Tactics.BOWL_ROLES[role].phase
	if phase == planned:
		return 1.5
	if role == "Death" and overs_left <= 2:
		return -4.0  # keep the last overs for the end
	return 0.0
