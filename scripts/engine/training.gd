class_name Training
extends RefCounted
## Training on the days between matches, for the club's squad, run from a calendar: two
## sessions a day (morning and afternoon) on every day between the club's matches.
##
## Any day can be set by hand (Season.training_plan); the rest follow defaults: the morning
## after a match is Recovery, the afternoon before one is Match prep, and the other sessions
## come from the chosen template (Season.training_template), whose days cycle.
##
## Every day off a match a player recovers RECOVERY_PER_DAY like other clubs' players; each
## session then adds its own recovery and takes its load. Skill sessions develop the session's
## attributes (or a player's own focus, Season.training_focus, if set), young players most,
## and carry a small injury risk that grows with fatigue. Match prep sessions lift the XI's
## confidence at the start of the next match. Other clubs just rest.

const SESSIONS := {
	"Batting nets": {"groups": ["Batting"], "load": 2.0, "injury": 0.0005,
		"desc": "Technique, timing, power, playing spin and running."},
	"Bowling": {"groups": ["Bowling"], "load": 2.5, "injury": 0.001,
		"desc": "Accuracy, movement, pace and variations. Hard on the body."},
	"Fielding drills": {"groups": ["Fielding"], "load": 1.5, "injury": 0.0005,
		"desc": "Catching, ground fielding and keeping."},
	"Fitness": {"groups": ["Physical"], "load": 3.5, "injury": 0.0015,
		"desc": "Stamina work. The most tiring session."},
	"Mental": {"groups": ["Mental"], "load": 0.0, "injury": 0.0,
		"desc": "Video and psychology: composure, concentration, aggression. No physical load."},
	"Match prep": {"groups": [], "load": 0.5, "injury": 0.0, "prep": true,
		"desc": "Plans for the next opponent: the XI starts the next match more confident."},
	"Recovery": {"groups": [], "load": -4.0, "injury": 0.0,
		"desc": "Pool, physio and stretching: the fastest way back to full fitness."},
	"Rest": {"groups": [], "load": -2.5, "injury": 0.0,
		"desc": "A session off."},
}
## Templates: the sessions for each day, cycling through the days between matches.
const TEMPLATES := {
	"Balanced": [["Batting nets", "Bowling"], ["Fielding drills", "Fitness"]],
	"Batting": [["Batting nets", "Batting nets"], ["Batting nets", "Fielding drills"]],
	"Bowling": [["Bowling", "Bowling"], ["Bowling", "Fielding drills"]],
	"Fitness": [["Fitness", "Fitness"], ["Fitness", "Fielding drills"]],
	"Skills": [["Batting nets", "Bowling"], ["Fielding drills", "Mental"]],
	"Light": [["Batting nets", "Rest"], ["Bowling", "Rest"]],
}
const TEMPLATE_HELP := {
	"Balanced": "A bit of everything.",
	"Batting": "Mostly nets.",
	"Bowling": "Mostly bowling; tiring for the seamers.",
	"Fitness": "Stamina first; players will be more tired on match day.",
	"Skills": "Cricket skills and mental work, no fitness.",
	"Light": "Half days: fresh legs, slow development.",
}
## Individual focuses: "Team" follows the session, the rest replace a skill session's
## attributes with their group's.
const INDIVIDUAL := ["Team", "Batting", "Bowling", "Fielding", "Mental", "Physical"]
const SLOTS := ["Morning", "Afternoon"]
## Attribute points per skill session, shared across its attributes, for a player young
## enough to develop fully.
const GROWTH_PER_SESSION := 0.07
## Starting confidence per Match prep session before a match (two count at most).
const PREP_CONFIDENCE := 3.0
const MAX_PREP := 2
## Skills a player doesn't use (below this) don't get trained, as in Development.
const UNUSED := 5.0


## How much of the full gain a player of this age gets: all of it up to 22, tailing off to a
## tenth by 31.
static func age_factor(age: int) -> float:
	return clampf((31.0 - age) / 9.0, 0.1, 1.0)


## The days the club trains before its next match after today: [first, last], or [] if it
## has no match to come. Training days are the days between today and that match.
static func block(s: Season) -> Array:
	var after := -1
	for f in s.fixtures:
		if s.involves(f, s.club) and f.day > s.day and (after < 0 or f.day < after):
			after = f.day
	if after < 0 or after - s.day < 2:
		return []
	return [s.day + 1, after - 1]


## The two sessions on a day: set by hand, or the defaults (see the header).
static func sessions_for(s: Season, d: int) -> Array:
	if s.training_plan.has(d):
		return s.training_plan[d]
	var match_days := {}
	for f in s.fixtures:
		if s.involves(f, s.club):
			match_days[f.day] = true
	# Count days since the last match day to cycle through the template.
	var since := 1
	while since < 30 and not match_days.has(d - since):
		since += 1
	var template: Array = TEMPLATES[s.training_template]
	var out: Array = template[(since - 1) % template.size()].duplicate()
	if match_days.has(d - 1):
		out[0] = "Recovery"
	if match_days.has(d + 1):
		out[1] = "Match prep"
	return out


## The attributes a session works for a player (their own focus replaces a skill session's).
static func session_attrs(p: CricketPlayer, s: Season, session: String) -> Array:
	var groups: Array = SESSIONS[session].groups
	if groups.is_empty():
		return []
	var own: String = s.training_focus.get(p, "Team")
	if own != "Team":
		groups = [own]
	var attrs := []
	for g in groups:
		attrs.append_array(CricketPlayer.ATTRIBUTES[g])
	return attrs.filter(func(a): return p.a(a) >= UNUSED)


## Runs the days after `from` up to `to` (a match day, not trained): recovery for every day,
## then each training day's sessions. Returns a report: {days: [{day, sessions}], gains:
## {player: points}, injured: [player], prep: sessions}.
static func run(s: Season, from: int, to: int) -> Dictionary:
	var report := {"days": [], "gains": {}, "injured": [], "prep": 0}
	for d in range(from + 1, to + 1):
		var sessions: Array = sessions_for(s, d) if d < to else []
		if d < to:
			report.days.append({"day": d, "sessions": sessions})
		for p: CricketPlayer in s.club.squad:
			s.condition[p] = minf(s.condition[p] + Season.RECOVERY_PER_DAY, 100.0)
			if s.injuries.get(p, -1) > d:
				continue
			for session: String in sessions:
				_session(s, p, session, report)
		for session: String in sessions:
			if SESSIONS[session].get("prep", false):
				report.prep += 1
	s.match_prep = mini(report.prep, MAX_PREP)
	return report


static func _session(s: Season, p: CricketPlayer, session: String, report: Dictionary) -> void:
	var info: Dictionary = SESSIONS[session]
	s.condition[p] = clampf(s.condition[p] - info.load, 0.0, 100.0)
	var attrs := session_attrs(p, s, session)
	if not attrs.is_empty():
		var each := GROWTH_PER_SESSION * age_factor(p.age) / attrs.size()
		for attr in attrs:
			p.attrs[attr] = minf(p.attrs[attr] + each, 20.0)
		report.gains[p] = report.gains.get(p, 0.0) + each * attrs.size()
	var risk: float = info.injury * (1.0 + 2.0 * MatchDynamics.fatigue(s.condition[p]))
	if risk > 0.0 and not s.is_injured(p) and s.rng.randf() < risk:
		s.injure(p, "in training")
		report.injured.append(p)


## A line for the inbox, or "" if no training was done.
static func summary(report: Dictionary, s: Season) -> String:
	var days: Array = report.get("days", [])
	if days.is_empty():
		return ""
	var counts := {}
	for d in days:
		for session in d.sessions:
			counts[session] = counts.get(session, 0) + 1
	var done := counts.keys().map(func(k): return "%s x%d" % [k, counts[k]] if counts[k] > 1 else k)
	var parts := ["%d days: %s." % [days.size(), ", ".join(done)]]
	var gains: Dictionary = report.gains
	var best := gains.keys()
	best.sort_custom(func(a, b): return gains[a] > gains[b])
	if not best.is_empty():
		parts.append("Most improved: %s." % ", ".join(best.slice(0, 3).map(func(p): return "%s (+%.2f)" % [p.name, gains[p]])))
	var squad: Array = s.club.squad
	var fresh: float = squad.reduce(func(acc, p): return acc + s.condition[p], 0.0) / maxf(squad.size(), 1.0)
	parts.append("Squad condition averages %d%%." % roundi(fresh))
	if report.prep > 0:
		parts.append("Match prep done: the XI starts more confident.")
	if not report.injured.is_empty():
		parts.append("Injured in training: %s." % ", ".join(report.injured.map(func(p): return p.name)))
	return " ".join(parts)
