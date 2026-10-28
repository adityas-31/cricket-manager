class_name Development
extends RefCounted
## What happens to players between seasons: a year older, attributes growing or fading with
## age (and a little with how well they played), retirements, and each club's youth intake.

## Average change per attribute per year, by age after the birthday.
const GROWTH_BY_AGE := [[20, 1.2], [22, 0.8], [25, 0.4], [29, 0.1], [31, -0.2], [33, -0.5], [99, -0.9]]
const PHYSICAL := ["speed", "stamina", "running", "fielding"]
const MENTAL := ["composure", "concentration"]
## Chance of retiring at the end of a season, by age.
const RETIREMENT := {35: 0.3, 36: 0.6}
const RETIRE_LATE := 0.9  # 37 and over
const NAMES_PATH := "res://data/names.json"


## Ages a player a year and develops their attributes. avg_rating is their season average
## (0 if they didn't play); good seasons help a little.
static func age_player(p: CricketPlayer, avg_rating: float, rng: RandomNumberGenerator) -> void:
	p.age += 1
	var growth := 0.0
	for band in GROWTH_BY_AGE:
		if p.age <= band[0]:
			growth = band[1]
			break
	var perf := clampf((avg_rating - 6.5) * 0.4, -0.3, 0.5) if avg_rating > 0.0 else 0.0
	for attr: String in p.attrs:
		if p.attrs[attr] < 5.0 and growth > 0.0:
			continue  # skills a player doesn't use don't grow (a batter's bowling, an outfielder's keeping)
		var delta := growth + perf + rng.randfn(0.0, 0.5)
		if attr in PHYSICAL and p.age >= 30:
			delta -= 0.3
		if attr in MENTAL and p.age >= 26:
			delta += 0.2
		p.attrs[attr] = clampf(p.attrs[attr] + delta, 1.0, 20.0)


static func retires(p: CricketPlayer, rng: RandomNumberGenerator) -> bool:
	if p.age >= 37:
		return rng.randf() < RETIRE_LATE
	return rng.randf() < RETIREMENT.get(p.age, 0.0)


## A 17-18 year old from the academy: modest now, but young players grow fast. Names come
## from the club's own pool in names.json (by_team) if it has one, else the shared lists.
static func youth_player(id: int, rng: RandomNumberGenerator, names: Dictionary, team_name := "") -> CricketPlayer:
	var own: Dictionary = names.get("by_team", {}).get(team_name, {})
	if not own.get("first", []).is_empty() and not own.get("last", []).is_empty():
		names = own
	var kinds := [["batter", "medium"], ["batter", "medium"], ["bowler", "pace"], ["bowler", "leg_spin"],
		["bowler", "off_spin"], ["all_rounder", "medium"], ["keeper", "medium"]]
	var kind: Array = kinds[rng.randi_range(0, kinds.size() - 1)]
	var bats: bool = kind[0] != "bowler"
	var bowls: bool = kind[0] in ["bowler", "all_rounder"]
	var attrs := {}
	for attr in ["technique", "timing", "power", "vs_spin", "running"]:
		attrs[attr] = rng.randf_range(7.0, 11.5) if bats else rng.randf_range(2.0, 6.0)
	for attr in ["accuracy", "movement", "variation"]:
		attrs[attr] = rng.randf_range(7.0, 11.5) if bowls else rng.randf_range(2.0, 6.0)
	attrs["speed"] = rng.randf_range(11.0, 16.0) if kind[1] == "pace" else rng.randf_range(4.0, 8.0)
	attrs["keeping"] = rng.randf_range(9.0, 13.0) if kind[0] == "keeper" else rng.randf_range(1.0, 3.0)
	for attr in ["catching", "fielding", "composure", "concentration", "stamina"]:
		attrs[attr] = rng.randf_range(7.0, 12.0)
	attrs["aggression"] = rng.randf_range(5.0, 17.0)
	var name := "Trialist %d" % id
	var first: Array = names.get("first", [])
	var last: Array = names.get("last", [])
	if not first.is_empty() and not last.is_empty():
		name = "%s %s" % [first[rng.randi_range(0, first.size() - 1)], last[rng.randi_range(0, last.size() - 1)]]
	return CricketPlayer.from_dict({"id": id, "name": name, "age": rng.randi_range(17, 18),
		"bats": "left" if rng.randf() < 0.27 else "right",
		"bowls": "left" if kind[1] == "pace" and rng.randf() < 0.2 else "right",
		"role": kind[0], "style": kind[1], "attributes": attrs})


static func load_names() -> Dictionary:
	if not FileAccess.file_exists(NAMES_PATH):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(NAMES_PATH))
	return data if typeof(data) == TYPE_DICTIONARY else {}
