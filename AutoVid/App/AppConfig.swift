import SwiftUI

enum AppConfig {
    
    enum UI {
        
        @MainActor enum Colors {
            static let primary = Color.blue
            static let success = Color.green
            static let warning = Color.orange
            static let error = Color.red
            static let recording = Color.red
            
            static let panelBackground = Color.primary.opacity(0.05)
            static let panelBackgroundDark = Color.black.opacity(0.15)
            static let capsuleBackground = Color.primary.opacity(0.1)
            static let successBackground = Color.green.opacity(0.05)
            static let warningBackground = Color.orange.opacity(0.05)
            static let errorBackground = Color.red.opacity(0.1)
            static let slightlyTransparent = Color.white.opacity(0.03)
            
            static let textSecondary = Color.secondary
        }
        
        enum Dimensions {
            static let defaultPadding: CGFloat = 16
            static let cornerRadius: CGFloat = 12
            static let smallCornerRadius: CGFloat = 8
            
            static let defaultWindowWidth: CGFloat = 450
            static let defaultWindowHeight: CGFloat = 650
            static let editorWindowWidth: CGFloat = 900
            static let editorWindowHeight: CGFloat = 750
            
            static let iconSmall: CGFloat = 10
            static let iconMedium: CGFloat = 14
            static let iconLarge: CGFloat = 20
            static let iconHuge: CGFloat = 30
            static let statusDotSize: CGFloat = 8
        }
        
        enum Strings {
            static let appName = "AutoVid"
            static let settingsTitle = "Settings"
            static let exportTitle = "Export Settings"
            static let editorTitle = "AutoVid Editor"
            
            static let refresh = "Refresh"
            static let browse = "Browse..."
            static let selectProjectFirst = "Select Project First"
            static let selectScheme = "Select Scheme"
            static let noSchemes = "No schemes found"
            
            static let exportButton = "Export Video"
            static let exporting = "Exporting..."
            static let resolution = "Resolution"
            static let frameRate = "Frame Rate"
            static let bitrate = "Bitrate"
        }
        
        enum Icons {
            static let settings = "gearshape.fill"
            static let close = "xmark.circle.fill"
            static let warning = "exclamationmark.triangle.fill"
            static let success = "checkmark.circle.fill"
            static let error = "xmark.circle.fill"
            
            static let play = "play.fill"
            static let pause = "pause.fill"
            static let stop = "stop.fill"
            
            static let refresh = "arrow.clockwise"
            static let terminal = "terminal.fill"
            static let cable = "cable.connector"
            
            static let export = "square.and.arrow.down.fill"
            static let folder = "folder.fill"
            
            static let chevronUp = "chevron.up"
            static let chevronDown = "chevron.down"
            
            static let video = "video.fill"
            static let hammer = "hammer.fill"
            
            static let iphone = "iphone.gen3"
            static let laptop = "laptopcomputer"
        }
    }
    
    enum Configuration {
        enum Defaults {
            static let defaultWindowSize = CGSize(width: 450, height: 650)
            static let editorWindowSize = CGSize(width: 900, height: 750)
            
            static let defaultFrameRate = 30
            static let defaultBitrate = 24_000_000
            static let appStoreLimitSeconds: Double = 30.0
        }
        
        enum Capture {
            static let targetWidth = 1290
            static let targetHeight = 2796
            static let folderName = "AutoVid"
            static let bitrate: Int = 24_000_000
        }
        
        enum StorageKeys {
            static let autoOpenEditor = "autoOpenEditor"
        }
    }
}

