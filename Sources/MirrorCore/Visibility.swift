import Foundation

public enum ActiveContext: Equatable {
    case host(UUID)
    case reference(UUID)
    case unrelated
}

public enum WorkspaceVisibility {
    public static func shouldShow(workspaceID: UUID, active: ActiveContext, hostAvailable: Bool) -> Bool {
        guard hostAvailable else { return false }
        switch active {
        case .host(let id), .reference(let id): return workspaceID == id
        case .unrelated: return false
        }
    }
}

public enum HostAvailability: Equatable, Sendable {
    case available, hidden, minimized, closed, unavailable, restoring
}

public enum WorkspacePhase: String, Sendable {
    case hostActive = "Host active"
    case ownedReferenceActive = "Reference active"
    case inactive = "Inactive"
    case minimized = "Host minimized"
    case closed = "Host closed"
    case unavailable = "Host access unavailable"
    case restoring = "Binding needed"
    public var visible: Bool { self == .hostActive || self == .ownedReferenceActive }
    public static func resolve(workspaceID: UUID, active: ActiveContext, availability: HostAvailability)
        -> Self
    {
        switch availability {
        case .minimized: return .minimized
        case .closed: return .closed
        case .unavailable: return .unavailable
        case .restoring: return .restoring
        case .hidden: return .inactive
        case .available:
            switch active {
            case .host(let id): return id == workspaceID ? .hostActive : .inactive
            case .reference(let id): return id == workspaceID ? .ownedReferenceActive : .inactive
            case .unrelated: return .inactive
            }
        }
    }
}
