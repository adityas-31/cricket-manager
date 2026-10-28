# Cricket Manager

A standalone cricket management game in Godot 4.6 with an FM24-style interface: an
eight-team T20 league season with a ball-by-ball match engine, tactics, player form and
fitness, a league table, play-offs, news, and autosaving.

## Running

Open `project.godot` in Godot 4.6.1 and press F5, or:

```
"%USERPROFILE%\Downloads\Godot_v4.6.1-stable_win64\Godot_v4.6.1-stable_win64.exe" --path .
```

### The Windows build

`build/CricketManager.exe` is a standalone build (about 100 MB, everything inside it): double-
click it. Windows may show a SmartScreen warning because the exe isn't code-signed; choose
"More info" then "Run anyway". Rebuild it after changing the game or the data:

```
"%USERPROFILE%\Downloads\Godot_v4.6.1-stable_win64\Godot_v4.6.1-stable_win64_console.exe" --headless --path . --export-release "Windows Desktop" build/CricketManager.exe
```

This needs Godot's 4.6.1 Windows export templates in `%APPDATA%\Godot\export_templates\4.6.1.stable\`
(from the export templates package on Godot's download page). `build/` isn't in git. The build
and the editor share the same save and logs, in `%APPDATA%\Godot\app_userdata\Cricket Manager\`.

### Play log and notes

Every session writes a play log to `%APPDATA%\Godot\app_userdata\Cricket Manager\logs\`
(`session-<date>-<time>.jsonl`, the newest 30 kept). Nothing is sent anywhere; it's there to
read back when reviewing a play-test. Each line is one JSON event:

- `session_start` / `session_end`: version, build, OS, club, date.
- `screen`, `advance`, `new_season`, `new_career`: moving around and through the calendar.
- `match_start` / `match_end`: teams, toss, your XI, the result and scores, player of the
  match, super overs, and a count of your in-match decisions.
- `decision`: each in-match choice (batting/bowling approach, field, moved fielder, next
  bowler, next batter, DRS review taken or not, and whether the call was really wrong), with
  the over and score.
- `result` (every fixture in the league), `injury`, `selection`, `bid`, `bid_received`,
  `bid_rejected`, `transfer`, `renewal`, `season_review`.
- `error`, `warning`, `script_error`: any engine or script error, with file, line and
  backtrace.
- `note`: press **F8** (or **Note** in the top bar) to write a note; it's saved with the screen,
  date, league position and, on Match Day, the score and last ball.

Godot's own console log is kept alongside as `godot.log`. Pass `--no-log` after `--` to run
without a play log.

**Continue** (top right) drives the game like FM's. On a day your club plays it takes you
to Tactics first: pick the XI and plan, then **Start Match** opens Match Day, where Continue
plays and pauses the match (Next Ball / Next Over / Sim to End step through it; the Speed
slider runs faster to the right). Play stops at the innings break until you press **Start 2nd
Innings**. When the match ends the Report tab opens (result, key performances, ratings, league
position, next match, the squad's condition and injuries); **Done** plays the day's other
fixtures, runs training up to the next match day and goes back to Home. Start a career with
another club from Home.

Command-line extras go after `--`: `--squad`, `--tactics`, `--training`, `--fixtures`, `--competition` or
`--match` opens that screen, `--demo` auto-plays Match Day fast, and `--save=user://x.json`
uses another career file.

## Building your own database (`data/teams.json`)

All player and team data lives in `data/teams.json`; nothing is hardcoded in the game. Replace
or edit it freely. The shape:

```json
{"teams": [
  {"name": "Northbridge Royals", "short": "NBR", "colour": "#e53935", "pitch": "balanced",
   "players": [
     {"id": 101, "name": "Arjun Mehta", "age": 28, "role": "batter", "style": "medium",
      "attributes": {"technique": 15, "timing": 15, "power": 11, "vs_spin": 13, "running": 13,
                     "accuracy": 5, "movement": 4, "speed": 6, "variation": 4,
                     "catching": 12, "fielding": 13, "keeping": 3,
                     "composure": 14, "concentration": 15, "aggression": 10, "stamina": 14}}
   ]}
]}
```

- **Team**: `name`, `short` (3 letters, defaults to the name's first three), `colour` (hex; the
  manager's club colour tints the whole UI), `pitch` (`balanced`, `flat`, `green` or `dusty`).
- **Player**: `id` must be unique across the whole file (saves refer to players by id).
  `bats` and `bowls` are `left` or `right` (default right; left-arm spinners always bowl
  left-arm).
  `role` is `batter`, `bowler`, `all_rounder` or `keeper`; `style` is `pace`, `medium`,
  `off_spin`, `leg_spin` or `left_arm_spin`. `age` defaults to 27. Attributes are 1-20;
  any missing one defaults to 8.
- **Squads**: at least 11 players, ideally 14-18 with a specialist keeper and 5+ bowlers
  (bowling rating 10+). The first 11 listed are the default XI before selection runs.
- **League size**: any number of teams from 2 up. Odd counts get a bye each round; fewer
  than 4 teams means no play-offs (top of the table wins). The transfer deadline is always
  halfway through the league.
- **Careers copy the database**: like FM, a new career takes a snapshot of `teams.json`
  and the save carries every player and club from then on (players age and develop, youth
  players join). Edits to `teams.json` apply to the next new career, not to an existing one.
- **Youth names** come from `data/names.json` (`first` and `last` lists); edit or replace it.

### Importing the cricket-players-2023 dataset

`tools/import_dataset.py` builds `teams.json` and `names.json` from the dataset zip (or its
extracted folder):

```
py -3 tools/import_dataset.py "%USERPROFILE%\Downloads\cricket-players-2023.zip"
```

- One team per country: by default the 8 with the most complete profiles (India, England,
  Pakistan, Afghanistan, Bangladesh, Australia, South Africa, Sri Lanka); choose your own with
  `--countries "India,England,New Zealand"` or a different count with `--teams 10`.
  `--gender f` builds women's teams.
- Squads of 16 (2 keepers, 5 batters, 4 all-rounders, 5 bowlers with a pace/spin mix), picking
  the most established players: those with a real profile photo, then the earliest added to
  the dataset (internationals came first).
- From the data: real names, ages for the 2026 season, batting hand, bowling arm and style,
  and role. Home pitches follow the continent (Asia dusty, Europe green, Oceania and Africa
  flat).
- **The dataset has no performance stats**, so skill attributes are generated from each
  player's role, and the better-known players in a squad get better numbers. Rate players
  from match stats with `--stats` (below), or set numbers by hand in the ratings spreadsheet.

### Rating players from Cricsheet ball-by-ball data (`--cricsheet`, `tools/cricsheet_import.py`)

```
py -3 tools/import_dataset.py "%USERPROFILE%\Downloads\cricket-players-2023.zip" --cricsheet data/cricsheet
```

`data/cricsheet/` holds Cricsheet's men's `t20s_male_json.zip`, `odis_male_json.zip` and
`tests_male_json.zip` (from https://cricsheet.org/downloads/) and the register's `names.csv`
and `people.csv` (https://cricsheet.org/register/). Re-download them for newer matches.

- **Every ball of every international since `--since`** (default 2022-01-01): about 3,300
  matches. Players are matched to the players dataset (which has the hands, styles and ages
  Cricsheet lacks) within their country: full name, a name that starts the other, or Cricsheet's
  "MA Starc" initials (including Sri Lankan initials like "PHKD Mendis").
- **Ratings**, each judged against par for its format and weighted T20I > ODI > Test:
  batting average and balls per dismissal (technique, concentration), strike rate and dot
  balls (timing, aggression), boundary share and six rate (power), runs per non-boundary ball
  (running), death-over strike rate (composure), strike rate and average against spinners
  (vs_spin); economy and dot balls (accuracy), strike rate (movement), average and death-over
  economy (variation); catches, stumpings and run-outs per match (fielding, keeping).
  Formats with under 60 balls don't count; ratings blend with the existing ones by sample
  (150 balls batting, 180 bowling, 400 runs for power). Par sits at 10.5 for batting and 13
  for bowling so data-rated teams land on the attribute levels the match engine is tuned for
  (India v England then averages 173 in T20s, 256 in ODIs).
- **Teams with no data** (Afghanistan) are levelled to the average data-rated team, so their
  generated ratings aren't better or worse by accident.
- **Squads** come from who has actually played: the most appearances since `--since`.
- **Afghanistan has no Cricsheet data** (Cricsheet withholds matches involving the Afghanistan
  men's team), so it keeps generated ratings. Players who debuted after the players dataset
  was made (2023) can't be matched.
- Cricsheet ratings take priority over `--stats`; `--ratings` still applies last.

**Licence and credit**: Cricsheet data is used under the Open Data Commons Attribution
License (ODC-By 1.0). Public use must credit Cricsheet and keep its notices (the README.txt and
LICENSE.txt inside each zip). The importer writes a `credits` line into `teams.json`; careers
keep it and the game shows it on Home.

### Rating players from match stats (`--stats`, `tools/stats_import.py`)

```
py -3 tools/import_dataset.py "%USERPROFILE%\Downloads\cricket-players-2023.zip" --stats "%USERPROFILE%\Downloads\crickeet-players-with-stats.zip"
```

takes per-innings records (`batsman.csv`: Player Name, Runs, BF, 4s, 6s, SR, Dismissal,
Match Type; `bowlers.csv`: Player Name, Overs, Runs, Wickets, Match Type) and:

- **Cleans them**: "-" read as 0; balls faced recovered from the strike rate when the two
  disagree; boundary counts that add up to more than the runs are ignored; overs read as
  cricket notation (3.5 = 3 overs 5 balls); format names tidied.
- **Matches names** to the players dataset: exact name, a longer name ending in it
  ("B Sai Sudharsan"), or surname plus initials ("KL Rahul" = Lokesh Rahul), preferring
  players with a real profile photo in the stats' country.
- **Rates them**: batting average, strike rate, share of runs in boundaries and balls per
  dismissal set technique, timing, power, aggression and concentration; economy, strike rate
  and bowling average set accuracy, movement and variation. Each is judged against par for
  its format (T20I strike rate 130, ODI 90, ...), weighted T20I > ODI > Test, and blended
  with the player's existing rating by sample size (10 innings / 8 spells = half and half).
- **Builds that country's squad** around the players who appear most in the stats.

The 2024 file covers 41 India players (40 matched; Ashwin is 39 by 2026, outside the default
age range). `--ratings` edits still apply last.
- Youth names come from each country's own players (`names.json` `by_team`).
- The old `teams.json` is copied to a dated `teams.backup-<time>.json`. The script prints a
  squad report and flags anything the game would trip over (no keeper, fewer than 5 bowlers,
  too small a squad).

### Editing ratings in a spreadsheet (`tools/ratings.py`)

```
py -3 tools/ratings.py template
```

writes `data/ratings/ratings.csv`: one row per player with id, name, team, role, style, hands and age
for reference, then every attribute (1-20) pre-filled with its current value. Edit it in
Excel, Google Sheets or a text editor (only `id` and the attribute columns are read back;
blank cells keep the current value), then either

```
py -3 tools/ratings.py apply
```

to write the numbers into `data/teams.json`, or rebuild from the dataset with them on top:

```
py -3 tools/import_dataset.py "%USERPROFILE%\Downloads\cricket-players-2023.zip" --ratings data/ratings/ratings.csv
```

Values that aren't numbers are reported and skipped; values outside 1-20 are clamped. Apply
also makes a dated backup of `teams.json`. Start a new career to play with the new ratings.

Attributes: batting (technique, timing, power, vs_spin, running), bowling (accuracy,
movement, speed, variation), fielding (catching, fielding, keeping), mental (composure,
concentration, aggression), physical (stamina).

Established players skew older (around 33 on average by 2026), so expect plenty of
retirements after the first season; clubs that drop below 14 players are topped up from
their academies.

`tools/generate_teams.py` made the original fictional teams; you don't need it.

## The season (`season.gd`)

- **Premier T20 League**: 8 teams, double round-robin (14 games each), a round every 3 days
  from Sat 4 Apr 2026. Win 2 points, tie 1; ties on points split by net run rate (an all-out
  side counts as facing its full 20 overs).
- **Play-offs**: 1st v 4th and 2nd v 3rd, then a final; the higher seed hosts and goes through
  on a tie.
- **Home pitch**: each team has one in `teams.json`; matches are played on the home side's.
- **Squads**: 16 players per club; the XI is picked from them (`selection.gd`). AI clubs pick
  their best fit XI before every match, which rotates tired players. Your XI is yours to pick
  on Tactics (or tick "Assistant picks the XI"); injured players in it are
  replaced at kick-off by the best reserve of the same kind, and the change goes in the news.
- **Workload**: every player in an XI loses 12% condition to a match day on top of what the
  match itself costs, and recovers 5% a day. Batters and spinners stay fresh; a fast bowler
  who plays every game drops below 75% (tired) after about five.
- **Injuries**: about 1.2% per player per match, rising to 6% for a spent player; out for
  3-28 days. Your club's injuries and returns are in the news.
- **Training** (`training.gd`, Training screen): on the days between matches your squad
  trains with a team focus (Balanced, Batting, Bowling, Fielding, Fitness, Recovery) at an
  intensity (Light, Normal, Hard), and any player can have their own focus. It replaces the
  plain 5%-a-day recovery for your club: Light recovers 40% faster, Hard 40% slower, Recovery
  focus 30% faster with no development. Focused attributes grow by 0.06 points a day at
  Normal (x0.5 Light, x1.7 Hard), shared across them, in full up to age 22 and tailing off to
  a tenth by 31; skills a player doesn't use (below 5) aren't trained. Hard sessions risk
  injuries (0.5% a player a day, more when tired), Normal 0.15%, Light none. A training report
  goes to the Inbox after each block. Other clubs just rest.
- **Between matches**: form (from match ratings) sets a player's starting confidence;
  season stats and ratings accumulate.
- **Transfers and contracts** (`transfers.gd`, Transfers and Finances screens): every player
  has a value (ability on an exponential scale, adjusted for age, form and contract), a
  yearly wage and a contract end year. Bid for players at other clubs: below 80% of the
  asking price is rejected, 80-99% gets a counter, the asking price is accepted (key
  players cost up to 2.2x value). Then the player names a wage (30% of value, +15% to move)
  and years (3 if 27 or under, 2 to 31, then 1); signing needs room in the balance and the
  board's wage budget, and a squad under 18. AI clubs bid for your players (mostly listed
  ones); accept or reject within 5 days. Renew contracts on the player's terms. The window
  shuts halfway through the league. Money: home gates (£50k + £8k per place above bottom),
  £150k per play-off match, weekly wages.
- **Player ratings** (`match_ratings.gd`): FM-style 3.0-10.0 from runs, strike rate,
  wickets, economy and fielding, +0.2 for winning. Best on the winning side is player of
  the match.
- **News**: results, fifties, hundreds, four-fors, the play-off draw and the champions.
- **End of season** (Continue after the final, `start_next_season()`): prize money
  (£1m champion, £600k runner-up, £350k beaten semi-finalists, £200k down to £50k for the
  rest); awards (player of the season, most runs, most wickets, young player) in the news and
  Competition > History; a board review comparing your finish with where the squad's strength
  said you'd finish (doing better raises the wage budget up to 15%); expiring contracts (AI
  clubs keep their top 13 under 34, the rest and your unrenewed players become free agents);
  retirements (30% at 35, 60% at 36, 90% from 37); everyone a year older with attributes
  growing fast when young (+1.2 a year at 20) and fading from about 30, nudged by how well
  they played (`development.gd`); one academy youngster (17-18) per club; AI clubs sign free
  agents up to 15 players. Then a new fixture list, form halfway back to average, everyone
  fit, and the transfer window open. Free agents can be signed any time the window is open,
  for no fee.
- **Saving**: autosaves to `user://career.json` (on Windows,
  `%APPDATA%\Godot\app_userdata\Cricket Manager\`) after every match and every Continue.
  Saves are self-contained: every player (with their current age and attributes), every
  club, free agents, the calendar, results, stats, form, condition, injuries, the XI,
  tactics, contracts, money, bids, news and season history. Saves from older versions can't
  be loaded; the game starts a new career.

## Layout

```
data/teams.json              Teams, home pitches and 16-man squads (attributes 1-20, like FM;
                             the first 11 listed are the default XI)
tools/import_dataset.py      Builds teams.json/names.json from the cricket-players-2023 dataset
tools/cricsheet_import.py    Cricsheet ball-by-ball data: aggregates, matches names, rates players
tools/stats_import.py        Cleans per-innings stats, matches names, turns them into ratings
data/cricsheet/              Cricsheet match zips and people register (ODC-By 1.0)
tools/ratings.py             Exports ratings to data/ratings/ratings.csv and applies edits back
data/ratings/ratings.csv     The editable ratings spreadsheet (from `ratings.py template`)
tools/generate_teams.py      The original fictional teams generator (seeded)
scripts/engine/              Simulation, no UI code
  cricket_player.gd          Player + attributes
  cricket_team.gd            Squad, playing XI (array order = batting order) and tactics
  selection.gd               Assistant XI picks, injury cover, selection warnings
  transfers.gd               Values, wages, bids, AI offers, renewals, starting finances
  development.gd             Ageing, attribute growth and decline, retirement, youth players
  match_format.gd            T20 / ODI rules, phases, batting tempo
  delivery_model.gd          What happens on each ball  <- main tuning point
  captain_ai.gd              Batting intent, bowling changes, field approach
  match_dynamics.gd          Condition, confidence and pressure meters
  tactics.gd                 Batting and bowling roles, suggestions
  training.gd                Training between matches: recovery, development, injuries
  innings.gd                 Score and scorecard state, lineup, reviews, super-over limits
  fields.gd                  Field presets, the 30-yard circle, fielding restrictions
  match_engine.gd            Toss, innings flow, result
  match_ratings.gd           Player ratings and player of the match
  commentary.gd              Ball-by-ball text
  season.gd                  Calendar, results, table, play-offs, form, news, saving
scripts/game_log.gd          Local play log (JSON lines) and error capture
scripts/ui/                  FM24-style interface
  ui_kit.gd                  Palette, theme, cards, tables, meters, attribute colours
  app.gd                     Shell: top bar, sidebar navigation, Continue
  home_screen.gd             Next match, last result, table, news, new career
  inbox_screen.gd            All news
  squad_screen.gd            Squad list with form/fitness/stats, player profile
  tactics_screen.gd          One page: XI in batting order with roles (drag and drop),
                             reserves, selection check, bowling plan, match instructions
  training_screen.gd         Team focus and intensity, individual focus, latest report
  match_screen.gd            Match Day (league fixtures and friendlies), wagon wheel,
                             innings break, post-match report
  field_view.gd              2D ground view
  fixtures_screen.gd         Club and competition fixtures and results
  competition_screen.gd      League table, play-offs, leading players
  transfers_screen.gd        Player search and bids, bids for us, contracts and transfer list
  finances_screen.gd         Balance, wage budget, transactions, league finances
tests/
  sim_stats.gd               Calibration: averages over 400 simulated matches
  season_test.gd             Plays two seasons; checks table, play-offs, transfers, the
                             rollover between them, and save/load
  engine_test.gd             Super overs, DRS, manager choices, fields, handedness matchups
  ui_smoke.gd                Plays fixtures through Continue (Tactics, Start Match, innings
                             break, report, Done), uses drag and drop, training, the match
                             controls and review prompts, and opens every screen/tab
```

## How a delivery is decided

`DeliveryModel.bowl()` compares batter skill (technique, timing, composure, vs spin, how
settled they are) with bowler skill (accuracy, movement, variation, pace, pitch help). That gap,
plus batting intent from `CaptainAI` (phase, chase rate, wickets left, aggression, role), scales
weights for dot / 1 / 2 / 3 / 4 / 6 / wicket. Wickets then split into caught (with drops),
bowled, lbw, stumped and run out.

## Match rules and in-match control

- **Super overs** (`match_engine.gd`): a tie goes to a super over, ICC style: one over each,
  three batters (each side's biggest hitters), two wickets, the side that batted second bats
  first, repeated if still level (up to 5). Super overs don't count towards stats, ratings or
  net run rate. In the league a super-over win is a win.
- **Handedness**: players have `bats` and `bowls` ("left"/"right") in `teams.json`. Spin
  turning away from the bat (off-spin to a left-hander, leg-spin or left-arm spin to a
  right-hander) and left-arm pace angling across a right-hander help the bowler; spin turning
  into the bat helps the batter; a left-right partnership disrupts the bowler's line. The 2D
  view mirrors the field for left-handers.
- **Fields** (`fields.gd`): presets (Attacking, Balanced, Middle overs, Defensive, Off-side,
  Leg-side, Death) or your own, set from Match Day's Instructions card or by clicking a fielder on the
  2D view and then where they should stand. The real 30-yard circle and restrictions (2 out in
  the powerplay, 5 after) are enforced; extra boundary riders are brought in. The field
  matters: boundary riders near a shot can cut off fours and catch sixes on the rope, ring
  fielders stop singles, gaps turn ones into twos, close catchers turn edges into wickets, and
  catches go to where a fielder actually stands.
- **Captain's choice** follows the phase: Balanced in the powerplay, Middle overs (no slip,
  four back) after it, Death at the end, Attacking or Defensive with those approaches. The
  Field picker shows which one the captain is using.
- **Wagon wheel**: tick it on Match Day to draw the striker's scoring shots this match on the
  ground, with their off/leg split and favourite area, to help set the field.
- **Bowling changes**: pick who bowls the next over (or leave it to the captain).
- **Batting order on the fly**: "Next in" sends any waiting batter in at the next wicket.
- **DRS**: umpires get about 1 in 10 given-out lbws/catches behind wrong, and some shouts
  given not out were out. Each side has 2 unsuccessful reviews per innings (1 per super over);
  a successful review is kept. When it's your call the match pauses, the ground shows the
  appealed ball, and the commentary bar asks Review / Accept Call; AI captains review most bad decisions and some good ones.

## In-match meters (`match_dynamics.gd`)

- **Condition** (0-100%): bowling drains it (pace 7, medium 5, spin 3.5 per over at stamina
  10), running drains batters, fielders recover 1.3 per over off. Below 75% players tire:
  bowlers lose control (more wides and no-balls) and quality, batters run fewer twos.
  The AI captain rests tired bowlers.
- **Confidence** (50 = neutral): boundaries and wickets lift it, dots, drops and being hit
  lower it, and it drifts back toward 50. Confident batters attack with less risk.
- **Pressure** (per innings): dots, wickets and a climbing required rate build it, scoring
  releases it, and it fades 4% a ball. It causes rash shots, less so for composed batters,
  and new batters walk in a little nervous.
- **Intent** (-1 block to 1 all out): the captain's read of the situation, the batter's role,
  the manager's batting instruction, and frustration from pressure.

On Match Day, the Instructions card sets your club's batting approach (Defend / Rotate /
Auto / Attack / All Out) or bowling approach (Auto / Defensive / Balanced / Attacking, which
also changes the field).

## Tactics (`tactics.gd`, Tactics screen)

Everything is on one page. Drag XI rows to change the batting order, drag a reserve onto an XI
player to swap them (or into the XI's empty space when it's short), and drag an XI player
onto Reserves to drop them; Pick and Drop buttons do the same.

- **Batting order**: the team's `players` order. Changing it mid-match changes who comes in next.
- **Batting roles** add intent per phase: Balanced, Anchor, Aggressor, Pinch Hitter, Finisher.
  Every team starts with roles suggested from attributes.
- **Bowling plan**: Auto, New Ball, Middle Overs, Death, Do Not Bowl. Roles pull a bowler
  towards their phase; Death bowlers keep their last two overs for the end; Do Not Bowl is a
  last resort only.
- **Match instructions**: the batting and bowling approach a new match starts with.

## Tests and calibration

```
godot --headless --path . --script res://tests/sim_stats.gd
godot --headless --path . --script res://tests/season_test.gd
godot --headless --path . --script res://tests/engine_test.gd
godot --headless --path . --script res://tests/ui_smoke.gd
```

The two season tests use their own save files, never `user://career.json`.

Current calibration (400 matches each, with fields, handedness and DRS):

| | 1st innings | Wickets | Dots | 4s / 6s | Ties |
|---|---|---|---|---|---|
| T20 | 173 | 6.3 | 38% | 16 / 7 | 0 (super overs) |
| ODI | 256 | 8.5 (in 45 overs) | 53% | 20 / 7 | 0 (super overs) |

Batting instructions (1st innings, same seeds):

| | Defend | Rotate | Auto | Attack | All Out |
|---|---|---|---|---|---|
| T20 | 137/4.2 | 153/5.6 | 168/6.7 | 182/7.2 | 187/7.6 |
| ODI | 226/6.0 | 238/7.9 | 246/8.8 | 258/9.5 | 231/9.8 |

Bowling plan (runs conceded in the 1st innings): T20 Auto 172/6.4 vs Suggested 174/6.4,
ODI Auto 233/8.9 vs Suggested 241/8.9.

DRS (60 T20 matches): about 3 reviews a match, a quarter of them overturned. An off-spinner
concedes 6.40 an over to left-handers and 6.77 to right-handers.

Winning margins (T20, defending side): identical teams median 23 runs; league teams median
42. A full simulated season gives net run rates within about ±1.6.

Re-run `sim_stats.gd` and `season_test.gd` after any change to `delivery_model.gd`,
`captain_ai.gd` or `match_dynamics.gd`.
