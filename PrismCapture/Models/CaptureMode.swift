import Foundation

enum CaptureMode: String, CaseIterable, Identifiable, Codable {
    case area
    case fullscreen
    case delayed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .area: return L10n.string("Area")
        case .fullscreen: return L10n.string("Full Screen")
        case .delayed: return L10n.string("Delayed")
        }
    }

    var systemImage: String {
        switch self {
        case .area: return "rectangle.dashed"
        case .fullscreen: return "rectangle.on.rectangle"
        case .delayed: return "timer"
        }
    }
}

enum CaptureDelay: Int, CaseIterable, Identifiable, Codable {
    case none = 0
    case three = 3
    case five = 5
    case ten = 10

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .none: return L10n.string("No delay")
        case .three: return "3 s"
        case .five: return "5 s"
        case .ten: return "10 s"
        }
    }
}
