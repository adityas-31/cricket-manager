class_name Training
extends RefCounted
## Training on the days between matches, for the club's squad. The team trains with a focus
## (which attribute groups get the work) at an intensity: harder sessions develop players
## faster but leave them less fresh and risk injuries; light ones help them recover. Any
## player can be given their own focus instead of the team's. Young players gain the most.
##
## Other clubs just rest between matches (Season.RECOVERY_PER_DAY).

const FOCUSES := {
	"Balanced": ["Batting", "Bowling", "Fielding", "Mental", "Physical"],
	"Batting": ["Batting"],
	"Bowling": ["Bowling"],
	"Fielding": ["Fielding"],
	"Fitness": ["Physical"],
	"Recovery": [],
}
const FOCUS_HELP := {
	"Balanced": "A bit of everything: slow, even improvement.",
	"Batting": "Nets: technique, timing, power, playing spin, running.",
	"Bowling": "Accuracy, movement, pace and variations.",
	"Fielding": "Catching, ground fielding and keeping.",
	"Fitness": "Stamina work, so players last longer in matches.",
	"Recovery": "Rest and treatment. No development, but players are fresher for the next match.",
}
## Individual focuses: "Team" follows the team focus, the rest are attribute groups.
const INDIVIDUAL := ["Team", "Batting", "Bowling", "Fielding", "Mental", "Physical"]
const INTENSITIES := {
	"Light": {"recovery": 1.4, "growth": 0.5, "injury": 0.0},
	"Normal": {"recovery": 1.0, "growth": 1.0, "injury": 0.0015},
	"Hard": {"recovery": 0.6, "growth": 1.7, "injury": 0.005},
}
const INTENSITY_HELP := {
	"Light": "Players recover faster; little development; no training injuries.",
	"Normal": "Normal recovery and development; the odd knock.",
	"Hard": "Faster development, but players start matches more tired and pick up more injuries.",
}
## Attribute points gained per day, shared across the focused attributes, at Normal for a
## player young enough to develop fully.
const GROWTH_PER_DAY := 0.06
const RECOVERY_FOCUS := 1.3
## Skills a player doesn't use (below this) don't get trained, as in Development.
const UNUSED := 5.0


static func default_plan() -> Dictionary:
	return {"focus": "Balanced", "intensity": "Normal"}


## How much of the full gain a player of this age gets: all of it up to 22, tailing off to a
## tenth by 31.
static func age_factor(age: int) -> float:
	return clampf((31.0 - age) / 9.0, 0.1, 1.0)


## The attributes a player works on, given the team focus and their own.
static func focus_attrs(p: CricketPlayer, s: Season) -> Array:
	var own: String = s.training_focus.get(p, "Team")
	var groups: Array = FOCUSES[s.training.focus] if own == "Team" else [own]
	var attrs := []
	for g in groups:
		attrs.append_array(CricketPlayer.ATTRIBUTES[g])
	return attrs.filter(func(a): return p.a(a) >= UNUSED)


## Runs `days` of training for the club's squad: recovery, development and training
## injuries. Returns a report: {days, focus, intensity, gains: {player: points}, injured: [player]}.
static func run(s: Season, days: int) -> Dictionary:
	var plan: Dictionary = INTENSITIES[s.training.intensity]
	var report := {"days": days, "focus": s.training.focus, "intensity": s.training.intensity, "gains": {}, "injured": []}
	if days <= 0:
		return report
	for p: CricketPlayer in s.club.squad:
		var rest := Season.RECOVERY_PER_DAY * days
		if s.is_injured(p):
			s.condition[p] = minf(s.condition[p] + rest, 100.0)
			continue
		rest *= plan.recovery * (RECOVERY_FOCUS if s.training.focus == "Recovery" else 1.0)
		s.condition[p] = minf(s.condition[p] + rest, 100.0)
		var attrs := focus_attrs(p, s)
		if not attrs.is_empty():
			var each: float = GROWTH_PER_DAY * days * plan.growth * age_factor(p.age) / attrs.size()
			for attr in attrs:
				p.attrs[attr] = minf(p.attrs[attr] + each, 20.0)
			report.gains[p] = each * attrs.size()
		var daily: float = plan.injury * (1.0 + 2.0 * MatchDynamics.fatigue(s.condition[p]))
		if daily > 0.0 and s.rng.randf() < 1.0 - pow(1.0 - daily, days):
			s.injure(p, "in training")
			report.injured.append(p)
	return report


## A line for the inbox, or "" if nothing happened.
static func summary(report: Dictionary, s: Season) -> String:
	if report.get("days", 0) <= 0:
		return ""
	var gains: Dictionary = report.gains
	var best := gains.keys()
	best.sort_custom(func(a, b): return gains[a] > gains[b])
	var parts := ["%d days of %s training, %s." % [report.days, str(report.focus).to_lower(), str(report.intensity).to_lower()]]
	if not best.is_empty():
		parts.append("Most improved: %s." % ", ".join(best.slice(0, 3).map(func(p): return "%s (+%.2f)" % [p.name, gains[p]])))
	var squad: Array = s.club.squad
	var fresh: float = squad.reduce(func(acc, p): return acc + s.condition[p], 0.0) / maxf(squad.size(), 1.0)
	parts.append("Squad condition averages %d%%." % roundi(fresh))
	if not report.injured.is_empty():
		parts.append("Injured in training: %s." % ", ".join(report.injured.map(func(p): return p.name)))
	return " ".join(parts)
