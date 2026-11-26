import SwiftUI
import UIKit

enum ThemeCategory: String, CaseIterable, Identifiable {
    case basic = "Basic", cool = "Cool", unique = "Unique"
    var id: String { rawValue }
}

struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let category: ThemeCategory
    let blurb: String
    let accent: Color
    /// Top → bottom gradient behind every screen; nil = the normal iPhone background.
    let background: [Color]?
    let scheme: ColorScheme?
    let font: Font.Design
    /// Alternate app icon that goes with it; nil = the original icon.
    let icon: String?

    static func == (a: Theme, b: Theme) -> Bool { a.id == b.id }

    var previewImage: String { "Preview-" + (icon.map { String($0.dropFirst("AppIcon-".count)) } ?? "Default") }

    static let classic = Theme(id: "classic", name: "Classic", category: .basic, blurb: "The original look.",
                               accent: .blue, background: nil, scheme: nil, font: .default, icon: nil)

    static let all: [Theme] = [
        classic,
        Theme(id: "light", name: "Clean Light", category: .basic, blurb: "Always light, crisp and simple.",
              accent: .blue, background: nil, scheme: .light, font: .default, icon: "AppIcon-Light"),
        Theme(id: "dark", name: "Dark", category: .basic, blurb: "Always dark, easy on the eyes at the gym.",
              accent: .blue, background: nil, scheme: .dark, font: .default, icon: nil),
        Theme(id: "mono", name: "Mono", category: .basic, blurb: "Black and white, no distractions.",
              accent: .primary, background: nil, scheme: nil, font: .default, icon: "AppIcon-Mono"),
        Theme(id: "crimson", name: "Crimson", category: .basic, blurb: "Red accents everywhere.",
              accent: .red, background: nil, scheme: nil, font: .default, icon: "AppIcon-Crimson"),
        Theme(id: "forest", name: "Forest", category: .basic, blurb: "Calm greens.",
              accent: .green, background: nil, scheme: nil, font: .default, icon: "AppIcon-Forest"),

        Theme(id: "midnight", name: "Midnight", category: .cool, blurb: "Deep navy with electric blue.",
              accent: Color(hex: 0x3AD1FF), background: [Color(hex: 0x0C1A3A), Color(hex: 0x02040C)], scheme: .dark,
              font: .default, icon: "AppIcon-Midnight"),
        Theme(id: "neon", name: "Neon", category: .cool, blurb: "Glowing green on pure black.",
              accent: Color(hex: 0x39FF88), background: [Color(hex: 0x0B0B10), .black], scheme: .dark,
              font: .rounded, icon: "AppIcon-Neon"),
        Theme(id: "sunset", name: "Sunset", category: .cool, blurb: "Purple fading into orange.",
              accent: Color(hex: 0xFF9F1C), background: [Color(hex: 0x3A1650), Color(hex: 0x6E2A1E)], scheme: .dark,
              font: .rounded, icon: "AppIcon-Sunset"),
        Theme(id: "ocean", name: "Ocean", category: .cool, blurb: "Teal water and deep blue.",
              accent: Color(hex: 0x2EE6D6), background: [Color(hex: 0x0B4F5C), Color(hex: 0x04182E)], scheme: .dark,
              font: .default, icon: "AppIcon-Ocean"),
        Theme(id: "ice", name: "Ice", category: .cool, blurb: "Frosty whites and blues.",
              accent: Color(hex: 0x1F7AE0), background: [.white, Color(hex: 0xDCEFFF)], scheme: .light,
              font: .rounded, icon: "AppIcon-Light"),

        Theme(id: "cockpit", name: "Glass Cockpit", category: .unique, blurb: "Amber on black with instrument-style numbers.",
              accent: Color(hex: 0xFFB000), background: [Color(hex: 0x0E1411), Color(hex: 0x020403)], scheme: .dark,
              font: .monospaced, icon: "AppIcon-Cockpit"),
        Theme(id: "acid", name: "Acid Wash", category: .unique, blurb: "Faded denim with a retro serif.",
              accent: Color(hex: 0x3E5C80), background: [Color(hex: 0xC9D8EA), Color(hex: 0xF4EFE2)], scheme: .light,
              font: .serif, icon: "AppIcon-Acid"),
        Theme(id: "gold", name: "Gold Rush", category: .unique, blurb: "Black and gold, a bit fancy.",
              accent: Color(hex: 0xF5C542), background: [Color(hex: 0x1A1408), .black], scheme: .dark,
              font: .serif, icon: "AppIcon-Gold"),
        Theme(id: "camo", name: "Camo", category: .unique, blurb: "Olive drab and khaki.",
              accent: Color(hex: 0xC2B280), background: [Color(hex: 0x2F3A22), Color(hex: 0x141A0E)], scheme: .dark,
              font: .default, icon: "AppIcon-Camo"),
        Theme(id: "vapor", name: "Vaporwave", category: .unique, blurb: "Hot pink and purple, very 80s.",
              accent: Color(hex: 0xFF6AD5), background: [Color(hex: 0x3B1360), Color(hex: 0x160626)], scheme: .dark,
              font: .rounded, icon: "AppIcon-Vapor"),
        Theme(id: "beast", name: "Beast Mode", category: .unique, blurb: "Blood red into black.",
              accent: Color(hex: 0xFF3B30), background: [Color(hex: 0x3D0000), .black], scheme: .dark,
              font: .default, icon: "AppIcon-Beast"),
    ]

    static func named(_ id: String) -> Theme { all.first { $0.id == id } ?? classic }
}

enum ThemeSettings {
    static let key = "themeID"
    static let matchIconKey = "themeMatchIcon"

    static func setIcon(_ name: String?) {
        guard UIApplication.shared.supportsAlternateIcons, UIApplication.shared.alternateIconName != name else { return }
        UIApplication.shared.setAlternateIconName(name) { _ in }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Puts the theme's gradient behind a List, Form or ScrollView.
struct ThemedBackground: ViewModifier {
    var fallback: Color? = nil
    @AppStorage(ThemeSettings.key) private var themeID = Theme.classic.id

    func body(content: Content) -> some View {
        let theme = Theme.named(themeID)
        if let bg = theme.background {
            content
                .scrollContentBackground(.hidden)
                .background(LinearGradient(colors: bg, startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        } else if let fallback {
            content.background(fallback)
        } else {
            content
        }
    }
}

extension View {
    func themedBackground(fallback: Color? = nil) -> some View { modifier(ThemedBackground(fallback: fallback)) }
}

// MARK: - Picker (People tab)

struct ThemeSection: View {
    @AppStorage(ThemeSettings.key) private var themeID = Theme.classic.id
    @AppStorage(ThemeSettings.matchIconKey) private var matchIcon = true

    var body: some View {
        Section {
            NavigationLink {
                ThemePickerView()
            } label: {
                HStack(spacing: 12) {
                    Image(Theme.named(themeID).previewImage)
                        .resizable()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading) {
                        Text("Theme")
                        Text(Theme.named(themeID).name).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Look")
        }
    }
}

struct ThemePickerView: View {
    @AppStorage(ThemeSettings.key) private var themeID = Theme.classic.id
    @AppStorage(ThemeSettings.matchIconKey) private var matchIcon = true

    private let icons: [String?] = [nil] + Theme.all.compactMap(\.icon).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }

    var body: some View {
        List {
            Section {
                Toggle("Change the app icon to match", isOn: $matchIcon)
            } footer: {
                Text("iPhone shows a quick message each time the icon changes.")
            }
            ForEach(ThemeCategory.allCases) { cat in
                Section(cat.rawValue) {
                    ForEach(Theme.all.filter { $0.category == cat }) { t in
                        Button {
                            themeID = t.id
                            if matchIcon { ThemeSettings.setIcon(t.icon) }
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(LinearGradient(colors: t.background ?? [Color(.systemGray5), Color(.systemGray4)],
                                                             startPoint: .top, endPoint: .bottom))
                                    Circle().fill(t.accent).frame(width: 16, height: 16)
                                }
                                .frame(width: 44, height: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.name).font(.system(.headline, design: t.font)).foregroundStyle(.primary)
                                    Text(t.blurb).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if t.id == themeID { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                    }
                }
            }
            Section("App icon only") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(icons, id: \.self) { icon in
                            Button {
                                ThemeSettings.setIcon(icon)
                            } label: {
                                Image("Preview-" + (icon.map { String($0.dropFirst("AppIcon-".count)) } ?? "Default"))
                                    .resizable()
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Theme")
        .themedBackground()
    }
}
