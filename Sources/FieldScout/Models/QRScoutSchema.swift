import Foundation

/// The exact 2026 QRScout Legacy spreadsheet contract used by MECO Robotics.
/// Header spellings and order intentionally match PayloadBuilder.m in the iPad app.
enum QRScoutSchema {
    static let fieldCount = 29

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
