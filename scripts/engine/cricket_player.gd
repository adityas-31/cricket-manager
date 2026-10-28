class_name CricketPlayer
extends RefCounted
## A cricketer and their attributes. Attributes use a 1-20 scale, like Football Manager.

enum Role { BATTER, BOWLER, ALL_ROUNDER, KEEPER }
enum Style { PACE, MEDIUM, OFF_SPIN, LEG_SPIN, LEFT_ARM_SPIN }

const ATTRIBUTES := {
	"Batting": ["technique", "timing", "power", "vs_spin", "running"],
	"Bowling": ["accuracy", "movement", "speed", "variation"],
	"Fielding": ["catching", "fielding", "keeping"],
	"Mental": ["composure", "concentration", "aggression"],
	"Physical": ["stamina"],
}

var id := 0
var name := ""
var age := 27
var left_handed := false  # bats left-handed
var left_arm := false  # bowls left-arm
var role := Role.BATTER
var style := Style.MEDIUM
var attrs := {}


static func from_dict(d: Dictionary) -> CricketPlayer:
	var p := CricketPlayer.new()
	p.id = int(d.get("id", 0))
	p.name = str(d.get("name", "Unknown"))
	p.age = int(d.get("age", 27))
	p.left_handed = str(d.get("bats", "right")) == "left"
	p.role = Role.get(str(d.get("role", "batter")).to_upper(), Role.BATTER)
	p.style = Style.get(str(d.get("style", "medium")).to_upper(), Style.MEDIUM)
	p.left_arm = str(d.get("bowls", "right")) == "left" or p.style == Style.LEFT_ARM_SPIN
	var given: Dictionary = d.get("attributes", {})
	for group in ATTRIBUTES.values():
		for attr in group:
			p.attrs[attr] = float(given.get(attr, 8))
	return p


## The inverse of from_dict, used by saves (attributes keep their fractional development).
func to_dict() -> Dictionary:
	return {"id": id, "name": name, "age": age, "bats": "left" if left_handed else "right",
		"bowls": "left" if left_arm else "right", "role": str(Role.keys()[role]).to_lower(),
		"style": str(Style.keys()[style]).to_lower(), "attributes": attrs.duplicate()}


func a(attr: String) -> float:
	return attrs.get(attr, 8.0)


func surname() -> String:
	return name.get_slice(" ", name.get_slice_count(" ") - 1)


func is_spinner() -> bool:
	return style in [Style.OFF_SPIN, Style.LEG_SPIN, Style.LEFT_ARM_SPIN]


func is_keeper() -> bool:
	return role == Role.KEEPER


func batting_rating() -> float:
	return a("technique") * 0.35 + a("timing") * 0.3 + a("power") * 0.15 + a("composure") * 0.1 + a("concentration") * 0.1


func bowling_rating() -> float:
	var r := a("accuracy") * 0.4 + a("movement") * 0.3 + a("variation") * 0.15 + a("composure") * 0.15
	if style == Style.PACE:
		r += (a("speed") - 10.0) * 0.15
	return r


func style_name() -> String:
	var s := str(Style.keys()[style]).capitalize()
	return "Left-arm " + s.to_lower() if left_arm and style != Style.LEFT_ARM_SPIN else s


func hand_text() -> String:
	return "Left-hand bat" if left_handed else "Right-hand bat"
