class_name Transfers
extends RefCounted
## The transfer market and contracts. Season holds the data (contracts, balances, wage
## budgets, offers, the transfer list); these functions price players and move them.
##
## - Value: ability (best of batting/bowling, plus an all-rounder and keeper bonus) on an
##   exponential scale, adjusted for age, form and contract length.
## - Buying: the selling club has an asking price (higher for its key players) and accepts,
##   counters or rejects a bid; then the player names a wage and contract length.
## - Selling: AI clubs bid for the manager's players, mostly ones on the transfer list.
## - Free agents (out of contract, no club) cost no fee: just agree their terms.
## - The window shuts halfway through the league; squads must stay between 14 and 18 players.

const SQUAD_MAX := 18
const SQUAD_MIN := 14
const OFFER_DAYS := 5
const GATE_BASE := 50000
const GATE_PER_PLACE := 8000
const PLAYOFF_GATE := 150000
const WAGE_SHARE := 0.3  # annual wage as a share of value


static func money(amount: float) -> String:
	var minus := "-" if amount < 0 else ""
	var a := absf(amount)
	if a >= 1000000.0:
		return "%s£%.2fm" % [minus, a / 1000000.0]
	return "%s£%dk" % [minus, roundi(a / 1000.0)]


## A single ability number on the 1-20 scale.
static func ability(p: CricketPlayer) -> float:
	var bat := p.batting_rating()
	var bowl := p.bowling_rating()
	var r := maxf(bat, bowl) + maxf(minf(bat, bowl) - 8.0, 0.0) * 0.3
	return r + (0.5 if p.is_keeper() else 0.0)


static func value(p: CricketPlayer, s: Season) -> int:
	var v := 25000.0 * pow(1.5, ability(p) - 8.0)
	if p.age < 22:
		v *= 1.3  # potential
	elif p.age >= 34:
		v *= 0.5
	elif p.age >= 31:
		v *= 0.75
	v *= 0.85 + s.form.get(p, 50.0) / 100.0 * 0.3
	if contract_years(p, s) <= 0:
		v *= 0.8  # free to talk to other clubs at the end of the season
	return _round(v)


## Seasons left after this one (0 = the contract ends this season).
static func contract_years(p: CricketPlayer, s: Season) -> int:
	return int(s.contracts[p].until) - s.year if s.contracts.has(p) else 2


static func wage_demand(p: CricketPlayer, s: Season, moving := false) -> int:
	return maxi(20000, _round(value(p, s) * WAGE_SHARE * (1.15 if moving else 1.0)))


static func demand_years(p: CricketPlayer) -> int:
	if p.age <= 27:
		return 3
	return 2 if p.age <= 31 else 1


static func window_open(s: Season) -> bool:
	return s.day <= deadline_day(s)


## The last day of the window: halfway through the league schedule, whatever its length.
static func deadline_day(s: Season) -> int:
	var days := s.fixtures.filter(func(f): return f.stage == "League").map(func(f): return f.day)
	return int(days.max()) / 2 if not days.is_empty() else 0


static func wage_bill(team: CricketTeam, s: Season) -> int:
	var total := 0
	for p in team.squad:
		total += int(s.contracts[p].wage)
	return total


## What the selling club wants: more for its key players, steady for a week at a time.
static func asking_price(p: CricketPlayer, s: Season) -> int:
	var seller := s.team_of(p)
	if seller == null:
		return 0  # free agent
	var rank := _squad_rank(p, seller)
	var mult := 1.15
	if rank < 3:
		mult = 2.2
	elif rank < CricketTeam.XI_SIZE:
		mult = 1.6
	var r := RandomNumberGenerator.new()
	r.seed = hash([p.id, s.day / 7])
	return _round(value(p, s) * mult * r.randf_range(0.95, 1.15))


## The selling club's answer to a bid: {result: "accept" | "counter" | "reject", asking, text}.
static func respond(p: CricketPlayer, fee: int, s: Season) -> Dictionary:
	var seller := s.team_of(p)
	var ask := asking_price(p, s)
	if seller == null:
		return {"result": "accept", "asking": 0, "text": "%s is a free agent: no fee, just agree terms." % p.name}
	if seller.squad.size() <= SQUAD_MIN:
		return {"result": "reject", "asking": ask, "text": "%s can't sell: their squad is down to %d." % [seller.name, SQUAD_MIN]}
	if fee >= ask:
		return {"result": "accept", "asking": ask, "text": "%s accept your bid of %s." % [seller.name, money(fee)]}
	if fee >= ask * 0.8:
		return {"result": "counter", "asking": ask, "text": "%s would sell for %s." % [seller.name, money(ask)]}
	return {"result": "reject", "asking": ask, "text": "%s reject %s out of hand. It would take something near %s." % [
		seller.name, money(fee), money(_round(ask * 1.05))]}


## Why a club can't complete a signing, or "" if it can.
static func blockers(p: CricketPlayer, buyer: CricketTeam, fee: int, wage: int, s: Season) -> String:
	if not window_open(s):
		return "The transfer window is closed"
	if buyer.squad.size() >= SQUAD_MAX:
		return "The squad is full (%d players)" % SQUAD_MAX
	if fee > s.balance[buyer]:
		return "Not enough money: the balance is %s" % money(s.balance[buyer])
	var over := wage_bill(buyer, s) + wage - int(s.wage_budget[buyer])
	if over > 0:
		return "That wage would put you %s over the wage budget" % money(over)
	return ""


## Moves a player (from a club or free agency): fee to the seller, new contract, squads and
## roles updated, news.
static func complete(p: CricketPlayer, buyer: CricketTeam, fee: int, wage: int, years: int, s: Season) -> void:
	var seller := s.team_of(p)
	if seller:
		seller.squad.erase(p)
		seller.players.erase(p)
		seller.bat_roles.erase(p)
		seller.bowl_roles.erase(p)
		s.balance[seller] += fee
	else:
		s.free_agents.erase(p)
	buyer.squad.append(p)
	s.balance[buyer] -= fee
	s.contracts[p] = {"wage": wage, "until": s.year + years}
	s.listed.erase(p)
	Tactics.suggest_batting(buyer)
	for o in s.offers:
		if o.player == p and o.status == "pending":
			o.status = "withdrawn"
	if s.club in [buyer, seller]:
		var from := seller.name if seller else "free agency"
		var text := "%s moves from %s to %s for %s on %s a year until %d" % [
			p.name, from, buyer.name, money(fee), money(wage), s.year + years]
		s.add_news("%s %s" % [p.name, "signs" if buyer == s.club else "sold"], text + ".")
		GameLog.event("transfer", {"player": p.name, "from": from, "to": buyer.name, "fee": fee, "wage": wage,
			"years": years, "value": value(p, s), "age": p.age, "date": s.date_text()})
		if fee > 0:
			s.log_money(-fee if buyer == s.club else fee, "%s %s" % ["Signed" if buyer == s.club else "Sold", p.name])


## Extends a club player's contract on their terms. Returns "" or why it can't be done.
static func renew(p: CricketPlayer, s: Season) -> String:
	var wage := wage_demand(p, s)
	var years := demand_years(p)
	var over := wage_bill(s.club, s) - int(s.contracts[p].wage) + wage - int(s.wage_budget[s.club])
	if over > 0:
		return "Renewing on %s would put you %s over the wage budget" % [money(wage), money(over)]
	s.contracts[p] = {"wage": wage, "until": s.year + years}
	s.add_news("%s signs a new contract" % p.name, "%s a year until %d." % [money(wage), s.year + years])
	GameLog.event("renewal", {"player": p.name, "wage": wage, "until": s.year + years})
	return ""


## AI clubs bid for the manager's players: listed players attract bids most days, the rest
## only occasionally.
static func make_ai_offers(s: Season, days: int) -> void:
	if not window_open(s) or s.club.squad.size() <= SQUAD_MIN:
		return
	for p: CricketPlayer in s.club.squad:
		if s.offers.any(func(o): return o.player == p and o.status == "pending"):
			continue
		var listed := s.listed.has(p)
		if s.rng.randf() >= (0.15 if listed else 0.006) * days:
			continue
		var v := value(p, s)
		var fee := _round(v * (s.rng.randf_range(0.7, 1.0) if listed else s.rng.randf_range(0.9, 1.3)))
		var buyers := s.teams.filter(func(t): return t != s.club and t.squad.size() < SQUAD_MAX and s.balance[t] >= fee)
		if buyers.is_empty():
			continue
		var buyer: CricketTeam = buyers[s.rng.randi_range(0, buyers.size() - 1)]
		s.offers.append({"player": p, "from": buyer, "fee": fee, "day": s.day, "status": "pending"})
		s.add_news("Bid for %s" % p.name, "%s offer %s. Respond on the Transfers screen within %d days." % [
			buyer.name, money(fee), OFFER_DAYS])
		GameLog.event("bid_received", {"player": p.name, "from": buyer.name, "fee": fee, "value": v, "listed": listed})


static func expire_offers(s: Season) -> void:
	for o in s.offers:
		if o.status == "pending" and (s.day - int(o.day) > OFFER_DAYS or not window_open(s)):
			o.status = "expired"


## Accepts an AI club's bid for one of the manager's players. Returns "" or why not.
static func accept_offer(o: Dictionary, s: Season) -> String:
	var p: CricketPlayer = o.player
	if not window_open(s):
		return "The transfer window is closed"
	if s.club.squad.size() <= SQUAD_MIN:
		return "You can't go below %d players" % SQUAD_MIN
	var buyer: CricketTeam = o.from
	if buyer.squad.size() >= SQUAD_MAX or s.balance[buyer] < o.fee:
		o.status = "withdrawn"
		return "%s can no longer complete the deal" % buyer.name
	o.status = "accepted"
	complete(p, buyer, int(o.fee), wage_demand(p, s, true), demand_years(p), s)
	return ""


## Starting contracts, balances and wage budgets for a new career.
static func setup(s: Season) -> void:
	for t: CricketTeam in s.teams:
		for p: CricketPlayer in t.squad:
			var r := RandomNumberGenerator.new()
			r.seed = p.id * 104729
			s.contracts[p] = {"wage": 0, "until": s.year + r.randi_range(0, 3)}
		var squad_value := 0
		for p: CricketPlayer in t.squad:
			s.contracts[p].wage = wage_demand(p, s)
			squad_value += value(p, s)
		s.balance[t] = float(_round(800000.0 + squad_value * 0.2))
		s.wage_budget[t] = _round(wage_bill(t, s) * 1.12)


static func _squad_rank(p: CricketPlayer, team: CricketTeam) -> int:
	var sorted := team.squad.duplicate()
	sorted.sort_custom(func(a, b): return ability(a) > ability(b))
	return sorted.find(p)


static func _round(x: float) -> int:
	if x >= 1000000.0:
		return int(snappedf(x, 50000.0))
	if x >= 100000.0:
		return int(snappedf(x, 10000.0))
	return int(snappedf(x, 5000.0))
