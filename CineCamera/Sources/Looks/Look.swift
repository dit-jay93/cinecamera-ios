import Foundation

public enum LookCategory: String, Codable, CaseIterable {
    case cinematic
    case period
    case stylized
    case broadcast
    case nightAndLowLight

    public var displayName: String {
        switch self {
        case .cinematic:        return "Cinematic"
        case .period:           return "Period"
        case .stylized:         return "Stylized"
        case .broadcast:        return "Broadcast"
        case .nightAndLowLight: return "Night & Low Light"
        }
    }
}

/// A named, serialisable look — a `PipelineGraph` plus presentation
/// metadata. Identifies its LUT (if any) by id; the actual mesh lives
/// in a `LUTLibrary` resolved at apply time.
public struct Look: Identifiable, Codable, Equatable {
    public let id: String
    public var name: String
    public var subtitle: String
    public var category: LookCategory
    public var graph: PipelineGraph
    public var lutReferenceId: String?
    public var creditedTo: String?

    public init(id: String,
                name: String,
                subtitle: String = "",
                category: LookCategory,
                graph: PipelineGraph,
                lutReferenceId: String? = nil,
                creditedTo: String? = nil) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.category = category
        self.graph = graph
        self.lutReferenceId = lutReferenceId
        self.creditedTo = creditedTo
    }
}
