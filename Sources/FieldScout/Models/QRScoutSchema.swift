import Foundation

/// The exact 2026 QRScout Legacy spreadsheet contract used by MECO Robotics.
/// Header spellings and order intentionally match PayloadBuilder.m in the iPad app.
enum QRScoutSchema {
    static let fieldCount = 29
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

    static func matchesHeader(_ columns: [SheetColumn]) -> Bool {
        columns.map(\.name) == headerNames
    }
}
