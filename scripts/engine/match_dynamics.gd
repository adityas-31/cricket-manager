class_name MatchDynamics
extends RefCounted
## The in-match meters that change ball by ball, like FM's condition and morale:
##
## - Condition (0-100): physical freshness. Bowling drains it (pace most), running drains
##   batters, and players recover while not bowling. Stamina slows the drain.
## - Confidence (0-100, 50 = neutral): rises with success, falls with failure.
## - Pressure (0-100, per innings, on the batting side): builds with dot balls, wickets and a
##   climbing required rate; boundaries release it.
##
## DeliveryModel reads all three; this class only updates them.

## Condition lost per over bowled at stamina 10.
const OVER_COST := {CricketPlayer.Style.PACE: 7.0, CricketPlayer.Style.MEDIUM: 5.0}
const SPIN_OVER_COST := 3.5
const RECOVERY_PER_OVER := 0.5
const INNINGS_BREAK_RECOVERY := 20.0
const PRESSURE_FADE := 0.96  # per delivery
const CONFIDENCE_SETTLE := 0.985  # per delivery involved in, pulls confidence back to 50


static func new_state() -> Dictionary:
	return {"condition": 100.0, "confidence": 50.0, "intent": 0.0}


## Below 75% condition a player starts to tire; at 25% they are spent. Returns 0..1.
static func fatigue(condition: float) -> float:
	return clampf((75.0 - condition) / 50.0, 0.0, 1.0)


## How quickly a player tires: 1.0 at stamina 10, 0.5 at 20, 1.3 at 4.
static func drain_rate(p: CricketPlayer) -> float:
	return 1.5 - p.a("stamina") / 20.0


static func after_ball(engine: MatchEngine, inn: Innings, e: Dictionary) -> void:
	var batter: CricketPlayer = e.batter
	var bowler: CricketPlayer = e.bowler
	var bat: Dictionary = engine.states[batter]
	var bowl: Dictionary = engine.states[bowler]

	bowl.condition -= OVER_COST.get(bowler.style, SPIN_OVER_COST) / 6.0 * drain_rate(bowler)
	for s: Dictionary in [bat, bowl]:
		s.confidence = 50.0 + (s.confidence - 50.0) * CONFIDENCE_SETTLE

	if e.extra == "wd":
		bowl.confidence -= 1.5
		inn.pressure -= 3.0
	else:
		bat.condition -= 0.12 * drain_rate(batter)
		if not e.boundary and e.runs > 0:
			for runner: CricketPlayer in [batter, inn.non_striker.player if inn.striker.player == batter else inn.striker.player]:
				engine.states[runner].condition -= e.runs * 0.35 * drain_rate(runner)
		bat.confidence += 0.25  # time at the crease settles a batter
		if e.extra == "nb":
			bowl.confidence -= 2.0

		if not e.wicket.is_empty():
			if e.wicket.kind != "run out":
				bowl.confidence += 10.0
			inn.pressure += 7.0
		elif e.dropped != null:
			engine.states[e.dropped].confidence -= 8.0
			bowl.confidence -= 2.0
			bat.confidence -= 2.0
		else:
			match int(e.runs):
				0:
					bat.confidence -= 1.2
					bowl.confidence += 1.0
					inn.pressure += 4.0
				1:
					bat.confidence += 0.6
					inn.pressure -= 2.0
				2, 3:
					bat.confidence += 1.0
					inn.pressure -= 4.0
				4:
					bat.confidence += 4.0
					bowl.confidence -= 3.0
					inn.pressure -= 12.0
				6:
					bat.confidence += 5.0
					bowl.confidence -= 5.0
					inn.pressure -= 14.0

		if inn.target > 0:
			var balls := maxi(inn.balls_left(engine.format), 1)
			var required := inn.runs_needed() * 6.0 / balls
			inn.pressure += clampf((required - engine.format.par_rate) * 0.4, -1.0, 3.0)

	# Pressure fades unless the squeeze is kept on.
	inn.pressure = clampf(inn.pressure * PRESSURE_FADE, 0.0, 100.0)
	# New batters walk in nervous when the pressure is on.
	if e.has("incoming"):
		var entry: Dictionary = engine.states[e.incoming.player]
		entry.confidence = clampf(minf(entry.confidence, 55.0) - inn.pressure * 0.15, 35.0, 60.0)
	_clamp_all(engine)


## Everyone in the field except the bowler gets a breather between overs.
static func end_of_over(engine: MatchEngine, inn: Innings, bowler: CricketPlayer) -> void:
	for p: CricketPlayer in inn.bowling_team.players:
		if p != bowler:
			engine.states[p].condition += RECOVERY_PER_OVER
	inn.pressure = maxf(inn.pressure - 2.0, 0.0)
	_clamp_all(engine)


static func innings_break(engine: MatchEngine) -> void:
	for s: Dictionary in engine.states.values():
		s.condition += INNINGS_BREAK_RECOVERY
	_clamp_all(engine)


static func _clamp_all(engine: MatchEngine) -> void:
	for s: Dictionary in engine.states.values():
		s.condition = clampf(s.condition, 0.0, 100.0)
		s.confidence = clampf(s.confidence, 0.0, 100.0)
