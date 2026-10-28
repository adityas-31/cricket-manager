class_name CricketTeam
extends RefCounted
## A club: its squad, the selected playing XI and its tactics. `players` is the XI in
## batting order (changing it mid-innings changes who comes in next); `squad` is everyone.

const XI_SIZE := 11

var name := ""
var short_name := ""
var colour := Color.WHITE
var home_pitch := "balanced"
var squad: Array = []
var players: Array = []
## When true the assistant picks the XI before every match (AI clubs always do).
var assistant_selects := false
var bat_roles := {}  # CricketPlayer -> key of Tactics.BAT_ROLES
var bowl_roles := {}  # CricketPlayer -> key of Tactics.BOWL_ROLES
## Instructions a match starts with (indices into MatchEngine.BAT_APPROACHES / BOWL_APPROACHES).
var default_bat_approach := 2
var default_bowl_approach := -1


static func from_dict(d: Dictionary) -> CricketTeam:
	var t := CricketTeam.new()
	t.name = str(d.get("name", "Unnamed XI"))
	t.short_name = str(d.get("short", t.name.left(3).to_upper()))
	t.colour = Color(str(d.get("colour", "#ffffff")))
	t.home_pitch = str(d.get("pitch", "balanced"))
	for p in d.get("players", []):
		t.squad.append(CricketPlayer.from_dict(p))
	t.players = t.squad.slice(0, XI_SIZE)
	Tactics.suggest_batting(t)
	return t


## Loads every team from a JSON file shaped {"teams": [...]}.
static func load_all(path: String) -> Array:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Could not parse teams file %s" % path)
		return []
	var teams := []
	for t in data.get("teams", []):
		teams.append(CricketTeam.from_dict(t))
	return teams


## The data credits a teams file asks to be shown (its optional "credits" list).
static func load_credits(path: String) -> Array:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data.get("credits", []) if typeof(data) == TYPE_DICTIONARY else []


func find_player(id: int) -> CricketPlayer:
	for p in squad:
		if p.id == id:
			return p
	return null


## The XI's wicketkeeper: a specialist if one is playing, otherwise the best gloveman.
func keeper() -> CricketPlayer:
	var best: CricketPlayer = players[0]
	for p: CricketPlayer in players:
		if p.is_keeper():
			return p
		if p.a("keeping") > best.a("keeping"):
			best = p
	return best


func reserves() -> Array:
	return squad.filter(func(p): return not p in players)


func average(attr: String) -> float:
	var total := 0.0
	for p in players:
		total += p.a(attr)
	return total / maxf(players.size(), 1)


## A random fielder other than the bowler and keeper.
func random_fielder(rng: RandomNumberGenerator, bowler: CricketPlayer) -> CricketPlayer:
	var options := players.filter(func(p): return p != bowler and not p.is_keeper())
	return options[rng.randi_range(0, options.size() - 1)]
