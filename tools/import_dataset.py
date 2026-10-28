"""Builds data/teams.json (and data/names.json) from the cricket-players-2023 dataset.

The dataset (players_data_with_all_info.csv + teams.csv, as a .zip or a folder) has
biographical data only: name, date of birth, gender, batting hand, bowling style, position
and country. So this script takes real names, ages, handedness, bowling styles and roles from
it, and builds one team per country with a balanced 16-player squad. It has no performance
stats, so skill attributes are generated from each player's role (seeded by player id, so
reruns give the same numbers). To use real ratings, pass --ratings with a CSV of your own:
an `id` column (the dataset's player id) plus any attribute columns (technique, timing,
power, vs_spin, running, accuracy, movement, speed, variation, catching, fielding, keeping,
composure, concentration, aggression, stamina) on the game's 1-20 scale.

Examples (from the project root):
  py -3 tools/import_dataset.py "%USERPROFILE%\\Downloads\\cricket-players-2023.zip"
  py -3 tools/import_dataset.py data.zip --teams 10
  py -3 tools/import_dataset.py data.zip --countries "India,England,Australia,New Zealand"
  py -3 tools/import_dataset.py data.zip --gender f --ratings my_ratings.csv

The existing teams.json is copied to a dated teams.backup-<time>.json first. Start a new career in the game
to use the new data (existing careers keep their own copy of the database).
"""

import argparse
import colorsys
import csv
import io
import json
import random
import shutil
import sys
import zipfile
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_teams import ATTRS, dump  # noqa: E402  (same file layout as the generator)
from ratings import backup_path, read_ratings  # noqa: E402
import stats_import  # noqa: E402
import cricsheet_import  # noqa: E402

# Bowling styles (from the players dataset) that count as spin for batting-v-spin ratings.
SPIN_STYLES = ("offbreak", "legbreak", "orthodox", "chinaman", "googly")

ROOT = Path(__file__).resolve().parent.parent
PLAYERS_CSV = "players_data_with_all_info.csv"
TEAMS_CSV = "teams.csv"
SEASON_START = (4, 4)  # the game's season opens on 4 April

# Squad make-up by role (16 players): the game wants a keeper and 5+ bowling options.
SQUAD_PLAN = [("keeper", 2), ("batter", 5), ("all_rounder", 4), ("bowler", 5)]
MIN_SQUAD = 14

POSITION_ROLE = {
    "Batsman": "batter", "Top Order Batter": "batter", "Middle Order Batter": "batter",
    "Bowler": "bowler",
    "Allrounder": "all_rounder", "Batting Allrounder": "all_rounder", "Bowling Allrounder": "all_rounder",
    "Wicketkeeper": "keeper",
}
# bowlingstyle -> (game style, bowling arm, pace band for the speed attribute)
BOWLING_STYLE = {
    "right-arm-fast": ("pace", "right", (15, 18)),
    "right-arm-fast-medium": ("pace", "right", (12, 15)),
    "left-arm-fast": ("pace", "left", (15, 18)),
    "left-arm-fast-medium": ("pace", "left", (12, 15)),
    "right-arm-offbreak": ("off_spin", "right", (4, 7)),
    "slow-right-arm-orthodox": ("off_spin", "right", (4, 7)),
    "legbreak": ("leg_spin", "right", (4, 7)),
    "legbreak-googly": ("leg_spin", "right", (4, 7)),
    "slow-left-arm-orthodox": ("left_arm_spin", "left", (4, 7)),
    "left-arm-chinaman": ("leg_spin", "left", (4, 7)),
    "": ("medium", "right", (6, 10)),  # no recorded style: a part-time trundler at most
}
# Home pitches follow the climate of the country's continent.
CONTINENT_PITCH = {"Asia": "dusty", "Europe": "green", "Oceania": "flat", "Africa": "flat"}

# Generated attribute ranges by role: (batting skills, bowling skills).
HIGH, MID, LOW, NONE = (11, 16), (9, 14), (4, 8), (2, 5)
ROLE_RANGES = {
    "batter": (HIGH, LOW),
    "keeper": (MID, NONE),
    "all_rounder": (MID, MID),
    "bowler": (LOW, HIGH),
}


def read_dataset(source: Path):
    """Returns (player rows, team rows) from a .zip or a folder holding the two CSVs."""
    def load(name, opener):
        with opener(name) as f:
            return list(csv.DictReader(io.TextIOWrapper(f, encoding="utf-8", newline="")))
    if source.suffix.lower() == ".zip":
        with zipfile.ZipFile(source) as z:
            names = {Path(n).name: n for n in z.namelist()}
            if PLAYERS_CSV not in names:
                sys.exit(f"{source} has no {PLAYERS_CSV}")
            players = load(names[PLAYERS_CSV], z.open)
            teams = load(names[TEAMS_CSV], z.open) if TEAMS_CSV in names else []
        return players, teams
    players = load(source / PLAYERS_CSV, lambda p: open(p, "rb"))
    teams_path = source / TEAMS_CSV
    teams = load(teams_path, lambda p: open(p, "rb")) if teams_path.exists() else []
    return players, teams


def age_at_season(dob: str, year: int) -> int:
    day, month, born = map(int, dob.split("-"))
    return year - born - (SEASON_START < (month, day))


def roll(rng, lo_hi, bonus):
    lo, hi = lo_hi
    return max(1, min(20, round(rng.uniform(lo, hi) + bonus)))


def make_player(row, role, age, standing):
    """Maps a dataset row to the game's player format, generating attributes by role.
    standing (-1..1) is how established the player is within their squad; better-known
    players get better attributes, plus some seeded noise."""
    style, arm, speed = BOWLING_STYLE.get(row["bowlingstyle"], BOWLING_STYLE[""])
    pid = int(row["id"])
    rng = random.Random(pid * 2654435761)
    bonus = standing * 1.3 + rng.uniform(-0.6, 0.6)  # this player's overall quality
    bat_range, bowl_range = ROLE_RANGES[role]
    if not row["bowlingstyle"]:
        bowl_range = NONE if role in ("batter", "keeper") else LOW
    a = {}
    for k in ["technique", "timing", "power", "vs_spin", "running"]:
        a[k] = roll(rng, bat_range, bonus)
    for k in ["accuracy", "movement", "variation"]:
        a[k] = roll(rng, bowl_range, bonus)
    a["speed"] = roll(rng, speed, 0)
    a["catching"] = roll(rng, (9, 14), bonus)
    a["fielding"] = roll(rng, (9, 15), bonus)
    a["keeping"] = roll(rng, (12, 16), bonus) if role == "keeper" else rng.randint(1, 3)
    for k in ["composure", "concentration"]:
        a[k] = roll(rng, (9, 15), bonus)
    a["aggression"] = rng.randint(6, 18)
    a["stamina"] = max(1, min(20, round(rng.uniform(10, 16) - max(age - 32, 0) * 0.5)))
    if role == "bowler" and style == "pace":
        a["stamina"] = min(20, a["stamina"] + 1)
    return {
        "id": pid,
        "name": row["fullname"].strip() or f"{row['firstname']} {row['lastname']}".strip(),
        "age": age,
        "bats": "left" if row["battingstyle"] == "left-hand-bat" else "right",
        "bowls": arm,
        "role": role,
        "style": style,
        "attributes": {k: a[k] for k in ATTRS},
    }


def prominence(r):
    """How established a player is, from the dataset's only hints: a real profile photo
    (most minor players have a placeholder), a recorded batting style, and a low id (the
    dataset added international players first). Higher sorts first. A missing bowling style
    isn't held against anyone: specialist batters and keepers often have none."""
    has_photo = "placeholder" not in r["image_path"] and r["image_path"] != ""
    return (has_photo, bool(r["battingstyle"]), -int(r["id"]))


def pick_squad(rows, size, key=prominence):
    """A balanced squad of the players ranked highest by key (default: most established)."""
    by_role = {role: [] for role, _ in SQUAD_PLAN}
    for r in sorted(rows, key=key, reverse=True):
        by_role[POSITION_ROLE.get(r["position"], "batter")].append(r)

    squad = []
    for role, count in SQUAD_PLAN:
        pool = by_role[role]
        if role == "bowler":  # a mix of pace and spin where the country has both
            spin = [r for r in pool if "spin" in BOWLING_STYLE.get(r["bowlingstyle"], ("",))[0]]
            pace = [r for r in pool if r not in spin]
            chosen = spin[:2] + pace[: count - min(2, len(spin))]
            chosen += [r for r in pool if r not in chosen][: count - len(chosen)]
        else:
            chosen = pool[:count]
        squad += [(r, role) for r in chosen]
    # Short of a role (small countries): fill up with the best remaining profiles.
    taken = {r["id"] for r, _ in squad}
    leftovers = sorted((r for r in rows if r["id"] not in taken), key=key, reverse=True)
    squad += [(r, POSITION_ROLE.get(r["position"], "batter")) for r in leftovers[: size - len(squad)]]
    return squad[:size]


def is_bowling_option(p):
    return p["role"] == "bowler" or (p["role"] == "all_rounder" and p["style"] != "medium")


def team_colours(n):
    out = []
    for i in range(n):
        r, g, b = colorsys.hsv_to_rgb(i / n, 0.7, 0.85)
        out.append("#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255)))
    return out


def short_code(name, codes, used):
    code = codes.get(name) or "".join(w[0] for w in name.split()[:3]).upper()
    if len(code) < 3:
        code = name.replace(" ", "")[:3].upper()
    base, n = code, 2
    while code in used:
        code = f"{base[:2]}{n}"
        n += 1
    used.add(code)
    return code


def apply_ratings(teams, path):
    """Overrides generated attributes with the user's own ratings, by player id (the same
    file format tools/ratings.py writes). Bad cells are reported and skipped."""
    ratings, problems = read_ratings(path)
    applied = 0
    for t in teams:
        for p in t["players"]:
            if p["id"] in ratings:
                p["attributes"].update(ratings[p["id"]])
                applied += 1
    for problem in problems:
        print("  ratings: " + problem)
    return applied


BAT_ATTRS = ["technique", "timing", "power", "composure", "concentration"]
BOWL_ATTRS = ["accuracy", "movement", "variation"]


def _strength(team, attrs, weights, top):
    scores = sorted((sum(p["attributes"][a] * w for a, w in zip(attrs, weights)) for p in team["players"]), reverse=True)
    return sum(scores[:top]) / top


def level_unrated_teams(teams, rated_ids):
    """Teams with no data-rated players (e.g. Afghanistan, which Cricsheet doesn't cover) keep
    generated ratings, which sit on a different scale. Shift their batting and bowling
    attributes so their best XI matches the average data-rated team, instead of being better
    or worse by accident."""
    bat_w, bowl_w = [0.35, 0.3, 0.15, 0.1, 0.1], [0.4, 0.3, 0.15]
    rated = [t for t in teams if sum(p["id"] in rated_ids for p in t["players"]) >= 8]
    unrated = [t for t in teams if not any(p["id"] in rated_ids for p in t["players"])]
    if not rated or not unrated:
        return
    bat_target = sum(_strength(t, BAT_ATTRS, bat_w, 7) for t in rated) / len(rated)
    bowl_target = sum(_strength(t, BOWL_ATTRS, bowl_w, 5) for t in rated) / len(rated)
    for t in unrated:
        bat_shift = bat_target - _strength(t, BAT_ATTRS, bat_w, 7)
        bowl_shift = (bowl_target - _strength(t, BOWL_ATTRS, bowl_w, 5)) / sum(bowl_w)
        for p in t["players"]:
            for a in BAT_ATTRS:
                p["attributes"][a] = max(1, min(20, round(p["attributes"][a] + bat_shift)))
            for a in BOWL_ATTRS:
                p["attributes"][a] = max(1, min(20, round(p["attributes"][a] + bowl_shift)))
        print(f"{t['name']} has no data: levelled to the average data-rated team "
              f"(batting {bat_shift:+.1f}, bowling {bowl_shift:+.1f})")


def validate(teams):
    """Prints a per-team report and returns a list of problems the game would trip over."""
    problems = []
    ids = [p["id"] for t in teams for p in t["players"]]
    if len(ids) != len(set(ids)):
        problems.append("duplicate player ids")
    print(f"\n{'Team':24} {'Code':5} {'Pitch':9} {'Squad':>5} {'Keep':>5} {'Bowl':>5} {'Spin':>5} {'LHB':>4} {'Age':>5}")
    for t in teams:
        ps = t["players"]
        keepers = sum(p["role"] == "keeper" for p in ps)
        bowlers = sum(is_bowling_option(p) for p in ps)
        spin = sum("spin" in p["style"] for p in ps)
        lefties = sum(p["bats"] == "left" for p in ps)
        avg_age = sum(p["age"] for p in ps) / len(ps)
        print(f"{t['name'][:24]:24} {t['short']:5} {t['pitch']:9} {len(ps):5} {keepers:5} {bowlers:5} {spin:5} {lefties:4} {avg_age:5.1f}")
        if len(ps) < MIN_SQUAD:
            problems.append(f"{t['name']}: only {len(ps)} players (the game wants {MIN_SQUAD}+)")
        if keepers == 0:
            problems.append(f"{t['name']}: no wicketkeeper")
        if bowlers < 5:
            problems.append(f"{t['name']}: only {bowlers} bowling options")
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("source", type=Path, help="the dataset .zip, or a folder with the CSVs")
    parser.add_argument("--teams", type=int, default=8, help="how many countries (default 8, most complete profiles first)")
    parser.add_argument("--countries", help="comma-separated country names instead of --teams")
    parser.add_argument("--gender", choices=["m", "f"], default="m")
    parser.add_argument("--squad", type=int, default=16, help="players per team (default 16, max 18)")
    parser.add_argument("--min-age", type=int, default=18)
    parser.add_argument("--max-age", type=int, default=38)
    parser.add_argument("--season-year", type=int, default=2026, help="ages are worked out for this season")
    parser.add_argument("--cricsheet", type=Path,
                        help="folder with Cricsheet *_json.zip files (+ register names.csv): rates players from "
                             "ball-by-ball data and picks squads from who has played recently")
    parser.add_argument("--since", default="2022-01-01", help="Cricsheet matches from this date (default 2022-01-01)")
    parser.add_argument("--stats", type=Path,
                        help="match stats (batsman.csv + bowlers.csv, .zip or folder): rates the players in it "
                             "from their numbers, and builds their country's squad around them")
    parser.add_argument("--ratings", type=Path, help="CSV of your own ratings to apply by player id (applied last)")
    parser.add_argument("--show", type=int, default=25, help="how many rated players to list (default 25)")
    parser.add_argument("--out", type=Path, default=ROOT / "data" / "teams.json")
    parser.add_argument("--names-out", type=Path, default=ROOT / "data" / "names.json",
                        help="youth name pools from the chosen countries ('' to skip)")
    args = parser.parse_args()
    args.squad = max(MIN_SQUAD, min(18, args.squad))

    players, team_rows = read_dataset(args.source)
    codes = {r["name"]: r["code"] for r in team_rows if r.get("code")}
    eligible = []
    for r in players:
        if r["gender"] != args.gender or not r["dateofbirth"]:
            continue
        try:
            age = age_at_season(r["dateofbirth"], args.season_year)
        except ValueError:
            continue
        if args.min_age <= age <= args.max_age:
            eligible.append((r, age))
    print(f"{len(players)} players in the dataset, {len(eligible)} eligible "
          f"({'men' if args.gender == 'm' else 'women'} aged {args.min_age}-{args.max_age} in {args.season_year})")

    by_country = {}
    for r, age in eligible:
        by_country.setdefault(r["country_name"], []).append(r)
    ages = {r["id"]: age for r, age in eligible}
    if args.countries:
        chosen = [c.strip() for c in args.countries.split(",") if c.strip()]
        missing = [c for c in chosen if c not in by_country]
        if missing:
            sys.exit(f"No eligible players for: {', '.join(missing)}. Countries available: "
                     + ", ".join(sorted(by_country)))
    else:
        complete = Counter(r["country_name"] for r, _ in eligible if r["battingstyle"] and r["bowlingstyle"])
        chosen = [c for c, _ in complete.most_common(args.teams)]
    if len(chosen) < 2:
        sys.exit("The game needs at least 2 teams")

    # Match stats: who they cover, and how often each player appears (the best hint at who
    # plays regularly now). Their country's squad is picked by appearances first.
    stats_by_id, played = {}, {}
    if args.stats:
        bat, bowl, notes = stats_import.clean(*stats_import.read_stats(args.stats))
        agg = stats_import.aggregate(bat, bowl)
        pool = [r for r, _ in eligible]
        matched, unmatched, stats_country = stats_import.match_players(sorted(agg), pool)
        for name, row in matched.items():
            stats_by_id[row["id"]] = agg[name]
            played[row["id"]] = stats_import.appearances(agg[name])
        print(f"Stats: {len(bat)} batting innings and {len(bowl)} bowling spells for {len(agg)} players, "
              f"{len(matched)} matched ({stats_country})")
        for note, n in sorted(notes.items()):
            print(f"  cleaned: {note}: {n}")
        if unmatched:
            print(f"  not matched (not in the dataset, or outside the age range): {', '.join(unmatched)}")

    # Cricsheet: ball-by-ball data for every international since --since. Takes priority over
    # --stats for players in both.
    cs_by_id, cs_played, cs_spin = {}, {}, {}
    if args.cricsheet:
        cs_players, pairs, read = cricsheet_import.load(args.cricsheet, args.since)
        variants = cricsheet_import.load_variants(args.cricsheet / "names.csv")
        matched = cricsheet_import.match_players(cs_players, variants, [r for r, _ in eligible])
        spinners = {pid for pid, row in matched.items() if any(s in row["bowlingstyle"] for s in SPIN_STYLES)}
        spin_records = cricsheet_import.vs_spin(pairs, spinners)
        for pid, row in matched.items():
            cs_by_id[row["id"]] = cs_players[pid]
            cs_played[row["id"]] = cricsheet_import.appearances(cs_players[pid])
            cs_spin[row["id"]] = spin_records.get(pid, {})
        in_chosen = [pid for pid, e in cs_players.items() if e["teams"] and e["teams"].most_common(1)[0][0] in chosen]
        print(f"Cricsheet: {sum(read.values())} international matches since {args.since} "
              f"({', '.join(f'{n} {f}' for f, n in sorted(read.items()))}); matched "
              f"{sum(1 for pid in in_chosen if pid in matched)} of {len(in_chosen)} players from the chosen countries")

    def squad_key(r):
        return (cs_played.get(r["id"], 0), played.get(r["id"], 0), prominence(r))

    colours = team_colours(len(chosen))
    used_codes = set()
    teams = []
    rated = []
    for i, country in enumerate(chosen):
        rows = by_country[country]
        continent = Counter(r["continent_name"] for r in rows).most_common(1)[0][0]
        squad = pick_squad(rows, args.squad, squad_key)
        ranked = sorted((r for r, _ in squad), key=squad_key, reverse=True)
        standing = {r["id"]: 1.0 - 2.0 * i / max(len(ranked) - 1, 1) for i, r in enumerate(ranked)}
        team_players = [make_player(r, role, ages[r["id"]], standing[r["id"]]) for r, role in squad]
        for p in team_players:
            pid = str(p["id"])
            before = dict(p["attributes"])
            if pid in cs_by_id:
                p["attributes"].update(cricsheet_import.ratings(cs_by_id[pid], cs_spin[pid], p["attributes"],
                                                                p["role"] == "keeper"))
                rated.append((p, before, cs_played[pid], "Cricsheet"))
            elif pid in stats_by_id:
                p["attributes"].update(stats_import.ratings(stats_by_id[pid], p["attributes"]))
                rated.append((p, before, played[pid], "stats"))
        # First 11 = a sensible default XI: batters, keeper, all-rounders, bowlers; then reserves.
        order = {"batter": 0, "keeper": 1, "all_rounder": 2, "bowler": 3}
        xi, reserves, seen = [], [], Counter()
        for p in team_players:
            limit = {"batter": 4, "keeper": 1, "all_rounder": 2, "bowler": 4}[p["role"]]
            (xi if seen[p["role"]] < limit else reserves).append(p)
            seen[p["role"]] += 1
        xi.sort(key=lambda p: order[p["role"]])
        teams.append({"name": country, "short": short_code(country, codes, used_codes), "colour": colours[i],
                      "pitch": CONTINENT_PITCH.get(continent, "balanced"), "players": (xi + reserves)})

    if rated:
        level_unrated_teams(teams, {p["id"] for p, *_ in rated})
        sources = Counter(source for *_, source in rated)
        print(f"\nRated from data: {', '.join(f'{n} from {s}' for s, n in sources.items())} "
              f"(of {sum(len(t['players']) for t in teams)} players); the rest keep generated ratings")
        print(f"  {'Player':22} {'Team':5} {'Apps':>4}  {'Tech':>7} {'Timing':>7} {'Power':>7} {'Acc':>7} {'Move':>7} {'Var':>7}")
        team_of = {p["id"]: t["short"] for t in teams for p in t["players"]}
        shown = sorted(rated, key=lambda x: -x[2])[: args.show]
        for p, before, n, _ in shown:
            cells = [f"{before[a]:>2}->{p['attributes'][a]:<2}" for a in
                     ["technique", "timing", "power", "accuracy", "movement", "variation"]]
            print(f"  {p['name'][:22]:22} {team_of[p['id']]:5} {n:4}  " + " ".join(f"{c:>7}" for c in cells))
        if len(rated) > len(shown):
            print(f"  ... and {len(rated) - len(shown)} more (--show N to list more)")

    if args.ratings:
        print(f"Applied your ratings to {apply_ratings(teams, args.ratings)} players")

    problems = validate(teams)
    if problems:
        print("\nProblems:")
        for p in problems:
            print("  - " + p)

    if args.out.exists():
        backup = backup_path(args.out)
        shutil.copyfile(args.out, backup)
        print(f"\nBacked up the old file to {backup}")
    credits = [cricsheet_import.CREDIT] if cs_by_id else []
    args.out.write_text(dump({"credits": credits, "teams": teams}), encoding="utf-8")
    print(f"Wrote {len(teams)} teams, {sum(len(t['players']) for t in teams)} players to {args.out}")

    if str(args.names_out):
        def pools(rows):
            return {"first": sorted({r["firstname"].strip() for r in rows if r["firstname"].strip()}),
                    "last": sorted({r["lastname"].strip() for r in rows if r["lastname"].strip()})}
        everyone = pools([r for c in chosen for r in by_country[c]])
        args.names_out.write_text(json.dumps({
            "_comment": "Youth name pools from the dataset: per team under by_team, with first/last as the "
                        "fallback for any team not listed. Edit freely.",
            **everyone,
            "by_team": {c: pools(by_country[c]) for c in chosen}}, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"Wrote youth name pools for {len(chosen)} teams to {args.names_out}")
    print("Start a new career in the game to play with this data.")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
