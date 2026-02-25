import SwiftUI

struct DashboardSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.system(size: AppConfig.UI.Dimensions.iconSmall, weight: .black))
                .foregroundColor(AppConfig.UI.Colors.textSecondary)

            content
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: AppConfig.UI.Dimensions.cornerRadius).fill(AppConfig.UI.Colors.panelBackground))
    }
}

struct StatusBadge: View {
    let text: String
    let isActive: Bool
    var color: Color = AppConfig.UI.Colors.success

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: AppConfig.UI.Dimensions.statusDotSize, height: AppConfig.UI.Dimensions.statusDotSize)
                .symbolEffect(.pulse, isActive: isActive)

            Text(text)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(AppConfig.UI.Colors.capsuleBackground))
    }
}

struct DeviceRow: View {
    let name: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(name)
        }
    }
}
