import Foundation

/// The exact 2026 QRScout Legacy spreadsheet contract used by MECO Robotics.
/// Header spellings and order intentionally match PayloadBuilder.m in the iPad app.
enum QRScoutSchema {
    static let fieldCount = 29
    /// Stable machine-readable identities for every QRScout field. These are kept
    /// separate from the visible headers so duplicate labels such as "Fuel Scored"
    /// and "Climbed" can never be confused by a scanner or import.
    static let fieldIdentifiers = [
        "si", "mn", "tn", "sp", "ns", "afs", "afc", "aaa", "ast", "acl",
        "tfs", "bt", "dbo", "ff", "oza", "ecl", "mi", "di", "ti", "se",
        "sh", "sl", "fps", "ph", "ds", "ca", "fp", "s2p", "co"
    ]
    private static let scoutFacingValues: [String: [String: String]] = [
        "startingposition": [
            "OT": "Outpost Trench",
            "OBFT": "Outpost Bump — Trench",
            "OBFH": "Outpost Bump — Hub",
            "H": "Hub",
            "DBFH": "Depot Bump — Hub",
            "DBFT": "Depot Bump — Trench",
            "DT": "Depot Trench"
        ],
        "wherecollectedfuel": [
            "1": "Outpost",
            "2": "Depot",
            "3": "Neutral Zone",
            "4": "Neutral Zone — 2nd Pass",
            "5": "Did Not Move",
            "6": "Moved Without Collecting"
        ],
        "otherautoactions": ["1": "Passed", "2": "Bump", "3": "Trench"],
        "bumptrench": ["1": "Bump", "2": "Trench"],
        "opposingzoneactions": ["1": "Collecting", "2": "Defense"],
        "scoringlocation": [
            "1": "Outpost Trench",
            "2": "Outpost",
            "3": "Hub",
            "4": "Ladder",
            "5": "Depot",
            "6": "Depot Trench"
        ]
    ]

    static func expandedStartingPosition(_ value: String) -> String {
        expandedValue(value, forColumnNamed: "Starting Position")
    }

    static func expandedValue(_ value: String, forColumnNamed columnName: String) -> String {
        guard let values = scoutFacingValues[normalized(columnName)] else { return value }
        return value
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { component in
                let original = component.trimmingCharacters(in: .whitespacesAndNewlines)
                return values[original.uppercased()] ?? original
            }
            .joined(separator: ", ")
    }

    static func expandedLegacyFields(_ fields: [String]) -> [String] {
        var expanded = fields
        for index in [3, 6, 7, 11, 14, 21] where expanded.indices.contains(index) {
            expanded[index] = expandedValue(expanded[index], forColumnNamed: headerNames[index])
        }
        return expanded
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().filter(\.isLetter)
    }

    static func columns() -> [SheetColumn] {
        [
            SheetColumn(name: "Scouter Initials"),
            SheetColumn(name: "Match Number", type: .integer, role: .matchNumber),
            SheetColumn(name: "Team Number", type: .integer, role: .teamNumber),
            SheetColumn(name: "Starting Position"),
            SheetColumn(name: "No Show", type: .boolean),
            SheetColumn(name: "Fuel Scored", type: .integer, role: .autoPoints),
            SheetColumn(name: "Where collected Fuel"),
            SheetColumn(name: "Other Auto actions"),
            SheetColumn(name: "Robot Stuck or a Stop in Auto", type: .boolean),
            SheetColumn(name: "Climbed", role: .autoPoints),
            SheetColumn(name: "Fuel Scored", type: .integer, role: .teleopPoints),
            SheetColumn(name: "Bump Trench"),
            SheetColumn(name: "Deffended by Opponent", type: .boolean),
            SheetColumn(name: "Fuel Fed", type: .integer),
            SheetColumn(name: "Opposing Zone Actions"),
            SheetColumn(name: "Climbed", role: .endgamePoints),
            SheetColumn(name: "Mechanical Issue", type: .boolean, role: .breakdown),
            SheetColumn(name: "Died", type: .boolean, role: .breakdown),
            SheetColumn(name: "Triped/Fell Over", type: .boolean, role: .breakdown),
            SheetColumn(name: "Scoring Efectiveness", type: .decimal),
            SheetColumn(name: "Scored How?"),
            SheetColumn(name: "Scoring Location"),
            SheetColumn(name: "Feeding/Passing Skill", type: .decimal),
            SheetColumn(name: "Passed How?"),
            SheetColumn(name: "Defense Skill", type: .decimal, role: .defenseRating),
            SheetColumn(name: "Yello/Red Card"),
            SheetColumn(name: "First Pick"),
            SheetColumn(name: "Second Pick"),
            SheetColumn(name: "Comments")
        ]
    }

    static var headerNames: [String] {
        columns().map(\.name)
    }

    static func orderedValues(from fieldsByIdentifier: [String: String]) -> [String]? {
        guard Set(fieldsByIdentifier.keys) == Set(fieldIdentifiers) else { return nil }
        return fieldIdentifiers.map { fieldsByIdentifier[$0] ?? "" }
    }

    /// Expands the scanner-sized QRSCOUT3 array into the same 29 visible values
    /// produced by QRScout's spreadsheet payload. Every code and bitmask is
    /// range-checked so a damaged scan cannot shift or invent column values.
    static func expandedCompactValues(_ compact: [Any]) -> [String]? {
        guard compact.count == fieldCount,
              let initials = compact[0] as? String,
              let comments = compact[28] as? String else { return nil }

        func integer(_ index: Int, range: ClosedRange<Int>) -> Int? {
            guard let number = compact[index] as? NSNumber else { return nil }
            let value = number.intValue
            guard number.doubleValue == Double(value), range.contains(value) else { return nil }
            return value
        }

        func optionalNumber(_ index: Int, range: ClosedRange<Int>) -> String? {
            guard let value = integer(index, range: -1...range.upperBound), value == -1 || range.contains(value) else { return nil }
            return value == -1 ? "" : String(value)
        }

        func choice(_ index: Int, options: [String], emptyCode: Int? = nil) -> String? {
            let upperBound = emptyCode ?? (options.count - 1)
            guard let code = integer(index, range: 0...upperBound) else { return nil }
            if code == emptyCode { return "" }
            guard options.indices.contains(code) else { return nil }
            return options[code]
        }

        func selections(_ index: Int, options: [String]) -> String? {
            guard let mask = integer(index, range: 0...((1 << options.count) - 1)) else { return nil }
            return options.indices.filter { mask & (1 << $0) != 0 }.map { options[$0] }.joined(separator: ",")
        }

        guard
            let match = optionalNumber(1, range: 1...9999),
            let team = optionalNumber(2, range: 1...99999),
            let startingPosition = choice(3, options: [
                "Outpost Trench", "Outpost Bump — Trench", "Outpost Bump — Hub", "Hub",
                "Depot Bump — Hub", "Depot Bump — Trench", "Depot Trench"
            ], emptyCode: 7),
            let noShow = choice(4, options: ["false", "true"]),
            let autoFuel = integer(5, range: 0...500),
            let autoCollection = selections(6, options: [
                "Outpost", "Depot", "Neutral Zone", "Neutral Zone — 2nd Pass",
                "Did Not Move", "Moved Without Collecting"
            ]),
            let autoActions = selections(7, options: ["Passed", "Bump", "Trench"]),
            let autoStuck = choice(8, options: ["false", "true"]),
            let autoClimb = choice(9, options: ["No", "C", "F"]),
            let teleopFuel = integer(10, range: 0...500),
            let bumpTrench = selections(11, options: ["Bump", "Trench"]),
            let defended = choice(12, options: ["false", "true"]),
            let fuelFed = integer(13, range: 0...500),
            let zoneActions = selections(14, options: ["Collecting", "Defense"]),
            let endgameClimb = choice(15, options: ["No", "L1", "L2", "L3", "F"]),
            let mechanical = choice(16, options: ["false", "true"]),
            let died = choice(17, options: ["false", "true"]),
            let tipped = choice(18, options: ["false", "true"]),
            let scoringEffectiveness = integer(19, range: 0...5),
            let scoredHow = choice(20, options: ["driving", "stationary", "both", "none"], emptyCode: 4),
            let scoringLocation = selections(21, options: [
                "Outpost Trench", "Outpost", "Hub", "Ladder", "Depot", "Depot Trench"
            ]),
            let passingSkill = integer(22, range: 0...5),
            let passedHow = choice(23, options: ["driving", "stationary", "both", "none"], emptyCode: 4),
            let defenseSkill = integer(24, range: 0...5),
            let card = choice(25, options: ["No Card", "Yellow", "Red"]),
            let firstPick = choice(26, options: ["Yes", "May", "No"], emptyCode: 3),
            let secondPick = choice(27, options: ["Yes", "May", "No"], emptyCode: 3)
        else { return nil }

        return [
            initials, match, team, startingPosition, noShow, String(autoFuel), autoCollection, autoActions,
            autoStuck, autoClimb, String(teleopFuel), bumpTrench, defended, String(fuelFed), zoneActions,
            endgameClimb, mechanical, died, tipped, String(scoringEffectiveness), scoredHow, scoringLocation,
            String(passingSkill), passedHow, String(defenseSkill), card, firstPick, secondPick, comments
        ]
    }

    /// Returns the input column index for each canonical QRScout column. Matching
    /// includes duplicate-header occurrence numbers, so the two Fuel Scored and
    /// Climbed columns remain distinct.
    static func importOrder(for header: [String]) -> [Int]? {
        guard header.count == fieldCount else { return nil }
        let expected = headerIdentityKeys(headerNames)
        let incoming = headerIdentityKeys(header)
        guard Set(incoming) == Set(expected), incoming.count == Set(incoming).count else { return nil }
        return expected.compactMap { incoming.firstIndex(of: $0) }
    }

    private static func headerIdentityKeys(_ names: [String]) -> [String] {
        var occurrences: [String: Int] = [:]
        return names.map { name in
            var token = normalized(name)
            let aliases = [
                "scout": "scouterinitials", "scouter": "scouterinitials",
                "match": "matchnumber", "team": "teamnumber",
                "defendedbyopponent": "deffendedbyopponent",
                "trippedfellover": "tripedfellover",
                "scoringeffectiveness": "scoringefectiveness",
                "yellowredcard": "yelloredcard"
            ]
            token = aliases[token] ?? token
            occurrences[token, default: 0] += 1
            return "\(token)#\(occurrences[token]!)"
        }
    }

    static func matchesHeader(_ columns: [SheetColumn]) -> Bool {
        columns.map(\.name) == headerNames
    }
}
