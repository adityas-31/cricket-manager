"""Rates players from Cricsheet ball-by-ball data (https://cricsheet.org).

Cricsheet match data and its people register are used under the Open Data Commons
Attribution License (ODC-By 1.0): credit Cricsheet in any public use, keep its notices
(the README.txt and LICENSE.txt inside each zip), and make the licence clear.

Reads every *_json.zip in a folder (e.g. t20s_male_json.zip, odis_male_json.zip,
tests_male_json.zip from https://cricsheet.org/downloads/) plus the register's names.csv,
aggregates each player's matches since a date, matches them to the players dataset (which has
the hands, styles and ages Cricsheet lacks), and turns the numbers into attributes on the
game's 1-20 scale. tools/import_dataset.py uses it through --cricsheet.
"""

import csv
import json
import re
import zipfile
from collections import Counter, defaultdict
from pathlib import Path

CREDIT = ("Cricket match data from Cricsheet (https://cricsheet.org), used under the Open Data Commons "
          "Attribution License (ODC-By 1.0). Player ratings are derived from it.")

FORMAT_OF = {"T20": "T20I", "IT20": "T20I", "ODI": "ODI", "ODM": "ODI", "Test": "Test", "MDM": "Test"}
FORMAT_WEIGHT = {"T20I": 1.0, "ODI": 0.8, "Test": 0.6}
# Death overs start at this 0-based over.
DEATH_FROM = {"T20I": 15, "ODI": 40}
NOT_BOWLERS_WICKET = {"run out", "retired hurt", "retired out", "retired not out", "obstructing the field",
                      "timed out", "handled the ball"}
# What an ordinary international manages in each format.
PAR = {
    "T20I": {"avg": 25, "sr": 130, "balls_per_out": 20, "dot": 38, "boundary_share": 55, "six_rate": 4.0,
             "econ": 8.0, "bowl_sr": 18, "bowl_avg": 24, "bowl_dot": 38, "death_sr": 160, "death_econ": 10.0},
    "ODI": {"avg": 35, "sr": 90, "balls_per_out": 40, "dot": 50, "boundary_share": 50, "six_rate": 1.5,
            "econ": 5.8, "bowl_sr": 33, "bowl_avg": 32, "bowl_dot": 50, "death_sr": 125, "death_econ": 7.5},
    "Test": {"avg": 35, "sr": 55, "balls_per_out": 70, "dot": 75, "boundary_share": 50, "six_rate": 0.5,
             "econ": 3.4, "bowl_sr": 60, "bowl_avg": 30, "bowl_dot": 75},
}
# Where par lands on the 1-20 scale, set so data-rated teams match the attribute levels the
# match engine is calibrated for (tests/sim_stats.gd) and the generated ratings of teams
# Cricsheet doesn't cover. Internationals' numbers are mostly above par, so batting par sits low.
BAT_PAR_RATING = 10.5
BOWL_PAR_RATING = 13.0
# Power is judged on runs scored, not balls: a tail-ender's few sixes shouldn't count much.
POWER_SHRINK_RUNS = 400
# A format only counts for a player once they've faced or bowled this many balls in it, so
# a tail-ender's three sixes don't make them a power hitter.
MIN_BALLS = 60
# Balls at which the numbers and the player's existing rating count equally.
BAT_SHRINK = 150
BOWL_SHRINK = 180
BOWLING_ATTRS = ("accuracy", "movement", "variation")


def _new_entry():
    return {"bat": defaultdict(Counter), "bowl": defaultdict(Counter), "field": Counter(),
            "matches": Counter(), "teams": Counter(), "names": set(), "vs": Counter()}


def load(folder: Path, since: str = "2022-01-01"):
    """{cricsheet person id: entry} for every player in matches on or after `since`.
    entry: bat/bowl {format: Counter}, field Counter, matches {format: n}, teams Counter,
    names (as they appear in the data), vs {bowler id: [balls, runs, outs]} per format."""
    players = defaultdict(_new_entry)
    pairs = defaultdict(Counter)  # (batter, bowler, format) -> balls, runs, outs
    read = Counter()
    for z in sorted(Path(folder).glob("*_json.zip")):
        with zipfile.ZipFile(z) as zf:
            for name in zf.namelist():
                if not name.endswith(".json"):
                    continue
                match = json.loads(zf.read(name))
                info = match["info"]
                fmt = FORMAT_OF.get(info.get("match_type"))
                if fmt is None or info["dates"][0] < since or info.get("team_type", "international") != "international":
                    continue
                read[fmt] += 1
                _add_match(match, fmt, players, pairs)
    return players, pairs, read


def _add_match(match, fmt, players, pairs):
    info = match["info"]
    ids = info["registry"]["people"]
    for team, names in info["players"].items():
        for n in names:
            p = players[ids[n]]
            p["matches"][fmt] += 1
            p["teams"][team] += 1
            p["names"].add(n)
    death = DEATH_FROM.get(fmt, 10 ** 6)
    for innings in match.get("innings", []):
        if innings.get("super_over"):
            continue
        for over in innings.get("overs", []):
            at_death = over["over"] >= death
            for d in over["deliveries"]:
                batter, bowler = ids[d["batter"]], ids[d["bowler"]]
                extras = d.get("extras", {})
                runs = d["runs"]["batter"]
                wide = "wides" in extras
                legal = not wide and "noballs" not in extras
                b = players[batter]["bat"][fmt]
                w = players[bowler]["bowl"][fmt]
                pair = pairs[(batter, bowler, fmt)]
                if not wide:
                    b["balls"] += 1
                    b["runs"] += runs
                    pair["balls"] += 1
                    pair["runs"] += runs
                    boundary = runs in (4, 6) and not d["runs"].get("non_boundary")
                    if boundary:
                        b["fours" if runs == 4 else "sixes"] += 1
                    else:
                        b["running_runs"] += runs
                        b["running_balls"] += 1
                    if runs == 0:
                        b["dots"] += 1
                    if at_death:
                        b["death_balls"] += 1
                        b["death_runs"] += runs
                conceded = runs + extras.get("wides", 0) + extras.get("noballs", 0)
                w["runs"] += conceded
                if legal:
                    w["balls"] += 1
                    if conceded == 0:
                        w["dots"] += 1
                    if at_death:
                        w["death_balls"] += 1
                        w["death_runs"] += conceded
                for wk in d.get("wickets", []):
                    out = ids.get(wk["player_out"])
                    if out:
                        players[out]["bat"][fmt]["outs"] += 1
                        if out == batter:
                            pair["outs"] += 1
                    kind = wk["kind"]
                    if kind not in NOT_BOWLERS_WICKET:
                        w["wickets"] += 1
                    for f in wk.get("fielders", []):
                        fid = ids.get(f.get("name", ""))
                        if fid and not f.get("substitute"):
                            key = {"stumped": "stumpings", "run out": "run_outs"}.get(kind, "catches")
                            players[fid]["field"][key] += 1
                    if kind == "caught and bowled":
                        players[bowler]["field"]["catches"] += 1


def load_variants(names_csv: Path):
    """{person id: [other names they're known by]} from the register's names.csv."""
    out = defaultdict(list)
    if names_csv and Path(names_csv).exists():
        with open(names_csv, encoding="utf-8", newline="") as f:
            for r in csv.DictReader(f):
                out[r["identifier"]].append(r["name"])
    return out


def _split(name):
    """("MA", "Starc") for "MA Starc"; ("", name) when it isn't initials + surname."""
    parts = name.split()
    if len(parts) >= 2 and re.fullmatch(r"[A-Z]{1,4}", parts[0]):
        return parts[0], " ".join(parts[1:])
    return "", name


def _norm(name):
    """Lower case, hyphens and dots as spaces, single spaces: "Imam-ul-Haq" -> "imam ul haq"."""
    return " ".join(re.sub(r"[-.]", " ", name).lower().split())


def match_players(entries, variants, rows):
    """Links Cricsheet people to rows of the players dataset, within the country they played
    for. In order: the exact full name; one name being the start of the other ("Mahmudullah",
    "Mohammad Wasim Jr"); surname + first initial (Cricsheet mostly writes "MA Starc"), using
    further initials against middle names when there's a choice; surname + any of the initials
    (Sri Lankan initials list every given name: "PHKD Mendis" is Kamindu Mendis). Ties go to
    a real profile photo, then the lowest id. Returns {person id: row}."""
    def rank(r):
        return ("placeholder" in r["image_path"], int(r["id"]))
    by_country = defaultdict(list)
    for r in rows:
        by_country[r["country_name"]].append(r)
    matched = {}
    for pid, e in entries.items():
        country = e["teams"].most_common(1)[0][0] if e["teams"] else ""
        pool = by_country.get(country, [])
        if not pool:
            continue
        names = sorted(e["names"]) + variants.get(pid, [])
        wanted = {_norm(n) for n in names}
        hits = [r for r in pool if _norm(r["fullname"]) in wanted]
        if not hits:
            hits = [r for r in pool for w in wanted if " " in w or len(w) > 6
                    if _norm(r["fullname"]).startswith(w + " ") or w.startswith(_norm(r["fullname"]) + " ")]
        for strict in (True, False):
            if hits:
                break
            for n in names:
                initials, surname = _split(n)
                if not initials:
                    continue
                tail = " " + _norm(surname)
                same_surname = [r for r in pool if _norm(r["fullname"]).endswith(tail)]
                if strict:
                    hits = [r for r in same_surname if r["firstname"][:1].upper() == initials[0]]
                    if len(hits) > 1 and len(initials) > 1:  # use middle initials to choose
                        def initials_of(r):
                            return "".join(g[0].upper() for g in _norm(r["fullname"])[: -len(tail)].split())
                        hits = [r for r in hits if initials_of(r).startswith(initials)] or hits
                else:
                    hits = [r for r in same_surname if r["firstname"][:1].upper() in initials]
                if hits:
                    break
        if hits:
            matched[pid] = min(hits, key=rank)
    return matched


def vs_spin(pairs, spinners):
    """{batter id: {format: Counter(balls, runs, outs)}} against bowlers in `spinners`."""
    out = defaultdict(lambda: defaultdict(Counter))
    for (batter, bowler, fmt), c in pairs.items():
        if bowler in spinners:
            out[batter][fmt].update(c)
    return out


def appearances(entry) -> int:
    return sum(entry["matches"].values())


def _blend(estimates, n, k, current):
    total = sum(w for _, w in estimates)
    if total <= 0:
        return None
    stat = max(1.0, min(20.0, sum(v * w for v, w in estimates) / total))
    share = n / (n + k)
    return max(1, min(20, round(share * stat + (1 - share) * float(current))))


def ratings(entry, spin_record, current, is_keeper):
    """New values for every attribute the numbers speak to, blended with the current ones by
    how many balls they're based on. Each figure is judged against par for its format."""
    est = defaultdict(list)
    bat_balls = bowl_balls = bat_runs = 0
    for fmt, c in entry["bat"].items():
        if fmt not in PAR or c["balls"] < MIN_BALLS:
            continue
        par, w = PAR[fmt], c["balls"] * FORMAT_WEIGHT[fmt]
        bat_balls += c["balls"]
        avg = c["runs"] / max(c["outs"], 1)
        sr = 100 * c["runs"] / c["balls"]
        est["technique"].append((BAT_PAR_RATING + (avg / par["avg"] - 1) * 6, w))
        est["timing"].append((BAT_PAR_RATING + (sr / par["sr"] - 1) * 16, w))
        est["concentration"].append((BAT_PAR_RATING + (c["balls"] / max(c["outs"], 1) / par["balls_per_out"] - 1) * 6, w))
        est["aggression"].append((BAT_PAR_RATING - 0.5 + (par["dot"] - 100 * c["dots"] / c["balls"]) * 0.3 + (sr / par["sr"] - 1) * 10, w))
        boundary_share = 100 * (4 * c["fours"] + 6 * c["sixes"]) / max(c["runs"], 1)
        six_rate = 100 * c["sixes"] / c["balls"]
        est["power"].append((BAT_PAR_RATING - 1.5 + (boundary_share - par["boundary_share"]) * 0.2
                             + (min(six_rate / par["six_rate"], 2.5) - 1) * 4, w))
        bat_runs += c["runs"]
        if c["running_balls"] >= 20:
            est["running"].append((10 + (c["running_runs"] / c["running_balls"] - 0.55) * 20, w))
        if fmt in DEATH_FROM and c["death_balls"] >= 20:
            est["composure"].append((BAT_PAR_RATING + (100 * c["death_runs"] / c["death_balls"] / par["death_sr"] - 1) * 15, w))
    for fmt, c in spin_record.items():
        if fmt in PAR and c["balls"] >= 30:
            par, w = PAR[fmt], c["balls"] * FORMAT_WEIGHT[fmt]
            avg = c["runs"] / max(c["outs"], 1)
            sr = 100 * c["runs"] / c["balls"]
            est["vs_spin"].append((BAT_PAR_RATING + (avg / par["avg"] - 1) * 5 + (sr / par["sr"] - 1) * 12, w))
    for fmt, c in entry["bowl"].items():
        if fmt not in PAR or c["balls"] < MIN_BALLS:
            continue
        par, w = PAR[fmt], c["balls"] * FORMAT_WEIGHT[fmt]
        bowl_balls += c["balls"]
        econ = 6 * c["runs"] / c["balls"]
        strike = c["balls"] / c["wickets"] if c["wickets"] else par["bowl_sr"] * 2
        average = c["runs"] / c["wickets"] if c["wickets"] else par["bowl_avg"] * 2
        dots = 100 * c["dots"] / c["balls"]
        base = BOWL_PAR_RATING
        est["accuracy"].append((base + (1 - econ / par["econ"]) * 28 + (dots - par["bowl_dot"]) * 0.15, w))
        est["movement"].append((base + (1 - strike / par["bowl_sr"]) * 16, w))
        est["variation"].append((base + (1 - average / par["bowl_avg"]) * 12, w))
        if fmt in DEATH_FROM and c["death_balls"] >= 30:
            death_econ = 6 * c["death_runs"] / c["death_balls"]
            est["variation"].append((base + (1 - death_econ / par["death_econ"]) * 20, w * 0.5))
    matches = sum(entry["matches"].values())
    if matches >= 5:
        per_match = entry["field"]["catches"] / matches
        if is_keeper:
            dismissals = (entry["field"]["catches"] + entry["field"]["stumpings"] * 1.5) / matches
            est["keeping"].append((10 + dismissals * 4, 1))
        else:
            est["catching"].append((10 + (per_match - 0.35) * 10, 1))
        est["fielding"].append((10 + entry["field"]["run_outs"] / matches * 25, 1))

    out = {}
    for attr, values in est.items():
        if attr in BOWLING_ATTRS:
            n, k = bowl_balls, BOWL_SHRINK
        elif attr in ("catching", "keeping", "fielding"):
            n, k = matches, 25
        elif attr == "power":
            n, k = bat_runs, POWER_SHRINK_RUNS
        else:
            n, k = bat_balls, BAT_SHRINK
        value = _blend(values, n, k, current.get(attr, 10))
        if value is not None:
            out[attr] = value
    return out
