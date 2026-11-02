import SwiftUI
import UserNotifications

// Only generic settings and failure timestamps live outside the encrypted ledger.
@MainActor final class ReminderNotifications {
    static let shared = ReminderNotifications()
    static func key(_ name: String) -> String {
        (HarborStore.testing ? "harbor.ui-testing.reminders." : "harbor.reminders.") + name
    }
    static var options: ReminderOptions {
        let defaults = UserDefaults.standard
        return ReminderOptions(failures: defaults.bool(forKey: key("failures")), bills: defaults.bool(forKey: key("bills")),
            reviews: defaults.bool(forKey: key("reviews")), checkIns: defaults.bool(forKey: key("checkIns")),
            hour: defaults.object(forKey: key("hour")) as? Int ?? 19, minute: defaults.integer(forKey: key("minute")))
    }
    private let center = UNUserNotificationCenter.current()
    private var scheduling: Task<Void, Never>?
    private let prefix = "harbor.reminder."

    func refresh(data: FinanceData, attentionCount: Int) {
        let plan = ReminderPlanner.plan(data: data, attentionCount: attentionCount, options: Self.options)
        let previous = scheduling
        previous?.cancel()
        // Serialize replacement so an older in-flight add cannot recreate a cancelled or paid bill alert.
        scheduling = Task {
            await previous?.value
            guard !Task.isCancelled, !HarborStore.testing else { return }
            let pending = await center.pendingNotificationRequests()
            guard !Task.isCancelled else { return }
            let settings = await center.notificationSettings()
            guard !Task.isCancelled else { return }
            let authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            let desired = authorized ? Set(plan.map { prefix + $0.id }) : []
            // Replacing a surviving ID updates its time/content without racing an asynchronous removal.
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) && !desired.contains($0) })
            guard authorized else { return }
            for item in plan {
                guard !Task.isCancelled else { return }
                let content = UNMutableNotificationContent()
                content.title = item.title; content.body = item.body
                content.sound = .default; content.threadIdentifier = "harbor.reminders"
                var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
                components.timeZone = Calendar.current.timeZone
                let request = UNNotificationRequest(identifier: prefix + item.id, content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
                do { try await center.add(request) }
                catch {
                    // Scheduling cannot fail a ledger save or recursively generate another failure alert.
                    UserDefaults.standard.set("Some reminders could not be scheduled. Reopen Harbor to try again.", forKey: Self.key("deliveryError"))
                    return
                }
            }
            if !Task.isCancelled { UserDefaults.standard.removeObject(forKey: Self.key("deliveryError")) }
        }
    }

    func reportFailure() {
        let now = Date()
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.key("lastFailure"))
        guard Self.options.failures, !HarborStore.testing else { return }
        let previous = UserDefaults.standard.double(forKey: Self.key("lastFailureAlert"))
        // Group repeated errors into one alert per fifteen minutes without suppressing the in-app error.
        guard now.timeIntervalSince1970 - previous >= 15 * 60 else { return }
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.key("lastFailureAlert"))
        Task { await send(id: "harbor.failure", title: "Harbor needs attention",
            body: "An operation could not finish. Open Harbor or check the Shortcut’s error before trying again.", option: "failures") }
    }

    func celebrate(days: Int) {
        guard CheckInStreak.isMilestone(days) else { return }
        Task { await send(id: "harbor.streak.\(days)", title: "A new check-in milestone",
            body: "You completed \(days) daily check-ins in a row. Small reviews add up.", option: "checkIns") }
    }
    private func send(id: String, title: String, body: String, option: String) async {
        guard !HarborStore.testing, UserDefaults.standard.bool(forKey: Self.key(option)) else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional,
              UserDefaults.standard.bool(forKey: Self.key(option)) else { return }
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        content.threadIdentifier = "harbor.reminders"
        do { try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) }
        catch { UserDefaults.standard.set("An alert could not be delivered. Open Harbor to check its status.", forKey: Self.key("deliveryError")) }
    }

    static func resetTestPreferences() {
        // Never clear production preferences or notification permissions from an automated UI run.
        guard HarborStore.testing else { return }
        for name in ["failures", "bills", "reviews", "checkIns", "hour", "minute", "lastFailure", "lastFailureAlert", "deliveryError"] {
            UserDefaults.standard.removeObject(forKey: key(name))
        }
    }
}

// Each category requests permission only when the user explicitly enables its switch.
struct ReminderCategoryToggle: View {
    @EnvironmentObject var store: HarborStore
    @AppStorage private var enabled: Bool
    @State private var requesting = false
    @State private var message = ""
    let title: String
    let option: String
    init(_ title: String, option: String) {
        self.title = title; self.option = option
        _enabled = AppStorage(wrappedValue: false, ReminderNotifications.key(option))
    }
    var body: some View {
        Toggle(title, isOn: Binding(get: { enabled }, set: { value in
            if !value { enabled = false; store.refreshReminders(); return }
            requesting = true
            Task { @MainActor in
                defer { requesting = false }
                do {
                    enabled = try await PurchaseNotifications.shared.requestPermission()
                    message = enabled ? "" : "Allow notifications in iPhone Settings, then enable this reminder."
                } catch { message = "Could not request permission. Try again." }
                store.refreshReminders()
            }
        }))
        .disabled(requesting).accessibilityIdentifier("reminders." + option)
        if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
    }
}

struct ReminderSettingsSection: View {
    @EnvironmentObject var store: HarborStore
    @AppStorage(ReminderNotifications.key("hour")) private var hour = 19
    @AppStorage(ReminderNotifications.key("minute")) private var minute = 0
    @AppStorage(ReminderNotifications.key("deliveryError")) private var deliveryError = ""
    @AppStorage(ReminderNotifications.key("lastFailure")) private var lastFailure = 0.0
    private var reminderTime: Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date() }, set: { date in
            hour = Calendar.current.component(.hour, from: date)
            minute = Calendar.current.component(.minute, from: date)
            store.refreshReminders()
        })
    }
    var body: some View {
        Section("Reminders & alerts") {
            ReminderCategoryToggle("Failures & capture problems", option: "failures")
            ReminderCategoryToggle("Upcoming & overdue bills", option: "bills")
            ReminderCategoryToggle("Items needing review", option: "reviews")
            ReminderCategoryToggle("Daily check-ins & milestones", option: "checkIns")
            DatePicker("Reminder time", selection: reminderTime, displayedComponents: .hourAndMinute)
                .accessibilityIdentifier("reminders.time")
            Text("Bills: the day before and on the due date, plus one overdue digest. Review and check-in reminders are combined when both are enabled. All alerts hide financial details.").font(.caption)
            Text("Based on your saved records. Schedules refresh when you open or update Harbor: bills cover the next 30 days and daily reminders cover the next 7 days. Check uncertain bill schedules first. Delivery follows iPhone notification and Focus settings.").font(.caption).foregroundStyle(.secondary)
            if lastFailure > 0 {
                Text("An operation needed attention \(Date(timeIntervalSince1970: lastFailure).formatted(date: .abbreviated, time: .shortened)). Check the original error in Harbor or Shortcuts.")
                    .font(.caption).accessibilityIdentifier("reminders.lastFailure")
                Button("Clear failure notice") { lastFailure = 0 }
            }
            if !deliveryError.isEmpty { Text(deliveryError).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

// One deliberate review per local calendar day earns progress; opening the app or spending earns nothing.
struct DailyCheckInCard: View {
    @EnvironmentObject var store: HarborStore
    // Distinguish the sheet's controls from the Home card retained underneath it.
    var location = "home"
    var compact = false
    @State private var now = Date()
    @Environment(\.scenePhase) private var scenePhase
    private var streak: CheckInStreak { store.data.checkInStreak ?? CheckInStreak() }
    var body: some View {
        Group {
            if compact {
                // Home uses one prominent button; the notification card retains the detailed history.
                Button {
                    now = Date()
                    store.completeDailyCheckIn(on: now)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: streak.completed(on: now) ? "checkmark.circle.fill" : "flame.fill")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(streak.completed(on: now) ? "Checked in today" : "Daily check-in").font(.headline)
                            Text(store.data.isDemo ? "Start fresh in Settings to begin" : "\(streak.current(on: now)) day streak · Best \(streak.best)").font(.caption)
                        }
                        Spacer(minLength: 0)
                        if !streak.completed(on: now) { Image(systemName: "checkmark.circle") }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .disabled(streak.completed(on: now) || store.data.isDemo)
                .accessibilityIdentifier("checkin.complete." + location)
            } else {
                HarborCard {
                    Label("Your daily check-in", systemImage: "flame.fill").font(.headline).foregroundStyle(HarborStyle.blue)
                    Text("\(streak.current(on: now)) day streak · Best \(streak.best) · \(streak.total) check-in\(streak.total == 1 ? "" : "s")")
                        .font(.subheadline).accessibilityIdentifier("checkin.progress." + location)
                    if streak.milestone > 0 {
                        Label("\(streak.milestone)-day milestone earned", systemImage: "medal.fill").font(.caption).foregroundStyle(HarborStyle.teal)
                    }
                    Text("Check your recent activity, review items needing attention, and glance at upcoming bills. Then mark today’s check-in complete. Missing a day simply starts a fresh streak.").font(.caption).foregroundStyle(.secondary)
                    Button(streak.completed(on: now) ? "Checked in today" : "Complete daily check-in") {
                        now = Date()
                        store.completeDailyCheckIn(on: now)
                    }
                    .buttonStyle(.borderedProminent).disabled(streak.completed(on: now) || store.data.isDemo)
                    .accessibilityIdentifier("checkin.complete." + location)
                    if store.data.isDemo { Text("Start fresh in Settings to begin your own streak.").font(.caption) }
                }
            }
        }
        // Refresh across foreground returns and midnight without awarding a check-in automatically.
        .task {
            while !Task.isCancelled {
                now = Date()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { now = Date() } }
    }
}
