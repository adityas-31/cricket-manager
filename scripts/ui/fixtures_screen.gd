extends VBoxContainer
## Fixtures: the club's schedule and results, or every fixture in the competition.

const VIEWS := ["Our Fixtures", "All Fixtures"]

var app: Node

var _view: String = VIEWS[0]
var _list: VBoxContainer


func title() -> String:
	return "Fixtures"


func subtitle() -> String:
	return "%s  ·  %s" % [app.club.name, Season.COMPETITION]


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	add_child(UIKit.sub_nav(VIEWS, func(v):
		_view = v
		on_shown()))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var c := UIKit.card("Schedule")
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(c)
	_list = UIKit.content(c)


func on_shown() -> void:
	UIKit.clear(_list)
	var s: Season = app.season
	if _view == VIEWS[0]:
		_list.add_child(_ours(s))
	else:
		_list.add_child(_all(s))


func _ours(s: Season) -> Control:
	var rows := []
	var selected := -1
	var mine := s.fixtures.filter(func(f): return s.involves(f, app.club))
	for i in mine.size():
		var f: Dictionary = mine[i]
		if f.day == s.day:
			selected = i
		var other: CricketTeam = s.opponent(f)
		var letter := "-"
		var score := ""
		if not f.result.is_empty():
			letter = "T" if f.result.winner == null else ("W" if f.result.winner == app.club else "L")
			score = s.score_line(f)
		rows.append([s.date_text(f.day), {"text": s.stage_text(f), "colour": UIKit.TEXT_DIM}, other.name,
			{"text": "H" if f.home == app.club else "A", "colour": UIKit.TEXT_DIM},
			{"text": letter, "colour": UIKit.result_colour(letter)}, {"text": score, "colour": UIKit.TEXT_DIM, "size": 13}])
	return UIKit.table([
		{"title": "Date", "width": 130}, {"title": "Stage", "width": 100}, {"title": "Opponent", "width": 210},
		{"title": "Venue", "width": 50, "align": "center"}, {"title": "Res", "width": 36, "align": "center"},
		{"title": "Score", "width": 0},
	], rows, Callable(), selected)


func _all(s: Season) -> Control:
	var rows := []
	var selected := -1
	for i in s.fixtures.size():
		var f: Dictionary = s.fixtures[i]
		if f.day == s.day and selected < 0:
			selected = i
		var colour: Color = app.club.colour.lightened(0.4) if s.involves(f, app.club) else UIKit.TEXT
		rows.append([s.date_text(f.day), {"text": s.stage_text(f), "colour": UIKit.TEXT_DIM},
			{"text": "%s v %s" % [f.home.name, f.away.name], "colour": colour},
			{"text": f.result.text if not f.result.is_empty() else "", "colour": UIKit.TEXT_DIM, "size": 13}])
	return UIKit.table([
		{"title": "Date", "width": 130}, {"title": "Stage", "width": 100},
		{"title": "Match", "width": 400}, {"title": "Result", "width": 0},
	], rows, Callable(), selected)
