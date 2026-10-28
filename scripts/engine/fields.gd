class_name Fields
extends RefCounted
## Field settings. A field is 9 fielders (the keeper and bowler are extra), each a spot
## [angle, distance]: degrees from straight down the ground (positive = the batter's off side)
## and metres from the striker. Spots are in the batter's frame, so the same field works for
## left- and right-handers; the 2D view mirrors it for left-handers.
##
## The 30-yard circle is two 27.43 m semicircles round each set of stumps joined by straight
## lines. Fielding restrictions: at most 2 fielders outside it in the powerplay, 5 after.

const AUTO := "Captain's choice"
const CUSTOM := "Custom"
const STRIKER := Vector2(0.7, 8.84)  # metres from the middle of the pitch, striker's end at +y
const STUMPS_Y := 10.06
const RING := 27.43
const BOUNDARY := 70.0
## Spots this close to the striker count as close catchers (slips, gully, short leg).
const CLOSE := 22.5

const PRESETS := {
	"Attacking": [[150, 19], [140, 20], [112, 21], [92, 24], [55, 25], [18, 25], [-20, 25], [-95, 23], [-150, 62]],
	"Balanced": [[150, 19], [95, 24], [55, 25], [18, 25], [-20, 25], [-60, 25], [-95, 24], [-150, 62], [140, 62]],
	"Middle overs": [[95, 24], [50, 25], [18, 25], [-20, 25], [-95, 24], [60, 64], [-60, 64], [-150, 62], [140, 62]],
	"Defensive": [[95, 24], [45, 25], [55, 64], [20, 66], [-20, 66], [-60, 64], [-95, 25], [-150, 62], [128, 24]],
	"Off-side": [[150, 19], [95, 24], [55, 25], [38, 26], [15, 25], [62, 64], [102, 62], [-22, 25], [-150, 62]],
	"Leg-side": [[95, 24], [20, 25], [-20, 25], [-55, 25], [-60, 64], [-95, 63], [-150, 62], [-20, 66], [140, 62]],
	"Death": [[95, 24], [70, 25], [45, 25], [20, 66], [-20, 66], [-60, 64], [-95, 63], [-150, 62], [-30, 25]],
}
const PRESET_HELP := {
	"Attacking": "Two slips and a gully, one man out. Edges get caught; gaps get hit.",
	"Balanced": "A slip, a ring of five, two men back: the powerplay field.",
	"Middle overs": "No slip, four men back on both sides: cut off the boundaries, give the single.",
	"Defensive": "Five on the boundary to stop fours. Singles are easy.",
	"Off-side": "Seven on the off side for bowling outside off stump.",
	"Leg-side": "Leg side packed with boundary riders for the short ball.",
	"Death": "Boundary riders straight and square for yorkers at the death.",
}


## Where a spot is, in metres from the middle of the pitch (batter's frame).
static func position(spot: Array) -> Vector2:
	var r := deg_to_rad(float(spot[0]))
	return STRIKER + Vector2(sin(r), -cos(r)) * float(spot[1])


## Inverse of position(): a point in metres back to [angle, distance] from the striker.
static func spot_at(point: Vector2) -> Array:
	var d := point - STRIKER
	return [rad_to_deg(atan2(d.x, -d.y)), d.length()]


static func outside_ring(spot: Array) -> bool:
	var p := position(spot)
	var dy := maxf(absf(p.y) - STUMPS_Y, 0.0)
	return Vector2(p.x, dy).length() > RING


static func outside_count(field: Array) -> int:
	return field.filter(func(s): return outside_ring(s)).size()


static func max_outside(phase: String) -> int:
	return 2 if phase == "powerplay" else 5


## A copy of the field that obeys the restrictions: the deepest extra boundary riders are
## brought in to the edge of the circle along the same line.
static func legalise(field: Array, phase: String) -> Array:
	var out := field.map(func(s): return [float(s[0]), float(s[1])])
	while outside_count(out) > max_outside(phase):
		var deep := out.filter(func(s): return outside_ring(s))
		deep.sort_custom(func(a, b): return a[1] > b[1])
		var spot: Array = deep[0]
		while outside_ring(spot) and spot[1] > 5.0:
			spot[1] -= 1.0
	return out


## The field the captain sets for a bowling approach (0 defensive, 1 balanced, 2 attacking).
static func auto_preset(approach: int, phase: String) -> String:
	if approach == 2:
		return "Attacking"
	if phase == "death":
		return "Death"
	if approach == 0:
		return "Defensive"
	return "Middle overs" if phase == "middle" else "Balanced"


static func angle_gap(a: float, b: float) -> float:
	return absf(wrapf(a - b, -180.0, 180.0))


## The smallest angular gap (degrees) between a shot and any fielder between the given
## distances from the striker; 180 if there's nobody there.
static func nearest_gap(field: Array, angle: float, min_dist: float, max_dist: float) -> float:
	var best := 180.0
	for s in field:
		if s[1] >= min_dist and s[1] <= max_dist:
			best = minf(best, angle_gap(angle, s[0]))
	return best


static func nearest_spot(field: Array, angle: float) -> Array:
	var best: Array = field[0]
	for s in field:
		if angle_gap(angle, s[0]) < angle_gap(angle, best[0]):
			best = s
	return best


static func close_catchers(field: Array) -> int:
	return field.filter(func(s): return s[1] <= CLOSE).size()
