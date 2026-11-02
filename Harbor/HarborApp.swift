import SwiftUI

@main struct HarborApp: App {
    @StateObject private var store: HarborStore
    @StateObject private var lock: HarborLock
    // A nil scheme follows device changes, including while the lock screen is visible.
    @AppStorage(HarborAppearance.preferenceKey) private var appearance = HarborAppearance.system.rawValue
    @Environment(\.scenePhase) private var scenePhase
    init() {
        // Initialize the isolated test store before reading its lock preference.
        let store = HarborStore()
        _store = StateObject(wrappedValue: store)
        _lock = StateObject(wrappedValue: HarborLock(keychain: HarborStore.keychain))
        // Retain a foreground notification delegate without prompting for permission on launch.
        PurchaseNotifications.shared.configure()
    }
    var body: some Scene {
        WindowGroup {
            ZStack {
                if lock.unlocked {
                    RootView().environmentObject(store).environmentObject(lock)
                        .task { store.load() }
                        .accessibilityHidden(scenePhase != .active)
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "lock.shield.fill").font(.system(size: 56)).foregroundStyle(HarborStyle.blue)
                        Text("Harbor is locked").font(.title.bold())
                        Text("Use Face ID, Touch ID, or your device passcode to open your records.").multilineTextAlignment(.center)
                        Button("Unlock Harbor") { Task { await lock.unlock() } }
                            .buttonStyle(.borderedProminent).disabled(lock.authenticating)
                        if let message = lock.message { Text(message).font(.callout).foregroundStyle(.secondary) }
                    }.padding(32)
                }
                // Hide root content during inactivity; the window shield also covers presented sheets.
                if scenePhase != .active {
                    HarborStyle.canvas.ignoresSafeArea()
                    Label("Harbor", systemImage: "lock.shield.fill").font(.title)
                }
            }
            .preferredColorScheme((HarborAppearance(rawValue: appearance) ?? .system).colorScheme)
            .onChange(of: scenePhase) { _, phase in
                // Capture files may arrive while the already-unlocked app is active or returning.
                if phase == .active && lock.unlocked {
                    store.drainApplePayInbox()
                    // Crossing into a new calendar month changes the eligible history window.
                    store.refreshBudgets()
                }
                if phase == .background {
                    lock.lock()
                    if lock.enabled { store.conceal() }
                }
            }
        }
    }
}
struct RootView: View {
    @EnvironmentObject var store: HarborStore
    @State private var tab = 0
    @State private var addingTransaction = false
    @State private var notifications = false
    @State private var showingProfile = false
    @State private var homeNavigationID = 0
    var body: some View {
        TabView(selection: $tab) {
            shell("Home") { HomeScreen(tab: $tab) }.tabItem { Label("Home", systemImage: "house") }.tag(0)
            shell("Activity") { ActivityScreen() }.tabItem { Label("Activity", systemImage: "receipt") }.tag(1)
            // Preserve Budget/Goals selection IDs used by Home while giving Categories its own place.
            shell("Categories") { CategoriesScreen() }.tabItem { Label("Categories", systemImage: "square.grid.2x2") }.tag(4)
            shell("Budget") { BudgetScreen() }.tabItem { Label("Budget", systemImage: "chart.pie") }.tag(2)
            shell("Goals") { GoalsScreen() }.tabItem { Label("Goals", systemImage: "target") }.tag(3)
        }
        .tint(HarborStyle.blue)
        .sheet(isPresented: $addingTransaction) { TransactionEditor() }
        .sheet(isPresented: $notifications) { NotificationsScreen() }
        .sheet(isPresented: $showingProfile) { ProfileScreen() }
        .alert("Unable to save", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    private func shell<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            // Each main destination shares the same compact header and profile entry point.
            content().navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .scrollResponsiveTabBar()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        // Recreate Home's stack so the logo also returns from a pushed Home destination.
                        Button { homeNavigationID += 1; tab = 0 } label: {
                            Label("Harbor", systemImage: "sailboat.fill").font(.headline).foregroundStyle(HarborStyle.blue)
                        }.accessibilityLabel("Go to Home").accessibilityIdentifier("navigation.home")
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { notifications = true } label: { Image(systemName: "bell") }.accessibilityLabel("Notifications")
                        Button { showingProfile = true } label: { Image(systemName: "person.crop.circle") }
                            .accessibilityLabel("Profile").accessibilityIdentifier("navigation.profile")
                    }
                }
                .safeAreaInset(edge: .bottom, alignment: .trailing) {
                    // Transaction entry belongs on Home and Activity, not settings or planning tabs.
                    if tab == 0 || tab == 1 {
                        Button { addingTransaction = true } label: { Image(systemName: "plus").font(.title2.bold()).foregroundStyle(.white).frame(width: 56, height: 56).background(HarborStyle.blue, in: Circle()).shadow(color: HarborStyle.blue.opacity(0.25), radius: 10, y: 4) }
                            .accessibilityLabel("Add transaction").padding(.trailing, 20).padding(.bottom, 8)
                    }
                }
        }.id(title == "Home" ? homeNavigationID : 0)
    }
}
