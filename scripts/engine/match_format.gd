class_name MatchFormat
extends RefCounted
## Rules and tempo for a limited-overs format.

var name := ""
var overs := 20
var max_bowler_overs := 4
var powerplay_overs := 6
var death_overs := 4
## Runs per over an average side scores; chases compare the required rate against it.
var par_rate := 8.0
## Baseline batting intent per phase, from -1 (block) to 1 (all-out attack).
var phase_intent := {}


static func t20() -> MatchFormat:
	var f := MatchFormat.new()
	f.name = "T20"
	f.overs = 20
	f.max_bowler_overs = 4
	f.powerplay_overs = 6
	f.death_overs = 4
	f.par_rate = 8.0
	f.phase_intent = {"powerplay": 0.4, "middle": 0.2, "death": 0.8}
	return f


static func odi() -> MatchFormat:
	var f := MatchFormat.new()
	f.name = "ODI"
	f.overs = 50
	f.max_bowler_overs = 10
	f.powerplay_overs = 10
	f.death_overs = 10
	f.par_rate = 5.5
	f.phase_intent = {"powerplay": -0.35, "middle": -0.6, "death": 0.3}
	return f


## "powerplay", "middle" or "death" for a 0-based over index.
func phase(over: int) -> String:
	if over < powerplay_overs:
		return "powerplay"
	if over >= overs - death_overs:
		return "death"
	return "middle"
