//
//  Profile.swift
//  Claude Switch
//

import Foundation

nonisolated enum Profile: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case personal
    case work

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .personal: String(localized: "profile.personal")
        case .work: String(localized: "profile.work")
        }
    }

    var symbolName: String {
        switch self {
        case .personal: "person.crop.circle"
        case .work: "briefcase"
        }
    }
}
