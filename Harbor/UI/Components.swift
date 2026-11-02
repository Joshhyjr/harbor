import SwiftUI
import UIKit

extension View {
    @ViewBuilder func scrollResponsiveTabBar() -> some View {
        // Native scroll phases include momentum and leave iOS 17's navigation available.
        if #available(iOS 18.0, *) {
            modifier(ScrollResponsiveTabBar())
        } else {
            self
        }
    }
}

@available(iOS 18.0, *)
private struct ScrollResponsiveTabBar: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var scrolling = false

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { _, phase in
                // A touch alone must not hide navigation; keep it hidden through deceleration.
                switch phase {
                case .interacting, .decelerating: scrolling = true
                case .idle: scrolling = false
                default: break
                }
            }
            // Keep navigation stable for VoiceOver, and respect the device's motion preference.
            .toolbar(scrolling && !voiceOverEnabled ? .hidden : .visible, for: .tabBar)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: scrolling)
            .onDisappear { scrolling = false }
    }
}

// Store appearance separately from the encrypted ledger so it also applies to the lock screen.
@MainActor enum HarborAppearance: String, CaseIterable {
    case system, light, dark
    static var preferenceKey: String { HarborStore.testing ? "harbor.ui-testing.appearance" : "harbor.appearance" }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}

// Dynamic colors preserve Harbor's light palette and resolve again when system appearance changes.
enum HarborStyle {
    private static func adaptive(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    static let blue = adaptive(UIColor(red: 0.28, green: 0.33, blue: 0.96, alpha: 1), UIColor(red: 0.38, green: 0.42, blue: 0.94, alpha: 1))
    static let navy = adaptive(UIColor(red: 0.09, green: 0.13, blue: 0.22, alpha: 1), .label)
    // Hero cards remain navy in either mode, so their labels and progress bars stay pale.
    static let heroAccent = Color(red: 0.88, green: 0.87, blue: 1)
    static let hero = Color(red: 0.09, green: 0.13, blue: 0.22)
    static let canvas = adaptive(UIColor(red: 0.97, green: 0.97, blue: 0.99, alpha: 1), .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    // Explicit opaque prompt colors avoid system placeholder dimming on dark search surfaces.
    static let searchPrompt = adaptive(.darkGray, UIColor(white: 0.85, alpha: 1))
    static let lavender = adaptive(UIColor(red: 0.88, green: 0.87, blue: 1, alpha: 1), UIColor(red: 0.19, green: 0.18, blue: 0.32, alpha: 1))
    static let teal = adaptive(UIColor(red: 0.1, green: 0.55, blue: 0.49, alpha: 1), UIColor(red: 0.28, green: 0.78, blue: 0.68, alpha: 1))
}
struct HarborCard<Content: View>: View {
    let dark: Bool
    @ViewBuilder var content: Content
    init(dark: Bool = false, @ViewBuilder content: () -> Content) { self.dark = dark; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(dark ? HarborStyle.hero : HarborStyle.surface, in: RoundedRectangle(cornerRadius: 26))
            .foregroundStyle(dark ? .white : HarborStyle.navy)
    }
}
struct Screen<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 20) { content }.padding(16).padding(.bottom, 24) }
            .background(HarborStyle.canvas)
    }
}
// Pass the enclosing button's press through without adding a gesture that could steal navigation.
private struct PiggyBankPressedKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var piggyBankPressed: Bool {
        get { self[PiggyBankPressedKey.self] }
        set { self[PiggyBankPressedKey.self] = newValue }
    }
}

struct PiggyBankCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.environment(\.piggyBankPressed, configuration.isPressed)
    }
}

// The silhouette fills from the feet upward; an unset limit stays distinct from zero usage.
struct PiggyBankGauge: View {
    let progress: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.piggyBankPressed) private var isPressed
    @State private var appeared = false
    @State private var reaction = 0
    // Match the existing budget labels: exactly 100% is reached, only greater than 100% is angry.
    private enum Mood: String {
        case unset = "No monthly limit set", calm = "On track"
        case concerned = "Near limit", reached = "Budget reached", angry = "Over budget"
    }
    private var mood: Mood {
        guard let progress else { return .unset }
        return progress > 1 ? .angry : progress == 1 ? .reached : progress >= 0.85 ? .concerned : .calm
    }
    private var fill: Double { min(1, max(0, progress ?? 0)) }
    private var color: Color {
        guard let progress else { return .secondary }
        return progress > 1 ? .red : progress >= 0.85 ? .orange : HarborStyle.blue
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Keep the tail outside the clipping mask so the pig remains recognizable when empty.
                Path { path in
                    path.move(to: CGPoint(x: geometry.size.width * 0.18, y: geometry.size.height * 0.43))
                    path.addCurve(to: CGPoint(x: geometry.size.width * 0.08, y: geometry.size.height * 0.30), control1: CGPoint(x: 0, y: geometry.size.height * 0.50), control2: CGPoint(x: 0, y: geometry.size.height * 0.18))
                }.stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                PiggyBankShape().fill(color.opacity(0.08))
                Rectangle().fill(color.opacity(0.65))
                    .frame(height: geometry.size.height * fill)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .clipShape(PiggyBankShape())
                PiggyBankShape().stroke(color, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                // The coin slot, eye and nostril remain readable at every fill level and appearance.
                Capsule().fill(HarborStyle.navy).frame(width: geometry.size.width * 0.18, height: 2)
                    .position(x: geometry.size.width * 0.49, y: geometry.size.height * 0.25)
                Circle().fill(HarborStyle.navy).frame(width: 4, height: 4)
                    .position(x: geometry.size.width * 0.77, y: geometry.size.height * 0.38)
                Circle().fill(HarborStyle.navy).frame(width: 3, height: 3)
                    .position(x: geometry.size.width * 0.92, y: geometry.size.height * 0.49)
                // A smile becomes a worried mouth and slanted brow as spending approaches its limit.
                if mood != .unset {
                    Path { path in
                        path.move(to: CGPoint(x: geometry.size.width * 0.75, y: geometry.size.height * 0.60))
                        path.addQuadCurve(to: CGPoint(x: geometry.size.width * 0.84, y: geometry.size.height * 0.60),
                                          control: CGPoint(x: geometry.size.width * 0.795, y: geometry.size.height * (mood == .calm ? 0.72 : 0.49)))
                    }.stroke(HarborStyle.navy, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    if mood != .calm {
                        Capsule().fill(HarborStyle.navy)
                            .frame(width: geometry.size.width * 0.10, height: 2)
                            .rotationEffect(.degrees(mood == .angry ? 24 : -18))
                            .position(x: geometry.size.width * 0.77, y: geometry.size.height * 0.30)
                    }
                }
            }.padding(2)
        }
        // One short spring on entry, with finite reactions on press or a budget-status change.
        .scaleEffect(reduceMotion || appeared ? 1 : 0.92, anchor: .bottom)
        .offset(y: reduceMotion || appeared ? 0 : 5)
        .phaseAnimator([0.0, -1.0, 1.0, -0.6, 0.6, 0.0], trigger: reaction) { content, phase in
            content
                .rotationEffect(.degrees(reduceMotion ? 0 : phase * (mood == .angry ? 5 : 3)), anchor: .bottom)
                .offset(x: reduceMotion || mood != .angry ? 0 : phase * 2)
        } animation: { _ in reduceMotion ? nil : .easeInOut(duration: 0.08) }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: fill)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: mood)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.55)) { appeared = true }
            if mood == .angry && !reduceMotion { reaction += 1 }
        }
        .onDisappear { appeared = false }
        .onChange(of: isPressed) { _, pressed in
            if pressed && !reduceMotion { reaction += 1 }
        }
        .onChange(of: mood) { _, _ in
            if appeared && !reduceMotion { reaction += 1 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Budget used")
        .accessibilityValue(progress.map { "\(Int($0 * 100)) percent, \(mood.rawValue)" } ?? mood.rawValue)
    }
}

private struct PiggyBankShape: Shape {
    func path(in rect: CGRect) -> Path {
        // Normalized coordinates let the same vector scale cleanly in Home tiles and Budget cards.
        var path = Path()
        path.move(to: CGPoint(x: 0.29, y: 0.23))
        path.addLine(to: CGPoint(x: 0.28, y: 0.05))
        path.addQuadCurve(to: CGPoint(x: 0.44, y: 0.18), control: CGPoint(x: 0.39, y: 0.07))
        path.addCurve(to: CGPoint(x: 0.85, y: 0.38), control1: CGPoint(x: 0.65, y: 0.10), control2: CGPoint(x: 0.79, y: 0.23))
        path.addLine(to: CGPoint(x: 0.97, y: 0.39))
        path.addLine(to: CGPoint(x: 0.97, y: 0.60))
        path.addLine(to: CGPoint(x: 0.85, y: 0.62))
        path.addQuadCurve(to: CGPoint(x: 0.76, y: 0.77), control: CGPoint(x: 0.82, y: 0.72))
        path.addLine(to: CGPoint(x: 0.73, y: 0.94))
        path.addLine(to: CGPoint(x: 0.60, y: 0.94))
        path.addLine(to: CGPoint(x: 0.58, y: 0.83))
        path.addQuadCurve(to: CGPoint(x: 0.38, y: 0.81), control: CGPoint(x: 0.46, y: 0.86))
        path.addLine(to: CGPoint(x: 0.35, y: 0.94))
        path.addLine(to: CGPoint(x: 0.22, y: 0.94))
        path.addLine(to: CGPoint(x: 0.21, y: 0.72))
        path.addCurve(to: CGPoint(x: 0.29, y: 0.23), control1: CGPoint(x: 0.06, y: 0.57), control2: CGPoint(x: 0.12, y: 0.32))
        path.closeSubpath()
        return path.applying(CGAffineTransform(scaleX: rect.width, y: rect.height))
            .applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}

struct MoneyLabel: View {
    @EnvironmentObject private var store: HarborStore
    let cents: Int
    var size: CGFloat = 28
    var currency: String? = nil
    @ScaledMetric(relativeTo: .title) private var scale = 1.0
    var body: some View { Text(store.format(cents, currency: currency)).font(.system(size: size * scale, weight: .bold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1).accessibilityLabel(store.format(cents, currency: currency) + " " + (currency ?? store.data.reportingCurrency)) }
}
// Every category/goal surface shares the same renderer, including labels without a surrounding tile.
struct SymbolGlyph: View {
    let symbol: String
    var body: some View {
        Group {
            if let emoji = HarborIcon.emoji(in: symbol) { Text(emoji) }
            else { Image(systemName: symbol) }
        }.accessibilityHidden(true)
    }
}

struct IconTile: View {
    let symbol: String
    var body: some View { SymbolGlyph(symbol: symbol).font(.title3).foregroundStyle(HarborStyle.blue).frame(width: 44, height: 44).background(HarborStyle.lavender, in: RoundedRectangle(cornerRadius: 14)).accessibilityHidden(true) }
}
struct MonthPicker: View {
    @EnvironmentObject var store: HarborStore
    var body: some View {
        // Explicit styles keep the two arrows independent inside List and Form rows.
        HStack {
            Button { store.shiftMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.buttonStyle(.borderless).accessibilityLabel("Previous month")
            Spacer()
            Text(store.month.formatted(.dateTime.month(.wide).year())).font(.headline).accessibilityIdentifier("month.selected")
            Spacer()
            Button { store.shiftMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.buttonStyle(.borderless).accessibilityLabel("Next month")
        }.background(HarborStyle.surface, in: Capsule())
    }
}
struct Stat: View {
    var currency: String? = nil
    let title: String
    let cents: Int
    var body: some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption).opacity(0.7); MoneyLabel(cents: cents, size: 17, currency: currency) }.frame(maxWidth: .infinity, alignment: .leading) }
}
struct LedgerRow: View {
    @EnvironmentObject var store: HarborStore
    let transaction: Transaction
    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: transaction.isTransfer ? "arrow.left.arrow.right" : transaction.kind == .income ? "arrow.down.left" : store.data.category(transaction.categoryID)?.symbol ?? "creditcard")
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.merchant).font(.headline).foregroundStyle(HarborStyle.navy)
                Text(transaction.isTransfer ? "Transfer · " + store.data.accountName(transaction.transferAccountID!) : store.data.category(transaction.categoryID)?.name ?? "").font(.caption).foregroundStyle(.secondary)
                Text(store.data.accountName(transaction.accountID)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                MoneyLabel(cents: transaction.signedAmount, size: 17, currency: store.data.currency(transaction.accountID)).foregroundStyle(transaction.kind == .income ? HarborStyle.teal : HarborStyle.navy)
                Label(transaction.needsReview ? "Needs review" : "Reviewed", systemImage: transaction.needsReview ? "flag" : "checkmark.seal").font(.caption2).foregroundStyle(HarborStyle.blue)
            }
        }.padding(.vertical, 8).contentShape(Rectangle())
    }
}
struct EmptyCard: View {
    let title: String
    let detail: String
    var body: some View { HarborCard { Label(title, systemImage: "tray").font(.headline); Text(detail).font(.subheadline).foregroundStyle(.secondary) } }
}
struct SectionTitle: View {
    let title: String
    var body: some View { Text(title).font(.title3.bold()).padding(.top, 4) }
}

// Unselected filters use adaptive text and surfaces in both appearances.
struct FilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) { Text(title).font(.subheadline.weight(.semibold)).padding(.horizontal, 16).frame(minHeight: 44).foregroundStyle(selected ? .white : HarborStyle.navy).background(selected ? HarborStyle.blue : HarborStyle.lavender.opacity(0.5), in: Capsule()) }
            .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// Reporting chooses one currency; account balances are never implicitly converted or summed across currencies.
struct ReportingCurrencyPicker: View {
    @EnvironmentObject var store: HarborStore
    var title = "Report totals in"
    var body: some View {
        Picker(title, selection: Binding(get: { store.data.reportingCurrency }, set: { code in store.update { $0.reportingCurrencyCode = code } })) {
            ForEach(Currency.supported, id: \.self) { Text($0).tag($0) }
        }.accessibilityIdentifier("report.currency")
    }
}

// Keep optional technical explanations one tap away from concise, task-focused descriptions.
struct LearnMoreLink: View {
    let title: String
    let paragraphs: [String]
    var body: some View {
        NavigationLink("Learn more") { HarborHelpScreen(title: title, paragraphs: paragraphs) }
            .font(.subheadline).accessibilityLabel("Learn more about " + title)
    }
}
struct HarborHelpScreen: View {
    let title: String
    let paragraphs: [String]
    var body: some View {
        List {
            ForEach(paragraphs, id: \.self) { paragraph in Text(paragraph).font(.body) }
        }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}
