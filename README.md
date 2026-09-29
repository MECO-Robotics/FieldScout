# FieldScout

FieldScout is an offline-first desktop spreadsheet for FRC field-scouting data on macOS and Windows. Raw scouting entries stay in the sheet while team summaries, charts, and rankings are calculated as separate views.

The app icon is built around Team 8324 MECO Robotics' blue-and-red rocket identity, combining a scouting grid with a rising performance trajectory.

## What works in this MVP

- Editable spreadsheet with text, numeric, and checkbox cells
- CSV import and export, including quoted commas and multiline notes
- Scanner Intake screen for iPad-generated barcodes and keyboard-wedge scanners
- JSON, `key=value`, CSV-row, and tab-separated scan payloads
- Exact raw scan preservation in the local document archive and duplicate-scan protection
- Team-and-match conflict review with side-by-side values and replace/keep-both choices
- Exact compatibility with QRScout Legacy's 29-field tab-separated barcode contract
- Preservation of unrecognized CSV columns
- Configurable analytics roles for any column
- Automatic grouping by team number without modifying source rows
- Rankings for projected EPA, breakdown rate, offense, and defense
- Event Status coverage for six robots per match plus missing/invalid data checks
- Undo/redo, bulk tab-separated row paste, and automatic recoverable snapshots
- Lightweight Favorite, Watch, and Do Not Pick flags with one short team note
- Team match-trend and scoring-composition charts
- Offline questions about top teams, reliability, offense, defense, and team comparisons
- Automatic local persistence in `Application Support/FieldScout/scouting-data.json`
- Automatic app updates from signed GitHub Releases on installed macOS and Windows builds

No account, server, or API key is required. Scouting, analytics, scanning, import/export, and backups work without internet and never upload scouting data. FieldScout only uses the internet to check GitHub Releases for app updates.

## Download

Download the current packaged macOS and Windows builds from [GitHub Releases](https://github.com/MECO-Robotics/FieldScout/releases/latest).

- **Windows:** use the `.exe` installer for automatic updates. The portable `.zip` remains available, but it must be replaced manually for each release. The Windows build is currently unsigned, so Microsoft Defender SmartScreen may show an unknown-publisher warning.
- **macOS:** requires macOS 14 or newer and supports both Apple silicon and Intel. The build is ad-hoc signed but not Apple-notarized, so macOS may require opening it with Control-click → **Open** the first time.

## Automatic updates

Version 0.5.0 is the first updater-enabled release. Anyone running 0.4.0 or earlier must install 0.5.0 once; after that, installed copies can update themselves without downloading and reinstalling the app manually.

- macOS checks the signed Sparkle feed and can download, install, and relaunch into a new version. Use **FieldScout → Check for Updates…** to check immediately.
- The installed Windows app checks shortly after launch and every six hours, downloads a newer release in the background, and asks to restart when it is ready. Use the **Updates** toolbar button to check immediately.
- Updates preserve the scouting document and local backups. macOS archives are verified with an Ed25519 signature; Windows installers are verified against the SHA-512 value in the generated update manifest.
- GitHub Releases is only needed for update checks and downloads. If an event has no internet connection, FieldScout continues working normally and checks again later.

## Use an iPad app and barcode scanner

1. Open **Scanner Intake** in FieldScout.
2. Pair or plug in a barcode scanner configured as a keyboard. Sending Return after a scan is optional.
3. Show the scouting barcode on the iPad and scan it.
4. FieldScout appends the 29 QRScout values as one row, archives the original barcode outside the visible grid, and refreshes rankings immediately.

FieldScout imports a complete barcode automatically after the scanner pauses, splits its values into separate columns, and then returns focus for the next scan. A packed barcode accidentally scanned into a blank spreadsheet cell is also detected and distributed across that row. Literal tabs and common printable scanner aliases such as `<TAB>`, `\t`, and `⇥` are accepted. Exact duplicate payloads are ignored. A QRScout Legacy barcode is recognized by its 29 values and mapped to the precise source-app field order. Named payloads can still introduce new fields without losing them, and generic positional CSV or tab-separated payloads remain supported.

If a different barcode has the same team and match as an existing row, FieldScout pauses and shows the changed values side by side. Choose **Replace Existing**, **Keep Both**, or cancel without changing the sheet.

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

## Event-day reliability

The **Event Status** screen intentionally keeps operational checks in one place:

- Data quality identifies missing or invalid team/match numbers, missing scouter initials, duplicate team-match entries, and ratings outside 0–5.
- Match coverage shows how many of the expected six robots have been scouted for each match. Team coverage shows teams with the fewest collected entries first.
- FieldScout automatically creates timestamped snapshots while data changes and before destructive actions. The 20 newest snapshots are retained and can be restored from Event Status; the current sheet is backed up before a restore.
- Undo and redo are available from the spreadsheet toolbar and with Command-Z/Command-Shift-Z on macOS or Ctrl-Z/Ctrl-Shift-Z on Windows.
- **Paste Rows** appends tab-separated clipboard rows in the current column order.
- Favorite, Watch, and Do Not Pick are human scouting flags. They include a short note and never change calculated rankings.

Backups remain local alongside the main data file in `~/Library/Application Support/FieldScout/Backups` on macOS and `%APPDATA%\FieldScout\Backups` on Windows.

## Run it on macOS

Open `Package.swift` in Xcode and run the `FieldScout` scheme, or run:

```sh
swift run FieldScout
```

To produce a standalone app bundle:

```sh
./Scripts/package-app.sh
open outputs/FieldScout.app
```

The generated app is a universal Intel/Apple-silicon build and includes Sparkle. It is ad-hoc signed for local use and is not notarized for public distribution. The packaged build includes the MECO app icon in its bundle and also applies it directly to the running app so the Dock uses the correct artwork.

## Run it on Windows

The Windows app lives in `Windows/` and uses Electron for the desktop shell. Install Node.js 24 or newer, then run:

```powershell
cd Windows
npm ci
npm start
```

To build the Windows installer and portable archive from Windows:

```powershell
npm run build:win
```

GitHub Actions tests and packages both platforms whenever a version tag is pushed. It publishes the macOS Sparkle feed plus the Windows `latest.yml` manifest alongside the installers. Windows scouting data is stored locally in `%APPDATA%\FieldScout\scouting-data.json`; internet is only needed to check for and download updates.

For a release, update `CFBundleShortVersionString` in `Resources/Info.plist` and `version` in `Windows/package.json` to the same value, increment the macOS `CFBundleVersion`, then push a matching `vX.Y.Z` tag. The release workflow rejects a tag whose version does not match either app.

## Import existing scouting data

1. Export the field-scouting app's data as UTF-8 CSV.
2. In the Scouting Sheet toolbar, choose **Import**.
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

```powershell
cd Windows
npm test
```

The macOS and Windows test suites cover the exact 29-field QRScout contract, tab payload detection, 2026 climb scoring, QRScout breakdown mapping, aggregation immutability, projected EPA shrinkage, CSV quoting, header-role inference, exact duplicates, team-match conflicts, data-quality coverage, and offline analyst responses.
