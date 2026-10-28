class_name FieldView
extends Control
## FM-style flat 2D view of the ground: the bowling side's actual field, the batters and
## bowler, and the latest delivery's path, with the last few shots left as faint lines.
## Distances are metres; the striker is at the bottom end. Fields are stored in the batter's
## frame (Fields), so for a left-hander everything is mirrored: their off side is on the left.
##
## When `editable`, the manager can move fielders: click one, then click where it should go.
## Each move emits field_edited with the new spots (batter's frame).

signal field_edited(spots: Array)

const VIEW_RADIUS := 74.0
const NON_STRIKER := Vector2(-3.2, -9.4)
const BOWLER := Vector2(1.2, -12.5)
const ANIM_TIME := 0.7
const RECENT_SHOTS := 6
const PICK_RADIUS := 5.0  # metres

var editable := false

var _batting_colour := Color.WHITE
var _bowling_colour := Color.WHITE
var _spots: Array = []  # the field, batter's frame
var _labels: Array = []  # shirt numbers for _spots
var _mirror := 1.0  # -1 when the striker is left-handed
var _batters: Array = []
var _bowler := {}
var _keeper := {}
var _shots: Array = []  # recent deliveries: {angle, distance, runs, wicket, innings, mirror}
var _anim := 1.0
var _chaser := -1
var _selected := -1


func show_state(engine: MatchEngine, event: Dictionary, animate: bool) -> void:
	var inn := engine.current()
	var batting := inn.batting_team
	var bowling := inn.bowling_team
	var this_innings: bool = not event.is_empty() and event.has("innings") and event.innings == inn.number
	var bowler: CricketPlayer = inn.bowler.player if not inn.bowler.is_empty() else inn.last_over_bowler
	if this_innings:
		bowler = event.bowler
	_batting_colour = batting.colour
	_bowling_colour = bowling.colour

	var striker: CricketPlayer = inn.striker.player
	_mirror = -1.0 if striker.left_handed else 1.0
	_batters = [
		{"pos": _flip(Fields.STRIKER), "label": _number(batting, striker)},
		{"pos": NON_STRIKER, "label": _number(batting, inn.non_striker.player)},
	]
	var keeper := bowling.keeper()
	var spinner := bowler != null and bowler.is_spinner()
	_keeper = {"pos": Vector2(0, Fields.STUMPS_Y + (1.5 if spinner else 12.0)), "label": _number(bowling, keeper)}
	_bowler = {"pos": BOWLER, "label": _number(bowling, bowler) if bowler else ""}

	_spots = engine.current_field(inn)
	_labels = []
	for p in bowling.players:
		if p != bowler and p != keeper and _labels.size() < _spots.size():
			_labels.append(_number(bowling, p))

	_shots = _shots.filter(func(s): return s.innings == inn.number)
	_chaser = -1
	if this_innings and event.get("extra", "") != "wd" and not event.has("review_pending"):
		var m := -1.0 if event.batter.left_handed else 1.0
		_shots.append({"angle": event.angle, "distance": event.distance, "runs": event.runs,
			"wicket": not event.wicket.is_empty(), "innings": event.innings, "mirror": m})
		if _shots.size() > RECENT_SHOTS:
			_shots.pop_front()
		if event.distance > 0.0 and _mirror == m:
			_chaser = _nearest_spot(_shots[-1])
	if _selected >= _spots.size():
		_selected = -1
	_anim = 0.0 if animate else 1.0
	queue_redraw()


func _process(delta: float) -> void:
	if _anim < 1.0:
		_anim = minf(_anim + delta / ANIM_TIME, 1.0)
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not editable or not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var metres: Vector2 = (event.position - size / 2.0) / _scale()
	var picked := -1
	for i in _spots.size():
		if _flip(Fields.position(_spots[i])).distance_to(metres) <= PICK_RADIUS:
			picked = i
	if picked >= 0:
		_selected = -1 if picked == _selected else picked
	elif _selected >= 0:
		var spot := Fields.spot_at(_flip(metres))
		var limit := Fields.BOUNDARY - 2.0
		var centre_dist := Fields.position(spot).length()
		if centre_dist > limit:
			spot = Fields.spot_at(Fields.position(spot) * (limit / centre_dist))
		var spots := _spots.duplicate(true)
		spots[_selected] = spot
		_selected = -1
		field_edited.emit(spots)
	queue_redraw()
	accept_event()


func _scale() -> float:
	return minf(size.x, size.y) / 2.0 / VIEW_RADIUS


## Batter's frame to screen frame (and back): mirrored for a left-handed striker.
func _flip(v: Vector2) -> Vector2:
	return Vector2(v.x * _mirror, v.y)


func _draw() -> void:
	var c := size / 2.0
	var s := _scale()
	var to_screen := func(m: Vector2) -> Vector2: return c + m * s

	draw_circle(c, VIEW_RADIUS * s, Color("1e4d2b"))
	_draw_stripes(c, Fields.BOUNDARY * s, 12)
	draw_arc(c, Fields.BOUNDARY * s, 0, TAU, 128, Color(1, 1, 1, 0.9), 2.0)
	_draw_ring(c, s)

	draw_rect(Rect2(to_screen.call(Vector2(-1.6, -11.0)), Vector2(3.2, 22.0) * s), Color("c9b48a"))
	for y in [-8.84, 8.84]:
		draw_line(to_screen.call(Vector2(-1.6, y)), to_screen.call(Vector2(1.6, y)), Color.WHITE, 1.5)
	for y in [-Fields.STUMPS_Y, Fields.STUMPS_Y]:
		draw_rect(Rect2(to_screen.call(Vector2(-0.12, y - 0.1)), Vector2(0.24, 0.2) * s), Color("3b2a1a"))

	var striker: Vector2 = _batters[0].pos if not _batters.is_empty() else Fields.STRIKER
	for i in _shots.size() - 1:
		var shot: Dictionary = _shots[i]
		if shot.distance > 0.0:
			var col := _shot_colour(shot)
			col.a = 0.25
			draw_line(to_screen.call(striker), to_screen.call(_landing(shot)), col, 1.5)

	var t := ease(_anim, 0.6)
	var radius := maxf(9.0, 1.7 * s)
	for i in _spots.size():
		var pos := _flip(Fields.position(_spots[i]))
		if i == _chaser:
			pos = pos.lerp(_landing(_shots[-1]), t * 0.75)
		var label: String = _labels[i] if i < _labels.size() else ""
		var outside := Fields.outside_ring(_spots[i])
		_draw_player(to_screen.call(pos), radius, _bowling_colour.darkened(0.15) if outside else _bowling_colour, label)
		if editable and i == _selected:
			draw_arc(to_screen.call(pos), radius + 4.0, 0, TAU, 24, UIKit.WARNING, 3.0)
	if not _keeper.is_empty():
		_draw_player(to_screen.call(_keeper.pos), radius, _bowling_colour.darkened(0.25), _keeper.label)
	if not _bowler.is_empty() and _bowler.label != "":
		_draw_player(to_screen.call(_bowler.pos), radius, _bowling_colour.lightened(0.15), _bowler.label)
	for b in _batters:
		_draw_player(to_screen.call(b.pos), radius, _batting_colour, b.label)

	if not _shots.is_empty():
		var shot: Dictionary = _shots[-1]
		var end := _landing(shot)
		var ball: Vector2 = striker.lerp(end, t)
		var lift := sin(t * PI) * (14.0 if shot.runs == 6 else 4.0) if shot.distance > 30.0 else 0.0
		if shot.distance > 0.0:
			draw_line(to_screen.call(striker), to_screen.call(ball), _shot_colour(shot), 2.5)
		draw_circle(to_screen.call(ball), 3.5, Color(0, 0, 0, 0.4))
		draw_circle(to_screen.call(ball) - Vector2(0, lift), 4.0, Color.WHITE)
		if shot.wicket and _anim >= 1.0:
			_draw_cross(to_screen.call(end if shot.distance > 0.0 else striker + Vector2(0, 1.2)), 8.0)

	# The striker's off side is on the right for a right-hander, the left for a left-hander.
	var font := ThemeDB.fallback_font
	var right_label := "OFF" if _mirror > 0.0 else "LEG"
	var left_label := "LEG" if _mirror > 0.0 else "OFF"
	draw_string(font, c + Vector2(Fields.BOUNDARY * s - 46, -Fields.BOUNDARY * s + 30), right_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.5))
	draw_string(font, c + Vector2(-Fields.BOUNDARY * s + 22, -Fields.BOUNDARY * s + 30), left_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.5))
	if editable:
		var hint := "Click a fielder, then click where they should stand"
		var w := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, Vector2(c.x - w / 2.0, size.y - 12.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.WARNING)


## The 30-yard circle: semicircles round each set of stumps joined by straight lines, dashed.
func _draw_ring(c: Vector2, s: float) -> void:
	var col := Color(1, 1, 1, 0.45)
	var r := Fields.RING * s
	var top := c + Vector2(0, -Fields.STUMPS_Y * s)
	var bottom := c + Vector2(0, Fields.STUMPS_Y * s)
	for i in 32:
		if i % 2 == 0:
			draw_arc(top, r, PI + PI * i / 32.0, PI + PI * (i + 1) / 32.0, 4, col, 1.5)
			draw_arc(bottom, r, PI * i / 32.0, PI * (i + 1) / 32.0, 4, col, 1.5)
	for x in [-r, r]:
		for k in 4:
			if k % 2 == 0:
				draw_line(top + Vector2(x, (bottom.y - top.y) * k / 4.0), top + Vector2(x, (bottom.y - top.y) * (k + 1) / 4.0), col, 1.5)


func _draw_stripes(c: Vector2, r: float, count: int) -> void:
	var band := 2.0 * r / count
	for i in count:
		var y0 := -r + band * i
		var y1 := y0 + band
		var pts := PackedVector2Array()
		for k in 9:
			var y := lerpf(y0, y1, k / 8.0)
			pts.append(c + Vector2(sqrt(maxf(r * r - y * y, 0.0)), y))
		for k in 9:
			var y := lerpf(y1, y0, k / 8.0)
			pts.append(c + Vector2(-sqrt(maxf(r * r - y * y, 0.0)), y))
		draw_colored_polygon(pts, Color("2f7a3c") if i % 2 == 0 else Color("358643"))


func _draw_player(pos: Vector2, radius: float, colour: Color, text: String) -> void:
	draw_circle(pos + Vector2(1.5, 2), radius, Color(0, 0, 0, 0.3))
	draw_circle(pos, radius, colour)
	draw_arc(pos, radius, 0, TAU, 24, Color.WHITE, 1.5)
	var font := ThemeDB.fallback_font
	var fs := int(radius * 1.05)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, pos + Vector2(-w / 2.0, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _draw_cross(pos: Vector2, r: float) -> void:
	draw_line(pos + Vector2(-r, -r), pos + Vector2(r, r), UIKit.NEGATIVE, 3.0)
	draw_line(pos + Vector2(-r, r), pos + Vector2(r, -r), UIKit.NEGATIVE, 3.0)


func _shot_colour(shot: Dictionary) -> Color:
	if shot.wicket:
		return UIKit.NEGATIVE
	match int(shot.runs):
		4:
			return UIKit.FOUR
		6:
			return UIKit.SIX
	return Color(1, 1, 1, 0.85)


## Where a shot ended up, in screen-frame metres (mirrored for the batter who played it).
func _landing(shot: Dictionary) -> Vector2:
	var p := Fields.position([shot.angle, shot.distance])
	return Vector2(p.x * shot.mirror, p.y)


func _nearest_spot(shot: Dictionary) -> int:
	var target := _landing(shot)
	var best := -1
	var best_d := INF
	for i in _spots.size():
		var d := _flip(Fields.position(_spots[i])).distance_to(target)
		if d < best_d:
			best_d = d
			best = i
	return best


static func _number(team: CricketTeam, p: CricketPlayer) -> String:
	return str(team.players.find(p) + 1)
