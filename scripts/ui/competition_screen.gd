extends VBoxContainer
## Competition: the league table with play-offs, and the season's leading players.

const VIEWS := ["Table", "Stats", "History"]

var app: Node

var _view: String = VIEWS[0]
var _body: VBoxContainer


func title() -> String:
	return Season.COMPETITION


func subtitle() -> String:
	var s: Season = app.season
	return "Season %d  ·  Champions: %s" % [s.year, s.champion.name] if s.is_over() else "Season %d  ·  %s" % [s.year, s.date_text()]


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	add_child(UIKit.sub_nav(VIEWS, func(v):
		_view = v
		on_shown()))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 12)
	scroll.add_child(_body)


func on_shown() -> void:
	UIKit.clear(_body)
	match _view:
		"Table":
			_show_table()
		"Stats":
			_show_stats()
		_:
			_show_history()


func _show_history() -> void:
	var s: Season = app.season
	var c := UIKit.card("Past Seasons")
	_body.add_child(c)
	if s.history.is_empty():
		UIKit.content(c).add_child(UIKit.label("No completed seasons yet. The %d season ends after the final." % s.year, 13, UIKit.TEXT_DIM))
		return
	var seasons: Array = s.history.duplicate()
	seasons.reverse()
	var rows := []
	for h in seasons:
		var finish := int(h.club_finish)
		rows.append([str(h.year), {"text": h.champion, "colour": UIKit.WARNING}, h.runner_up,
			{"text": "%s (%s)" % [Season.ordinal(finish), h.club], "colour": UIKit.POSITIVE if finish <= 4 else UIKit.TEXT},
			h.player_of_season, h.top_runs, h.top_wickets, h.young_player])
	UIKit.content(c).add_child(UIKit.table([
		{"title": "Year", "width": 44}, {"title": "Champions", "width": 150}, {"title": "Runners-up", "width": 150},
		{"title": "Your finish", "width": 170}, {"title": "Player of the season", "width": 0},
		{"title": "Most runs", "width": 0}, {"title": "Most wickets", "width": 0}, {"title": "Young player", "width": 0},
	], rows))


func _show_table() -> void:
	var s: Season = app.season
	if s.is_over():
		var banner := PanelContainer.new()
		var style := UIKit.flat(s.champion.colour.darkened(0.35), 4, 16, 12)
		style.border_width_left = 6
		style.border_color = s.champion.colour
		banner.add_theme_stylebox_override("panel", style)
		banner.add_child(UIKit.label("%s are the %s champions" % [s.champion.name, Season.COMPETITION], 20, Color.WHITE))
		_body.add_child(banner)

	var c := UIKit.card("League Table")
	var rows := []
	var selected := -1
	var table := s.table()
	for i in table.size():
		var r: Dictionary = table[i]
		if r.team == app.club:
			selected = i
		var pos := {"text": str(i + 1), "colour": UIKit.POSITIVE if i < 4 else UIKit.TEXT_DIM}
		rows.append([pos, r.team.name, r.p, r.w, r.l, r.t, {"text": str(r.pts), "colour": UIKit.TEXT},
			"%+.3f" % r.nrr, {"text": "  ".join(r.form.slice(-5)), "colour": UIKit.TEXT_DIM}])
	var cols := [{"title": "Pos", "width": 40, "align": "center"}, {"title": "Team", "width": 0}]
	for t in ["P", "W", "L", "T", "Pts"]:
		cols.append({"title": t, "width": 40, "align": "right"})
	cols.append_array([{"title": "NRR", "width": 80, "align": "right"}, {"title": "Last 5", "width": 120, "align": "right"}])
	UIKit.content(c).add_child(UIKit.table(cols, rows, Callable(), selected))
	UIKit.content(c).add_child(UIKit.label("Top four (green) reach the semi-finals: 1st v 4th and 2nd v 3rd, higher seed at home. A tied knockout goes to the higher seed.", 12, UIKit.TEXT_DIM))
	_body.add_child(c)

	var playoffs := s.fixtures.filter(func(f): return f.stage != "League")
	if not playoffs.is_empty():
		var p := UIKit.card("Play-offs")
		for f in playoffs:
			var result: String = f.result.text if not f.result.is_empty() else s.date_text(f.day)
			UIKit.content(p).add_child(UIKit.stat_row("%s:  %s v %s" % [f.stage, f.home.name, f.away.name], result))
		_body.add_child(p)


func _show_stats() -> void:
	var s: Season = app.season
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	_body.add_child(h)

	var runs := []
	for p: CricketPlayer in s.leaders("runs"):
		var st: Dictionary = s.stats[p]
		runs.append([p.name, _team(p), {"text": "%d" % st.runs, "colour": UIKit.TEXT},
			"%.1f" % s.batting_average(p), "%.0f" % (st.runs * 100.0 / maxf(st.balls, 1.0)),
			"%d%s" % [st.hs, "*" if st.hs_not_out else ""]])
	h.add_child(_leader_card("Most Runs", ["Runs", "Avg", "SR", "HS"], runs))

	var wkts := []
	for p: CricketPlayer in s.leaders("wickets"):
		var st: Dictionary = s.stats[p]
		wkts.append([p.name, _team(p), {"text": "%d" % st.wickets, "colour": UIKit.TEXT},
			"%.2f" % (st.bowl_runs * 6.0 / maxf(st.bowl_balls, 1.0)), "%d-%d" % [st.best_w, st.best_r]])
	h.add_child(_leader_card("Most Wickets", ["Wkts", "Econ", "Best"], wkts))

	var rated := []
	for p: CricketPlayer in s.leaders("rating"):
		var r := s.average_rating(p)
		rated.append([p.name, _team(p), "%d" % s.stats[p].apps,
			{"text": "%.2f" % r, "colour": UIKit.POSITIVE if r >= 7.5 else UIKit.TEXT}])
	h.add_child(_leader_card("Best Average Rating", ["Apps", "Rating"], rated))


func _team(p: CricketPlayer) -> Dictionary:
	var t: CricketTeam = app.season.team_of(p)
	if t == null:
		return {"text": "FA", "colour": UIKit.TEXT_DIM}
	return {"text": t.short_name, "colour": t.colour.lightened(0.3)}


func _leader_card(card_title: String, stat_titles: Array, rows: Array) -> Control:
	var c := UIKit.card(card_title)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cols := [{"title": "Player", "width": 0}, {"title": "Team", "width": 42}]
	for t in stat_titles:
		cols.append({"title": t, "width": 48, "align": "right"})
	if rows.is_empty():
		UIKit.content(c).add_child(UIKit.label("No matches played yet", 13, UIKit.TEXT_DIM))
	else:
		UIKit.content(c).add_child(UIKit.table(cols, rows))
	return c
