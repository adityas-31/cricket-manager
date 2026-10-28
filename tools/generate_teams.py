"""Adds generated league teams to data/teams.json.

Keeps every existing team as it is (adding a home pitch if missing) and appends the teams
in NEW_TEAMS with players generated from slot archetypes. Seeded, so reruns give the same
squads. Run from the project root:  py -3 tools/generate_teams.py
"""

import json
import random
from pathlib import Path

PATH = Path(__file__).resolve().parent.parent / "data" / "teams.json"
ATTRS = ["technique", "timing", "power", "vs_spin", "running", "accuracy", "movement", "speed",
         "variation", "catching", "fielding", "keeping", "composure", "concentration", "aggression", "stamina"]

EXISTING_PITCHES = {"Northbridge Royals": "balanced", "Harbour City Strikers": "flat"}
NEW_TEAMS = [
    ("Eastgate Titans", "EGT", "#fb8c00", "green", 0.4),
    ("Riverside Rangers", "RVR", "#43a047", "dusty", 0.0),
    ("Kingsport Mariners", "KPM", "#00acc1", "flat", 0.2),
    ("Ashford Falcons", "ASF", "#8e24aa", "balanced", -0.3),
    ("Southmere Cyclones", "SMC", "#fdd835", "dusty", -0.1),
    ("Westvale Warriors", "WVW", "#6d4c41", "green", -0.5),
]

FIRST = ["Aarav", "Ben", "Callum", "Dev", "Eli", "Faisal", "George", "Hamza", "Isaac", "Jack", "Kabir",
         "Luke", "Mitchell", "Nathan", "Owen", "Parth", "Quinn", "Ravi", "Sam", "Tariq", "Umar", "Vihaan",
         "Will", "Yash", "Zane", "Adil", "Brendon", "Chris", "Dinesh", "Ewan", "Fraser", "Gavin", "Harry",
         "Imad", "Jordan", "Kane", "Lewis", "Mohsin", "Noah", "Ollie", "Pranav", "Rory", "Shane", "Tom"]
LAST = ["Ahmed", "Barnes", "Chopra", "Dawson", "Evans", "Fernando", "Gill", "Hughes", "Iqbal", "Jones",
        "Khan", "Lyon", "Marsh", "Naidu", "O'Brien", "Patel", "Quayle", "Reddy", "Singh", "Taylor", "Usman",
        "Vance", "Walsh", "Yadav", "Zaman", "Ashworth", "Bose", "Crane", "Dhillon", "Ellis", "Foster",
        "Gupta", "Hale", "Joshi", "Kerr", "Lowe", "Malhotra", "Nash", "Pope", "Rashid", "Stone", "Thorpe"]

# Per batting slot: role, bowling style, and (low, high) ranges for each attribute group.
BAT_HI, BAT_MID, BAT_LO = (12, 16), (10, 14), (4, 8)
BOWL_HI, BOWL_MID, BOWL_LO = (12, 15), (10, 13), (3, 8)
SLOTS = [
    ("batter", "medium", BAT_HI, BOWL_LO),
    ("batter", "medium", BAT_HI, BOWL_LO),
    ("batter", "off_spin", BAT_HI, BOWL_LO),
    ("batter", "medium", BAT_HI, BOWL_LO),
    ("batter", "medium", BAT_MID, BOWL_LO),
    ("keeper", "medium", BAT_MID, (2, 3)),
    ("all_rounder", "pace", BAT_MID, BOWL_MID),
    ("all_rounder", "off_spin", BAT_MID, BOWL_MID),
    ("bowler", "pace", BAT_LO, BOWL_HI),
    ("bowler", "leg_spin", BAT_LO, BOWL_HI),
    ("bowler", "pace", BAT_LO, BOWL_HI),
]


# Reserve squad members reuse first-team slot archetypes: two batters, a keeper, a seamer
# and a spinning all-rounder.
RESERVE_SLOTS = [1, 4, 5, 8, 7]
RESERVE_PENALTY = -1.2


def roll(rng, lo_hi, bonus):
    lo, hi = lo_hi
    return max(1, min(20, round(rng.uniform(lo, hi) + bonus)))


def make_player(rng, pid, slot, bonus, used_names):
    role, style, bat, bowl = SLOTS[slot]
    while True:
        name = f"{rng.choice(FIRST)} {rng.choice(LAST)}"
        if name not in used_names:
            used_names.add(name)
            break
    a = {}
    for k in ["technique", "timing", "power", "vs_spin", "running"]:
        a[k] = roll(rng, bat, bonus)
    for k in ["accuracy", "movement", "variation"]:
        a[k] = roll(rng, bowl, bonus)
    a["speed"] = roll(rng, (13, 17) if style == "pace" else (4, 7) if "spin" in style else (6, 10), 0)
    a["catching"] = roll(rng, (9, 14), bonus)
    a["fielding"] = roll(rng, (9, 15), bonus)
    a["keeping"] = roll(rng, (12, 16), bonus) if role == "keeper" else rng.randint(2, 3)
    for k in ["composure", "concentration"]:
        a[k] = roll(rng, (9, 15), bonus)
    a["aggression"] = rng.randint(6, 18)
    a["stamina"] = roll(rng, (10, 16), 0)
    return {"id": pid, "name": name, "role": role, "style": style, "attributes": {k: a[k] for k in ATTRS}}


def dump(data):
    """Same layout as the hand-written file: one team block, two lines per player, and any
    data credits (shown in the game) at the top."""
    out = ['{']
    if data.get("credits"):
        out.append('  "credits": ' + json.dumps(data["credits"], ensure_ascii=False) + ",")
    out.append('  "teams": [')
    for ti, t in enumerate(data["teams"]):
        out.append("    {")
        for key in ["name", "short", "colour", "pitch"]:
            out.append(f'      "{key}": {json.dumps(t[key])},')
        out.append('      "players": [')
        for pi, p in enumerate(t["players"]):
            head = {k: p[k] for k in ["id", "name", "age", "bats", "bowls", "role", "style"] if k in p}
            comma = "," if pi < len(t["players"]) - 1 else ""
            out.append("        " + json.dumps(head)[:-1] + ",")
            out.append('         "attributes": ' + json.dumps(p["attributes"]) + "}" + comma)
        out.append("      ]")
        out.append("    }" + ("," if ti < len(data["teams"]) - 1 else ""))
    out += ["  ]", "}", ""]
    return "\n".join(out)


def main():
    data = json.loads(PATH.read_text(encoding="utf-8"))
    names = {t["name"] for t in data["teams"]}
    used = {p["name"] for t in data["teams"] for p in t["players"]}
    for t in data["teams"]:
        t.setdefault("pitch", EXISTING_PITCHES.get(t["name"], "balanced"))
    rng = random.Random(2026)
    added = 0
    for i, (name, short, colour, pitch, bonus) in enumerate(NEW_TEAMS):
        if name in names:
            continue
        base = 301 + 100 * i
        players = [make_player(rng, base + s, s, bonus, used) for s in range(len(SLOTS))]
        data["teams"].append({"name": name, "short": short, "colour": colour, "pitch": pitch, "players": players})
        added += 1

    # Reserves: squads of 11 get five back-ups, a notch below the first team.
    bonuses = {name: bonus for name, _, _, _, bonus in NEW_TEAMS}
    reserve_rng = random.Random(4242)
    reserves = 0
    for t in data["teams"]:
        if len(t["players"]) != len(SLOTS):
            continue
        next_id = max(p["id"] for p in t["players"]) + 1
        for k, slot in enumerate(RESERVE_SLOTS):
            bonus = bonuses.get(t["name"], 0.0) + RESERVE_PENALTY
            t["players"].append(make_player(reserve_rng, next_id + k, slot, bonus, used))
            reserves += 1
    # Ages, seeded per player so they never change between runs: first-teamers mostly in
    # their mid-to-late twenties, reserves younger.
    aged = 0
    for t in data["teams"]:
        for i, p in enumerate(t["players"]):
            if "age" in p:
                continue
            r = random.Random(p["id"] * 7919)
            p["age"] = round(r.triangular(19, 28, 24)) if i >= len(SLOTS) else round(r.triangular(21, 35, 28))
            aged += 1
    # Handedness, seeded per player: about a quarter of batters are left-handed and a fifth of
    # seamers bowl left-arm (left-arm spinners always do).
    handed = 0
    for t in data["teams"]:
        for p in t["players"]:
            if "bats" in p:
                continue
            r = random.Random(p["id"] * 15485863)
            p["bats"] = "left" if r.random() < 0.27 else "right"
            if p["style"] == "left_arm_spin":
                p["bowls"] = "left"
            else:
                p["bowls"] = "left" if p["style"] in ("pace", "medium") and r.random() < 0.2 else "right"
            handed += 1
    PATH.write_text(dump(data), encoding="utf-8")
    print(f"{len(data['teams'])} teams ({added} added, {reserves} reserves added, {aged} ages set, {handed} handedness set)")


if __name__ == "__main__":
    main()
