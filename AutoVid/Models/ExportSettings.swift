import Foundation
import CoreGraphics

struct ExportSettings {
    var resolution: Resolution
    var frameRate: Int
    var bitrate: Int

    enum Resolution: String, CaseIterable {
        case original = "Original"
        case appStorePreview = "iPhone App Store"
        case ipadPortrait = "iPad App Store (Portrait)"
        case ipadLandscape = "iPad App Store (Landscape)"
        case hdPortrait = "HD Portrait"
        case hdLandscape = "HD Landscape"
        case custom = "Custom"

        var size: CGSize {
            switch self {
            case .original: return .zero // Use source size
            case .appStorePreview: return CGSize(width: 1290, height: 2796)
            case .ipadPortrait: return CGSize(width: 2048, height: 2732)
            case .ipadLandscape: return CGSize(width: 2732, height: 2048)
            case .hdPortrait: return CGSize(width: 1080, height: 1920)
            case .hdLandscape: return CGSize(width: 1920, height: 1080)
            case .custom: return CGSize(width: 1920, height: 1080)
            }
        }

        var description: String {
            switch self {
            case .original: return "Same as Source"
            case .appStorePreview: return "1290×2796"
            case .ipadPortrait: return "2048×2732"
            case .ipadLandscape: return "2732×2048"
            case .hdPortrait: return "1080×1920"
            case .hdLandscape: return "1920×1080"
            case .custom: return "Custom"
            }
        }
    }

    static let appStoreDefault = ExportSettings(
        resolution: .appStorePreview,
        frameRate: 30,
        bitrate: 24000000
    )
}

