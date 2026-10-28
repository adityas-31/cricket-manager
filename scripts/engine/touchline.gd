class_name Touchline
extends RefCounted
## Messages from the dressing room to the middle: cricket's version of FM's touchline shouts.
##
## A message lasts MESSAGE_BALLS legal balls; then the side waits COOLDOWN_BALLS before it can
## send another. Sending the same message again in an innings works less well each time
## (REPEAT_FACTOR): players stop listening. Messages end at the end of an innings.
##
## Effects, all optional: "intent" nudges the batters' intent; "w" multiplies the delivery
## outcome weights (see DeliveryModel.BASE); "wide"/"noball" multiply those chances;
## "pressure" and "confidence" change the meters once, when the message is sent; "bowler"
## ties a batting message to the bowler on at the time; "sledge" fires up a composed striker
## instead of rattling him.

const MESSAGE_BALLS := 12
const COOLDOWN_BALLS := 12
const REPEAT_FACTOR := 0.6
## A striker with at least this much composure feeds off a sledge.
const SLEDGE_COMPOSURE := 14.0

const MESSAGES := {
	"Rotate the strike": {"side": "bat", "intent": -0.15, "w": {"0": 0.85, "1": 1.15, "2": 1.1, "4": 0.92, "6": 0.85},
		"desc": "Work the ones and twos: fewer dots, fewer boundaries, less risk."},
	"Take him on": {"side": "bat", "intent": 0.4, "bowler": true,
		"desc": "Go after the bowler on now: more boundaries off him, and more risk."},
	"See off this spell": {"side": "bat", "intent": -0.45, "w": {"W": 0.85}, "bowler": true,
		"desc": "Play the bowler on now with care: fewer runs and fewer wickets off him."},
	"Settle down": {"side": "bat", "intent": -0.1, "pressure": -15.0, "confidence": 6.0,
		"desc": "Calm things after a wobble: eases the pressure and lifts the batters' confidence."},
	"Lift the tempo": {"side": "bat", "intent": 0.25, "w": {"2": 1.25},
		"desc": "Push on: more intent and harder running between the wickets."},
	"Attack the stumps": {"side": "bowl", "w": {"W": 1.12, "1": 1.05, "4": 1.06},
		"desc": "Full and straight: more bowled and lbw, but runs off the pads."},
	"Dry it up": {"side": "bowl", "w": {"0": 1.1, "4": 0.82, "6": 0.82, "W": 0.88}, "wide": 1.3,
		"desc": "Wide outside off: fewer boundaries, fewer wickets, a few more wides."},
	"Short-ball plan": {"side": "bowl", "w": {"W": 1.15, "4": 1.08, "6": 1.25}, "noball": 1.6,
		"desc": "Bouncers: catches in the deep, but sixes and no-balls too."},
	"Yorkers": {"side": "bowl", "w": {"6": 0.75, "4": 0.95, "W": 1.05, "0": 1.05}, "wide": 1.25,
		"desc": "Aim at the toes: hard to hit for six, but miss and it's a full toss or a wide."},
	"Get in his ear": {"side": "bowl", "pressure": 10.0, "sledge": true,
		"desc": "Chirp the striker: raises the pressure. A composed batter may feed off it."},
	"Encourage": {"side": "any", "confidence": 5.0,
		"desc": "Lift everyone after a bad spell: confidence up for your players in the middle."},
}


## The messages a side can send in its current role ("bat" or "bowl").
static func names_for(role: String) -> Array:
	return MESSAGES.keys().filter(func(n): return MESSAGES[n].side in [role, "any"])


## A message's effects scaled by factor (1 = full strength), moving every multiplier
## towards 1 and every offset towards 0.
static func scaled(name: String, factor: float) -> Dictionary:
	var m: Dictionary = MESSAGES[name]
	var out := {"intent": m.get("intent", 0.0) * factor, "w": {},
		"wide": 1.0 + (m.get("wide", 1.0) - 1.0) * factor, "noball": 1.0 + (m.get("noball", 1.0) - 1.0) * factor}
	var w: Dictionary = m.get("w", {})
	for k in w:
		out.w[k] = 1.0 + (w[k] - 1.0) * factor
	return out
