"""Turns per-innings batting and bowling records into player attributes.

Reads a stats dataset with batsman.csv (Player Name, Runs, BF, 4s, 6s, SR, Dismissal, Match
Type, ...) and bowlers.csv (Player Name, Overs, Maidens, Runs, Wickets, Economy, Match Type,
...), from a .zip or a folder, cleans known data problems, matches names to the players
dataset, and estimates attributes on the game's 1-20 scale. tools/import_dataset.py uses it
through --stats.

Ratings are judged against what's normal in each format (a T20I strike rate of 130 is par,
an ODI one 90), combined across formats with T20I counting most (the game plays T20), and
pulled towards the player's existing rating when there are only a few innings, so one big
score doesn't make a star.
"""

import csv
import io
import zipfile
from collections import Counter, defaultdict
from pathlib import Path

BAT_FILE = "batsman.csv"
BOWL_FILE = "bowlers.csv"

FORMAT_WEIGHT = {"T20I": 1.0, "ODI": 0.8, "Test": 0.6}
OTHER_FORMAT_WEIGHT = 0.5
# What an ordinary international manages in each format.
PAR = {
    "T20I": {"bat_avg": 25, "bat_sr": 130, "balls_per_out": 20, "econ": 8.0, "bowl_sr": 18, "bowl_avg": 24},
    "ODI": {"bat_avg": 35, "bat_sr": 90, "balls_per_out": 40, "econ": 5.5, "bowl_sr": 33, "bowl_avg": 32},
    "Test": {"bat_avg": 35, "bat_sr": 55, "balls_per_out": 70, "econ": 3.2, "bowl_sr": 60, "bowl_avg": 30},
}
# Innings / spells at which the stats and the existing rating count equally.
BAT_SHRINK = 10
BOWL_SHRINK = 8
NOT_OUT = {"not out", "retired notout", "retired not out", "dnb"}


def _num(x):
    x = (x or "").strip()
    return 0.0 if x in ("", "-") else float(x)


def _balls(overs):
    """Cricket overs notation: 3.5 is 3 overs and 5 balls."""
    o = _num(overs)
    return int(o) * 6 + round((o - int(o)) * 10)


def _format(name):
    name = (name or "").strip()
    return {"t20i": "T20I", "odi": "ODI", "test": "Test"}.get(name.lower(), name)


def read_stats(source: Path):
    """(batting rows, bowling rows) as lists of dicts with stripped keys and values."""
    def parse(raw: bytes):
        reader = csv.DictReader(io.StringIO(raw.decode("utf-8-sig")))
        return [{k.strip(): (v or "").strip() for k, v in r.items() if k and k.strip()} for r in reader]
    if source.suffix.lower() == ".zip":
        with zipfile.ZipFile(source) as z:
            files = {Path(n).name: n for n in z.namelist()}
            missing = [f for f in (BAT_FILE, BOWL_FILE) if f not in files]
            if missing:
                raise SystemExit(f"{source} has no {', '.join(missing)}")
            return parse(z.read(files[BAT_FILE])), parse(z.read(files[BOWL_FILE]))
    found = {p.name: p for p in source.rglob("*.csv")}
    return parse(found[BAT_FILE].read_bytes()), parse(found[BOWL_FILE].read_bytes())


def clean(bat_rows, bowl_rows):
    """Fixes the known problems and returns (batting, bowling, notes):
    "-" for zero; balls faced recovered from the strike rate when the two disagree;
    boundary counts that add up to more than the runs scored ignored; bowling overs in
    cricket notation; inconsistent capitalisation and spacing."""
    notes = Counter()
    bat = []
    for r in bat_rows:
        try:
            runs, bf, sr = _num(r.get("Runs")), _num(r.get("BF")), _num(r.get("SR"))
            fours, sixes = _num(r.get("4s")), _num(r.get("6s"))
        except ValueError:
            notes["batting rows skipped (not numbers)"] += 1
            continue
        if "-" in (r.get("4s"), r.get("6s")):
            notes["'-' read as 0"] += 1
        if sr > 0 and (bf <= 0 or abs(runs * 100 / bf - sr) > 1):
            bf = round(runs * 100 / sr)
            notes["balls faced recovered from strike rate"] += 1
        boundaries_ok = fours * 4 + sixes * 6 <= runs
        if not boundaries_ok:
            notes["impossible boundary counts ignored"] += 1
        bat.append({"name": r.get("Player Name", "").strip(), "fmt": _format(r.get("Match Type")),
                    "runs": runs, "balls": bf, "fours": fours, "sixes": sixes, "boundaries_ok": boundaries_ok,
                    "out": r.get("Dismissal", "").strip().lower() not in NOT_OUT})
    bowl = []
    for r in bowl_rows:
        try:
            balls, runs, wkts = _balls(r.get("Overs")), _num(r.get("Runs")), _num(r.get("Wickets"))
        except ValueError:
            notes["bowling rows skipped (not numbers)"] += 1
            continue
        if balls > 0:
            bowl.append({"name": r.get("Player Name", "").strip(), "fmt": _format(r.get("Match Type")),
                         "balls": balls, "runs": runs, "wickets": wkts})
    return bat, bowl, notes


def aggregate(bat, bowl):
    """{name: {"bat": {fmt: Counter}, "bowl": {fmt: Counter}}}"""
    out = defaultdict(lambda: {"bat": defaultdict(Counter), "bowl": defaultdict(Counter)})
    for r in bat:
        c = out[r["name"]]["bat"][r["fmt"]]
        c["inns"] += 1
        c["runs"] += r["runs"]
        c["balls"] += r["balls"]
        c["outs"] += r["out"]
        if r["boundaries_ok"]:
            c["boundary_runs"] += r["fours"] * 4 + r["sixes"] * 6
            c["boundary_base"] += r["runs"]
    for r in bowl:
        c = out[r["name"]]["bowl"][r["fmt"]]
        c["spells"] += 1
        c["balls"] += r["balls"]
        c["runs"] += r["runs"]
        c["wickets"] += r["wickets"]
    return out


def appearances(entry) -> int:
    return sum(c["inns"] for c in entry["bat"].values()) + sum(c["spells"] for c in entry["bowl"].values())


def match_players(names, players):
    """Links stats names to rows of the players dataset. Tries, in order: the exact full
    name; a full name ending in the stats name ("B Sai Sudharsan" for "Sai Sudharsan"); the
    same surname with a first initial from a set of initials ("Lokesh Rahul" for "KL Rahul").
    The fuzzy steps only look in the country most exact matches came from, and only at
    players with a real profile photo. Ties go to the photo, then the lowest id.
    Returns ({stats name: player row}, [unmatched names], country)."""
    def rank(r):
        return ("placeholder" in r["image_path"], int(r["id"]))
    by_name = defaultdict(list)
    for r in players:
        by_name[r["fullname"].strip().lower()].append(r)
    matched, pending = {}, []
    for n in names:
        hits = by_name.get(n.lower(), [])
        if hits:
            matched[n] = min(hits, key=rank)
        else:
            pending.append(n)
    country = Counter(r["country_name"] for r in matched.values()).most_common(1)
    country = country[0][0] if country else ""
    pool = [r for r in players if r["country_name"] == country and "placeholder" not in r["image_path"]]
    unmatched = []
    for n in pending:
        parts = n.split()
        suffix = [r for r in pool if r["fullname"].lower().endswith(" " + n.lower())]
        initials = parts[0] if len(parts) > 1 and parts[0].isupper() and len(parts[0]) <= 3 else ""
        by_initial = [r for r in pool if initials and r["lastname"].strip().lower() == parts[-1].lower()
                      and r["firstname"][:1].upper() in initials]
        hits = suffix or by_initial
        if hits:
            matched[n] = min(hits, key=rank)
        else:
            unmatched.append(n)
    return matched, unmatched, country


def _weighted(estimates):
    """Weighted mean of [(value, weight)], or None."""
    total = sum(w for _, w in estimates)
    return sum(v * w for v, w in estimates) / total if total > 0 else None


def ratings(entry, current):
    """New values for the attributes the stats speak to, blended with the current ones."""
    est = defaultdict(list)
    bat_n = 0
    for fmt, c in entry["bat"].items():
        if c["inns"] == 0 or fmt not in PAR:
            continue
        par = PAR[fmt]
        w = c["inns"] * FORMAT_WEIGHT.get(fmt, OTHER_FORMAT_WEIGHT)
        bat_n += c["inns"]
        avg = c["runs"] / max(c["outs"], 1)
        sr = c["runs"] * 100 / max(c["balls"], 1)
        est["technique"].append((12 + (avg / par["bat_avg"] - 1) * 8, w))
        est["timing"].append((12 + (sr / par["bat_sr"] - 1) * 25, w))
        est["aggression"].append((11 + (sr / par["bat_sr"] - 1) * 15, w))
        est["concentration"].append((12 + (c["balls"] / max(c["outs"], 1) / par["balls_per_out"] - 1) * 6, w))
        if c["boundary_base"] > 0:
            share = 100 * c["boundary_runs"] / c["boundary_base"]
            est["power"].append((8 + (share - 40) * 0.22, w))
    bowl_n = 0
    for fmt, c in entry["bowl"].items():
        if c["spells"] == 0 or fmt not in PAR:
            continue
        par = PAR[fmt]
        w = c["spells"] * FORMAT_WEIGHT.get(fmt, OTHER_FORMAT_WEIGHT)
        bowl_n += c["spells"]
        econ = c["runs"] * 6 / c["balls"]
        strike = c["balls"] / c["wickets"] if c["wickets"] else par["bowl_sr"] * 2
        average = c["runs"] / c["wickets"] if c["wickets"] else par["bowl_avg"] * 2
        est["accuracy"].append((12 + (1 - econ / par["econ"]) * 20, w))
        est["movement"].append((12 + (1 - strike / par["bowl_sr"]) * 14, w))
        est["variation"].append((12 + (1 - average / par["bowl_avg"]) * 12, w))
    out = {}
    for attr, values in est.items():
        n = bowl_n if attr in ("accuracy", "movement", "variation") else bat_n
        k = BOWL_SHRINK if attr in ("accuracy", "movement", "variation") else BAT_SHRINK
        share = n / (n + k)
        stat = max(1.0, min(20.0, _weighted(values)))
        out[attr] = max(1, min(20, round(share * stat + (1 - share) * float(current.get(attr, 10)))))
    return out
