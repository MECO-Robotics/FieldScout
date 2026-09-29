# FieldScout

FieldScout is a fully offline, native macOS spreadsheet for FRC field-scouting data. Raw scouting entries stay in the sheet while team summaries, charts, and rankings are calculated as separate views.

The app icon is built around Team 8324 MECO Robotics' blue-and-red rocket identity, combining a scouting grid with a rising performance trajectory.

## What works in this MVP

- Editable spreadsheet with text, numeric, and checkbox cells
- CSV import and export, including quoted commas and multiline notes
- Scanner Intake screen for iPad-generated barcodes and keyboard-wedge scanners
- JSON, `key=value`, CSV-row, and tab-separated scan payloads
- Exact raw scan preservation in the local document archive and duplicate-scan protection
- Exact compatibility with QRScout Legacy's 29-field tab-separated barcode contract
- Preservation of unrecognized CSV columns
- Configurable analytics roles for any column
- Automatic grouping by team number without modifying source rows
- Rankings for projected EPA, breakdown rate, offense, and defense
- Team match-trend and scoring-composition charts
- Offline questions about top teams, reliability, offense, defense, and team comparisons
- Automatic local persistence in `Application Support/FieldScout/scouting-data.json`

No account, server, API key, or internet connection is used.

## Download

Download the current packaged macOS build from [GitHub Releases](https://github.com/MECO-Robotics/FieldScout/releases/latest). FieldScout requires macOS 14 or newer. The build is ad-hoc signed but not Apple-notarized, so macOS may require opening it with Control-click → **Open** the first time.

## Use an iPad app and barcode scanner

1. Open **Scanner Intake** in FieldScout.
2. Pair or plug in a barcode scanner configured as a keyboard and set it to send Return after every scan.
3. Show the scouting barcode on the iPad and scan it.
4. FieldScout appends the 29 QRScout values as one row, archives the original barcode outside the visible grid, and refreshes rankings immediately.

The scanner field automatically regains focus after each accepted scan and captures literal Tab keystrokes from keyboard-wedge scanners. Exact duplicate payloads are ignored. A QRScout Legacy barcode is recognized by its 29 tab-separated values and mapped to the precise source-app field order. Named payloads can still introduce new fields without losing them, and generic positional CSV or tab-separated payloads remain supported.

### QRScout Legacy columns

The starter sheet mirrors `PayloadBuilder.m` from MECO Robotics' 2026 QRScout Legacy repository. It retains the source spreadsheet's intentional legacy spellings and duplicate phase-specific headers:

```text
Scouter Initials, Match Number, Team Number, Starting Position, No Show,
Fuel Scored, Where collected Fuel, Other Auto actions,
Robot Stuck or a Stop in Auto, Climbed, Fuel Scored, Bump Trench,
Deffended by Opponent, Fuel Fed, Opposing Zone Actions, Climbed,
Mechanical Issue, Died, Triped/Fell Over, Scoring Efectiveness,
Scored How?, Scoring Location, Feeding/Passing Skill, Passed How?,
Defense Skill, Yello/Red Card, First Pick, Second Pick, Comments
```

## Run it

Open `Package.swift` in Xcode and run the `FieldScout` scheme, or run:

```sh
swift run FieldScout
```

To produce a standalone app bundle:

```sh
./Scripts/package-app.sh
open outputs/FieldScout.app
```

The generated app is ad-hoc signed for local use. It is not notarized for public distribution. The packaged build includes the MECO app icon in its bundle and also applies it directly to the running app so the Dock uses the correct artwork.

## Import existing scouting data

1. Export the field-scouting app's data as UTF-8 CSV.
2. In FieldScout, choose **Import CSV**.
3. Click a column header to check its **Analytics role**.
4. Map the team, match, scoring, defense, and breakdown columns as needed.

FieldScout guesses common header names such as `Team Number`, `Auto Points`, `Teleop Points`, `Defense Rating`, and `Robot Broke Down?`. Unknown columns remain untouched and can be mapped manually.

Import currently replaces the open sheet. Export first if the current sheet needs to be retained.

## Ranking definitions

- **Projected EPA:** a recency-weighted average of QRScout's Auto Fuel, Teleop Fuel, AUTO climb, and endgame climb values. Fuel is worth 1 point, AUTO climb is 15, and endgame L1/L2/L3 are 10/20/30. The estimate is shrunk toward the event average by the equivalent of two matches, reducing overreaction to a one-match sample.
- **Breakdown rate:** matches with `Mechanical Issue`, `Died`, or `Triped/Fell Over` divided by scouted matches. One affected match out of one is shown as 100% breakdown. Lower-breakdown teams rank first.
- **Offense:** average scouted auto + teleop + endgame - penalty points.
- **Defense:** average value across columns mapped to Defense Rating. The starter sheet assumes a 0–5 scale.

This projected EPA is a scouting-data estimate, not the official Statbotics EPA model. A future version can add alliance/opponent adjustment while remaining offline if schedule and result data are imported.

## Tests

```sh
swift test
```

Tests cover the exact 29-field QRScout contract, tab payload detection, 2026 climb scoring, QRScout breakdown mapping, aggregation immutability, projected EPA shrinkage, CSV quoting, and header-role inference.
