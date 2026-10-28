extends HBoxContainer
## Home, like FM's portal: the next match, the last result, the league table, the latest
## news, and starting a new career.

const NEWS_SHOWN := 4

var app: Node

var _next: VBoxContainer
var _last: VBoxContainer
var _table: VBoxContainer
var _news: VBoxContainer
var _career: VBoxContainer
var _confirming := false


func title() -> String:
	return "Home"


func subtitle() -> String:
	return "%s  ·  %s" % [app.club.name, Season.COMPETITION]


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	var left := _column(330)
	_next = _add_card(left, "Next Match")
	_last = _add_card(left, "Last Result", true)
	var middle := _column(0)
	_table = _add_card(middle, "League Table", true)
	var right := _column(300)
	_news = _add_card(right, "News", true)
	_career = _add_card(right, "Career")


func on_shown() -> void:
	_confirming = false
	_fill_next()
	_fill_last()
	_fill_table()
	_fill_news()
	_fill_career()


func _fill_next() -> void:
	UIKit.clear(_next)
	var s: Season = app.season
	if s.is_over():
		_next.add_child(UIKit.label("Season %d complete" % s.year, 13, UIKit.TEXT_DIM))
		_next.add_child(UIKit.label("%s are champions" % s.champion.name, 20, s.champion.colour.lightened(0.3)))
		_next.add_child(UIKit.stat_row("%s finished" % app.club.short_name, UIKit.ordinal(s.final_standings().find(app.club) + 1)))
		_next.add_child(UIKit.wrapped("Continue to the end-of-season review: prize money, awards, the board's verdict, expiring contracts, retirements and the youth intake. Then the %d season begins." % (s.year + 1), 13))
		return
	var f := s.next_user_fixture()
	if f.is_empty():
		_next.add_child(UIKit.label("Waiting for the play-off draw", 13, UIKit.TEXT_DIM))
		return
	var other: CricketTeam = s.opponent(f)
	var home: bool = f.home == app.club
	_next.add_child(UIKit.label("%s  ·  %s" % [s.date_text(f.day), s.stage_text(f)], 12, UIKit.TEXT_DIM))
	_next.add_child(UIKit.label("%s %s" % ["v" if home else "@", other.name], 22, other.colour.lightened(0.35)))
	_next.add_child(UIKit.stat_row("Venue", "%s (%s pitch)" % ["Home" if home else "Away", f.home.home_pitch.capitalize()]))
	var rows := s.table()
	for team: CricketTeam in [app.club, other]:
		var row: Dictionary = rows.filter(func(r): return r.team == team)[0]
		var h := HBoxContainer.new()
		var name_label := UIKit.label("%s  ·  %s" % [team.short_name, UIKit.ordinal(s.position(team))], 13, UIKit.TEXT_DIM)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(name_label)
		h.add_child(UIKit.form_chips(row.form.slice(-5)))
		_next.add_child(h)
	var club: CricketTeam = app.club
	var expiring := club.squad.filter(func(p): return Transfers.contract_years(p, s) <= 0)
	if not expiring.is_empty():
		var renew := Button.new()
		renew.text = "%d contract%s expire this season" % [expiring.size(), "" if expiring.size() == 1 else "s"]
		renew.add_theme_color_override("font_color", UIKit.WARNING)
		renew.tooltip_text = "Renew them under Transfers > Our Contracts or they leave for free after the final:\n" + \
			"\n".join(expiring.map(func(p): return p.name))
		renew.pressed.connect(app.show_screen.bind("transfers"))
		_next.add_child(renew)
	var problems := Selection.issues(club, s)
	if club.assistant_selects:
		_next.add_child(UIKit.label("Your assistant will pick the XI", 13, UIKit.TEXT_DIM))
	elif not problems.is_empty():
		var warn := Button.new()
		warn.text = "%d selection issue%s: check Tactics" % [problems.size(), "" if problems.size() == 1 else "s"]
		warn.add_theme_color_override("font_color", UIKit.WARNING)
		warn.tooltip_text = "\n".join(problems)
		warn.pressed.connect(app.show_screen.bind("tactics"))
		_next.add_child(warn)
	if f.day == s.day:
		var go := Button.new()
		go.text = "Go to Match Day"
		go.theme_type_variation = "AccentButton"
		go.pressed.connect(app.show_screen.bind("match"))
		_next.add_child(go)
	else:
		_next.add_child(UIKit.label("In %d days" % (f.day - s.day), 12, UIKit.TEXT_DIM))


func _fill_last() -> void:
	UIKit.clear(_last)
	var s: Season = app.season
	var f := s.last_user_result()
	if f.is_empty():
		_last.add_child(UIKit.label("No matches played yet", 13, UIKit.TEXT_DIM))
		return
	var res: Dictionary = f.result
	var letter := "T" if res.winner == null else ("W" if res.winner == app.club else "L")
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.add_child(UIKit.form_chips([letter]))
	h.add_child(UIKit.label("%s v %s" % [f.home.name, f.away.name], 15))
	_last.add_child(h)
	_last.add_child(UIKit.label("%s  ·  %s" % [s.date_text(f.day), s.stage_text(f)], 12, UIKit.TEXT_DIM))
	_last.add_child(UIKit.wrapped(s.score_line(f), 13, UIKit.TEXT))
	_last.add_child(UIKit.wrapped(res.text))
	var potm: CricketPlayer = res.potm
	_last.add_child(UIKit.stat_row("Player of the match", "%s (%.1f)" % [potm.name, res.ratings[potm]], UIKit.WARNING))


func _fill_table() -> void:
	UIKit.clear(_table)
	var rows := []
	var selected := -1
	var table: Array = app.season.table()
	for i in table.size():
		var r: Dictionary = table[i]
		if r.team == app.club:
			selected = i
		rows.append([str(i + 1), r.team.name, r.p, r.w, r.l, {"text": str(r.pts), "colour": UIKit.TEXT},
			{"text": "%+.3f" % r.nrr, "colour": UIKit.TEXT_DIM}, {"text": "".join(r.form.slice(-5)), "colour": UIKit.TEXT_DIM}])
	_table.add_child(UIKit.table([
		{"title": "Pos", "width": 34, "align": "center"}, {"title": "Team", "width": 0},
		{"title": "P", "width": 26, "align": "right"}, {"title": "W", "width": 26, "align": "right"},
		{"title": "L", "width": 26, "align": "right"}, {"title": "Pts", "width": 34, "align": "right"},
		{"title": "NRR", "width": 58, "align": "right"}, {"title": "Form", "width": 66, "align": "right"},
	], rows, Callable(), selected))
	_table.add_child(UIKit.label("Top four reach the semi-finals. Win 2 pts, tie 1. Ties on points split by net run rate.", 12, UIKit.TEXT_DIM))


func _fill_news() -> void:
	UIKit.clear(_news)
	var s: Season = app.season
	var items: Array = s.news.slice(-NEWS_SHOWN)
	items.reverse()
	for n in items:
		_news.add_child(UIKit.label(n.title, 14))
		_news.add_child(UIKit.label(s.news_date(n), 11, UIKit.TEXT_DIM))
		_news.add_child(UIKit.wrapped(n.body))
		_news.add_child(HSeparator.new())
	var all := Button.new()
	all.text = "All News"
	all.pressed.connect(app.show_screen.bind("inbox"))
	_news.add_child(all)


func _fill_career() -> void:
	UIKit.clear(_career)
	_career.add_child(UIKit.label("Start again with any club. This replaces your saved career.", 12, UIKit.TEXT_DIM))
	for credit in app.season.credits:
		_career.add_child(UIKit.wrapped(str(credit), 11))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var pick := OptionButton.new()
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.clip_text = true
	pick.custom_minimum_size.x = 120
	for t: CricketTeam in app.teams:
		pick.add_item(t.name)
	pick.selected = app.teams.find(app.club)
	h.add_child(pick)
	var start := Button.new()
	start.text = "New Career"
	start.pressed.connect(func():
		if _confirming:
			app.new_career(pick.selected)
		else:
			_confirming = true
			start.text = "Confirm?")
	h.add_child(start)
	_career.add_child(h)


func _column(width: float) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	if width > 0:
		v.custom_minimum_size.x = width
	else:
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(v)
	return v


func _add_card(column: VBoxContainer, card_title: String, expand := false) -> VBoxContainer:
	var c := UIKit.card(card_title)
	if expand:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(c)
	return UIKit.content(c)
