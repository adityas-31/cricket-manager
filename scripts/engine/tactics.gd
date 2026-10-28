class_name Tactics
extends RefCounted
## Batting and bowling roles. Teams store a role per player (CricketTeam.bat_roles /
## bowl_roles); CaptainAI reads them when setting intent and choosing bowlers.

## Intent added per phase on top of the captain's read of the situation.
const BAT_ROLES := {
	"Balanced": {"powerplay": 0.0, "middle": 0.0, "death": 0.0,
		"desc": "Plays the situation as the captain reads it."},
	"Anchor": {"powerplay": -0.2, "middle": -0.25, "death": 0.1,
		"desc": "Holds an end together and keeps risk low until the death overs."},
	"Aggressor": {"powerplay": 0.25, "middle": 0.25, "death": 0.25,
		"desc": "Takes the bowling on from the first ball."},
	"Pinch Hitter": {"powerplay": 0.55, "middle": 0.2, "death": 0.2,
		"desc": "Slogs while the field is up. Best promoted up the order."},
	"Finisher": {"powerplay": -0.1, "middle": -0.1, "death": 0.4,
		"desc": "Builds quietly, then cuts loose in the death overs."},
}
const BAT_DEFAULT := "Balanced"

## The phase each bowling role is planned for.
const BOWL_ROLES := {
	"Auto": {"phase": "", "desc": "The captain decides when to bowl them."},
	"New Ball": {"phase": "powerplay", "desc": "Opens the bowling and bowls through the powerplay."},
	"Middle Overs": {"phase": "middle", "desc": "Controls the middle overs."},
	"Death": {"phase": "death", "desc": "Overs are saved for the end of the innings."},
	"Do Not Bowl": {"phase": "", "desc": "Only bowls if nobody else can."},
}
const BOWL_DEFAULT := "Auto"


static func bat_role(team: CricketTeam, p: CricketPlayer) -> String:
	return team.bat_roles.get(p, BAT_DEFAULT)


static func bowl_role(team: CricketTeam, p: CricketPlayer) -> String:
	return team.bowl_roles.get(p, BOWL_DEFAULT)


static func intent_offset(team: CricketTeam, p: CricketPlayer, phase: String) -> float:
	return BAT_ROLES[bat_role(team, p)].get(phase, 0.0)


## Suggested batting roles for the whole squad from attributes and place in the XI's order.
static func suggest_batting(team: CricketTeam) -> void:
	for p: CricketPlayer in team.squad:
		var i := team.players.find(p)
		var role := BAT_DEFAULT
		if p.a("technique") + p.a("concentration") >= 30.0 and p.a("aggression") <= 11.0:
			role = "Anchor"
		elif p.a("aggression") >= 15.0:
			role = "Aggressor"
		elif i >= 4 and i <= 7 and p.a("power") >= 14.0:
			role = "Finisher"
		team.bat_roles[p] = role


## Suggested bowling plan: swing bowlers take the new ball, the pace bowler with the best
## variations bowls at the death, spinners control the middle, weak part-timers rest.
static func suggest_bowling(team: CricketTeam) -> void:
	team.bowl_roles.clear()
	var pace := team.squad.filter(func(p): return not p.is_spinner() and p.bowling_rating() >= 10.0)
	pace.sort_custom(func(a, b): return a.a("variation") > b.a("variation"))
	if not pace.is_empty():
		team.bowl_roles[pace[0]] = "Death"
	var openers := pace.filter(func(p): return not team.bowl_roles.has(p))
	openers.sort_custom(func(a, b): return a.a("movement") > b.a("movement"))
	for p in openers.slice(0, 2):
		team.bowl_roles[p] = "New Ball"
	for p: CricketPlayer in team.squad:
		if p.is_spinner() and p.bowling_rating() >= 10.0:
			team.bowl_roles[p] = "Middle Overs"
		elif p.bowling_rating() < 7.0 and not p.is_keeper():
			team.bowl_roles[p] = "Do Not Bowl"
