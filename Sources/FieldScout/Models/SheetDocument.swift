import Foundation

enum ColumnDataType: String, Codable, CaseIterable, Identifiable, Sendable {
    case text = "Text"
    case integer = "Whole Number"
    case decimal = "Decimal"
    case boolean = "Yes / No"

    var id: String { rawValue }
}

enum AnalyticsRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case none = "Not used in rankings"
    case teamNumber = "Team number"
    case matchNumber = "Match number"
    case autoPoints = "Auto points"
    case teleopPoints = "Teleop points"
    case endgamePoints = "Endgame points"
    case penaltyPoints = "Penalty points"
    case defenseRating = "Defense rating"
    case breakdown = "Broke down"

    var id: String { rawValue }
}

struct SheetColumn: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var type: ColumnDataType
    var role: AnalyticsRole

    init(
        id: UUID = UUID(),
        name: String,
        type: ColumnDataType = .text,
        role: AnalyticsRole = .none
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.role = role
    }
}

struct ScoutingRow: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var values: [UUID: String]

    init(id: UUID = UUID(), values: [UUID: String] = [:]) {
        self.id = id
        self.values = values
    }
}

enum TeamFlag: String, Codable, CaseIterable, Identifiable, Sendable {
    case none = "No flag"
    case favorite = "Favorite"
    case watch = "Watch"
    case doNotPick = "Do Not Pick"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .none: "flag"
        case .favorite: "star.fill"
        case .watch: "eye.fill"
        case .doNotPick: "hand.raised.fill"
        }
    }
}

struct TeamAnnotation: Codable, Identifiable, Hashable, Sendable {
    var teamNumber: Int
    var flag: TeamFlag
    var note: String

    var id: Int { teamNumber }
}

struct SheetDocument: Codable, Sendable {
    var title: String
    var columns: [SheetColumn]
    var rows: [ScoutingRow]
    var updatedAt: Date
    /// Exact accepted scanner payloads used for duplicate detection, kept out of the spreadsheet grid.
    var ingestedScanPayloads: [String]? = nil
    /// Deliberate pick-list notes kept separate from calculated rankings and raw scouting rows.
    var teamAnnotations: [TeamAnnotation]? = nil

    static func starter() -> SheetDocument {
        return SheetDocument(
            title: "MECO QRScout 2026",
            columns: QRScoutSchema.columns(),
            rows: [ScoutingRow()],
            updatedAt: .now,
            ingestedScanPayloads: [],
            teamAnnotations: []
        )
    }
}
