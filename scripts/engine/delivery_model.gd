class_name DeliveryModel
extends RefCounted
## Decides what happens on one delivery from the players' attributes and the match situation.
##
## Each outcome starts from a base weight tuned to an average T20 ball. The batter-vs-bowler
## skill gap, batting intent, phase, pitch and fielding then scale those weights before one
## outcome is drawn. Calibrate the numbers with tests/sim_stats.gd.

const BASE := {"0": 0.32, "1": 0.37, "2": 0.07, "3": 0.006, "4": 0.077, "6": 0.025, "W": 0.034}
const WICKET_KINDS := {"caught": 0.55, "bowled": 0.18, "lbw": 0.15, "run out": 0.05, "stumped": 0.0}
## Batters take about this many balls to get their eye in.
const SETTLE_BALLS := 10.0
## Skill-gap points per unit of advantage; larger means talent differences matter less.
const SKILL_SCALE := 7.5
## Field effects: chance a boundary rider right on the line cuts off a four / catches a six.
const CUT_OFF := 0.4
const ROPE_CATCH := 0.1
## Umpiring: share of given-out lbws/catches behind that were not out, chance a dot ball
## brings a close shout given not out, and the share of those that were out.
const WRONG_OUT := 0.1
const CLOSE_SHOUT := 0.04
const SHOUT_OUT := 0.3
## Bowler quality bonus when the ball leaves the batter (off-spin to a left-hander, leg-spin
## or left-arm spin to a right-hander, left-arm pace across a right-hander), and penalty when
## a spinner turns it into the bat.
const AWAY_BONUS := 0.6
const ACROSS_BONUS := 0.4
const INTO_PENALTY := 0.3
const MIXED_PAIR_PENALTY := 0.3


## ctx: batter, batter_balls, bowler, intent, phase, pitch, progress (0-1 through the
## innings), fielding (CricketTeam), free_hit, and the MatchDynamics meters: batter_state,
## bowler_state ({condition, confidence}), pressure (0-100), bowling_approach (0-2).
## Optional: field (spots, see Fields; without one the field has no effect), mixed_pair
## (a left-right batting partnership, which disrupts the bowler's line), and bat_message /
## bowl_message (running touchline messages, see Touchline.scaled).
## Returns {extra ("", "wd", "nb"), extra_runs, runs, legal, boundary, wicket ({} or
## {kind, fielder?, non_striker?}), dropped (fielder or null), missed_stumping, angle, distance,
## region, fielded ("" or how the field changed the ball: "cut off", "rope catch", "gap",
## "stopped"), appeal ({} or {kind, given_out, truly_out}: a reviewable umpire's call)}.
static func bowl(rng: RandomNumberGenerator, ctx: Dictionary) -> Dictionary:
	var batter: CricketPlayer = ctx.batter
	var bowler: CricketPlayer = ctx.bowler
	var fielding: CricketTeam = ctx.fielding
	var intent: float = ctx.intent
	var accuracy := bowler.a("accuracy")
	var bat_state: Dictionary = ctx.get("batter_state", MatchDynamics.new_state())
	var bowl_state: Dictionary = ctx.get("bowler_state", MatchDynamics.new_state())
	var bat_tired := MatchDynamics.fatigue(bat_state.condition)
	var bowl_tired := MatchDynamics.fatigue(bowl_state.condition)
	var bat_conf: float = (bat_state.confidence - 50.0) / 50.0
	var bowl_conf: float = (bowl_state.confidence - 50.0) / 50.0
	var pressure: float = ctx.get("pressure", 0.0) / 100.0
	var approach: int = ctx.get("bowling_approach", 1)

	var result := {
		"extra": "", "extra_runs": 0, "runs": 0, "legal": true, "boundary": false,
		"wicket": {}, "dropped": null, "missed_stumping": false,
		"angle": 0.0, "distance": 0.0, "region": "", "fielded": "", "appeal": {},
	}
	var spots: Array = ctx.get("field", [])
	var bat_msg: Dictionary = ctx.get("bat_message", {})
	var bowl_msg: Dictionary = ctx.get("bowl_message", {})

	# Tired bowlers lose their radar.
	var wide_chance: float = clampf(0.045 + (10.0 - accuracy) * 0.003, 0.01, 0.09) * (1.0 + bowl_tired) * bowl_msg.get("wide", 1.0)
	if rng.randf() < wide_chance:
		result.extra = "wd"
		result.extra_runs = 1
		result.legal = false
		return result
	var pace_bonus := 0.004 if bowler.style == CricketPlayer.Style.PACE else 0.0
	if rng.randf() < clampf(0.005 + (10.0 - accuracy) * 0.001 + pace_bonus, 0.001, 0.03) * (1.0 + bowl_tired) * bowl_msg.get("noball", 1.0):
		result.extra = "nb"
		result.extra_runs = 1
		result.legal = false

	# Free hits and no-balls can't produce a dismissal, so the batter swings freely.
	var protected: bool = result.extra == "nb" or ctx.free_hit
	if protected:
		intent = minf(intent + 0.5, 1.0)

	var settled := clampf(float(ctx.batter_balls) / SETTLE_BALLS, 0.0, 1.0)
	var bowl_q := _bowler_quality(bowler, ctx) - bowl_tired * 2.5 + bowl_conf * 1.2 + rng.randfn(0.0, 2.5)
	var bat_q := _batter_quality(batter, bowler) * (0.92 + 0.08 * settled) - bat_tired * 1.5 + bat_conf * 1.5 + rng.randfn(0.0, 2.5)
	var d := (bat_q - bowl_q) / SKILL_SCALE
	var field := fielding.average("fielding") - 10.0
	# Blocking protects the wicket more than slogging exposes it, and a confident batter
	# gets away with attacking more often than a nervous one.
	var risk := intent * ((0.6 - 0.2 * bat_conf) if intent > 0.0 else 0.9)
	# Pressure forces rash shots, less so for batters with composure.
	var rash := 1.0 + pressure * maxf(0.6 - batter.a("composure") / 40.0, 0.1)

	var w := {
		"0": BASE["0"] * exp(-0.5 * d - (0.5 if intent > 0.0 else 1.0) * intent),
		"1": BASE["1"] * exp(0.1 * d - 0.1 * intent - field * 0.01),
		"2": BASE["2"] * exp(0.2 * d + (batter.a("running") - 10.0) * 0.05 - field * 0.04) * (1.0 - 0.4 * bat_tired),
		"3": BASE["3"] * exp(0.2 * d),
		"4": BASE["4"] * exp(0.6 * d + 0.6 * intent + (batter.a("timing") - 10.0) * 0.04 - field * 0.02),
		"6": BASE["6"] * exp(0.6 * d + 1.0 * intent + (batter.a("power") - 10.0) * 0.08),
		"W": 0.0 if protected else BASE["W"] * exp(-0.8 * d + risk) * (1.0 + 0.2 * (1.0 - settled)) * rash,
	}
	# The line and length the approach asks for; the field itself does the rest (see _apply_field).
	match approach:
		0:  # defensive: tight lines, singles on offer
			w["W"] *= 0.9
			w["1"] *= 1.05
		2:  # attacking: full and at the stumps
			w["W"] *= 1.1
			w["1"] *= 0.97
	for msg in [bat_msg, bowl_msg]:
		var mult: Dictionary = msg.get("w", {})
		for k in mult:
			w[k] *= mult[k]
	if ctx.phase == "death":
		w["6"] *= 1.15
	if ctx.phase == "powerplay":  # new ball, hard and fast off the bat
		w["4"] *= 1.25
		w["6"] *= 1.1

	var pick := _weighted(rng, w)
	if pick == "W":
		_resolve_wicket(rng, ctx, intent, result)
	else:
		result.runs = int(pick)
		result.boundary = pick == "4" or pick == "6"
	_place_shot(rng, result, intent, spots)
	if not spots.is_empty():
		_apply_field(rng, ctx, result, spots)
	_umpire(rng, ctx, result)
	return result


## How the field changes where the ball goes: boundary riders cut off fours and catch
## sixes on the rope, ring fielders stop singles, and gaps turn ones into twos.
static func _apply_field(rng: RandomNumberGenerator, ctx: Dictionary, result: Dictionary, spots: Array) -> void:
	if not result.wicket.is_empty() or result.dropped != null:
		return
	var angle: float = result.angle
	var deep := Fields.nearest_gap(spots, angle, 45.0, 90.0)
	var ring := Fields.nearest_gap(spots, angle, 0.0, 40.0)
	match int(result.runs):
		4:
			if deep < 14.0 and rng.randf() < CUT_OFF * (1.0 - deep / 14.0):
				result.runs = 2 if deep > 6.0 else 1
				result.boundary = false
				result.distance = 62.0
				result.fielded = "cut off"
		6:
			if deep < 10.0 and rng.randf() < ROPE_CATCH * (1.0 - deep / 10.0):
				var fielding: CricketTeam = ctx.fielding
				result.runs = 0
				result.boundary = false
				result.distance = 68.0
				result.wicket = {"kind": "caught", "fielder": fielding.random_fielder(rng, ctx.bowler)}
				result.fielded = "rope catch"
		1:
			if ring < 6.0 and rng.randf() < 0.25:
				result.runs = 0
				result.distance = 18.0
				result.fielded = "stopped"
			elif ring > 30.0 and rng.randf() < 0.3:
				result.runs = 2
				result.distance = 40.0
				result.fielded = "gap"
		2:
			if deep > 40.0 and result.distance > 45.0 and rng.randf() < 0.2:
				result.runs = 4
				result.boundary = true
				result.distance = 70.0
				result.fielded = "gap"
	result.region = region_name(angle, result.runs == 6)


## Umpires get some close calls wrong. Given-out lbws and catches behind are sometimes not
## out, and the odd shout given not out was out; both can be reviewed (MatchEngine runs DRS).
static func _umpire(rng: RandomNumberGenerator, ctx: Dictionary, result: Dictionary) -> void:
	var kind: String = result.wicket.get("kind", "")
	var behind: bool = kind == "caught" and result.wicket.fielder.is_keeper()
	if kind == "lbw" or behind:
		result.appeal = {"kind": "lbw" if kind == "lbw" else "caught behind", "given_out": true,
			"truly_out": rng.randf() >= WRONG_OUT}
	elif kind == "" and result.runs == 0 and result.extra == "" and not ctx.free_hit and rng.randf() < CLOSE_SHOUT:
		var fielding: CricketTeam = ctx.fielding
		result.appeal = {"kind": "lbw" if rng.randf() < 0.6 else "caught behind", "given_out": false,
			"truly_out": rng.randf() < SHOUT_OUT, "keeper": fielding.keeper()}
		# The ball went where the appeal says: into the pad, or through to the keeper.
		if result.appeal.kind == "lbw":
			result.angle = 0.0
			result.distance = 0.0
		else:
			result.angle = 180.0 - absf(rng.randfn(0.0, 15.0))
			result.distance = 18.0
		result.region = ""


static func _bowler_quality(bowler: CricketPlayer, ctx: Dictionary) -> float:
	var q := bowler.bowling_rating()
	var progress: float = ctx.progress
	match ctx.pitch:
		"flat":
			q -= 0.8
		"green":
			if not bowler.is_spinner():
				q += 1.0 * (1.0 - progress)
		"dusty":
			if bowler.is_spinner():
				q += 0.3 + 1.2 * progress
	if ctx.phase == "death":
		q += (bowler.a("variation") - 10.0) * 0.1
	var batter: CricketPlayer = ctx.batter
	if bowler.is_spinner():
		var off_spin := bowler.style == CricketPlayer.Style.OFF_SPIN
		q += AWAY_BONUS if off_spin == batter.left_handed else -INTO_PENALTY
	elif bowler.left_arm and not batter.left_handed:
		q += ACROSS_BONUS
	if ctx.get("mixed_pair", false):
		q -= MIXED_PAIR_PENALTY
	return q


static func _batter_quality(batter: CricketPlayer, bowler: CricketPlayer) -> float:
	if bowler.is_spinner():
		return batter.a("technique") * 0.3 + batter.a("timing") * 0.25 + batter.a("vs_spin") * 0.25 + batter.a("composure") * 0.2
	return batter.a("technique") * 0.4 + batter.a("timing") * 0.3 + batter.a("composure") * 0.15 + batter.a("concentration") * 0.15


static func _resolve_wicket(rng: RandomNumberGenerator, ctx: Dictionary, intent: float, result: Dictionary) -> void:
	var bowler: CricketPlayer = ctx.bowler
	var fielding: CricketTeam = ctx.fielding
	var keeper := fielding.keeper()
	var kinds := WICKET_KINDS.duplicate()
	kinds["caught"] += 0.15 * intent
	var spots: Array = ctx.get("field", [])
	if not spots.is_empty():  # slips and short catchers turn edges into wickets
		kinds["caught"] *= 1.0 + 0.06 * (Fields.close_catchers(spots) - 2)
	if bowler.is_spinner():
		kinds["lbw"] += 0.03
		kinds["stumped"] = 0.05 + maxf(intent, 0.0) * 0.06

	match _weighted(rng, kinds):
		"caught":
			var r := rng.randf()
			var fielder: CricketPlayer
			if r < 0.05:
				fielder = bowler
			elif r < 0.3 and not bowler.is_spinner():
				fielder = keeper
			else:
				fielder = fielding.random_fielder(rng, bowler)
			var hands := fielder.a("keeping") if fielder == keeper else fielder.a("catching")
			if rng.randf() < clampf(0.75 + (hands - 10.0) * 0.02, 0.5, 0.95):
				result.wicket = {"kind": "caught", "fielder": fielder}
			else:
				result.dropped = fielder
				result.runs = [0, 0, 1, 1, 2, 4][rng.randi_range(0, 5)]
				result.boundary = result.runs == 4
		"stumped":
			if rng.randf() < clampf(0.7 + (keeper.a("keeping") - 10.0) * 0.03, 0.4, 0.97):
				result.wicket = {"kind": "stumped", "fielder": keeper}
			else:
				result.missed_stumping = true
		"run out":
			result.runs = rng.randi_range(0, 1)
			result.wicket = {
				"kind": "run out",
				"fielder": fielding.random_fielder(rng, null),
				"non_striker": rng.randf() < 0.3,
			}
		var kind:
			result.wicket = {"kind": kind}


## Picks where the ball went. Angles are degrees from straight down the ground,
## positive to the off side of a right-hander.
static func _place_shot(rng: RandomNumberGenerator, result: Dictionary, intent: float, spots: Array) -> void:
	var runs: int = result.runs
	var kind: String = result.wicket.get("kind", "")
	var angle := rng.randfn(0.0, 70.0)
	if runs == 6 or (runs == 4 and intent > 0.5):
		angle = rng.randfn(-25.0, 45.0)  # big hits favour the leg side
	angle = wrapf(angle, -180.0, 180.0)

	var distance: float
	if kind in ["bowled", "lbw", "stumped"] or result.missed_stumping:
		angle = 0.0
		distance = 0.0
	elif kind == "caught" and result.wicket.fielder.is_keeper():
		angle = 180.0 - absf(rng.randfn(0.0, 15.0))
		distance = 18.0
	elif (kind == "caught" or result.dropped != null) and not spots.is_empty():
		var spot: Array = spots[rng.randi_range(0, spots.size() - 1)]  # to where a fielder stands
		angle = spot[0]
		distance = spot[1]
	elif kind == "caught" or result.dropped != null:
		distance = rng.randf_range(15.0, 66.0)
	elif runs == 6:
		distance = rng.randf_range(74.0, 92.0)
	elif runs == 4:
		distance = 70.0
	else:
		distance = [rng.randf_range(3.0, 18.0), rng.randf_range(12.0, 35.0), rng.randf_range(35.0, 58.0), rng.randf_range(55.0, 67.0)][runs]

	result.angle = angle
	result.distance = distance
	result.region = region_name(angle, runs == 6)


static func region_name(angle: float, aerial: bool) -> String:
	var side := absf(angle)
	if aerial:
		if angle >= 0.0:
			return "over long-off" if side < 35.0 else ("over extra cover" if side < 90.0 else "over third man")
		return "over long-on" if side < 35.0 else ("over deep midwicket" if side < 90.0 else "over fine leg")
	if side < 15.0:
		return "straight down the ground"
	var off := ["wide of mid-off", "through the covers", "past point", "backward of point", "down to third man"]
	var leg := ["wide of mid-on", "through midwicket", "to square leg", "behind square", "down to fine leg"]
	var bands := [40.0, 70.0, 100.0, 135.0, 181.0]
	for i in bands.size():
		if side < bands[i]:
			return off[i] if angle > 0.0 else leg[i]
	return ""


static func _weighted(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += weights[k]
	var r := rng.randf() * total
	for k in weights:
		r -= weights[k]
		if r <= 0.0:
			return k
	return weights.keys()[-1]
