extends HBoxContainer
## Finances: the club's balance, wage bill against the board's budget, money in and out,
## and how every club in the league stands.

var app: Node

var _overview: VBoxContainer
var _league: VBoxContainer
var _ledger: VBoxContainer


func title() -> String:
	return "Finances"


func subtitle() -> String:
	return "%s  ·  Balance %s" % [app.club.name, Transfers.money(app.season.balance[app.club])]


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 440
	left.add_theme_constant_override("separation", 12)
	add_child(left)
	var overview := UIKit.card("Overview")
	left.add_child(overview)
	_overview = UIKit.content(overview)
	var league := UIKit.card("League Finances")
	league.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(league)
	_league = UIKit.content(league)

	var ledger := UIKit.card("Transactions")
	ledger.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(ledger)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UIKit.content(ledger).add_child(scroll)
	_ledger = VBoxContainer.new()
	_ledger.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_ledger)


func on_shown() -> void:
	var s: Season = app.season
	var club: CricketTeam = app.club

	UIKit.clear(_overview)
	var bill := Transfers.wage_bill(club, s)
	var budget: int = s.wage_budget[club]
	var income := 0.0
	var spending := 0.0
	for entry in s.ledger:
		if entry.amount > 0:
			income += entry.amount
		else:
			spending -= entry.amount
	_overview.add_child(UIKit.stat_row("Balance", Transfers.money(s.balance[club]), UIKit.POSITIVE if s.balance[club] >= 0 else UIKit.NEGATIVE))
	_overview.add_child(UIKit.stat_row("Wage bill", "%s a year (%s a week)" % [Transfers.money(bill), Transfers.money(bill / 52.0)]))
	_overview.add_child(UIKit.meter("Wage budget", float(bill) / budget, UIKit.NEGATIVE if bill > budget else UIKit.POSITIVE,
		Transfers.money(budget)))
	_overview.add_child(UIKit.stat_row("Room in wage budget", Transfers.money(budget - bill)))
	_overview.add_child(UIKit.stat_row("Income this season", Transfers.money(income), UIKit.POSITIVE))
	_overview.add_child(UIKit.stat_row("Spending this season", Transfers.money(spending), UIKit.NEGATIVE))
	var window := "open until %s" % s.date_text(Transfers.deadline_day(s)) if Transfers.window_open(s) else "closed"
	_overview.add_child(UIKit.stat_row("Transfer window", window))
	_overview.add_child(UIKit.wrapped("Money comes in from home gates (bigger the higher you sit) and play-offs; wages go out weekly. Transfer fees come straight off the balance.", 12))

	UIKit.clear(_league)
	var teams := s.teams.duplicate()
	teams.sort_custom(func(a, b): return s.balance[a] > s.balance[b])
	var rows := []
	for t: CricketTeam in teams:
		rows.append([{"text": t.name, "colour": t.colour.lightened(0.3) if t == club else UIKit.TEXT},
			Transfers.money(s.balance[t]), Transfers.money(Transfers.wage_bill(t, s)), str(t.squad.size())])
	_league.add_child(UIKit.table([{"title": "Club", "width": 0}, {"title": "Balance", "width": 70, "align": "right"},
		{"title": "Wages", "width": 70, "align": "right"}, {"title": "Squad", "width": 46, "align": "right"}], rows,
		Callable(), teams.find(club)))

	UIKit.clear(_ledger)
	if s.ledger.is_empty():
		_ledger.add_child(UIKit.label("No transactions yet", 13, UIKit.TEXT_DIM))
		return
	var entries: Array = s.ledger.duplicate()
	entries.reverse()
	var ledger_rows := []
	for entry in entries:
		var amount: float = entry.amount
		ledger_rows.append([{"text": s.date_text(int(entry.day)), "colour": UIKit.TEXT_DIM}, entry.text,
			{"text": ("+" if amount > 0 else "") + Transfers.money(amount), "colour": UIKit.POSITIVE if amount > 0 else UIKit.NEGATIVE}])
	_ledger.add_child(UIKit.table([{"title": "Date", "width": 130}, {"title": "Item", "width": 0},
		{"title": "Amount", "width": 90, "align": "right"}], ledger_rows))
