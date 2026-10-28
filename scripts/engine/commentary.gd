class_name Commentary
extends RefCounted
## Turns a delivery event from MatchEngine into a line of ball-by-ball commentary.

const WIDE := ["wide, sprays it down the leg side", "wide, too far outside off", "wide, the umpire stretches the arms out"]
const DOT := ["defended back down the pitch", "beaten outside off!", "pushed to the fielder, no run", "left alone outside off", "dug out, no run", "tucked to the infield, no run"]
const SINGLE := ["worked %s for a single", "dabbed %s, quick single", "pushed %s and they run one"]
const TWO := ["placed %s, they come back for two", "two, driven %s and well run"]
const THREE := ["three, chased down %s just inside the rope"]
const FOUR := ["FOUR! Cracked %s", "FOUR! Glorious timing, %s", "FOUR! Finds the gap %s"]
const SIX := ["SIX! Launched %s", "SIX! That's huge, %s", "SIX! Clears the rope %s"]


static func describe(e: Dictionary, rng: RandomNumberGenerator) -> String:
	var lead := "%s to %s, " % [e.bowler.surname(), e.batter.surname()]
	if e.free_hit:
		lead = "Free hit. " + lead
	var text: String
	if e.extra == "wd":
		text = _pick(rng, WIDE)
	elif not e.wicket.is_empty():
		text = _wicket(e)
	elif e.dropped != null:
		text = "DROPPED! %s puts down the chance. %s" % [e.dropped.surname(), _runs_text(e, rng)]
	elif e.missed_stumping:
		text = "missed stumping! The keeper can't gather"
	else:
		text = _runs_text(e, rng)
	if e.extra == "nb":
		text = "NO BALL! " + text + ". Free hit to come"
	return lead + text + _review_text(e)


## The umpire's call and, if there was one, the review.
static func _review_text(e: Dictionary) -> String:
	var appeal: Dictionary = e.get("appeal", {})
	if appeal.is_empty():
		return ""
	var review: Dictionary = e.get("review", {})
	if review.is_empty():
		return "" if appeal.given_out else ". Big shout for %s, given not out" % appeal.kind
	var who: String = review.team.short_name
	var call := "given out %s" % appeal.kind if appeal.given_out else "not out %s" % appeal.kind
	if review.overturned:
		var now := "NOT OUT, the decision is overturned" if appeal.given_out else "OUT, the decision is overturned"
		return ". Originally %s; %s review and ball-tracking says %s" % [call, who, now]
	return ". %s review the %s call, but it stands (%d review%s left)" % [who, appeal.kind, review.left, "" if review.left == 1 else "s"]


static func _runs_text(e: Dictionary, rng: RandomNumberGenerator) -> String:
	var region: String = e.region
	match e.get("fielded", ""):
		"cut off":
			return "hit hard %s, but the boundary rider cuts it off. %s" % [region, _plural_runs(e.runs)]
		"stopped":
			return "drilled %s, superb stop in the ring, no run" % region
		"gap":
			return "finds the gap %s, %s" % [region, "and it races away for FOUR" if e.runs == 4 else "they come back for two"]
	match int(e.runs):
		0:
			return _pick(rng, DOT)
		1:
			return _pick(rng, SINGLE) % region
		2:
			return _pick(rng, TWO) % region
		3:
			return _pick(rng, THREE) % region
		4:
			return _pick(rng, FOUR) % region
		6:
			return _pick(rng, SIX) % region
	return "%d runs" % e.runs


static func _plural_runs(n: int) -> String:
	return "%d run%s" % [n, "" if n == 1 else "s"]


static func _wicket(e: Dictionary) -> String:
	var out: Dictionary = e.out
	if e.get("fielded", "") == "rope catch":
		return "OUT! Launched %s, but %s takes it on the rope! %s %d (%d)" % [
			e.region.trim_prefix("over "), e.wicket.fielder.surname(), out.how_out, out.runs, out.balls]
	var line := "%s %d (%d)" % [out.how_out, out.runs, out.balls]
	var fielder: CricketPlayer = e.wicket.get("fielder")
	match e.wicket.kind:
		"bowled":
			return "OUT! Clean bowled, the stumps are rearranged. " + line
		"lbw":
			return "OUT! Trapped in front, given lbw. " + line
		"stumped":
			return "OUT! Down the track, beaten, and %s whips the bails off. %s" % [fielder.surname(), line]
		"run out":
			return "OUT! Run out, %s hits the stumps. %s" % [fielder.surname(), line]
	if fielder == e.bowler:
		return "OUT! Chipped back and caught by the bowler. " + line
	if fielder.is_keeper():
		return "OUT! Edged and taken behind. " + line
	return "OUT! Picks out %s %s. %s" % [fielder.surname(), e.region, line]


static func _pick(rng: RandomNumberGenerator, options: Array) -> String:
	return options[rng.randi_range(0, options.size() - 1)]
