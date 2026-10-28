extends VBoxContainer
## Match Day, laid out like FM24's match screen: sub-navigation, a scoreboard strip, the 2D
## ground flanked by live panels, a commentary bar, and match controls along the bottom.
##
## On a day the club plays, it loads that fixture: Continue plays and pauses it, and once
## it's over the result goes into the season and Continue moves the calendar on. On other
## days it hosts friendlies (format and pitch pickers), which don't count for anything.

const FORMATS := ["T20", "ODI"]
const VIEWS := ["Match", "Scorecard", "Commentary", "Report"]

var app: Node
var engine: MatchEngine
var fixture: Dictionary = {}  # the season fixture being played, or {} for a friendly
var auto_play := false

var _timer := 0.0
var _last_event := {}
var _views := {}
var _view_buttons := {}
var _break := false  # paused between innings until the manager carries on
var _news_before := 0  # season news count before the result went in, for the report
var _report: VBoxContainer
var _scoreboard: HBoxContainer
var _field: FieldView
var _bar: PanelContainer
var _bar_label: Label
var _review_box: HBoxContainer
var _decisions := {}  # decision kind -> count this match, for the play log
var _end_logged := false
var _shots_by_batter := {}  # CricketPlayer -> scoring shots this match, for the wagon wheel
var _wagon_toggle: CheckBox
var _batting: VBoxContainer
var _bowling: VBoxContainer
var _instructions: VBoxContainer
var _stats: VBoxContainer
var _scorecards: VBoxContainer
var _log: RichTextLabel
var _friendly_controls: HBoxContainer
var _format: OptionButton
var _pitch: OptionButton
var _speed: HSlider


func title() -> String:
	return "Match Day" if not fixture.is_empty() else "Friendly"


func subtitle() -> String:
	if engine == null:
		return ""
	var what := "%s  ·  %s" % [Season.COMPETITION, app.season.stage_text(fixture)] if not fixture.is_empty() else "Friendly  ·  %s" % engine.format.name
	return "%s v %s  ·  %s  ·  %s pitch" % [engine.teams[0].name, engine.teams[1].name, what, engine.pitch.capitalize()]


func continue_label() -> String:
	if engine.finished:
		return "Done" if not fixture.is_empty() else app.default_continue_label()
	if fixture.is_empty():
		return app.default_continue_label()
	if _break:
		return "Start Super Over" if engine.current().super_over else "Start 2nd Innings"
	return "Pause" if auto_play else "Continue"


func on_continue() -> void:
	if engine.finished and not fixture.is_empty():
		app.finish_match_day()
		return
	if fixture.is_empty() or engine.finished:
		auto_play = false
		app.advance()
		return
	auto_play = true if _break else not auto_play
	_break = false
	_timer = 0.0
	app.refresh_header()


func on_shown() -> void:
	var today: Dictionary = app.season.user_fixture_today()
	if not today.is_empty() and today.result.is_empty():
		if fixture.is_empty() or fixture.id != today.id:
			_start_fixture(today)
	elif engine == null or (not fixture.is_empty() and fixture.day != app.season.day):
		new_match()
	_friendly_controls.visible = fixture.is_empty()
	_refresh(false)


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_build()
	if "--demo" in OS.get_cmdline_user_args():
		_speed.value = _speed.max_value
		auto_play = true


func _process(delta: float) -> void:
	if engine == null or not auto_play or engine.finished:
		return
	_timer += delta
	if _timer >= _seconds_per_ball():
		_timer = 0.0
		_play("ball", true)


## A friendly between the club and its next opponent, using the format and pitch pickers.
func new_match() -> void:
	var fmt := MatchFormat.odi() if _format.selected == 1 else MatchFormat.t20()
	var pitch: String = MatchEngine.PITCHES[_pitch.selected]
	var next: Dictionary = app.season.next_user_fixture()
	var opponent: CricketTeam = app.season.opponent(next) if not next.is_empty() else app.teams[1 if app.club == app.teams[0] else 0]
	fixture = {}
	engine = MatchEngine.new(app.club, opponent, fmt, pitch)
	engine.manager_team = app.club
	_reset_log("Friendly. %s. %s pitch, %s." % [engine.toss_text, pitch.capitalize(), fmt.name])
	_friendly_controls.visible = true
	_log_match_start("friendly")
	_refresh(false)


func _start_fixture(f: Dictionary) -> void:
	fixture = f
	engine = app.season.start_match(f)
	engine.manager_team = app.club
	_reset_log("%s, %s at %s. %s. %s pitch." % [Season.COMPETITION, app.season.stage_text(f), f.home.name,
		engine.toss_text, engine.pitch.capitalize()])
	for line in app.season.last_selection_changes:
		_log.append_text("[color=#ffca28]Team change: %s[/color]\n" % line)
	_log_match_start(app.season.stage_text(f))


func _reset_log(intro: String) -> void:
	_shots_by_batter = {}
	_break = false
	_select_view("Match")
	_last_event = {}
	_log.clear()
	_log.append_text("[color=#9aa0a6]%s[/color]\n" % intro)


## mode: "ball", "over" or "end". Stops early when the manager has a review to decide.
func _play(mode: String, animate := false) -> void:
	if engine.finished or not engine.pending_review.is_empty():
		return
	_break = false
	while true:
		var e := engine.bowl_ball()
		if e.has("review_pending"):
			auto_play = false  # wait for the manager's call
			break
		_last_event = e
		_log_event(e)
		if _innings_break(e):
			break
		if engine.finished or mode == "ball" or (mode == "over" and (e.end_of_over or e.innings_complete)):
			break
	_after_play(animate or mode == "ball")


## The manager's DRS call on the pending decision.
func _resolve_review(take: bool) -> void:
	var appeal: Dictionary = engine.pending_review.result.appeal
	var e := engine.resolve_review(take)
	var review: Dictionary = e.get("review", {})
	_decision("review", {"taken": take, "call": appeal.kind, "given_out": appeal.given_out,
		"was_wrong": appeal.given_out != appeal.truly_out, "overturned": review.get("overturned", false)})
	_last_event = e
	_log_event(e)
	_innings_break(e)
	_after_play(true)


## Stops play at the end of an innings (not the match) so the manager can read the scorecard
## and set up for the chase before carrying on.
func _innings_break(e: Dictionary) -> bool:
	if not e.get("innings_complete", false) or engine.finished:
		return false
	_break = true
	auto_play = false
	return true


func _after_play(animate: bool) -> void:
	if engine.finished:
		auto_play = false
		if not fixture.is_empty() and fixture.result.is_empty():
			_news_before = app.season.news.size()
			app.season.record(fixture, engine)
			app.season.save()
		var potm := _player_of_match()
		_log.append_text("[color=#9aa0a6]Player of the match: %s (%.1f)[/color]\n" % [potm.name, _ratings()[potm]])
		_log_match_end(potm)
		_select_view("Report")
	_refresh(animate)


# --- play log ----------------------------------------------------------------

func _log_match_start(stage: String) -> void:
	_decisions = {}
	_end_logged = false
	GameLog.event("match_start", {"stage": stage, "date": app.season.date_text(), "format": engine.format.name,
		"pitch": engine.pitch, "home": engine.teams[0].name, "away": engine.teams[1].name, "toss": engine.toss_text,
		"xi": app.club.players.map(func(p): return p.name)})


func _log_match_end(potm: CricketPlayer) -> void:
	if _end_logged:
		return
	_end_logged = true
	GameLog.event("match_end", {"stage": "friendly" if fixture.is_empty() else app.season.stage_text(fixture),
		"result": engine.result_text, "scores": engine.innings.map(func(i): return "%s%s %s (%s)" % [
			"SO " if i.super_over else "", i.batting_team.short_name, i.score_text(), Innings.overs_text(i.legal_balls)]),
		"potm": potm.name, "super_overs": engine.super_overs, "decisions": _decisions,
		"position": app.season.position(app.club)})


## Logs one of the manager's in-match decisions, with the match situation.
func _decision(kind: String, details: Dictionary = {}) -> void:
	_decisions[kind] = _decisions.get(kind, 0) + 1
	var inn := engine.current()
	var event := {"kind": kind, "over": Innings.overs_text(inn.legal_balls),
		"score": "%s %s" % [inn.batting_team.short_name, inn.score_text()], "batting": inn.batting_team == app.club}
	event.merge(details)
	GameLog.event("decision", event)


## The match situation, for play-test notes written while this screen is open.
func log_context() -> Dictionary:
	if engine == null:
		return {}
	var inn := engine.current()
	return {"match": "%s v %s" % [engine.teams[0].short_name, engine.teams[1].short_name],
		"score": "%s %s (%s)" % [inn.batting_team.short_name, inn.score_text(), Innings.overs_text(inn.legal_balls)],
		"finished": engine.finished, "last_ball": _last_event.get("commentary", "")}


## Ratings for the finished match (the season's stored copy for fixtures).
func _ratings() -> Dictionary:
	if not fixture.is_empty() and not fixture.result.is_empty():
		return fixture.result.ratings
	return MatchRatings.compute(engine)


func _player_of_match() -> CricketPlayer:
	if not fixture.is_empty() and not fixture.result.is_empty():
		return fixture.result.potm
	return MatchRatings.player_of_match(engine, _ratings())


func _log_event(e: Dictionary) -> void:
	if e.get("extra", "") != "wd" and e.get("runs", 0) > 0 and e.get("distance", 0.0) > 0.0:
		var list: Array = _shots_by_batter.get_or_add(e.batter, [])
		list.append({"angle": e.angle, "distance": e.distance, "runs": e.runs})
	var colour := "#e8eaed"
	if not e.wicket.is_empty():
		colour = "#ef5350"
	elif e.runs == 4 and e.boundary:
		colour = "#42a5f5"
	elif e.runs == 6:
		colour = "#b388ff"
	_log.append_text("[color=#9aa0a6]%s[/color]  [color=%s]%s[/color]\n" % [e.over_label, colour, e.commentary])
	var inn: Innings = engine.innings[e.innings - 1]
	if e.end_of_over:
		_log.append_text("[color=#9aa0a6]— End of over %d: %s  %s —[/color]\n" % [
			inn.legal_balls / 6, " ".join(inn.this_over), inn.batting_team.short_name + " " + inn.score_text()])
	if e.innings_complete and not engine.finished:
		var next := engine.current()
		if next.super_over and next.target < 0:
			_log.append_text("\n[b][color=#ffca28]Scores level! SUPER OVER.[/color][/b] %s bat first: %s.\n\n" % [
				next.batting_team.name, ", ".join(next.lineup.map(func(p): return p.surname()))])
		elif next.super_over:
			_log.append_text("\n[b]%s need %d from the super over.[/b] %s to bat.\n\n" % [next.batting_team.name, next.target,
				", ".join(next.lineup.map(func(p): return p.surname()))])
		else:
			_log.append_text("\n[b]Innings break.[/b] %s need %d to win.\n\n" % [next.batting_team.name, next.target])
	if engine.finished:
		_log.append_text("\n[b][color=#3ecf8e]%s[/color][/b]\n" % engine.result_text)


# --- layout ------------------------------------------------------------------

func _build() -> void:
	var sub := HBoxContainer.new()
	sub.add_theme_constant_override("separation", 4)
	add_child(sub)
	var group := ButtonGroup.new()
	for v in VIEWS:
		var b := Button.new()
		b.text = v
		b.theme_type_variation = "SubNavButton"
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = v == VIEWS[0]
		b.pressed.connect(_show_view.bind(v))
		_view_buttons[v] = b
		sub.add_child(b)

	_scoreboard = HBoxContainer.new()
	_scoreboard.add_theme_constant_override("separation", 0)
	add_child(_scoreboard)

	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(stack)
	_views["Match"] = _build_match_view()
	_views["Scorecard"] = _build_scorecard_view()
	_views["Commentary"] = _build_commentary_view()
	_views["Report"] = _build_report_view()
	for v in _views.values():
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		stack.add_child(v)
	_show_view(VIEWS[0])

	add_child(_build_controls())


func _build_match_view() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 330
	left.add_theme_constant_override("separation", 12)
	h.add_child(left)
	var bat_card := UIKit.card("Batting")
	left.add_child(bat_card)
	_batting = UIKit.content(bat_card)
	var stats_card := UIKit.card("Match Stats")
	stats_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(stats_card)
	_stats = UIKit.content(stats_card)

	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.add_theme_constant_override("separation", 0)
	h.add_child(centre)
	var ground := PanelContainer.new()
	ground.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ground.add_theme_stylebox_override("panel", UIKit.flat(Color("17331f"), 4, 0, 0))
	centre.add_child(ground)
	_field = FieldView.new()
	_field.field_edited.connect(func(spots):
		engine.set_field(app.club, Fields.CUSTOM, spots)
		_decision("move_fielder")
		_refresh(false))
	ground.add_child(_field)
	_bar = PanelContainer.new()
	centre.add_child(_bar)
	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 10)
	_bar.add_child(bar_row)
	_bar_label = UIKit.label("", 16)
	_bar_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bar_label.custom_minimum_size.y = 44
	_bar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bar_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_row.add_child(_bar_label)
	_review_box = HBoxContainer.new()
	_review_box.add_theme_constant_override("separation", 6)
	var take := Button.new()
	take.text = "Review"
	take.theme_type_variation = "AccentButton"
	take.pressed.connect(_resolve_review.bind(true))
	var leave := Button.new()
	leave.text = "Accept Call"
	leave.pressed.connect(_resolve_review.bind(false))
	_review_box.add_child(take)
	_review_box.add_child(leave)
	bar_row.add_child(_review_box)

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 330
	right.add_theme_constant_override("separation", 12)
	h.add_child(right)
	var instructions_card := UIKit.card("Instructions")
	right.add_child(instructions_card)
	_instructions = UIKit.content(instructions_card)
	var bowl_card := UIKit.card("Bowling")
	bowl_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(bowl_card)
	_bowling = UIKit.content(bowl_card)
	return h


func _build_scorecard_view() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scorecards = VBoxContainer.new()
	_scorecards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scorecards.add_theme_constant_override("separation", 14)
	scroll.add_child(_scorecards)
	return scroll


func _build_report_view() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_report = VBoxContainer.new()
	_report.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_report.add_theme_constant_override("separation", 14)
	scroll.add_child(_report)
	return scroll


func _build_commentary_view() -> Control:
	var c := UIKit.card("Commentary")
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UIKit.content(c).add_child(_log)
	return c


func _build_controls() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UIKit.flat(UIKit.PANEL, 4, 12, 8))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	bar.add_child(h)

	_friendly_controls = HBoxContainer.new()
	_friendly_controls.add_theme_constant_override("separation", 10)
	h.add_child(_friendly_controls)
	_friendly_controls.add_child(UIKit.label("Friendly", 13, UIKit.TEXT_DIM))
	_format = OptionButton.new()
	for f in FORMATS:
		_format.add_item(f)
	_friendly_controls.add_child(_format)
	_pitch = OptionButton.new()
	for p in MatchEngine.PITCHES:
		_pitch.add_item(p.capitalize())
	_friendly_controls.add_child(_pitch)
	_friendly_controls.add_child(_button("New Friendly", new_match))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)

	h.add_child(_button("Next Ball", _play.bind("ball", true)))
	h.add_child(_button("Next Over", _play.bind("over", false)))
	h.add_child(_button("Sim to End", _play.bind("end", false)))
	_wagon_toggle = CheckBox.new()
	_wagon_toggle.text = "Wagon wheel"
	_wagon_toggle.tooltip_text = "Show where the striker has scored this match"
	_wagon_toggle.toggled.connect(func(_on): _refresh(false))
	h.add_child(_wagon_toggle)
	h.add_child(UIKit.label("Speed", 13, UIKit.TEXT_DIM))
	_speed = HSlider.new()
	_speed.min_value = 1
	_speed.max_value = 10
	_speed.step = 1
	_speed.value = 4
	_speed.tick_count = 10
	_speed.ticks_on_borders = true
	_speed.custom_minimum_size = Vector2(140, 0)
	_speed.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_speed.tooltip_text = "Match speed: further right is faster"
	h.add_child(_speed)
	return bar


## Feeds the striker's wagon wheel to the field view when the toggle is on: their scoring
## shots this match and a summary of where the runs went.
func _update_wagon() -> void:
	_field.wagon = []
	_field.wagon_caption = ""
	if not _wagon_toggle.button_pressed or engine.finished:
		return
	var striker: CricketPlayer = engine.current().striker.player
	var shots: Array = _shots_by_batter.get(striker, [])
	_field.wagon = shots
	var off := 0
	var total := 0
	var regions := {}
	for shot in shots:
		total += shot.runs
		if shot.angle > 0.0:
			off += shot.runs
		var region := DeliveryModel.region_name(shot.angle, false)
		regions[region] = regions.get(region, 0) + shot.runs
	if total == 0:
		_field.wagon_caption = "%s: no runs yet" % striker.surname()
		return
	var best: String = regions.keys().reduce(func(a, b): return a if regions[a] >= regions[b] else b)
	_field.wagon_caption = "%s: %d runs  ·  off side %d%%, leg side %d%%  ·  most %s (%d)" % [
		striker.surname(), total, roundi(100.0 * off / total), 100 - roundi(100.0 * off / total), best, regions[best]]


## Speed 1 (slowest, 1.5 s a ball) to 10 (fastest, 0.03 s a ball), evenly spaced in feel.
func _seconds_per_ball() -> float:
	return 1.5 * pow(0.02, (_speed.value - 1.0) / 9.0)


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	return b


func _show_view(view: String) -> void:
	for key in _views:
		_views[key].visible = key == view
	if view == "Scorecard":
		_refresh_scorecards()
	elif view == "Report":
		_refresh_report()


func _select_view(view: String) -> void:
	_view_buttons[view].button_pressed = true
	_show_view(view)


# --- refresh -----------------------------------------------------------------

func _refresh(animate: bool) -> void:
	_refresh_scoreboard()
	_refresh_batting()
	_refresh_instructions()
	_refresh_bowling()
	_refresh_stats()
	_refresh_bar()
	_update_wagon()
	_field.editable = engine.manager_team == app.club and engine.current().bowling_team == app.club \
		and not engine.finished
	# While a review waits, show the appealed ball, not the one before it.
	var shown := _last_event
	if not engine.pending_review.is_empty():
		shown = engine.pending_review.result.duplicate()
		shown.merge(engine.pending_review.meta)
	_field.show_state(engine, shown, animate)
	if _views["Scorecard"].visible:
		_refresh_scorecards()
	if _views["Report"].visible:
		_refresh_report()
	app.refresh_header()


func _refresh_scoreboard() -> void:
	UIKit.clear(_scoreboard)
	var main := engine.main_innings()
	var first: Innings = main[0]
	var second: Innings = main[1] if main.size() > 1 else null
	_scoreboard.add_child(_score_block(first.batting_team, first, true))

	var centre := PanelContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.add_theme_stylebox_override("panel", UIKit.flat(UIKit.PANEL, 0, 16, 8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	centre.add_child(v)
	var status := UIKit.label(_status_text(), 16)
	var detail := UIKit.label(_detail_text(), 12, UIKit.TEXT_DIM)
	for l in [status, detail]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	_scoreboard.add_child(centre)

	_scoreboard.add_child(_score_block(first.bowling_team, second, false))


func _score_block(team: CricketTeam, inn: Innings, left: bool) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size.x = 380
	var style := UIKit.flat(team.colour.darkened(0.35), 0, 16, 8)
	if left:
		style.border_width_left = 6
	else:
		style.border_width_right = 6
	style.border_color = team.colour
	p.add_theme_stylebox_override("panel", style)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	p.add_child(h)
	var team_label := UIKit.label(team.name, 17, Color.WHITE)
	team_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	team_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var score := UIKit.label(inn.score_text() if inn else "Yet to bat", 28 if inn else 14, Color.WHITE)
	score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var overs := UIKit.label("(%s ov)" % Innings.overs_text(inn.legal_balls) if inn else "", 13, Color(1, 1, 1, 0.7))
	overs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var parts: Array = [team_label, score, overs] if left else [overs, score, team_label]
	if not left:
		team_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for part in parts:
		h.add_child(part)
	return p


func _status_text() -> String:
	if engine.finished:
		return engine.result_text
	var inn := engine.current()
	if inn.super_over:
		var so := "SUPER OVER: %s %s" % [inn.batting_team.short_name, inn.score_text()]
		return so + ("  ·  need %d from %d" % [inn.runs_needed(), inn.balls_left()] if inn.target > 0 else "")
	if inn.target > 0:
		var balls := inn.balls_left(engine.format)
		return "Need %d from %d balls  ·  RRR %.2f" % [inn.runs_needed(), balls, inn.runs_needed() * 6.0 / maxi(balls, 1)]
	var projected := inn.runs + roundi(inn.run_rate() * inn.balls_left(engine.format) / 6.0)
	return "CRR %.2f  ·  Projected %d" % [inn.run_rate(), projected]


func _detail_text() -> String:
	if engine.finished:
		return engine.toss_text
	var inn := engine.current()
	var stage := "Super over" if inn.super_over else ("1st innings" if inn.number == 1 else "2nd innings")
	var drs := "DRS %s %d, %s %d" % [inn.batting_team.short_name, inn.reviews[inn.batting_team],
		inn.bowling_team.short_name, inn.reviews[inn.bowling_team]]
	var text := "%s  ·  %s  ·  %s  ·  %s" % [stage, inn.phase(engine.format).capitalize(), engine.format.name, drs]
	return text + ("  ·  FREE HIT" if inn.free_hit else "")


func _refresh_batting() -> void:
	UIKit.clear(_batting)
	var inn := engine.current()
	var rows := []
	for entry in [inn.striker, inn.non_striker]:
		var star := " *" if is_same(entry, inn.striker) else ""
		rows.append(_batting_row(entry, entry.player.surname() + star))
	_batting.add_child(UIKit.table(_batting_columns(false), rows))
	var part := inn.partnership()
	_batting.add_child(UIKit.stat_row("Partnership", "%d (%d)" % [part.runs, part.balls]))
	if not inn.fall_of_wickets.is_empty():
		var last: Dictionary = inn.fall_of_wickets[-1]
		var out: Dictionary = inn.batters.filter(func(b): return b.player == last.player)[0]
		_batting.add_child(UIKit.stat_row("Last wicket", "%s %d (%d)" % [out.player.surname(), out.runs, out.balls]))
	for entry in [inn.striker, inn.non_striker]:
		var p: CricketPlayer = entry.player
		var s: Dictionary = engine.states[p]
		var intent := engine.batting_intent(inn, entry)
		var role := Tactics.bat_role(inn.batting_team, p)
		_batting.add_child(UIKit.label("%s  ·  %s  ·  %s" % [p.name.to_upper(), "LHB" if p.left_handed else "RHB",
			role.to_upper()], 11, UIKit.TEXT_DIM))
		_add_condition_meters(_batting, s)
		_batting.add_child(UIKit.meter("Intent", (intent + 1.0) / 2.0, UIKit.intent_colour(intent), UIKit.intent_text(intent)))


func _add_condition_meters(parent: Control, s: Dictionary) -> void:
	parent.add_child(UIKit.meter("Condition", s.condition / 100.0, UIKit.condition_colour(s.condition), "%d%%" % roundi(s.condition)))
	parent.add_child(UIKit.meter("Confidence", s.confidence / 100.0, UIKit.confidence_colour(s.confidence), UIKit.confidence_text(s.confidence)))


## FM-style touchline instructions for the manager's club: batting approach while batting,
## bowling approach while in the field.
func _refresh_instructions() -> void:
	UIKit.clear(_instructions)
	if engine.finished:
		_instructions.add_child(UIKit.label("Match over", 13, UIKit.TEXT_DIM))
		return
	var club: CricketTeam = app.club
	var inn := engine.current()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	if inn.batting_team == club:
		_instructions.add_child(UIKit.label("BATTING APPROACH", 11, UIKit.TEXT_DIM))
		for i in MatchEngine.BAT_APPROACHES.size():
			row.add_child(_approach_button(MatchEngine.BAT_APPROACHES[i], engine.bat_approach[club] == i,
				func(): engine.bat_approach[club] = i))
		_instructions.add_child(row)
		var waiting := inn.yet_to_bat()
		if not waiting.is_empty():
			_instructions.add_child(_labelled_picker("NEXT IN",
				waiting.map(func(p): return "%s  (%s, %s)" % [p.name, "LHB" if p.left_handed else "RHB",
					Tactics.bat_role(inn.batting_team, p)]), 0,
				func(i):
					inn.promote(waiting[i])
					_decision("next_batter", {"player": waiting[i].name})
					_refresh(false)))
	else:
		_instructions.add_child(UIKit.label("BOWLING APPROACH", 11, UIKit.TEXT_DIM))
		row.add_child(_approach_button("Auto", engine.bowl_approach[club] == MatchEngine.BOWL_AUTO,
			func(): engine.bowl_approach[club] = MatchEngine.BOWL_AUTO))
		for i in MatchEngine.BOWL_APPROACHES.size():
			row.add_child(_approach_button(MatchEngine.BOWL_APPROACHES[i], engine.bowl_approach[club] == i,
				func(): engine.bowl_approach[club] = i))
		_instructions.add_child(row)

		var bowlers := engine.eligible_bowlers(inn)
		var chosen: CricketPlayer = engine.next_bowler.get(club)
		var labels := ["Captain's choice"]
		for p: CricketPlayer in bowlers:
			var used := inn.overs_bowled_by(p)
			labels.append("%s  (%d ov left, %d%%)" % [p.name, engine.format.max_bowler_overs - used if not inn.super_over else 1,
				roundi(engine.states[p].condition)])
		_instructions.add_child(_labelled_picker("NEXT OVER" if inn.bowler.is_empty() else "NEXT OVER (after this one)",
			labels, bowlers.find(chosen) + 1,
			func(i):
				engine.set_next_bowler(club, null if i == 0 else bowlers[i - 1])
				_decision("next_bowler", {"player": "captain" if i == 0 else bowlers[i - 1].name})
				_refresh(false)))

		var fields := [Fields.AUTO] + Fields.PRESETS.keys()
		var current: String = engine.field_choice.get(club, Fields.AUTO)
		if current == Fields.CUSTOM:
			fields.append(Fields.CUSTOM)
		# Show which field the captain is using, since it changes with the phase and approach.
		var field_labels := fields.map(func(f): return "%s (%s)" % [f, engine.field_name(inn)] if f == Fields.AUTO else f)
		_instructions.add_child(_labelled_picker("FIELD", field_labels, fields.find(current),
			func(i):
				engine.set_field(club, fields[i])
				_decision("field", {"field": fields[i]})
				_refresh(false)))
		var spots := engine.current_field(inn)
		var phase := inn.phase(engine.format)
		var help: String = Fields.PRESET_HELP.get(engine.field_name(inn), "Your own field.")
		_instructions.add_child(_hint("%s  %d of %d allowed outside the circle. Click fielders on the pitch to move them." % [
			help, Fields.outside_count(spots), Fields.max_outside(phase)]))


func _labelled_picker(title: String, items: Array, selected: int, on_pick: Callable) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := UIKit.label(title, 11, UIKit.TEXT_DIM)
	l.custom_minimum_size.x = 92
	h.add_child(l)
	var o := OptionButton.new()
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.clip_text = true
	o.add_theme_font_size_override("font_size", 12)
	for item in items:
		o.add_item(item)
	o.selected = selected
	o.item_selected.connect(on_pick)
	h.add_child(o)
	return h


func _approach_button(text: String, active: bool, apply: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = active
	b.add_theme_font_size_override("font_size", 12)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func():
		apply.call()
		_decision("approach", {"setting": text})
		_refresh(false))
	return b


func _hint(text: String) -> Label:
	var l := UIKit.label(text, 12, UIKit.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _refresh_bowling() -> void:
	UIKit.clear(_bowling)
	var inn := engine.current()
	var current: Dictionary = inn.bowler
	if current.is_empty() and inn.last_over_bowler:
		current = inn.bowlers.filter(func(b): return b.player == inn.last_over_bowler)[0]
	if current.is_empty():
		_bowling.add_child(UIKit.label("Waiting for the first ball", 13, UIKit.TEXT_DIM))
		return
	var p: CricketPlayer = current.player
	_bowling.add_child(UIKit.label(p.name, 18))
	var plan := Tactics.bowl_role(inn.bowling_team, p)
	_bowling.add_child(UIKit.label(p.style_name() + ("" if plan == Tactics.BOWL_DEFAULT else "  ·  " + plan), 12, UIKit.TEXT_DIM))
	_add_condition_meters(_bowling, engine.states[p])
	_bowling.add_child(UIKit.table(_bowling_columns(), [_bowling_row(current)]))

	_bowling.add_child(UIKit.label("THIS OVER", 11, UIKit.TEXT_DIM))
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 4)
	for symbol in inn.this_over:
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UIKit.flat(UIKit.symbol_colour(symbol).darkened(0.55), 12, 9, 3))
		chip.add_child(UIKit.label(symbol, 13, UIKit.symbol_colour(symbol).lightened(0.2)))
		chips.add_child(chip)
	_bowling.add_child(chips)

	_bowling.add_child(UIKit.label("ALL BOWLERS", 11, UIKit.TEXT_DIM))
	var rows := []
	for b in inn.bowlers:
		rows.append(_bowling_row(b))
	_bowling.add_child(UIKit.table(_bowling_columns(), rows))


func _refresh_stats() -> void:
	UIKit.clear(_stats)
	var inn := engine.current()
	_stats.add_child(UIKit.meter("Pressure", inn.pressure / 100.0,
		UIKit.POSITIVE.lerp(UIKit.NEGATIVE, inn.pressure / 70.0), UIKit.pressure_text(inn.pressure)))
	_stats.add_child(UIKit.stat_row("Run rate", "%.2f" % inn.run_rate()))
	_stats.add_child(UIKit.stat_row("Fours / Sixes", "%d / %d" % [inn.fours, inn.sixes]))
	_stats.add_child(UIKit.stat_row("Dot balls", "%d%%" % roundi(100.0 * inn.dots / maxi(inn.legal_balls, 1))))
	_stats.add_child(UIKit.stat_row("Extras", "%d (wd %d, nb %d)" % [inn.extras(), inn.wides, inn.no_balls]))
	_stats.add_child(UIKit.stat_row("Pitch", engine.pitch.capitalize()))
	var toss := UIKit.label(engine.toss_text, 12, UIKit.TEXT_DIM)
	toss.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats.add_child(toss)


func _refresh_bar() -> void:
	var accent := UIKit.LINE
	var text := "%s. Press Continue to start the match." % engine.toss_text
	if not _last_event.is_empty():
		text = "%s  %s" % [_last_event.over_label, _last_event.commentary]
		accent = UIKit.symbol_colour(_last_event.get("symbol", ""))
	if _break:
		var done: Innings = engine.innings[-2]
		var next := engine.current()
		var chase := "Super over: %s bat first" % next.batting_team.name
		if next.target > 0:
			chase = "%s need %d from %s" % [next.batting_team.name, next.target,
				"the super over" if next.super_over else "%d overs" % (next.max_balls / 6)]
		text = "Innings break.  %s %s (%s ov).  %s.  Set your approach, then press Continue." % [
			done.batting_team.short_name, done.score_text(), Innings.overs_text(done.legal_balls), chase]
		accent = UIKit.WARNING
	if engine.finished:
		var potm := _player_of_match()
		text = "%s.  Player of the match: %s (%.1f)" % [engine.result_text, potm.name, _ratings()[potm]]
		accent = UIKit.POSITIVE
	var pending := engine.pending_review
	_review_box.visible = not pending.is_empty()
	if not pending.is_empty():
		var appeal: Dictionary = pending.result.appeal
		var meta: Dictionary = pending.meta
		var inn := engine.current()
		if appeal.given_out:
			text = "%s  %s to %s: the umpire gives %s OUT, %s. Review? (%d left)" % [meta.over_label, meta.bowler.surname(),
				meta.batter.surname(), meta.batter.surname(), appeal.kind, inn.reviews[pending.team]]
		else:
			text = "%s  %s to %s: big shout for %s, given NOT OUT. Review? (%d left)" % [meta.over_label, meta.bowler.surname(),
				meta.batter.surname(), appeal.kind, inn.reviews[pending.team]]
		accent = UIKit.WARNING
	var style := UIKit.flat(UIKit.PANEL_HEADER, 0, 14, 8)
	style.border_width_left = 6
	style.border_color = accent
	_bar.add_theme_stylebox_override("panel", style)
	_bar_label.text = text


func _refresh_scorecards() -> void:
	UIKit.clear(_scorecards)
	for inn: Innings in engine.innings:
		var c := UIKit.card("%s%s  —  %s (%s ov)" % ["Super over: " if inn.super_over else "", inn.batting_team.name,
			inn.score_text(), Innings.overs_text(inn.legal_balls)])
		var body := UIKit.content(c)
		var rows := []
		for entry in inn.batters:
			rows.append(_batting_row(entry, entry.player.name, entry.how_out))
		body.add_child(UIKit.table(_batting_columns(true), rows))
		body.add_child(UIKit.stat_row("Extras", "%d (wd %d, nb %d)" % [inn.extras(), inn.wides, inn.no_balls]))
		body.add_child(UIKit.stat_row("Total", "%s (%s overs, RR %.2f)" % [inn.score_text(), Innings.overs_text(inn.legal_balls), inn.run_rate()]))
		var yet := inn.yet_to_bat().map(func(p): return p.name)
		if not yet.is_empty():
			body.add_child(UIKit.stat_row("Yet to bat", ", ".join(yet)))
		if not inn.fall_of_wickets.is_empty():
			var fow := inn.fall_of_wickets.map(func(f): return "%d-%d (%s, %s)" % [f.runs, f.wicket, f.player.surname(), Innings.overs_text(f.balls)])
			var l := UIKit.label("Fall of wickets: " + ", ".join(fow), 12, UIKit.TEXT_DIM)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.add_child(l)
		var bowl_rows := []
		for b in inn.bowlers:
			bowl_rows.append(_bowling_row(b))
		body.add_child(UIKit.table(_bowling_columns(), bowl_rows))
		_scorecards.add_child(c)
	if engine.finished:
		_scorecards.add_child(_ratings_card())


## The post-match report: the result, who decided it, ratings and, for fixtures, what it
## means for the season and the squad, so there's a pause before the next match.
func _refresh_report() -> void:
	UIKit.clear(_report)
	if engine == null or not engine.finished:
		_report.add_child(UIKit.label("The match report appears here when the match is over.", 14, UIKit.TEXT_DIM))
		return
	var ratings := _ratings()
	var potm := _player_of_match()
	var result := UIKit.card("Result")
	var body := UIKit.content(result)
	body.add_child(UIKit.label(engine.result_text, 22, UIKit.POSITIVE))
	for inn: Innings in engine.innings:
		body.add_child(UIKit.stat_row(("Super over: " if inn.super_over else "") + inn.batting_team.name,
			"%s (%s ov)" % [inn.score_text(), Innings.overs_text(inn.legal_balls)]))
	body.add_child(UIKit.stat_row("Player of the match", "%s  %.1f" % [potm.name, ratings[potm]], UIKit.WARNING))
	body.add_child(UIKit.wrapped(engine.toss_text))
	_report.add_child(result)

	var performers := UIKit.card("Key Performances")
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	UIKit.content(performers).add_child(h)
	for inn: Innings in engine.main_innings():
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(UIKit.label("%s BATTING" % inn.batting_team.short_name, 11, UIKit.TEXT_DIM))
		var batters := inn.batters.duplicate()
		batters.sort_custom(func(a, b): return a.runs > b.runs)
		for b in batters.slice(0, 3):
			col.add_child(UIKit.stat_row(b.player.name, "%d%s (%d)" % [b.runs, "" if b.out else "*", b.balls]))
		col.add_child(UIKit.label("%s BOWLING" % inn.bowling_team.short_name, 11, UIKit.TEXT_DIM))
		var bowlers := inn.bowlers.duplicate()
		bowlers.sort_custom(func(a, b): return a.wickets > b.wickets if a.wickets != b.wickets else a.runs < b.runs)
		for b in bowlers.slice(0, 3):
			col.add_child(UIKit.stat_row(b.player.name, "%d-%d (%s)" % [b.wickets, b.runs, Innings.overs_text(b.balls)]))
		h.add_child(col)
	_report.add_child(performers)
	_report.add_child(_ratings_card())
	if fixture.is_empty():
		return

	var season: Season = app.season
	var outlook := UIKit.card("Season")
	var ob := UIKit.content(outlook)
	ob.add_child(UIKit.stat_row("League position", UIKit.ordinal(season.position(app.club))))
	var next: Dictionary = season.next_user_fixture()
	ob.add_child(UIKit.stat_row("Next match", "None" if next.is_empty() else "%s v %s, %s" % [
		season.stage_text(next), season.opponent(next).name, season.date_text(next.day)]))
	for n in season.news.slice(_news_before):
		ob.add_child(UIKit.wrapped("%s. %s" % [n.title, n.body], 13, UIKit.TEXT))
	ob.add_child(UIKit.wrapped("Press Done to go back to Home. Training runs on the days before the next match."))
	_report.add_child(outlook)

	var fitness := UIKit.card("Squad After the Match")
	var rows := []
	for p: CricketPlayer in app.club.players:
		var c: float = season.condition[p]
		rows.append([p.name, {"text": "%d%%" % roundi(c), "colour": UIKit.condition_colour(c)},
			UIKit.form_rating(season.form[p]),
			{"text": "Injured, %d days" % season.injury_days(p) if season.is_injured(p) else "", "colour": UIKit.NEGATIVE}])
	UIKit.content(fitness).add_child(UIKit.table([{"title": "Player", "width": 0},
		{"title": "Condition", "width": 90, "align": "right"}, {"title": "Form", "width": 60, "align": "right"},
		{"title": "", "width": 140, "align": "right"}], rows))
	_report.add_child(fitness)


## FM-style player ratings for both sides, best first.
func _ratings_card() -> Control:
	var ratings := _ratings()
	var potm := _player_of_match()
	var c := UIKit.card("Player Ratings")
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	UIKit.content(c).add_child(h)
	for team: CricketTeam in engine.teams:
		var players := team.players.duplicate()
		players.sort_custom(func(a, b): return ratings[a] > ratings[b])
		var rows := []
		for p: CricketPlayer in players:
			var r: float = ratings[p]
			var colour := UIKit.POSITIVE if r >= 7.5 else (UIKit.NEGATIVE if r < 6.0 else UIKit.TEXT)
			rows.append([p.name + ("  ★" if p == potm else ""), {"text": "%.1f" % r, "colour": colour}])
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(UIKit.label(team.name.to_upper(), 11, UIKit.TEXT_DIM))
		col.add_child(UIKit.table([{"title": "Player", "width": 0}, {"title": "Rating", "width": 60, "align": "right"}], rows))
		h.add_child(col)
	return c


# --- table helpers -------------------------------------------------------------

func _batting_columns(with_dismissal: bool) -> Array:
	var cols := [{"title": "Batter", "width": 0}]
	if with_dismissal:
		cols.append({"title": "", "width": 260})
	for t in ["R", "B", "4s", "6s"]:
		cols.append({"title": t, "width": 34, "align": "right"})
	cols.append({"title": "SR", "width": 52, "align": "right"})
	return cols


func _batting_row(entry: Dictionary, shown_name: String, how_out := "") -> Array:
	var row: Array = [shown_name]
	if how_out != "":
		row.append({"text": how_out, "colour": UIKit.TEXT_DIM, "size": 13})
	var runs_colour := UIKit.WARNING if entry.runs >= 50 else UIKit.TEXT
	row.append_array([{"text": str(entry.runs), "colour": runs_colour}, entry.balls, entry.fours, entry.sixes,
		"%.1f" % (100.0 * entry.runs / maxi(entry.balls, 1))])
	return row


func _bowling_columns() -> Array:
	var cols := [{"title": "Bowler", "width": 0}]
	for t in ["O", "M", "R", "W"]:
		cols.append({"title": t, "width": 26, "align": "right"})
	cols.append({"title": "Econ", "width": 42, "align": "right"})
	cols.append({"title": "Fit", "width": 38, "align": "right"})
	return cols


func _bowling_row(b: Dictionary) -> Array:
	var p: CricketPlayer = b.player
	var condition: float = engine.states[p].condition
	return [p.surname(), Innings.overs_text(b.balls), b.maidens, b.runs,
		{"text": str(b.wickets), "colour": UIKit.POSITIVE if b.wickets >= 3 else UIKit.TEXT},
		"%.2f" % (b.runs * 6.0 / maxi(b.balls, 1)),
		{"text": "%d%%" % roundi(condition), "colour": UIKit.condition_colour(condition)}]
