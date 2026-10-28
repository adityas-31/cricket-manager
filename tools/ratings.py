"""Exports player ratings to a spreadsheet you can edit, and applies the edits back.

  py -3 tools/ratings.py template            writes data/ratings/ratings.csv from data/teams.json
  py -3 tools/ratings.py apply               applies data/ratings/ratings.csv to data/teams.json

The template has one row per player: id, name, team, role, style, bats, bowls and age for
reference (only id is read back), then every attribute pre-filled with its current value on
the game's 1-20 scale. Change any numbers in Excel, Google Sheets or a text editor; blank
cells keep the current value. Apply writes them into teams.json (backing it up first), or
pass the same file to the importer to rebuild from the dataset with your ratings on top:

  py -3 tools/import_dataset.py <dataset.zip> --ratings data/ratings/ratings.csv

Attributes:
  Batting   technique, timing, power, vs_spin, running
  Bowling   accuracy, movement, speed (pace), variation
  Fielding  catching, fielding, keeping
  Mental    composure, concentration, aggression
  Physical  stamina
"""

import argparse
import csv
import json
import shutil
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_teams import ATTRS, dump  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
INFO = ["id", "name", "team", "role", "style", "bats", "bowls", "age"]


def backup_path(path: Path) -> Path:
    """A dated name next to the file, so earlier backups are never overwritten."""
    return path.with_name(f"{path.stem}.backup-{datetime.now():%Y%m%d-%H%M%S}.json")


def load_teams(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_template(teams_path: Path, out: Path) -> None:
    data = load_teams(teams_path)
    rows = 0
    out.parent.mkdir(parents=True, exist_ok=True)
    # utf-8-sig so Excel shows accented names correctly
    with open(out, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(INFO + ATTRS)
        for t in data["teams"]:
            for p in t["players"]:
                info = [p["id"], p["name"], t["name"], p.get("role", ""), p.get("style", ""),
                        p.get("bats", "right"), p.get("bowls", "right"), p.get("age", "")]
                w.writerow(info + [round(float(p["attributes"].get(a, 8))) for a in ATTRS])
                rows += 1
    print(f"Wrote {rows} players to {out}")


def read_ratings(path: Path) -> tuple[dict, list]:
    """{player id: {attribute: value}} from the CSV, plus a list of problems found."""
    ratings, problems = {}, []
    with open(path, encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        unknown = [c for c in (reader.fieldnames or []) if c not in INFO + ATTRS]
        if unknown:
            problems.append(f"ignored unknown columns: {', '.join(unknown)}")
        for line, row in enumerate(reader, start=2):
            pid = (row.get("id") or "").strip()
            if not pid.isdigit():
                problems.append(f"line {line}: no valid id")
                continue
            values = {}
            for a in ATTRS:
                cell = (row.get(a) or "").strip()
                if not cell:
                    continue
                try:
                    v = float(cell)
                except ValueError:
                    problems.append(f"line {line} ({row.get('name', pid)}): {a} = {cell!r} is not a number")
                    continue
                if not 1 <= v <= 20:
                    problems.append(f"line {line} ({row.get('name', pid)}): {a} = {cell} clamped to 1-20")
                values[a] = max(1, min(20, round(v)))
            ratings[int(pid)] = values
    return ratings, problems


def apply(teams_path: Path, ratings_path: Path) -> int:
    ratings, problems = read_ratings(ratings_path)
    data = load_teams(teams_path)
    changed, players, matched = 0, 0, set()
    for t in data["teams"]:
        for p in t["players"]:
            players += 1
            new = ratings.get(p["id"])
            if new is None:
                continue
            matched.add(p["id"])
            for a, v in new.items():
                if p["attributes"].get(a) != v:
                    p["attributes"][a] = v
                    changed += 1
    missing = sorted(set(ratings) - matched)
    if missing:
        problems.append(f"{len(missing)} ids not in {teams_path.name}: {', '.join(map(str, missing[:10]))}"
                        + (" ..." if len(missing) > 10 else ""))
    backup = backup_path(teams_path)
    shutil.copyfile(teams_path, backup)
    teams_path.write_text(dump(data), encoding="utf-8")
    print(f"Matched {len(matched)} of {players} players; changed {changed} attribute values.")
    print(f"Backed up the old file to {backup}; wrote {teams_path}")
    for p in problems:
        print("  - " + p)
    print("Start a new career in the game to use the new ratings.")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0],
                                     formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    parser.add_argument("command", choices=["template", "apply"])
    parser.add_argument("--teams", type=Path, default=ROOT / "data" / "teams.json")
    parser.add_argument("--csv", type=Path, default=ROOT / "data" / "ratings" / "ratings.csv")
    args = parser.parse_args()
    if args.command == "template":
        write_template(args.teams, args.csv)
        return 0
    if not args.csv.exists():
        sys.exit(f"No ratings file at {args.csv}; run `template` first")
    return apply(args.teams, args.csv)


if __name__ == "__main__":
    sys.exit(main())
