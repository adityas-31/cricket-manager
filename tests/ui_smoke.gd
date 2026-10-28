extends SceneTree
## Opens the app on a throwaway career, edits tactics, plays the club's first few fixtures
## through Match Day with Continue, plays a friendly, and opens every screen and tab, so UI
## code paths that need clicks get exercised.
##
## Run: godot --headless --path . --script res://tests/ui_smoke.gd

const SAVE := "user://smoke_career.json"

var _frames := 0
var _app: Node


func _initialize() -> void:
	Season.save_path = SAVE
	GameLog.dir = LOG_DIR
	_clear_logs()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	_app = load("res://scenes/app.tscn").instantiate()
	root.add_child(_app)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	if _frames > 3:
		print("UI SMOKE FAILED (see errors above)")
		return true  # an error aborted the previous pass; don't loop forever
	var season: Season = _app.season
	var club: CricketTeam = _app.club

	# Selection: drop a player, pick a reserve, then let the assistant auto-select.
	_app.show_screen("tactics")
	var tactics: Node = _app._screens["tactics"]
	var dropped: CricketPlayer = club.players[2]
	club.players.erase(dropped)
	tactics.on_shown()
	assert(Selection.issues(club, season).any(func(l): return l.contains("10 players")), "short XI flagged")
	var reserve: CricketPlayer = club.reserves().filter(func(p): return p != dropped)[0]
	club.players.append(reserve)
	tactics.on_shown()
	assert(club.players.size() == 11 and reserve in club.players, "reserve picked")
	var auto: Array = tactics._check.find_children("*", "Button", true, false).filter(func(b): return b.text == "Auto Select")
	auto[0].pressed.emit()
	assert(club.players.size() == 11, "Auto Select picked an XI")
	tactics._show_view("Roles & Plan")
	tactics._show_view("Selection")
	print("selection ok: %d in XI, %d reserves" % [club.players.size(), club.reserves().size()])

	# Injury cover: injure a picked player and check the XI is fixed at kick-off.
	var hurt: CricketPlayer = club.players[0]
	season.injuries[hurt] = season.day + 5
	assert(Selection.issues(club, season).any(func(l): return l.contains("injured")), "injury flagged")

	# Tactics: promote a batter, give him a role, suggest a plan.
	var seventh: CricketPlayer = club.players[6]
	tactics._move(6, -1)
	tactics._move(5, -1)
	assert(club.players[4] == seventh, "batting order move failed")
	club.bat_roles[seventh] = "Pinch Hitter"
	Tactics.suggest_bowling(club)
	tactics._build_plan()
	print("tactics ok: %s bats 5th as %s" % [seventh.surname(), Tactics.bat_role(club, seventh)])

	# Play three rounds the way a player would: Continue to Match Day, play, Continue on.
	for round in 3:
		_app._on_continue()
		var match_screen: Node = _app._screens["match"]
		assert(_app._current == match_screen, "Continue should open Match Day on a match day")
		assert(not match_screen.fixture.is_empty(), "Match Day should load today's fixture")
		assert(not club.players.any(func(p): return season.is_injured(p)), "injured player kept in the XI")
		if round == 0:
			assert(not season.last_selection_changes.is_empty(), "injury cover reported")
			print("cover: %s" % season.last_selection_changes[0])
		var buttons: Array = match_screen._instructions.find_children("*", "Button", true, false).filter(
			func(b): return not b is OptionButton)
		buttons[-1].pressed.emit()
		match_screen._play("over")
		if round == 0:
			_use_match_controls(match_screen, club)
		_finish(match_screen)
		assert(not match_screen.fixture.result.is_empty(), "result recorded into the season")
		for view in match_screen.VIEWS:
			match_screen._show_view(view)
		print("%s: %s" % [season.date_text(), match_screen.fixture.result.text])
		_app._on_continue()
	assert(season.fixtures.filter(func(f): return not f.result.is_empty()).size() == 12, "3 rounds of 4 fixtures played")

	# A friendly doesn't touch the season.
	var match_screen: Node = _app._screens["match"]
	_app.show_screen("match")
	match_screen._format.selected = 1
	match_screen.new_match()
	_finish(match_screen)
	print("friendly: %s" % match_screen.engine.result_text)
	assert(season.fixtures.filter(func(f): return not f.result.is_empty()).size() == 12, "friendly changed the season")

	for id in ["home", "inbox", "squad", "fixtures", "competition", "finances"]:
		_app.show_screen(id)

	# Transfers: bid low, then at the asking price, sign; list a player and take a bid.
	_app.show_screen("transfers")
	var market: Node = _app._screens["transfers"]
	var target: CricketPlayer = market._search_results(season)[-1]
	market._target = target
	market._bid(1000)
	assert(market._deal.response.result == "reject", "lowball bid should be rejected")
	market._bid(Transfers.asking_price(target, season))
	assert(market._deal.response.result == "accept", "asking price should be accepted")
	market.on_shown()
	var sign_buttons: Array = market._body.find_children("*", "Button", true, false).filter(func(b): return b.text.begins_with("Sign for"))
	assert(not sign_buttons.is_empty(), "sign button shown")
	sign_buttons[0].pressed.emit()
	assert(target in club.squad, "signing completed")
	print("signed %s; balance now %s" % [target.name, Transfers.money(season.balance[club])])
	for view in market.VIEWS:
		market._view = view
		market.on_shown()
	var listed: CricketPlayer = club.reserves()[0]
	season.listed[listed] = true
	var buyer: CricketTeam = season.teams.filter(func(t): return t != club)[0]
	season.offers.append({"player": listed, "from": buyer, "fee": 50000, "day": season.day, "status": "pending"})
	market._view = "Bids for Us"
	market.on_shown()
	# AI clubs may have made bids of their own: press Accept on this player's row.
	var accept: Array = market._body.find_children("*", "Button", true, false).filter(
		func(b): return b.text == "Accept" and b.get_parent().get_child(0).text == listed.name)
	accept[0].pressed.emit()
	assert(listed in buyer.squad, "bid accepted from the screen")
	print("sold %s to %s" % [listed.name, buyer.short_name])
	for view in ["All Fixtures", "Our Fixtures"]:
		_app._screens["fixtures"]._view = view
		_app._screens["fixtures"].on_shown()
	_app._screens["competition"]._view = "Stats"
	_app._screens["competition"].on_shown()
	_app._screens["squad"]._select(4)
	print("screens ok; %s are %s on %d pts; %d news items" % [club.name,
		UIKit.ordinal(season.position(club)), season.table().filter(func(r): return r.team == club)[0].pts, season.news.size()])

	# Fast-forward to the end of the season, then Continue into the next one.
	while not season.is_over():
		if season.user_match_pending():
			var f := season.user_fixture_today()
			var e := season.start_match(f)
			while not e.finished:
				e.bowl_ball()
			season.record(f, e)
		season.advance()
	_app.show_screen("home")
	assert(_app.default_continue_label() == "Next Season", "Continue offers the next season")
	var old_year := season.year
	_app._on_continue()
	assert(season.year == old_year + 1 and _app._current == _app._screens["home"], "Continue started the next season")
	_app.show_screen("competition")
	_app._screens["competition"]._view = "History"
	_app._screens["competition"].on_shown()
	if not season.free_agents.is_empty():
		_app.show_screen("transfers")
		market._view = "Search"
		market._target = season.free_agents[0]
		market._deal = {}
		market.on_shown()
		market._bid(0)
		assert(market._deal.response.result == "accept", "free agents need no fee")
	print("new season ok: %d, history %d, free agents %d" % [season.year, season.history.size(), season.free_agents.size()])

	var reloaded := Season.load_from(SAVE)
	assert(reloaded and reloaded.day == season.day, "autosave matches the live season")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	_check_log()
	print("UI SMOKE PASSED (%d review prompts answered)" % _reviews_answered)
	return true


var _reviews_answered := 0
const LOG_DIR := "user://smoke_logs"


## The play log should hold the session and everything the run did, plus a written note.
func _check_log() -> void:
	_app._note_text.text = "smoke test note"
	_app._save_note()
	var counts := {}
	for line in FileAccess.get_file_as_string(GameLog.path).split("\n", false):
		var e = JSON.parse_string(line)
		assert(typeof(e) == TYPE_DICTIONARY and e.has("type") and e.has("t"), "log line is JSON with a type")
		counts[e.type] = counts.get(e.type, 0) + 1
	for kind in ["session_start", "screen", "advance", "match_start", "match_end", "decision", "result", "transfer", "selection", "note"]:
		assert(counts.get(kind, 0) > 0, "log has %s events" % kind)
	print("log ok: %s" % JSON.stringify(counts))
	GameLog.stop()
	_clear_logs()


func _clear_logs() -> void:
	if not DirAccess.dir_exists_absolute(LOG_DIR):
		return
	var real := ProjectSettings.globalize_path(LOG_DIR)
	for f in DirAccess.get_files_at(LOG_DIR):
		DirAccess.remove_absolute(real.path_join(f))
	DirAccess.remove_absolute(real)


## Plays the match on screen to the end, answering review prompts (review every other one).
func _finish(match_screen: Node) -> void:
	var guard := 0
	while not match_screen.engine.finished and guard < 50:
		guard += 1
		match_screen._play("end")
		if not match_screen.engine.pending_review.is_empty():
			assert(match_screen._review_box.visible, "review prompt shown")
			match_screen._resolve_review(_reviews_answered % 2 == 0)
			_reviews_answered += 1
	assert(match_screen.engine.finished, "match finished")


## Uses every in-match control on the match in progress: field preset, a moved fielder,
## the next bowler, and who bats next.
func _use_match_controls(match_screen: Node, club: CricketTeam) -> void:
	var engine: MatchEngine = match_screen.engine
	var inn := engine.current()
	if inn.bowling_team == club:
		engine.set_field(club, "Defensive")
		var spots: Array = engine.current_field(inn)
		spots[0] = [30.0, 40.0]
		match_screen._field.field_edited.emit(spots)
		assert(engine.field_name(inn) == Fields.CUSTOM, "fielder moved")
		var choice: CricketPlayer = engine.eligible_bowlers(inn)[-1]
		engine.set_next_bowler(club, choice)
		var over := inn.legal_balls / 6
		var guard := 0
		while engine.current() == inn and (inn.legal_balls / 6 == over or inn.bowler.is_empty()) and guard < 40:
			guard += 1
			match_screen._play("ball")
			if not engine.pending_review.is_empty():
				match_screen._resolve_review(false)
		if engine.current() == inn and not inn.bowler.is_empty():
			assert(inn.bowler.player == choice, "chosen bowler bowled the next over")
			print("controls: field set, %s bowling the over they were picked for" % choice.surname())
	else:
		var waiting := inn.yet_to_bat()
		if waiting.size() > 1:
			inn.promote(waiting[-1])
			assert(inn.yet_to_bat()[0] == waiting[-1], "promoted batter is next in")
			print("controls: %s promoted to bat next" % waiting[-1].surname())
	match_screen._refresh(false)
