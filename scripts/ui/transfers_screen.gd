extends VBoxContainer
## Transfers, FM-style. Search: every player at other clubs, and a negotiation panel (bid,
## the club's answer, then the player's wage demand). Bids for Us: AI offers for your
## players. Our Contracts: values, wages, the transfer list and renewals.

const VIEWS := ["Search", "Bids for Us", "Our Contracts"]
const ROLE_FILTERS := ["All roles", "Batters", "Bowlers", "All-rounders", "Keepers"]
const SORTS := ["Ability", "Value", "Youngest"]
const SHOWN := 40

var app: Node

var _view: String = VIEWS[0]
var _status: Label
var _body: VBoxContainer
var _role_filter := 0
var _sort := 0
var _target: CricketPlayer = null
var _deal := {}  # the negotiation in progress: {fee, response, wage, years}
var _message := ""


func title() -> String:
	return "Transfers"


func subtitle() -> String:
	var s: Season = app.season
	var window := "Window open until %s" % s.date_text(Transfers.deadline_day(s)) if Transfers.window_open(s) else "Transfer window closed"
	return "%s  ·  %s" % [app.club.name, window]


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	add_child(UIKit.sub_nav(VIEWS, func(v):
		_view = v
		_message = ""
		on_shown()))
	_status = UIKit.label("", 13, UIKit.TEXT_DIM)
	add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 12)
	scroll.add_child(_body)


func on_shown() -> void:
	var s: Season = app.season
	var club: CricketTeam = app.club
	_status.text = "Balance %s  ·  Wage bill %s of %s a year  ·  Squad %d (%d-%d)" % [
		Transfers.money(s.balance[club]), Transfers.money(Transfers.wage_bill(club, s)),
		Transfers.money(s.wage_budget[club]), club.squad.size(), Transfers.SQUAD_MIN, Transfers.SQUAD_MAX]
	UIKit.clear(_body)
	match _view:
		"Search":
			_show_search()
		"Bids for Us":
			_show_bids()
		_:
			_show_contracts()
	if app.has_method("refresh_header"):
		app.refresh_header()


# --- search and negotiation ------------------------------------------------------

func _show_search() -> void:
	var s: Season = app.season
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	_body.add_child(h)

	var list_card := UIKit.card("Players at Other Clubs and Free Agents")
	list_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(list_card)
	var list := UIKit.content(list_card)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	filters.add_child(_picker(ROLE_FILTERS, _role_filter, func(i):
		_role_filter = i
		on_shown()))
	filters.add_child(_picker(SORTS.map(func(x): return "Sort: " + x), _sort, func(i):
		_sort = i
		on_shown()))
	list.add_child(filters)

	var players := _search_results(s)
	var rows := []
	for p: CricketPlayer in players:
		var team := s.team_of(p)
		var club_cell := {"text": team.short_name, "colour": team.colour.lightened(0.3)} if team else {"text": "FA", "colour": UIKit.POSITIVE}
		rows.append([p.name + ("  †" if p.is_keeper() else ""), club_cell,
			str(p.age), _rating(p.batting_rating()), _rating(p.bowling_rating()),
			Transfers.money(Transfers.value(p, s)), {"text": str(s.contracts[p].until) if s.contracts.has(p) else "-", "colour": UIKit.TEXT_DIM}])
	list.add_child(UIKit.table([
		{"title": "Player", "width": 0}, {"title": "Club", "width": 44}, {"title": "Age", "width": 34, "align": "right"},
		{"title": "Bat", "width": 34, "align": "center"}, {"title": "Bowl", "width": 38, "align": "center"},
		{"title": "Value", "width": 66, "align": "right"}, {"title": "Until", "width": 44, "align": "right"},
	], rows, func(i):
		_target = players[i]
		_deal = {}
		_message = ""
		on_shown(), players.find(_target)))

	var deal_card := UIKit.card("Negotiation")
	deal_card.custom_minimum_size.x = 390
	h.add_child(deal_card)
	_show_deal(UIKit.content(deal_card))


func _search_results(s: Season) -> Array:
	var club: CricketTeam = app.club
	var pool := s.free_agents.duplicate()
	for t: CricketTeam in s.teams:
		if t != club:
			pool.append_array(t.squad)
	pool = pool.filter(func(p): return _matches_role(p))
	match _sort:
		0:
			pool.sort_custom(func(a, b): return Transfers.ability(a) > Transfers.ability(b))
		1:
			pool.sort_custom(func(a, b): return Transfers.value(a, s) > Transfers.value(b, s))
		2:
			pool.sort_custom(func(a, b): return a.age < b.age)
	return pool.slice(0, SHOWN)


func _matches_role(p: CricketPlayer) -> bool:
	match _role_filter:
		1:
			return p.role == CricketPlayer.Role.BATTER
		2:
			return p.role == CricketPlayer.Role.BOWLER
		3:
			return p.role == CricketPlayer.Role.ALL_ROUNDER
		4:
			return p.role == CricketPlayer.Role.KEEPER
	return true


func _show_deal(box: VBoxContainer) -> void:
	var s: Season = app.season
	var club: CricketTeam = app.club
	if _target == null or not (_target in s.free_agents or s.teams.any(func(t): return t != club and _target in t.squad)):
		box.add_child(UIKit.wrapped("Pick a player from the list to make a bid.", 13))
		if _message != "":
			box.add_child(UIKit.wrapped(_message, 14, UIKit.POSITIVE))
		return
	var p := _target
	var seller := s.team_of(p)
	box.add_child(UIKit.label(p.name, 20))
	box.add_child(UIKit.label("%s  ·  %s  ·  age %d  ·  %s" % [str(CricketPlayer.Role.keys()[p.role]).capitalize(),
		p.style_name(), p.age, seller.name if seller else "Free agent"], 12, UIKit.TEXT_DIM))
	box.add_child(UIKit.stat_row("Value", Transfers.money(Transfers.value(p, s))))
	if seller:
		box.add_child(UIKit.stat_row("Current wage", "%s a year" % Transfers.money(s.contracts[p].wage)))
		box.add_child(UIKit.stat_row("Contract until", str(s.contracts[p].until)))
	else:
		box.add_child(UIKit.stat_row("Fee", "None: free agent", UIKit.POSITIVE))
	var form := UIKit.form_rating(s.form[p])
	box.add_child(UIKit.stat_row("Form  ·  avg rating", "%s  ·  %s" % [form.text,
		"%.2f" % s.average_rating(p) if s.stats[p].apps > 0 else "-"], form.colour))
	box.add_child(HSeparator.new())

	if not Transfers.window_open(s):
		box.add_child(UIKit.label("The transfer window is closed.", 13, UIKit.WARNING))
		return

	var response: Dictionary = _deal.get("response", {})
	if seller == null and response.is_empty():
		box.add_child(UIKit.small_button("Offer a Contract", func(): _bid(0), false, 160))
		return
	if response.get("result", "") != "accept":
		box.add_child(UIKit.label("YOUR BID", 11, UIKit.TEXT_DIM))
		var row := HBoxContainer.new()
		var bid := SpinBox.new()
		bid.min_value = 0
		bid.max_value = maxf(s.balance[club], 0.0)
		bid.step = 5000
		bid.prefix = "£"
		bid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bid.value = _deal.get("fee", Transfers.value(p, s))
		row.add_child(bid)
		row.add_child(UIKit.small_button("Submit Bid", func():
			_bid(int(bid.value)), false, 100))
		box.add_child(row)
		if not response.is_empty():
			var colour := UIKit.WARNING if response.result == "counter" else UIKit.NEGATIVE
			box.add_child(UIKit.wrapped(response.text, 14, colour))
			if response.result == "counter":
				box.add_child(UIKit.small_button("Bid %s" % Transfers.money(response.asking), func():
					_bid(int(response.asking)), int(response.asking) > s.balance[club], 140))
		return

	# Bid accepted: the player's terms.
	box.add_child(UIKit.wrapped(response.text, 14, UIKit.POSITIVE))
	box.add_child(UIKit.label("PLAYER'S TERMS", 11, UIKit.TEXT_DIM))
	box.add_child(UIKit.stat_row("Wage", "%s a year" % Transfers.money(_deal.wage)))
	box.add_child(UIKit.stat_row("Contract", "%d years (until %d)" % [_deal.years, app.season.year + _deal.years]))
	var blocker := Transfers.blockers(p, club, _deal.fee, _deal.wage, s)
	if blocker != "":
		box.add_child(UIKit.wrapped(blocker, 13, UIKit.NEGATIVE))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	var sign_button := Button.new()
	sign_button.text = "Sign for %s" % Transfers.money(_deal.fee) if _deal.fee > 0 else "Sign on a Free"
	sign_button.theme_type_variation = "AccentButton"
	sign_button.disabled = blocker != ""
	sign_button.pressed.connect(func():
		Transfers.complete(p, club, _deal.fee, _deal.wage, _deal.years, s)
		s.save()
		_message = "%s has signed. Pick them in Tactics > Selection." % p.name
		_target = null
		_deal = {}
		on_shown())
	actions.add_child(sign_button)
	actions.add_child(UIKit.small_button("Walk Away", func():
		_deal = {}
		on_shown(), false, 100))
	box.add_child(actions)


func _bid(fee: int) -> void:
	var s: Season = app.season
	var response := Transfers.respond(_target, fee, s)
	GameLog.event("bid", {"player": _target.name, "fee": fee, "value": Transfers.value(_target, s),
		"answer": response.result, "asking": response.asking})
	_deal = {"fee": fee, "response": response,
		"wage": Transfers.wage_demand(_target, s, true), "years": Transfers.demand_years(_target)}
	on_shown()


# --- incoming bids ------------------------------------------------------------------

func _show_bids() -> void:
	var s: Season = app.season
	var c := UIKit.card("Bids for Our Players")
	var box := UIKit.content(c)
	_body.add_child(c)
	if _message != "":
		box.add_child(UIKit.wrapped(_message, 14, UIKit.WARNING))
	var pending := s.offers.filter(func(o): return o.status == "pending")
	if pending.is_empty():
		box.add_child(UIKit.label("No bids at the moment. Transfer-list players under Our Contracts to attract offers.", 13, UIKit.TEXT_DIM))
	else:
		box.add_child(UIKit.grid_header([["Player", 0], ["From", 170], ["Bid", 80], ["Value", 80], ["Expires", 120], ["", 140]]))
		for i in pending.size():
			var o: Dictionary = pending[i]
			var p: CricketPlayer = o.player
			var h := UIKit.grid_row(i)
			h.add_child(UIKit.grid_cell(p.name, 0))
			h.add_child(UIKit.grid_cell(o.from.name, 170, o.from.colour.lightened(0.3)))
			h.add_child(UIKit.grid_cell(Transfers.money(o.fee), 80, UIKit.POSITIVE))
			h.add_child(UIKit.grid_cell(Transfers.money(Transfers.value(p, s)), 80, UIKit.TEXT_DIM))
			h.add_child(UIKit.grid_cell(s.date_text(int(o.day) + Transfers.OFFER_DAYS), 120, UIKit.TEXT_DIM, false, 13))
			h.add_child(UIKit.small_button("Accept", func():
				var err := Transfers.accept_offer(o, s)
				_message = err if err != "" else "%s sold to %s for %s." % [p.name, o.from.name, Transfers.money(o.fee)]
				s.save()
				on_shown()))
			h.add_child(UIKit.small_button("Reject", func():
				o.status = "rejected"
				GameLog.event("bid_rejected", {"player": p.name, "from": o.from.name, "fee": o.fee})
				s.save()
				on_shown()))
			box.add_child(h.get_parent())

	var past := s.offers.filter(func(o): return o.status != "pending")
	if not past.is_empty():
		var history := UIKit.card("Earlier Bids")
		var rows := []
		for o in past:
			rows.append([o.player.name, o.from.name, Transfers.money(o.fee), {"text": str(o.status).capitalize(), "colour": UIKit.TEXT_DIM}])
		UIKit.content(history).add_child(UIKit.table([{"title": "Player", "width": 0}, {"title": "From", "width": 180},
			{"title": "Bid", "width": 80, "align": "right"}, {"title": "Outcome", "width": 100}], rows))
		_body.add_child(history)


# --- our contracts ----------------------------------------------------------------------

func _show_contracts() -> void:
	var s: Season = app.season
	var club: CricketTeam = app.club
	var c := UIKit.card("Squad Contracts")
	var box := UIKit.content(c)
	_body.add_child(c)
	if _message != "":
		box.add_child(UIKit.wrapped(_message, 14, UIKit.WARNING))
	box.add_child(UIKit.grid_header([["Player", 0], ["Age", 40], ["Value", 76], ["Wage", 76], ["Until", 50], ["Status", 90], ["", 230]]))
	var squad: Array = club.players + club.reserves()
	for i in squad.size():
		var p: CricketPlayer = squad[i]
		var h := UIKit.grid_row(i)
		var expiring := Transfers.contract_years(p, s) <= 0
		h.add_child(UIKit.grid_cell(p.name + ("" if p in club.players else "  (res)"), 0))
		h.add_child(UIKit.grid_cell(str(p.age), 40, UIKit.TEXT, true))
		h.add_child(UIKit.grid_cell(Transfers.money(Transfers.value(p, s)), 76))
		h.add_child(UIKit.grid_cell(Transfers.money(s.contracts[p].wage), 76))
		h.add_child(UIKit.grid_cell(str(s.contracts[p].until), 50, UIKit.WARNING if expiring else UIKit.TEXT, true))
		var status := "Listed" if s.listed.has(p) else ("Expiring" if expiring else "")
		h.add_child(UIKit.grid_cell(status, 90, UIKit.WARNING if status != "" else UIKit.TEXT_DIM, false, 13))
		var listed: bool = s.listed.has(p)
		h.add_child(UIKit.small_button("Unlist" if listed else "List", func():
			if listed:
				s.listed.erase(p)
			else:
				s.listed[p] = true
			s.save()
			on_shown(), not Transfers.window_open(s) and not listed, 70))
		var demand := Transfers.wage_demand(p, s)
		var renew := UIKit.small_button("Renew (%s)" % Transfers.money(demand), func():
			var err := Transfers.renew(p, s)
			_message = err if err != "" else "%s has signed a new deal until %d." % [p.name, s.contracts[p].until]
			s.save()
			on_shown(), false, 150)
		renew.tooltip_text = "New deal: %s a year for %d years" % [Transfers.money(demand), Transfers.demand_years(p)]
		h.add_child(renew)
		box.add_child(h.get_parent())
	box.add_child(UIKit.wrapped("Listed players attract bids from other clubs while the window is open. Renewing agrees the player's current demand: wage from their value, length from their age.", 12))


func _picker(items: Array, selected: int, on_pick: Callable) -> OptionButton:
	var o := OptionButton.new()
	for item in items:
		o.add_item(item)
	o.selected = selected
	o.item_selected.connect(on_pick)
	return o


func _rating(v: float) -> Dictionary:
	return {"text": "%d" % roundi(v), "colour": UIKit.attr_colour(v)}
