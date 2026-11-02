import XCTest

// Exercise the real native forms and relaunch behavior against an isolated test ledger.
final class HarborUITests: XCTestCase {
    // Progress must survive an encrypted relaunch, and a second tap on the same day must earn nothing.
    @MainActor func testDailyCheckInPersistsWithoutChangingFinances() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        app.buttons["Notifications"].tap()
        let complete = app.buttons["checkin.complete.notifications"]
        reveal(complete, in: app)
        XCTAssertFalse(complete.isEnabled, "Demo data must not earn a personal streak")
        app.buttons["Done"].tap()
        openSettings(in: app)
        openSettingsDetail("reset", in: app)
        reveal(app.buttons["settings.clearAll"], in: app)
        app.buttons["settings.clearAll"].tap()
        app.alerts.buttons["Clear all data"].tap()
        XCTAssertTrue(app.staticTexts["All data cleared. Add an account to begin."].waitForExistence(timeout: 5))
        selectTab("Home", in: app)
        app.buttons["Notifications"].tap()
        reveal(complete, in: app); complete.tap()
        XCTAssertEqual(app.staticTexts["checkin.progress.notifications"].label, "1 day streak · Best 1 · 1 check-in")
        XCTAssertFalse(complete.isEnabled)
        app.terminate(); app.launchArguments = ["-ui-testing"]; app.launch()
        app.buttons["Notifications"].tap()
        reveal(complete, in: app)
        XCTAssertFalse(complete.isEnabled)
        XCTAssertEqual(app.staticTexts["checkin.progress.notifications"].label, "1 day streak · Best 1 · 1 check-in")
        capture(app, "Daily check-in retained after relaunch")
        app.buttons["Done"].tap()
        selectTab("Activity", in: app)
        XCTAssertFalse(app.staticTexts["Whole Foods Market"].exists)
    }

    // Category preferences are independent, remain opt-in, and persist across application relaunch.
    @MainActor func testReminderPreferencesPersistIndependently() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch(); app.buttons["Notifications"].tap()
        let failures = app.switches["reminders.failures"]
        let bills = app.switches["reminders.bills"]
        // List virtualizes offscreen rows; reveal each control before reading its accessibility value.
        reveal(bills, in: app)
        XCTAssertEqual(bills.value as? String, "0")
        reveal(failures, in: app)
        XCTAssertEqual(failures.value as? String, "0")
        let control = failures.switches.firstMatch
        if control.exists { control.tap() } else { failures.tap() }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 3), springboard.buttons["Allow"].exists {
            springboard.buttons["Allow"].tap()
        }
        expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: failures)
        waitForExpectations(timeout: 5)
        reveal(bills, in: app)
        XCTAssertEqual(bills.value as? String, "0")
        app.terminate(); app.launchArguments = ["-ui-testing"]; app.launch()
        app.buttons["Notifications"].tap()
        reveal(failures, in: app)
        XCTAssertEqual(failures.value as? String, "1")
        reveal(bills, in: app)
        XCTAssertEqual(bills.value as? String, "0")
        reveal(failures, in: app)
        if control.exists { control.tap() } else { failures.tap() }
        XCTAssertEqual(failures.value as? String, "0")
        capture(app, "Independent reminder controls")
    }

    // Exercise explicit permission, relaunch persistence, and the shared Apple Pay setup preference.
    @MainActor func testPurchaseNotificationOptInPersists() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        app.buttons["Notifications"].tap()
        let alerts = app.switches["notifications.purchaseAlerts"]
        XCTAssertTrue(alerts.waitForExistence(timeout: 5))
        XCTAssertEqual(alerts.value as? String, "0")
        addUIInterruptionMonitor(withDescription: "Notification permission") { alert in
            if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap(); return true }
            return false
        }
        // iOS exposes the labelled row and an inner control; tap the actual switch.
        let control = alerts.switches.firstMatch
        if control.exists { control.tap() } else { alerts.tap() }
        // Handle the system prompt directly as well, because it can arrive before another app gesture.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 3), springboard.buttons["Allow"].exists {
            springboard.buttons["Allow"].tap()
        }
        let enabled = NSPredicate(format: "value == '1'")
        expectation(for: enabled, evaluatedWith: alerts)
        waitForExpectations(timeout: 5)
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        openSettings(in: app)
        let shortcuts = app.buttons["Apple Pay Shortcuts"]
        reveal(shortcuts, in: app); shortcuts.tap()
        reveal(alerts, in: app)
        XCTAssertEqual(alerts.value as? String, "1")
        if control.exists { control.tap() } else { alerts.tap() }
        XCTAssertEqual(alerts.value as? String, "0")
        app.terminate(); app.launch()
        app.buttons["Notifications"].tap()
        XCTAssertEqual(alerts.value as? String, "0")
        capture(app, "Purchase alerts disabled after relaunch")
    }

    // The new tab scopes real activity, preserves category edits, and keeps Settings one profile away.
    @MainActor func testCategoriesTabBrowsingEditingAndSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        XCTAssertFalse(app.tabBars.buttons["Settings"].exists)
        selectTab("Categories", in: app)
        // Removed controls must not displace the native filters and category grid.
        XCTAssertFalse(app.buttons["categories.create"].exists)
        XCTAssertFalse(app.buttons["categories.organize"].exists)
        XCTAssertFalse(app.staticTexts["categories.monthlySpending"].exists)
        let tiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "categories.view."))
        XCTAssertGreaterThanOrEqual(tiles.count, 2)
        let first = tiles.element(boundBy: 0).frame
        let second = tiles.element(boundBy: 1).frame
        XCTAssertEqual(first.minY, second.minY, accuracy: 2)
        XCTAssertLessThan(first.maxX, second.minX)
        capture(app, "Categories overview")
        let search = app.textFields["categories.search"]
        reveal(search, in: app); search.tap(); search.typeText("groc\n")
        let groceries = app.buttons["categories.view.Groceries"]
        reveal(groceries, in: app)
        XCTAssertTrue(groceries.label.contains("152.63"))
        XCTAssertTrue(groceries.label.contains("2 transactions"))
        XCTAssertFalse(app.buttons["categories.view.Other"].exists)
        capture(app, "Categories monthly collection")
        groceries.tap()
        XCTAssertEqual(app.staticTexts["categoryTransactions.count"].label, "2 transactions")
        XCTAssertTrue(app.buttons["categoryTransactions.entry.Whole Foods Market"].exists)
        app.buttons["categoryTransactions.editCategory"].tap()
        XCTAssertTrue(app.navigationBars["Edit Category"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["category.automaticBudget"].exists)
        app.buttons["icon.picker"].tap()
        let emoji = app.textFields["icon.emoji"]
        XCTAssertTrue(emoji.waitForExistence(timeout: 5))
        emoji.tap(); emoji.typeText("🍉")
        app.buttons["icon.useEmoji"].tap()
        app.buttons["Save"].tap()
        app.buttons["Done"].tap()
        // A month with no activity stays empty; saved categories remain available explicitly.
        for _ in 0..<8 { if app.buttons["Previous month"].isHittable { break }; app.swipeDown() }
        app.buttons["Previous month"].tap()
        XCTAssertTrue(app.staticTexts["A fresh page"].waitForExistence(timeout: 5))
        app.segmentedControls["categories.scope"].buttons["All saved"].tap()
        let other = app.buttons["categories.view.Other"]
        reveal(other, in: app); XCTAssertTrue(other.exists)
        // The overview is for browsing; category creation stays available through Settings.
        openSettingsDetail("categories", in: app)
        app.buttons["Manage categories"].tap()
        let create = app.buttons["Create category"]
        reveal(create, in: app); create.tap()
        let name = app.textFields["Category name"]
        name.tap(); name.typeText("Weekend Fun")
        app.buttons["Save"].tap()
        selectTab("Categories", in: app)
        XCTAssertTrue(app.segmentedControls["categories.scope"].buttons["All saved"].isSelected)
        let created = app.buttons["categories.view.Weekend Fun"]
        reveal(created, in: app); XCTAssertTrue(created.exists)
        capture(app, "Categories saved collection")
        openSettings(in: app)
        XCTAssertTrue(app.staticTexts["Private by design"].waitForExistence(timeout: 5))
        capture(app, "Settings from Profile")
        selectTab("Budget", in: app)
        XCTAssertTrue(app.staticTexts["MASTER ENVELOPE · CAD"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = ["-ui-testing"]; app.launch()
        selectTab("Categories", in: app)
        reveal(groceries, in: app); groceries.tap()
        app.buttons["categoryTransactions.editCategory"].tap()
        XCTAssertEqual(app.buttons["icon.picker"].value as? String, "🍉")
        app.buttons["Monthly budget (optional)"].tap()
        XCTAssertEqual(app.textFields["Limit (CAD)"].value as? String, "900")
        app.buttons["Cancel"].tap(); app.buttons["Done"].tap()
        for _ in 0..<8 { if app.segmentedControls["categories.scope"].isHittable { break }; app.swipeDown() }
        app.segmentedControls["categories.scope"].buttons["All saved"].tap()
        reveal(created, in: app); XCTAssertTrue(created.exists)
        openSettings(in: app)
        app.segmentedControls["settings.appearance"].buttons["Dark"].tap()
        selectTab("Categories", in: app)
        for _ in 0..<8 { if app.buttons["Previous month"].isHittable { break }; app.swipeDown() }
        capture(app, "Categories dark collection")
    }

    // Exercise wrapping with real saved data, then verify the accessibility layout uses one column.
    @MainActor func testCategoryGridLongContentAndAccessibility() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        app.buttons["Add transaction"].tap()
        app.textFields["transaction.merchant"].tap()
        app.textFields["transaction.merchant"].typeText("Grid layout QA")
        app.textFields["transaction.amount"].tap()
        app.textFields["transaction.amount"].typeText("99999999.12")
        let categoryName = "A very long household essentials category"
        let custom = app.textFields["transaction.newCategory"]
        reveal(custom, in: app); custom.tap(); custom.typeText(categoryName)
        app.buttons["Save"].tap()
        selectTab("Categories", in: app)
        let category = app.buttons["categories.view." + categoryName]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        XCTAssertTrue(category.label.contains("99,999,999.12"))
        XCTAssertTrue(category.label.contains("CAD spent"))
        XCTAssertGreaterThanOrEqual(category.frame.minX, 0)
        XCTAssertLessThanOrEqual(category.frame.maxX, app.frame.maxX)
        capture(app, "Categories long name and large amount")
        app.terminate()
        app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); selectTab("Categories", in: app)
        reveal(category, in: app)
        XCTAssertTrue(category.isHittable)
        let firstFrame = category.frame
        capture(app, "Categories accessibility long content")
        let dining = app.buttons["categories.view.Dining"]
        reveal(dining, in: app)
        // Full-width cells distinguish the single-column fallback even after scrolling.
        XCTAssertEqual(firstFrame.width, dining.frame.width, accuracy: 2)
        XCTAssertGreaterThan(firstFrame.width, app.frame.width * 0.8)
        dining.tap()
        XCTAssertTrue(app.staticTexts["categoryTransactions.count"].waitForExistence(timeout: 5))
    }

    // Exercise the actual budget editor at each facial-expression boundary, keeping taps navigable.
    @MainActor func testPiggyBankBudgetExpressions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        selectTab("Budget", in: app)
        let groceries = app.buttons["budget.category.Groceries"]
        reveal(groceries, in: app)
        XCTAssertTrue(groceries.label.contains("On track"))
        capture(app, "Calm piggy bank")
        // The isolated demo ledger contains exactly $152.63 of grocery spending.
        for (amount, status) in [("170", "Near limit"), ("152.63", "Budget reached"), ("150", "Over budget"), ("0", "No budget")] {
            reveal(groceries, in: app); groceries.tap()
            app.buttons["categoryTransactions.editBudget"].tap()
            let limit = app.textFields["Limit (CAD)"]
            XCTAssertTrue(limit.waitForExistence(timeout: 5))
            let existing = limit.value as? String ?? ""
            limit.tap()
            limit.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count) + amount)
            app.buttons["Save"].tap()
            app.buttons["Done"].tap()
            reveal(groceries, in: app)
            XCTAssertTrue(groceries.label.contains(status), groceries.label)
            capture(app, "Piggy bank - " + status)
        }
    }

    // Budget planning keeps its controls while matching Categories' grid and large-text fallback.
    @MainActor func testBudgetGridLayoutAndAccessibility() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch(); selectTab("Budget", in: app)
        let tiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "budget.category."))
        let first = tiles.element(boundBy: 0)
        reveal(first, in: app)
        XCTAssertGreaterThanOrEqual(tiles.count, 2)
        let firstFrame = first.frame
        let secondFrame = tiles.element(boundBy: 1).frame
        XCTAssertEqual(firstFrame.minY, secondFrame.minY, accuracy: 2)
        XCTAssertLessThan(firstFrame.maxX, secondFrame.minX)
        // Bring the cards above the floating tab bar for useful visual review captures.
        if first.frame.minY > app.frame.height * 0.4 { app.swipeUp() }
        capture(app, "Budget grid light")
        openSettings(in: app)
        app.segmentedControls["settings.appearance"].buttons["Dark"].tap()
        selectTab("Budget", in: app); reveal(first, in: app)
        if first.frame.minY > app.frame.height * 0.4 { app.swipeUp() }
        capture(app, "Budget grid dark")
        app.terminate()
        app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); selectTab("Budget", in: app)
        reveal(first, in: app)
        XCTAssertGreaterThan(first.frame.width, app.frame.width * 0.8)
        if first.frame.minY > app.frame.height * 0.4 { app.swipeUp() }
        capture(app, "Budget grid accessibility")
        first.tap()
        XCTAssertTrue(app.navigationBars["Category transactions"].waitForExistence(timeout: 5))
    }

    // Emoji saves use the same category/goal drafts, including cancellation and encrypted relaunch.
    @MainActor func testEmojiIconsPersistForCategoriesAndGoals() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch(); openSettings(in: app)
        openSettingsDetail("categories", in: app)
        app.buttons["Manage categories"].tap()
        let groceries = app.buttons["categories.edit.Groceries"]
        reveal(groceries, in: app); groceries.tap()
        let picker = app.buttons["icon.picker"]
        reveal(picker, in: app); picker.tap()
        let emoji = app.textFields["icon.emoji"]
        XCTAssertTrue(emoji.waitForExistence(timeout: 5))
        emoji.tap(); emoji.typeText("coffee")
        XCTAssertFalse(app.buttons["icon.useEmoji"].isEnabled)
        XCTAssertTrue(app.staticTexts["icon.validation"].exists)
        emoji.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "🐾")
        app.buttons["icon.useEmoji"].tap()
        XCTAssertEqual(picker.value as? String, "🐾")
        app.buttons["Save"].tap()
        capture(app, "Category emoji in Harbor list")
        selectTab("Budget", in: app)
        capture(app, "Category emoji in budget")
        selectTab("Goals", in: app)
        let goal = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Emergency Fund'")).firstMatch
        reveal(goal, in: app); goal.tap()
        reveal(picker, in: app); picker.tap()
        emoji.tap(); emoji.typeText("🏡")
        app.buttons["icon.useEmoji"].tap()
        XCTAssertEqual(picker.value as? String, "🏡")
        app.buttons["Save"].tap()
        capture(app, "Goal emoji in Harbor tile")
        app.terminate(); app.launchArguments = ["-ui-testing"]; app.launch()
        openSettings(in: app); openSettingsDetail("categories", in: app)
        app.buttons["Manage categories"].tap(); reveal(groceries, in: app); groceries.tap()
        reveal(picker, in: app); XCTAssertEqual(picker.value as? String, "🐾")
        picker.tap(); app.buttons["icon.symbol.house"].tap()
        XCTAssertEqual(picker.value as? String, "house")
        app.buttons["Cancel"].tap()
        groceries.tap(); reveal(picker, in: app)
        XCTAssertEqual(picker.value as? String, "🐾")
        app.buttons["Cancel"].tap()
        selectTab("Goals", in: app); reveal(goal, in: app); goal.tap()
        reveal(picker, in: app); XCTAssertEqual(picker.value as? String, "🏡")
        picker.tap(); capture(app, "Emoji icon editor and expanded Harbor icons")
    }
    // Use a real import to verify the history estimate, manual override, and encrypted relaunch persistence.
    @MainActor func testAutomaticBudgetsUseHistoryAndPreserveManualOverride() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        importMonthlyStatement(in: app, replacingDemo: true)
        openSettingsDetail("categories", in: app)
        app.buttons["Manage categories"].tap()
        toggleSavedCategories(in: app)
        let groceries = app.buttons["categories.edit.Groceries"]
        reveal(groceries, in: app); groceries.tap()
        XCTAssertEqual(app.switches["category.automaticBudget"].value as? String, "0")
        toggleAutomaticBudget(in: app)
        XCTAssertEqual(app.staticTexts["category.estimatedLimit"].label, "Estimated limit: $20.00")
        app.buttons["Save"].tap()
        app.terminate(); app.launchArguments = ["-ui-testing"]; app.launch()
        openSettingsDetail("categories", in: app)
        app.buttons["Manage categories"].tap(); toggleSavedCategories(in: app)
        reveal(groceries, in: app); groceries.tap()
        XCTAssertEqual(app.switches["category.automaticBudget"].value as? String, "1")
        XCTAssertEqual(app.staticTexts["category.estimatedLimit"].label, "Estimated limit: $20.00")
        capture(app, "Automatic category budget from imported history")
        toggleAutomaticBudget(in: app)
        let limit = app.textFields["Limit (CAD)"]
        let existing = limit.value as? String ?? ""
        limit.tap(); limit.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count) + "123")
        app.buttons["Save"].tap()
        app.terminate(); app.launch()
        openSettingsDetail("categories", in: app)
        app.buttons["Manage categories"].tap(); toggleSavedCategories(in: app)
        reveal(groceries, in: app); groceries.tap()
        XCTAssertEqual(app.switches["category.automaticBudget"].value as? String, "0")
        XCTAssertEqual(limit.value as? String, "123")
        // Returning to automatic previews historical spending, rather than the unsaved manual amount.
        toggleAutomaticBudget(in: app)
        XCTAssertEqual(app.staticTexts["category.estimatedLimit"].label, "Estimated limit: $20.00")
    }

    @MainActor private func toggleAutomaticBudget(in app: XCUIApplication) {
        let row = app.switches["category.automaticBudget"]
        let control = row.switches.firstMatch
        if control.exists { control.tap() } else { row.tap() }
    }

    // Every root tab must regain usable navigation after a scroll, including a reverse scroll.
    @MainActor func testBottomMenuReturnsAfterScrolling() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        let menu = app.tabBars.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        for title in ["Home", "Activity", "Categories", "Budget", "Goals"] {
            menu.buttons[title].tap()
            app.swipeUp(velocity: .slow)
            XCTAssertTrue(menu.waitForExistence(timeout: 5), "Menu must return on \(title)")
            XCTAssertTrue(menu.buttons["Home"].isHittable)
            app.swipeDown(velocity: .slow)
            XCTAssertTrue(menu.waitForExistence(timeout: 5))
            XCTAssertTrue(menu.buttons["Categories"].isHittable)
        }
        menu.buttons["Home"].tap()
        XCTAssertTrue(app.buttons["Add transaction"].isHittable)
    }

    // The overview routes real tools, and account edits still save through the existing encrypted store.
    @MainActor func testSettingsOverviewRoutesAndAccountEditing() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch(); openSettings(in: app)
        XCTAssertTrue(app.staticTexts["Private by design"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Preferences"].exists)
        XCTAssertFalse(app.buttons["Add transaction"].isHittable)
        capture(app, "Settings overview light top")
        let appearance = app.segmentedControls["settings.appearance"]
        appearance.buttons["Dark"].tap()
        capture(app, "Settings overview dark top")
        reveal(app.buttons["settings.reset"], in: app)
        capture(app, "Settings overview dark security")
        for _ in 0..<8 { if appearance.isHittable { break }; app.swipeDown() }
        appearance.buttons["Light"].tap()
        openSettingsDetail("accounts", in: app)
        app.buttons["Add account"].tap()
        let name = app.textFields["Account name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Settings QA")
        let balance = app.textFields["Opening balance (CAD)"]
        balance.tap(); balance.typeText("25")
        app.buttons["Save"].tap()
        let account = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Settings QA'")).firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 5)); account.tap()
        XCTAssertTrue(app.navigationBars["Edit Account"].waitForExistence(timeout: 5))
        name.tap(); name.typeText(" edited"); app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Settings QA edited'")).firstMatch.waitForExistence(timeout: 5))
        openSettingsDetail("categories", in: app)
        XCTAssertTrue(app.buttons["Manage categories"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings.simplified"].exists)
        openSettingsDetail("imports", in: app)
        for title in ["Import CSV or PDF", "Import history", "Monthly reconciliation"] {
            let link = app.buttons[title]; reveal(link, in: app); link.tap()
            XCTAssertFalse(app.navigationBars["Imports & reconciliation"].exists)
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        openSettingsDetail("reset", in: app)
        XCTAssertTrue(app.buttons["Start fresh with my own data"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let backups = app.buttons["Backups and recovery"]
        reveal(backups, in: app); backups.tap()
        XCTAssertTrue(app.buttons["backup.createKey"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = ["-ui-testing"]; app.launch()
        openSettings(in: app); openSettingsDetail("accounts", in: app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Settings QA edited'")).firstMatch.waitForExistence(timeout: 5))
    }
    // At accessibility sizes the appearance picker gets its own line and every destination stays reachable.
    @MainActor func testSettingsOverviewLargeText() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); openSettings(in: app)
        XCTAssertTrue(app.staticTexts["Private by design"].waitForExistence(timeout: 10))
        capture(app, "Settings accessibility text top")
        openSettingsDetail("accounts", in: app)
        XCTAssertTrue(app.buttons["Add account"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let lock = app.switches["settings.appLock"]
        reveal(lock, in: app); XCTAssertTrue(lock.isHittable)
        capture(app, "Settings accessibility security")
        openSettingsDetail("reset", in: app)
        let clear = app.buttons["settings.clearAll"]
        reveal(clear, in: app); XCTAssertTrue(clear.isHittable)
        capture(app, "Settings accessibility reset")
    }
    // Exercise a real statement import, receipt, saved comparison, relaunch, and an ordinary transaction edit.
    @MainActor func testImportHistoryAndMonthlyReconciliationPersist() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        importMonthlyStatement(in: app, replacingDemo: true)
        openStatementHistory(in: app)
        let receipt = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "importHistory.receipt.")).firstMatch
        XCTAssertTrue(receipt.waitForExistence(timeout: 5)); receipt.tap()
        XCTAssertEqual(app.descendants(matching: .any)["importHistory.added"].value as? String, "3")
        XCTAssertEqual(app.descendants(matching: .any)["importHistory.duplicates"].value as? String, "0")
        let compare = app.buttons["importHistory.compare"]
        reveal(compare, in: app); compare.tap()
        let result = app.staticTexts["reconciliation.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5)); XCTAssertEqual(result.label, "Balances match")
        capture(app, "Monthly reconciliation overview")
        let balance = app.textFields["reconciliation.statementBalance"]
        for _ in 0..<8 { if balance.isHittable { break }; app.swipeDown() }
        balance.tap()
        let old = balance.value as? String ?? ""
        balance.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + "1074")
        XCTAssertEqual(result.label, "Balances differ")
        XCTAssertEqual(app.descendants(matching: .any)["reconciliation.difference"].value as? String, "$1.00")
        let save = app.buttons["reconciliation.save"]
        reveal(save, in: app); save.tap()
        let status = app.staticTexts["reconciliation.status"]
        reveal(status, in: app)
        XCTAssertTrue(status.waitForExistence(timeout: 5)); XCTAssertTrue(status.label.contains("comparison saved"))
        capture(app, "Monthly reconciliation saved difference")
        app.terminate(); app.launchArguments = ["-ui-testing"]; app.launch()
        openSettings(in: app)
        openSettingsDetail("imports", in: app)
        let reconciliation = app.buttons["Monthly reconciliation"]
        reveal(reconciliation, in: app); reconciliation.tap()
        let saved = app.buttons["reconciliation.saved.2026-09-30"]
        reveal(saved, in: app); XCTAssertTrue(saved.exists); saved.tap()
        for _ in 0..<8 { if result.isHittable { break }; app.swipeDown() }
        XCTAssertEqual(result.label, "Balances differ")
        let review = app.buttons["Review transactions in closing month"]
        reveal(review, in: app); review.tap()
        let cafe = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Cafe")).firstMatch
        XCTAssertTrue(cafe.waitForExistence(timeout: 5)); cafe.tap()
        let amount = app.textFields["transaction.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5)); amount.tap()
        let previous = amount.value as? String ?? ""
        amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + "6.00")
        app.buttons["Save"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        for _ in 0..<8 { if result.isHittable { break }; app.swipeDown() }
        XCTAssertEqual(result.label, "Balances match")
        capture(app, "Saved statement comparison recalculates after edit")
    }
    // Reimporting the same statement records skipped rows without creating new financial entries.
    @MainActor func testDuplicateOnlyImportSavesReceipt() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        importMonthlyStatement(in: app, replacingDemo: true)
        importMonthlyStatement(in: app, replacingDemo: false)
        app.terminate(); app.launchArguments = ["-ui-testing"]; app.launch()
        openStatementHistory(in: app)
        let receipts = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "importHistory.receipt."))
        XCTAssertEqual(receipts.count, 2)
        receipts.firstMatch.tap()
        XCTAssertEqual(app.descendants(matching: .any)["importHistory.added"].value as? String, "0")
        XCTAssertEqual(app.descendants(matching: .any)["importHistory.duplicates"].value as? String, "3")
        capture(app, "Duplicate-only import receipt")
    }
    @MainActor private func importMonthlyStatement(in app: XCUIApplication, replacingDemo: Bool) {
        openSettings(in: app)
        openSettingsDetail("imports", in: app)
        let importing = app.buttons["Import CSV or PDF"]
        reveal(importing, in: app); importing.tap()
        chooseImport("Harbor-monthly-reconciliation", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["import.count"].waitForExistence(timeout: 15))
        if replacingDemo {
            let replace = app.switches["import.removeDemo"]
            reveal(replace, in: app)
            // Newer iOS exposes an inner switch; target it so the row cannot swallow the toggle tap.
            let control = replace.switches.firstMatch
            if control.exists { control.tap() } else { replace.tap() }
            XCTAssertEqual(replace.value as? String, "1")
        }
        let commit = app.buttons["import.commit"]
        reveal(commit, in: app)
        XCTAssertEqual(commit.label, replacingDemo ? "Import 3 transactions" : "Record skipped import")
        XCTAssertTrue(commit.isEnabled); commit.tap()
        app.buttons["Save import"].tap()
        XCTAssertTrue(app.alerts["Import complete"].waitForExistence(timeout: 5))
        app.alerts.buttons["Done"].tap()
    }
    @MainActor private func openStatementHistory(in app: XCUIApplication) {
        openSettings(in: app)
        openSettingsDetail("imports", in: app)
        let history = app.buttons["Import history"]
        reveal(history, in: app); history.tap()
    }
    // Export from the real Files flow; attachments contain only the recovery key for this fictional QA ledger.
    @MainActor func testBackupSourceExportForDeviceMigration() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing", "-ui-testing-legacy"]
        app.launch()
        openSettings(in: app)
        app.segmentedControls["settings.appearance"].buttons["Dark"].tap()
        let shortcuts = app.buttons["Apple Pay Shortcuts"]
        reveal(shortcuts, in: app); shortcuts.tap()
        app.buttons["shortcuts.account"].tap(); app.buttons["TD Chequing · CAD"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let backups = app.buttons["Backups and recovery"]
        reveal(backups, in: app); backups.tap()
        try exportBackup("Harbor-device-migration", in: app)
    }
    // Run after installing the newer build over the source app, without a reset or namespace change.
    @MainActor func testBackupSourceSurvivesAppUpdate() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch(); openSettings(in: app)
        XCTAssertTrue(app.segmentedControls["settings.appearance"].buttons["Dark"].isSelected)
        assertProfileName("Migration Test", in: app)
        let shortcuts = app.buttons["Apple Pay Shortcuts"]
        reveal(shortcuts, in: app); shortcuts.tap()
        XCTAssertEqual(app.buttons["shortcuts.account"].value as? String, "TD Chequing · CAD")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let backups = app.buttons["Backups and recovery"]
        reveal(backups, in: app); backups.tap()
        try exportBackup("Harbor-after-update", in: app)
    }
    // A separate simulator imports the source export with its recovery key and exports the restored ledger.
    @MainActor func testBackupDestinationRestoreAndExport() throws {
        let recoveryKey = try migrationRecoveryKey()
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch(); openSettings(in: app)
        let backups = app.buttons["Backups and recovery"]
        reveal(backups, in: app); backups.tap()
        app.buttons["backup.chooseRestore"].tap()
        chooseBackupFixture("Harbor-device-migration", in: app)
        let key = app.secureTextFields["backup.restoreKey"]
        XCTAssertTrue(key.waitForExistence(timeout: 5)); key.tap()
        key.typeText(recoveryKey)
        app.buttons["backup.validate"].tap()
        XCTAssertTrue(app.buttons["Replace records"].waitForExistence(timeout: 5))
        app.buttons["Replace records"].tap()
        let status = app.staticTexts["backup.status"]
        reveal(status, in: app)
        XCTAssertTrue(status.label.contains("Backup restored"))
        app.terminate(); app.launch(); openSettings(in: app)
        assertProfileName("Migration Test", in: app)
        // Device preferences are intentionally local, rather than restored from another phone's backup.
        XCTAssertTrue(app.segmentedControls["settings.appearance"].buttons["System"].isSelected)
        reveal(backups, in: app); backups.tap()
        try exportBackup("Harbor-restored-roundtrip", in: app)
    }
    // The host passes only a synthetic recovery key to the test runner for the separate-device run.
    private func migrationRecoveryKey() throws -> String {
        guard let key = ProcessInfo.processInfo.environment["HARBOR_QA_RECOVERY_KEY"] else {
            throw XCTSkip("Requires a staged fictional source export and HARBOR_QA_RECOVERY_KEY in the test runner environment.")
        }
        return key
    }
    // Failed restore validation must leave the destination ledger untouched, including after relaunch.
    @MainActor func testBackupDestinationRejectsWrongKeyAndDamage() throws {
        let validKey = try migrationRecoveryKey()
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch(); openSettings(in: app)
        let backups = app.buttons["Backups and recovery"]
        reveal(backups, in: app); backups.tap()
        for (filename, recoveryKey) in [("Harbor-device-migration", String(repeating: "CD", count: 32)),
                                         ("Harbor-damaged-migration", validKey)] {
            let choose = app.buttons["backup.chooseRestore"]
            for _ in 0..<8 { if choose.isHittable { break }; app.swipeDown() }
            choose.tap(); chooseBackupFixture(filename, in: app)
            let key = app.secureTextFields["backup.restoreKey"]
            XCTAssertTrue(key.waitForExistence(timeout: 5)); key.tap(); key.typeText(recoveryKey)
            app.buttons["backup.validate"].tap()
            let status = app.staticTexts["backup.status"]
            reveal(status, in: app)
            XCTAssertTrue(status.label.contains("Could not unlock backup"))
            XCTAssertFalse(app.buttons["Replace records"].exists)
            let cancel = app.buttons["Cancel restore"]
            for _ in 0..<8 { if cancel.isHittable { break }; app.swipeDown() }
            cancel.tap()
        }
        app.terminate(); app.launch(); openSettings(in: app)
        assertProfileName("Maya", in: app)
    }
    @MainActor private func exportBackup(_ filename: String, in app: XCUIApplication) throws {
        let create = app.buttons["backup.createKey"]
        for _ in 0..<8 { if create.isHittable { break }; app.swipeDown() }
        create.tap()
        let key = app.staticTexts["backup.recoveryKey"].label
        XCTAssertEqual(key.count, 64)
        let attachment = XCTAttachment(string: key)
        attachment.name = filename + "-fictional-key"
        attachment.lifetime = .keepAlways
        add(attachment)
        let confirmation = app.secureTextFields["backup.confirmKey"]
        confirmation.tap(); confirmation.typeText(key)
        app.buttons["backup.exportEncrypted"].tap()
        let picker = XCUIApplication(bundleIdentifier: "com.apple.DocumentManagerUICore.Service")
        XCTAssertTrue(picker.wait(for: .runningForeground, timeout: 10))
        // Foreground activation precedes loading the Files form; wait before editing its filename.
        let name = picker.textFields["DOCPicker.filenameTextField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap()
        let old = name.value as? String ?? ""
        // Files appends the registered backup extension; enter only the base name.
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + filename)
        if picker.buttons["On My iPhone"].exists { picker.buttons["On My iPhone"].tap() }
        else if picker.staticTexts["On My iPhone"].exists { picker.staticTexts["On My iPhone"].tap() }
        // Select a real folder cell rather than a transient navigation title named Harbor.
        let folder = picker.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", "Harbor,")).firstMatch
        if folder.waitForExistence(timeout: 3) {
            if folder.images.firstMatch.exists { folder.images.firstMatch.tap() } else { folder.tap() }
        }
        let save = picker.buttons["Save"].exists ? picker.buttons["Save"] : picker.buttons["Export"]
        XCTAssertTrue(save.waitForExistence(timeout: 5)); save.tap()
        // Dedicated QA exports have fixed names so a repeat run can replace its own earlier artifact.
        if picker.buttons["Replace"].waitForExistence(timeout: 2) { picker.buttons["Replace"].tap() }
        let status = app.staticTexts["backup.status"]
        reveal(status, in: app)
        XCTAssertTrue(status.label.contains("Backup exported"), app.debugDescription)
    }
    // Correcting a restored purchase keeps it held across restart until the user explicitly releases it.
    @MainActor func testHeldApplePayAccountRecovery() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing", "-ui-testing-held-capture"]
        app.launch()
        func openShortcuts() {
            openSettings(in: app)
            let shortcuts = app.buttons["Apple Pay Shortcuts"]
            reveal(shortcuts, in: app); shortcuts.tap()
        }
        openShortcuts()
        let release = app.buttons["Release this capture for import"]
        reveal(release, in: app)
        XCTAssertTrue(app.staticTexts["Destination: Account unavailable"].exists)
        app.buttons["Change destination account"].tap()
        app.buttons["TD Chequing · CAD"].tap()
        XCTAssertTrue(app.staticTexts["Destination: TD Chequing"].exists)
        XCTAssertTrue(release.exists)
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch(); openShortcuts(); reveal(release, in: app)
        XCTAssertTrue(app.staticTexts["Destination: TD Chequing"].exists)
        release.tap()
        XCTAssertFalse(release.exists)
        XCTAssertFalse(app.alerts["Unable to save"].exists, "Releasing must not also fire Delete held capture")
        selectTab("Activity", in: app)
        XCTAssertTrue(app.staticTexts["Restored held purchase"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        selectTab("Activity", in: app)
        XCTAssertTrue(app.staticTexts["Restored held purchase"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "Restored held purchase").count, 1)
    }
    // A setup choice must survive navigation and process restart without enabling capture.
    @MainActor func testApplePayAccountChoicePersists() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        func openShortcuts() {
            openSettings(in: app)
            let shortcuts = app.buttons["Apple Pay Shortcuts"]
            reveal(shortcuts, in: app); shortcuts.tap()
        }
        openShortcuts()
        let picker = app.buttons["shortcuts.account"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String, "Choose an account")
        picker.tap()
        app.buttons["TD Chequing · CAD"].tap()
        XCTAssertEqual(picker.value as? String, "TD Chequing · CAD")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openShortcuts()
        XCTAssertEqual(picker.value as? String, "TD Chequing · CAD")
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        openShortcuts()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String, "TD Chequing · CAD")
        // Changing and clearing the saved choice must also persist across launches.
        picker.tap()
        app.buttons["EQ Savings · CAD"].tap()
        app.terminate(); app.launch(); openShortcuts()
        XCTAssertEqual(picker.value as? String, "EQ Savings · CAD")
        picker.tap()
        app.buttons["Choose an account"].tap()
        app.terminate(); app.launch(); openShortcuts()
        XCTAssertEqual(picker.value as? String, "Choose an account")
    }
    // A Budget drill-down must show only its category/month, and retain access to both native editors.
    @MainActor func testBudgetCategoryShowsRelatedTransactions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        selectTab("Budget", in: app)
        let groceries = app.buttons["budget.category.Groceries"]
        reveal(groceries, in: app); groceries.tap()
        XCTAssertTrue(app.navigationBars["Category transactions"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["categoryTransactions.count"].label, "2 transactions")
        XCTAssertTrue(app.buttons["categoryTransactions.entry.Whole Foods Market"].exists)
        XCTAssertTrue(app.buttons["categoryTransactions.entry.Farm Boy Organic"].exists)
        XCTAssertFalse(app.buttons["categoryTransactions.entry.Blue Bottle Coffee"].exists)
        capture(app, "Budget category related transactions")
        app.buttons["categoryTransactions.editBudget"].tap()
        XCTAssertTrue(app.navigationBars["Edit Budget"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Category name"].value as? String, "Groceries")
        app.buttons["Cancel"].tap()
        app.buttons["categoryTransactions.entry.Whole Foods Market"].tap()
        XCTAssertTrue(app.textFields["transaction.merchant"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["transaction.merchant"].value as? String, "Whole Foods Market")
        app.buttons["Cancel"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.tabBars.buttons["Budget"].exists)
    }
    // Monthly category views change with transactions while saved limits remain accessible on request.
    @MainActor func testMonthlyCategoriesHideUnusedSavedCategories() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        selectTab("Budget", in: app)
        let groceries = app.buttons["budget.category.Groceries"]
        reveal(groceries, in: app)
        XCTAssertTrue(groceries.exists)
        XCTAssertFalse(app.buttons["budget.category.Other"].exists)
        for _ in 0..<10 { if app.buttons["Previous month"].isHittable { break }; app.swipeDown() }
        app.buttons["Previous month"].tap()
        reveal(app.staticTexts["No spending categories here"], in: app)
        XCTAssertTrue(app.staticTexts["No spending categories here"].exists)
        XCTAssertFalse(groceries.exists)
        app.buttons["Manage saved categories"].tap()
        XCTAssertTrue(app.switches["categories.showSaved"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["categories.edit.Groceries"].exists)
        capture(app, "No unused categories in an empty month")
        toggleSavedCategories(in: app)
        XCTAssertEqual(app.switches["categories.showSaved"].value as? String, "1")
        capture(app, "Saved category toggle enabled")
        reveal(app.buttons["categories.edit.Groceries"], in: app)
        XCTAssertTrue(app.buttons["categories.edit.Groceries"].exists, app.debugDescription)
        capture(app, "Saved categories remain accessible by choice")
    }
    // The user's category overrides a clear model/rule suggestion and is created with the saved transaction.
    @MainActor func testTransactionCreatesOnlyUserChosenCategory() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        app.buttons["Add transaction"].tap()
        app.textFields["transaction.merchant"].tap()
        app.textFields["transaction.merchant"].typeText("Apple iCloud")
        app.textFields["transaction.amount"].tap()
        app.textFields["transaction.amount"].typeText("3.99")
        reveal(app.buttons["Suggest category"], in: app)
        app.buttons["Suggest category"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Suggested: Subscription")).firstMatch.waitForExistence(timeout: 5))
        let custom = app.textFields["transaction.newCategory"]
        reveal(custom, in: app)
        custom.tap(); custom.typeText("Cloud storage")
        app.buttons["Save"].tap()
        selectTab("Budget", in: app)
        let category = app.buttons["budget.category.Cloud storage"]
        reveal(category, in: app)
        XCTAssertTrue(category.exists)
        XCTAssertFalse(app.buttons["budget.category.Subscription"].exists)
        capture(app, "User category overrides subscription suggestion")
        app.terminate(); app.launchArguments = ["-ui-testing"]; app.launch()
        selectTab("Budget", in: app)
        reveal(category, in: app)
        XCTAssertTrue(category.exists)
    }
    // One clear iCloud charge needs only a schedule check; confirming it must survive encrypted relaunch.
    @MainActor func testICloudSchedulePromptCanBeConfirmed() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        openSettings(in: app)
        openSettingsDetail("imports", in: app)
        reveal(app.buttons["Import CSV or PDF"], in: app)
        app.buttons["Import CSV or PDF"].tap()
        chooseImport("Harbor-test-icloud-single", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["import.count"].waitForExistence(timeout: 15))
        reveal(app.switches["import.removeDemo"], in: app)
        app.switches["import.removeDemo"].tap()
        reveal(app.buttons["import.commit"], in: app)
        app.buttons["import.commit"].tap(); app.buttons["Save import"].tap()
        XCTAssertTrue(app.alerts["Import complete"].waitForExistence(timeout: 10))
        app.alerts.buttons["Done"].tap()
        // Settings retains the lower import-row scroll position after dismissing the preview.
        for _ in 0..<8 { if app.buttons["Recurring Bills"].isHittable { break }; app.swipeDown() }
        app.buttons["Recurring Bills"].tap()
        let prompt = app.buttons["bill.reviewSchedule.Apple iCloud"]
        reveal(prompt, in: app)
        XCTAssertTrue(prompt.exists)
        XCTAssertFalse(app.buttons["bill.markPaid.Apple iCloud"].exists)
        XCTAssertEqual(app.staticTexts["bill.category.Apple iCloud"].label, "Subscription")
        capture(app, "iCloud asks only for missing billing schedule")
        prompt.tap()
        app.buttons["Save"].tap()
        XCTAssertFalse(prompt.exists)
        app.terminate(); app.launchArguments = ["-ui-testing"]; app.launch()
        openSettings(in: app)
        reveal(app.buttons["Recurring Bills"], in: app)
        app.buttons["Recurring Bills"].tap()
        XCTAssertTrue(app.staticTexts["bill.category.Apple iCloud"].waitForExistence(timeout: 5))
        XCTAssertFalse(prompt.exists)
        capture(app, "Confirmed iCloud schedule persists")
    }
    // A category-only approval must be visible in the preview and persist through the encrypted store.
    @MainActor func testClearCategoryReviewFlagsPersist() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        openSettings(in: app)
        openSettingsDetail("categories", in: app)
        reveal(app.buttons["Manage categories"], in: app)
        app.buttons["Manage categories"].tap()
        app.buttons["Auto-categorise unreviewed transactions"].tap()
        XCTAssertTrue(app.navigationBars["Review Categories"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "3 clear transactions no longer need review")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Presto Transit"].exists)
        capture(app, "Clear transaction review flags preview")
        reveal(app.buttons["categories.apply"], in: app)
        XCTAssertTrue(app.buttons["categories.apply"].isEnabled)
        app.buttons["categories.apply"].tap()
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        selectTab("Activity", in: app)
        app.staticTexts["Presto Transit"].tap()
        let review = app.switches["Needs review"]
        reveal(review, in: app)
        XCTAssertEqual(review.value as? String, "0")
        capture(app, "Clear transaction remains reviewed after relaunch")
    }
    @MainActor func testNativeFlowsAndPersistence() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["TOTAL NET WORTH"].waitForExistence(timeout: 10))
        capture(app, "Home")
        app.buttons["Add transaction"].tap()
        let merchant = app.textFields["transaction.merchant"]
        XCTAssertTrue(merchant.waitForExistence(timeout: 5))
        merchant.tap(); merchant.typeText("UI Test Coffee")
        let amount = app.textFields["transaction.amount"]
        amount.tap(); amount.typeText("12.34")
        app.buttons["Save"].tap()
        selectTab("Activity", in: app)
        XCTAssertTrue(app.staticTexts["UI Test Coffee"].waitForExistence(timeout: 5))
        capture(app, "Activity")
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        selectTab("Activity", in: app)
        XCTAssertTrue(app.staticTexts["UI Test Coffee"].waitForExistence(timeout: 5))
        app.staticTexts["UI Test Coffee"].tap()
        let editAmount = app.textFields["transaction.amount"]
        XCTAssertTrue(editAmount.waitForExistence(timeout: 5))
        editAmount.tap()
        editAmount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "20.00")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'UI Test Coffee' AND label CONTAINS '20.00'")).firstMatch.waitForExistence(timeout: 5))
        selectTab("Budget", in: app)
        XCTAssertTrue(app.staticTexts["MASTER ENVELOPE · CAD"].waitForExistence(timeout: 5))
        capture(app, "Budget")
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Housing & Utilities'")).firstMatch.tap()
        // Budget categories now open their transaction list before the budget editor.
        app.buttons["categoryTransactions.editBudget"].tap()
        XCTAssertTrue(app.navigationBars["Edit Budget"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        app.buttons["Done"].tap()
        selectTab("Goals", in: app)
        XCTAssertTrue(app.staticTexts["TOTAL SAVED ACROSS GOALS"].waitForExistence(timeout: 5))
        capture(app, "Goals")
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Emergency Fund'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Edit Goal"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        // Analytics lives with spending exploration in Budget.
        selectTab("Budget", in: app)
        app.buttons["budget.analytics"].tap()
        XCTAssertTrue(app.staticTexts["Trajectory Curve"].waitForExistence(timeout: 5))
        capture(app, "Analytics")
    }
    @MainActor func testCreateBudgetGoalAndPayBill() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        selectTab("Budget", in: app)
        reveal(app.buttons["Create Custom Category"], in: app)
        app.buttons["Create Custom Category"].tap()
        let categoryName = app.textFields["Category name"]
        XCTAssertTrue(categoryName.waitForExistence(timeout: 5))
        categoryName.tap(); categoryName.typeText("UI Budget")
        // These scenarios deliberately create fixed limits rather than history-derived estimates.
        toggleAutomaticBudget(in: app)
        let limit = app.textFields["Limit (CAD)"]
        limit.tap(); limit.typeText(XCUIKeyboardKey.delete.rawValue + "100.00")
        app.buttons["Save"].tap()
        XCTAssertFalse(app.navigationBars["New Category"].exists)
        selectTab("Goals", in: app)
        reveal(app.buttons["Create New Goal"], in: app)
        app.buttons["Create New Goal"].tap()
        let goalName = app.textFields["Goal name"]
        XCTAssertTrue(goalName.waitForExistence(timeout: 5))
        goalName.tap(); goalName.typeText("UI Goal")
        let target = app.textFields["Target (CAD)"]
        target.tap(); target.typeText("500.00")
        app.buttons["Save"].tap()
        XCTAssertFalse(app.navigationBars["New Goal"].exists)
        reveal(app.staticTexts["UI Goal"], in: app)
        XCTAssertTrue(app.staticTexts["UI Goal"].exists)
        openSettings(in: app)
        app.buttons["Recurring Bills"].tap()
        app.buttons["bill.markPaid.Spotify Family"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["bill.paid.Spotify Family"].waitForExistence(timeout: 5))
        selectTab("Activity", in: app)
        let search = app.textFields["Search transactions"]
        search.tap(); search.typeText("Spotify")
        XCTAssertTrue(app.staticTexts["Spotify Family"].waitForExistence(timeout: 5))
    }
    // A locked launch must never render financial screens, even across process restarts.
    @MainActor func testLockedLaunchHidesRecordsAndPersists() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing", "-ui-testing-locked"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Harbor is locked"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["TOTAL NET WORTH"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Keychain is unavailable'")).firstMatch.exists)
        XCTAssertFalse(app.tabBars.buttons["Categories"].exists)
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["Unlock Harbor"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.buttons["Home"].exists)
        capture(app, "Locked launch")
    }
    // Migration must preserve the user's records and reopen the encrypted replacement.
    @MainActor func testLegacyMigrationPersists() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing", "-ui-testing-legacy"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Categories"].waitForExistence(timeout: 10))
        openSettings(in: app)
        assertProfileName("Migration Test", in: app)
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        openSettings(in: app)
        assertProfileName("Migration Test", in: app)
    }
    // Use the system Files picker and the supplied fixtures staged in Harbor's Documents folder.
    @MainActor func testCSVImportThenPDFDuplicatePreview() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        openSettings(in: app)
        openSettingsDetail("imports", in: app)
        reveal(app.buttons["Import CSV or PDF"], in: app)
        app.buttons["Import CSV or PDF"].tap()
        chooseImport("Harbor-test-transactions", in: app)
        guard app.descendants(matching: .any)["import.count"].waitForExistence(timeout: 15) else {
            capture(app, "CSV picker state"); XCTFail(app.debugDescription); return
        }
        reveal(app.switches["import.removeDemo"], in: app)
        XCTAssertEqual(app.switches["import.removeDemo"].value as? String, "0")
        app.switches["import.removeDemo"].tap()
        reveal(app.buttons["import.commit"], in: app)
        XCTAssertTrue(app.buttons["import.commit"].isEnabled)
        capture(app, "CSV import preview")
        app.buttons["import.commit"].tap()
        app.buttons["Save import"].tap()
        XCTAssertTrue(app.alerts["Import complete"].waitForExistence(timeout: 10))
        app.alerts.buttons["Done"].tap()
        openSettingsDetail("imports", in: app)
        reveal(app.buttons["Import CSV or PDF"], in: app)
        app.buttons["Import CSV or PDF"].tap()
        chooseImport("Harbor-test-statement", in: app)
        guard app.descendants(matching: .any)["import.count"].waitForExistence(timeout: 15) else {
            capture(app, "PDF picker state"); XCTFail(app.debugDescription); return
        }
        // The PDF repeat automatically uses the CSV account; deliberately choosing new must show a guard.
        reveal(app.buttons["import.commit"], in: app)
        // Duplicate-only statements can now record a history receipt without adding transactions.
        XCTAssertEqual(app.buttons["import.commit"].label, "Record skipped import")
        XCTAssertTrue(app.buttons["import.commit"].isEnabled)
        for _ in 0..<8 { if app.buttons["import.account"].isHittable { break }; app.swipeDown() }
        // Move a clipped row below the navigation bar once; repeated swipes can overshoot it.
        if app.buttons["import.account"].exists && app.buttons["import.account"].frame.minY < 110 { app.swipeDown() }
        app.buttons["import.account"].tap()
        XCTAssertTrue(app.buttons["Create new account"].waitForExistence(timeout: 3))
        app.buttons["Create new account"].tap()
        reveal(app.switches["import.allowMatchingAccount"], in: app)
        XCTAssertTrue(app.switches["import.allowMatchingAccount"].exists)
        reveal(app.buttons["import.commit"], in: app)
        XCTAssertFalse(app.buttons["import.commit"].isEnabled)
        capture(app, "Repeat statement new account guarded")
        for _ in 0..<8 { if app.buttons["import.account"].isHittable { break }; app.swipeDown() }
        // Apply the same bounded reveal when returning from the separate-account warning.
        if app.buttons["import.account"].exists && app.buttons["import.account"].frame.minY < 110 { app.swipeDown() }
        app.buttons["import.account"].tap()
        app.buttons["Imported chequing"].tap()
        reveal(app.buttons["import.commit"], in: app)
        XCTAssertTrue(app.buttons["import.commit"].isEnabled)
        XCTAssertEqual(app.buttons["import.commit"].label, "Record skipped import")
        capture(app, "PDF duplicate preview")
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        openSettings(in: app)
        let savedAccount = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Imported chequing' AND label CONTAINS '7,493.08'")).firstMatch
        // The additional category settings can put the account below the initially rendered List rows.
        reveal(savedAccount, in: app)
        XCTAssertTrue(savedAccount.exists)
    }
    // Verify the user's new formats through Files, with a cross-format repeat against the same account.
    @MainActor func testExpandedCSVAndPDFImports() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        openSettings(in: app)
        openSettingsDetail("imports", in: app)
        reveal(app.buttons["Import CSV or PDF"], in: app)
        app.buttons["Import CSV or PDF"].tap()
        chooseImport("Harbor-expanded-transactions", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["import.count"].waitForExistence(timeout: 15))
        reveal(app.staticTexts["import.transferWarning"], in: app)
        XCTAssertTrue(app.staticTexts["import.transferWarning"].exists)
        reveal(app.buttons["import.commit"], in: app)
        XCTAssertEqual(app.buttons["import.commit"].label, "Import 683 transactions")
        XCTAssertTrue(app.buttons["import.commit"].isEnabled)
        capture(app, "Expanded CSV preview and transfer warning")
        app.buttons["import.commit"].tap(); app.buttons["Save import"].tap()
        XCTAssertTrue(app.alerts["Import complete"].waitForExistence(timeout: 10))
        app.alerts.buttons["Done"].tap()
        openSettingsDetail("imports", in: app)
        reveal(app.buttons["Import CSV or PDF"], in: app)
        app.buttons["Import CSV or PDF"].tap()
        chooseImport("Harbor-expanded-statement", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["import.count"].waitForExistence(timeout: 15))
        capture(app, "Expanded PDF statement preview")
        reveal(app.buttons["import.commit"], in: app)
        XCTAssertEqual(app.buttons["import.commit"].label, "Record skipped import")
        XCTAssertTrue(app.buttons["import.commit"].isEnabled)
        capture(app, "Expanded PDF 683 duplicate transactions skipped")
    }
    // Import real fixture files through the on-device UI, then verify native units, balanced savings, and persistence.
    @MainActor func testUSDImportSavingsAndReporting() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch(); openSettings(in: app)
        openSettingsDetail("imports", in: app)
        reveal(app.buttons["Import CSV or PDF"], in: app); app.buttons["Import CSV or PDF"].tap()
        chooseImport("Harbor-USD-savings", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["import.count"].waitForExistence(timeout: 15))
        reveal(app.switches["import.autoSavings"], in: app)
        XCTAssertTrue(app.switches["import.autoSavings"].exists)
        capture(app, "USD currency and savings preview")
        reveal(app.buttons["import.commit"], in: app)
        XCTAssertTrue(app.buttons["import.commit"].isEnabled)
        XCTAssertEqual(app.buttons["import.commit"].label, "Import 5 transactions")
        app.buttons["import.commit"].tap(); app.buttons["Save import"].tap()
        XCTAssertTrue(app.alerts["Import complete"].waitForExistence(timeout: 10)); app.alerts.buttons["Done"].tap()
        let savings = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Imported chequing Savings' AND label CONTAINS 'USD' AND label CONTAINS '250.00'")).firstMatch
        // Return toward Accounts because More retains its import-entry scroll position.
        for _ in 0..<10 { if savings.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(savings.exists)
        capture(app, "USD savings account attached")
        // The default reporting currency is managed in Settings, not transaction screens.
        let report = app.buttons["report.currency"]
        for _ in 0..<10 { if report.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(report.waitForExistence(timeout: 5)); report.tap(); app.buttons["USD"].tap()
        selectTab("Home", in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'USD' AND label CONTAINS '1,245.00'")).firstMatch.waitForExistence(timeout: 5))
        capture(app, "USD totals exclude CAD and savings spending")
        app.terminate(); app.launchArguments = ["-ui-testing"]; app.launch()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'USD' AND label CONTAINS '1,245.00'")).firstMatch.waitForExistence(timeout: 10))
    }
    @MainActor func testVisionGBPPDFImport() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch(); openSettings(in: app)
        openSettingsDetail("imports", in: app)
        reveal(app.buttons["Import CSV or PDF"], in: app); app.buttons["Import CSV or PDF"].tap()
        chooseImport("Harbor-GBP-vision", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["import.count"].waitForExistence(timeout: 20))
        let evidence = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Document recognition was used'")).firstMatch
        reveal(evidence, in: app); XCTAssertTrue(evidence.exists)
        capture(app, "Vision GBP PDF detected")
        reveal(app.buttons["import.commit"], in: app)
        XCTAssertTrue(app.buttons["import.commit"].isEnabled)
        XCTAssertEqual(app.buttons["import.commit"].label, "Import 3 transactions")
        app.buttons["import.commit"].tap(); app.buttons["Save import"].tap()
        XCTAssertTrue(app.alerts["Import complete"].waitForExistence(timeout: 10)); app.alerts.buttons["Done"].tap()
        openSettingsDetail("accounts", in: app)
        let account = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Imported chequing' AND label CONTAINS 'GBP' AND label CONTAINS '105.00'")).firstMatch
        for _ in 0..<10 { if account.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(account.exists); capture(app, "GBP native account balance")
    }
    // Exercise the explicit cleanup action against combined and flat categories in the test ledger.
    @MainActor func testSimplifyCategoriesPreservesBudget() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        openSettings(in: app)
        openSettingsDetail("categories", in: app)
        let completed = app.descendants(matching: .any)["settings.simplified"]
        XCTAssertTrue(completed.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["settings.simplify"].exists)
        selectTab("Budget", in: app)
        reveal(app.buttons["Create Custom Category"], in: app)
        app.buttons["Create Custom Category"].tap()
        let name = app.textFields["Category name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Housing & Utilities")
        // These scenarios deliberately create fixed limits rather than history-derived estimates.
        toggleAutomaticBudget(in: app)
        let limit = app.textFields["Limit (CAD)"]
        limit.tap(); limit.typeText(XCUIKeyboardKey.delete.rawValue + "100.00")
        app.buttons["Save"].tap()
        openSettings(in: app)
        openSettingsDetail("categories", in: app)
        app.buttons["Simplify combined categories"].tap()
        app.buttons["Simplify categories"].tap()
        XCTAssertTrue(completed.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["settings.simplify"].exists)
        XCTAssertTrue(app.staticTexts["settings.simplifyResult"].label.contains("Total budget preserved"))
        capture(app, "Animated category simplification confirmation")
        selectTab("Budget", in: app)
        XCTAssertFalse(app.staticTexts["Housing & Utilities"].exists)
        // This unused plan now lives in the explicit saved-category view rather than monthly spending cards.
        reveal(app.buttons["Manage saved categories"], in: app)
        app.buttons["Manage saved categories"].tap()
        toggleSavedCategories(in: app)
        let utilities = app.buttons["categories.edit.Utilities"]
        reveal(utilities, in: app)
        XCTAssertTrue(utilities.isHittable)
        utilities.tap()
        XCTAssertEqual(app.textFields["Limit (CAD)"].value as? String, "150")
        capture(app, "Simplified Utilities budget")
        app.buttons["Cancel"].tap()
        // Completion survives a new launch without a separate UI preference or another save.
        app.terminate(); app.launchArguments = ["-ui-testing"]; app.launch()
        openSettings(in: app)
        openSettingsDetail("categories", in: app)
        XCTAssertTrue(completed.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["settings.simplify"].exists)
        capture(app, "Category cleanup stays completed after relaunch")
    }
    // Clear fixture history creates subscription reminders without confirmation and persists across relaunch.
    @MainActor func testAutomaticRecurringBillsFromCSVAndPersistence() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        openSettings(in: app)
        openSettingsDetail("imports", in: app)
        reveal(app.buttons["Import CSV or PDF"], in: app)
        app.buttons["Import CSV or PDF"].tap()
        chooseImport("Harbor-test-transactions", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["import.count"].waitForExistence(timeout: 15))
        reveal(app.switches["import.removeDemo"], in: app)
        app.switches["import.removeDemo"].tap()
        reveal(app.buttons["import.commit"], in: app)
        app.buttons["import.commit"].tap(); app.buttons["Save import"].tap()
        XCTAssertTrue(app.alerts["Import complete"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS 'recurring bill suggestions'")).firstMatch.exists)
        app.alerts.buttons["Done"].tap()
        // More retains its scroll position after dismissing the Files import screen.
        for _ in 0..<8 { if app.buttons["Recurring Bills"].isHittable { break }; app.swipeDown() }
        app.buttons["Recurring Bills"].tap()
        let cloudCategory = app.staticTexts["bill.category.Apple iCloud"]
        reveal(cloudCategory, in: app)
        XCTAssertEqual(cloudCategory.label, "Subscription")
        XCTAssertFalse(app.buttons["bill.track.APPLE ICLOUD+"].exists)
        XCTAssertFalse(app.buttons["bill.reviewSchedule.Apple iCloud"].exists)
        capture(app, "iCloud automatically tracked as Subscription")
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        openSettings(in: app); app.buttons["Recurring Bills"].tap()
        reveal(cloudCategory, in: app)
        XCTAssertTrue(cloudCategory.exists)
        XCTAssertEqual(cloudCategory.label, "Subscription")
        XCTAssertFalse(app.buttons["bill.track.COASTAL TENANT INSURANCE"].exists)
        capture(app, "Recurring bill tracked after relaunch")
    }
    // Import fictional history through Files, append October examples, and verify both Budget tabs and the info sheet.
    @MainActor func testOctoberForecastFromImportedHistory() throws {
        // A completed October correctly shows actuals; this scenario exercises an open October forecast.
        let octoberEnd = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        guard Date() < octoberEnd else { throw XCTSkip("October 2026 is complete; use the fixed-date core tests for this forecast scenario.") }
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        openSettings(in: app)
        openSettingsDetail("imports", in: app)
        reveal(app.buttons["Import CSV or PDF"], in: app)
        app.buttons["Import CSV or PDF"].tap()
        chooseImport("Harbor-test-transactions", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["import.count"].waitForExistence(timeout: 15))
        reveal(app.switches["import.removeDemo"], in: app)
        let replaceDemo = app.switches["import.removeDemo"]
        XCTAssertEqual(replaceDemo.value as? String, "0")
        // Target the switch thumb rather than the wide SwiftUI row's center.
        replaceDemo.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(replaceDemo.value as? String, "1")
        reveal(app.buttons["import.commit"], in: app)
        app.buttons["import.commit"].tap()
        app.buttons["Save import"].tap()
        XCTAssertTrue(app.alerts["Import complete"].waitForExistence(timeout: 10))
        app.alerts.buttons["Done"].tap()
        // Append the same user-requested sample set in the isolated test ledger, never the normal one.
        app.terminate()
        app.launchArguments = ["-ui-testing", "-append-october-examples", "-example-account", "Imported chequing"]
        app.launch()
        selectTab("Budget", in: app)
        let tabs = app.segmentedControls["budget.spendingTabs"]
        XCTAssertTrue(tabs.buttons["Current spending"].isSelected)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '2,039.47'")).firstMatch.waitForExistence(timeout: 5))
        capture(app, "Budget current October spending")
        tabs.buttons["Forecasted Spending"].tap()
        XCTAssertTrue(app.staticTexts["forecast.total"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["forecast.total"].label.contains("3,134.45"), app.staticTexts["forecast.total"].label)
        capture(app, "Budget forecasted October spending")
        app.buttons["budget.forecastInfo"].tap()
        XCTAssertTrue(app.navigationBars["About Forecasted Spending"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["An estimate of your total spending by the end of the selected month."].exists)
        capture(app, "Forecast information sheet")
        app.buttons["Done"].tap()
        reveal(app.staticTexts["Forecast trajectory"], in: app)
        capture(app, "Budget October forecast trajectory")
        // Repeating the explicit append must skip existing samples, and the saved ledger must reopen unchanged.
        app.terminate()
        app.launch()
        selectTab("Budget", in: app)
        app.segmentedControls["budget.spendingTabs"].buttons["Forecasted Spending"].tap()
        XCTAssertTrue(app.staticTexts["forecast.total"].label.contains("3,134.45"))
    }
    // Appearance persists independently of the ledger; cancellation and relaunch protect reset semantics.
    @MainActor func testAppearanceAndClearAllData() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        openSettings(in: app)
        let appearance = app.segmentedControls["settings.appearance"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 10))
        XCTAssertTrue(appearance.buttons["System"].isSelected)
        appearance.buttons["Dark"].tap()
        XCTAssertTrue(appearance.buttons["Dark"].isSelected)
        capture(app, "Settings-Dark")
        selectTab("Home", in: app)
        capture(app, "Home-Dark")
        app.buttons["Add transaction"].tap()
        capture(app, "Transaction-Dark")
        app.buttons["Cancel"].tap()
        for title in ["Activity", "Budget", "Goals"] {
            app.tabBars.buttons[title].tap()
            capture(app, title + "-Dark")
        }
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        openSettings(in: app)
        XCTAssertTrue(appearance.buttons["Dark"].waitForExistence(timeout: 5))
        XCTAssertTrue(appearance.buttons["Dark"].isSelected)
        appearance.buttons["Light"].tap()
        capture(app, "Settings-Light")
        appearance.buttons["System"].tap()
        XCTAssertTrue(appearance.buttons["System"].isSelected)

        // Cancel leaves the seeded ledger untouched.
        openSettingsDetail("reset", in: app)
        reveal(app.buttons["settings.clearAll"], in: app)
        app.buttons["settings.clearAll"].tap()
        app.alerts.buttons["Cancel"].tap()
        selectTab("Activity", in: app)
        XCTAssertTrue(app.staticTexts["Whole Foods Market"].waitForExistence(timeout: 5))
        openSettings(in: app)
        // Delete a populated ledger through the complete reset, including its budget categories.
        openSettingsDetail("reset", in: app)
        reveal(app.buttons["settings.clearAll"], in: app)
        app.buttons["settings.clearAll"].tap()
        app.alerts.buttons["Clear all data"].tap()
        XCTAssertTrue(app.staticTexts["All data cleared. Add an account to begin."].waitForExistence(timeout: 5))
        capture(app, "Settings-Cleared")
        app.terminate()
        app.launch()
        openSettings(in: app)
        XCTAssertTrue(appearance.buttons["System"].waitForExistence(timeout: 5))
        XCTAssertTrue(appearance.buttons["System"].isSelected)
        assertProfileName("You", in: app)
        selectTab("Activity", in: app)
        XCTAssertFalse(app.staticTexts["Whole Foods Market"].exists)
        selectTab("Budget", in: app)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Groceries'")).firstMatch.exists)
        capture(app, "Budget-Cleared-After-Relaunch")
        selectTab("Goals", in: app)
        XCTAssertTrue(app.staticTexts["No goals here yet"].waitForExistence(timeout: 5))
        openSettings(in: app)
        app.buttons["Recurring Bills"].tap()
        XCTAssertTrue(app.staticTexts["No recurring bills"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Settings"].tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS 'TD Chequing'")).firstMatch.exists)
        // The full reset stays available for a non-demo ledger and is safe to repeat.
        openSettingsDetail("reset", in: app)
        reveal(app.buttons["settings.clearAll"], in: app)
        app.buttons["settings.clearAll"].tap()
        app.alerts.buttons["Clear all data"].tap()
        XCTAssertTrue(app.staticTexts["All data cleared. Add an account to begin."].waitForExistence(timeout: 5))
    }
    // The native category flow hides zero-use rows, preserves a custom name, and previews existing-ledger cleanup.
    @MainActor func testCategoryAnalyticsRenameAndCleanup() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        // Analytics lives with spending exploration in Budget.
        selectTab("Budget", in: app)
        app.buttons["budget.analytics"].tap()
        reveal(app.staticTexts["Top Categories"], in: app)
        XCTAssertTrue(app.staticTexts["Top Categories"].exists)
        XCTAssertFalse(app.buttons["analytics.category.Other"].exists)
        let groceries = app.buttons["analytics.category.Groceries"]
        reveal(groceries, in: app)
        groceries.tap()
        capture(app, "Category-Editor-Opened")
        let name = app.textFields["Category name"]
        guard name.waitForExistence(timeout: 5) else { XCTFail("Category name field is unavailable"); return }
        name.tap(); name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 9) + "Food at home")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["analytics.category.Food at home"].waitForExistence(timeout: 5))
        capture(app, "Top-Categories-Actual-Spending")
        openSettingsDetail("categories", in: app)
        reveal(app.buttons["Manage categories"], in: app)
        app.buttons["Manage categories"].tap()
        XCTAssertTrue(app.buttons["categories.edit.Food at home"].waitForExistence(timeout: 5))
        app.buttons["Review category cleanup"].tap()
        XCTAssertTrue(app.navigationBars["Review Categories"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        // Unused records are available only through the explicit saved-category view.
        toggleSavedCategories(in: app)
        XCTAssertTrue(app.buttons["categories.edit.Other"].exists)
        app.buttons["Review category cleanup"].tap()
        reveal(app.buttons["categories.apply"], in: app)
        capture(app, "Category-Cleanup-Preview")
        app.buttons["categories.apply"].tap()
        XCTAssertTrue(app.navigationBars["Manage Categories"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["categories.edit.Other"].exists)
        XCTAssertTrue(app.buttons["categories.edit.Food at home"].exists)
        capture(app, "Manage-Categories-After-Cleanup")
        // Manual forms can request a suggestion without committing it when the user cancels.
        selectTab("Home", in: app)
        app.buttons["Add transaction"].tap()
        let merchant = app.textFields["transaction.merchant"]
        XCTAssertTrue(merchant.waitForExistence(timeout: 5))
        merchant.tap(); merchant.typeText("Rent")
        let amount = app.textFields["transaction.amount"]
        amount.tap(); amount.typeText("200.00")
        reveal(app.buttons["Suggest category"], in: app)
        app.buttons["Suggest category"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Suggested: Rent'")).firstMatch.waitForExistence(timeout: 5))
        capture(app, "Manual-Category-Suggestion")
        app.buttons["Cancel"].tap()
    }
    @MainActor private func chooseImport(_ filename: String, in app: XCUIApplication) {
        app.buttons["Choose CSV or PDF"].tap()
        let picker = XCUIApplication(bundleIdentifier: "com.apple.DocumentManagerUICore.Service")
        let file = picker.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR label == %@ OR label == %@", filename, filename + ".csv", filename + ".pdf")).firstMatch
        if !file.waitForExistence(timeout: 3) {
            if picker.buttons["Browse"].waitForExistence(timeout: 5) { picker.buttons["Browse"].tap() }
            if picker.staticTexts["On My iPhone"].waitForExistence(timeout: 3) { picker.staticTexts["On My iPhone"].tap() }
            if picker.staticTexts["Harbor"].waitForExistence(timeout: 3) { picker.staticTexts["Harbor"].tap() }
        }
        XCTAssertTrue(file.waitForExistence(timeout: 5))
        let cell = picker.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", filename + ",")).firstMatch
        // In icon mode the filename label is not the document's activation target.
        if cell.exists, cell.images.firstMatch.exists { cell.images.firstMatch.tap() } else { file.tap() }
        // Newer Files pickers require an explicit Open after choosing a document.
        if picker.buttons["Open"].waitForExistence(timeout: 2) { picker.buttons["Open"].tap() }
    }
    // Use actual Files import, authenticated decryption, preview cancellation, and confirmed replacement.
    @MainActor func testEncryptedRestoreValidationAndCancellation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch(); openSettings(in: app)
        let backups = app.buttons["Backups and recovery"]
        reveal(backups, in: app); backups.tap()
        app.buttons["backup.chooseRestore"].tap()
        chooseBackupFixture("Harbor-encrypted-QA", in: app)
        let key = app.secureTextFields["backup.restoreKey"]
        XCTAssertTrue(key.waitForExistence(timeout: 5)); key.tap(); key.typeText(String(repeating: "CD", count: 32))
        app.buttons["backup.validate"].tap()
        let status = app.staticTexts["backup.status"]
        reveal(status, in: app)
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("Could not unlock backup"))
        for _ in 0..<5 { if key.isHittable { break }; app.swipeDown() }
        key.tap(); key.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 64) + String(repeating: "AB", count: 32))
        app.buttons["backup.validate"].tap()
        XCTAssertTrue(app.buttons["Replace records"].waitForExistence(timeout: 5))
        capture(app, "Validated encrypted restore preview")
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        else {
            // iOS popovers omit the cancel button; tapping outside dismisses without replacing records.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.75)).tap()
        }
        XCTAssertFalse(app.secureTextFields["backup.restoreKey"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        assertProfileName("Maya", in: app)
        reveal(backups, in: app); backups.tap()
        app.buttons["backup.chooseRestore"].tap()
        chooseBackupFixture("Harbor-encrypted-QA", in: app)
        XCTAssertTrue(key.waitForExistence(timeout: 5)); key.tap(); key.typeText(String(repeating: "AB", count: 32))
        app.buttons["backup.validate"].tap()
        app.buttons["Replace records"].tap()
        reveal(status, in: app)
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("Backup restored"))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        assertProfileName("Restored QA ledger", in: app)
        app.terminate(); app.launchArguments = ["-ui-testing"]; app.launch()
        openSettings(in: app)
        assertProfileName("Restored QA ledger", in: app)
    }
    @MainActor private func chooseBackupFixture(_ filename: String, in app: XCUIApplication) {
        let picker = XCUIApplication(bundleIdentifier: "com.apple.DocumentManagerUICore.Service")
        let file = picker.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR label == %@", filename, filename + ".harborbackup")).firstMatch
        if !file.waitForExistence(timeout: 3) {
            if picker.buttons["Browse"].waitForExistence(timeout: 3) { picker.buttons["Browse"].tap() }
            if picker.staticTexts["On My iPhone"].waitForExistence(timeout: 3) { picker.staticTexts["On My iPhone"].tap() }
            if picker.staticTexts["Harbor"].waitForExistence(timeout: 3) { picker.staticTexts["Harbor"].tap() }
        }
        XCTAssertTrue(file.waitForExistence(timeout: 5))
        let cell = picker.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@ OR identifier BEGINSWITH %@", filename + ",", filename + ".harborbackup,")).firstMatch
        if cell.exists, cell.images.firstMatch.exists { cell.images.firstMatch.tap() } else { file.tap() }
        if picker.buttons["Open"].waitForExistence(timeout: 2) { picker.buttons["Open"].tap() }
    }
    // Recovery-key confirmation is required before export, and cancellation discards key material.
    @MainActor func testEncryptedBackupSetupAndCancellation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        openSettings(in: app)
        let backups = app.buttons["Backups and recovery"]
        reveal(backups, in: app); backups.tap()
        let create = app.buttons["backup.createKey"]
        XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap()
        let key = app.staticTexts["backup.recoveryKey"].label
        XCTAssertEqual(key.count, 64)
        let export = app.buttons["backup.exportEncrypted"]
        XCTAssertFalse(export.isEnabled)
        let confirm = app.secureTextFields["backup.confirmKey"]
        confirm.tap(); confirm.typeText(key)
        XCTAssertTrue(export.isEnabled)
        capture(app, "Encrypted backup key confirmation")
        app.buttons["Cancel backup"].tap()
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["backup.recoveryKey"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let applePay = app.buttons["Apple Pay Shortcuts"]
        reveal(applePay, in: app); applePay.tap()
        capture(app, "Guided Apple Pay setup")
        let verification = app.staticTexts["No capture verified yet"]
        reveal(verification, in: app)
        XCTAssertTrue(verification.waitForExistence(timeout: 5))
    }
    // Verify the actual weekly drill-down and persisted profile confirmation with isolated data.
    @MainActor func testHomeWeeklySummaryAndNameConfirmation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["TOTAL NET WORTH"].waitForExistence(timeout: 10))
        capture(app, "Compact Home header")
        let week = app.buttons["home.week.0"]
        reveal(week, in: app)
        XCTAssertTrue(week.isHittable)
        week.tap()
        XCTAssertTrue(app.navigationBars["Weekly summary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Daily average"].exists)
        capture(app, "Weekly daily summary")
        app.buttons["Done"].tap()
        let budgets = app.staticTexts["Budget Health"]
        reveal(budgets, in: app)
        app.swipeUp()
        capture(app, "Square bill and budget grids")
        app.buttons["navigation.profile"].tap()
        let name = app.textFields["profile.name"]
        reveal(name, in: app)
        name.tap()
        let previous = name.value as? String ?? ""
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + "Jordan")
        app.buttons["profile.saveName"].tap()
        XCTAssertTrue(app.alerts["Name updated"].waitForExistence(timeout: 5))
        capture(app, "Profile save confirmation")
        app.alerts.buttons["Done"].tap()
        app.buttons["profile.done"].tap()
        app.buttons["navigation.home"].tap()
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Hello, Jordan"].waitForExistence(timeout: 10))
    }
    // Reach offscreen square tiles through the horizontal grid, then verify its navigation.
    @MainActor func testHomeSquareGridHorizontalNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["TOTAL NET WORTH"].waitForExistence(timeout: 10))
        let grid = app.scrollViews["home.budgets"]
        for _ in 0..<8 {
            if app.buttons["home.budget.Rent"].isHittable { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
        }
        XCTAssertTrue(app.buttons["home.budget.Rent"].isHittable)
        capture(app, "Budget square grid")
        // Reach the last used category; unused Other intentionally stays out of the month's grid.
        XCTAssertFalse(app.buttons["home.budget.Other"].exists)
        let shopping = app.buttons["home.budget.Shopping"]
        for _ in 0..<5 { if shopping.isHittable { break }; grid.swipeLeft() }
        XCTAssertTrue(shopping.isHittable)
        capture(app, "Budget grid scrolled horizontally")
        shopping.tap()
        // A Home tile must open its own transactions, rather than the generic Budget tab.
        XCTAssertTrue(app.navigationBars["Category transactions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Shopping"].exists)
        XCTAssertFalse(app.buttons["categoryTransactions.entry.Whole Foods Market"].exists)
        XCTAssertTrue(app.buttons["categoryTransactions.editBudget"].exists)
        capture(app, "Home budget category transactions")
        app.buttons["Done"].tap()
        XCTAssertTrue(shopping.isHittable)
    }
    // Verify navigation, optional explanations and an unobstructed reset without deleting records.
    @MainActor func testSettingsNavigationAndOptionalHelp() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["Add transaction"].waitForExistence(timeout: 10))
        selectTab("Activity", in: app)
        XCTAssertTrue(app.buttons["Add transaction"].exists)
        selectTab("Budget", in: app)
        XCTAssertFalse(app.buttons["Add transaction"].isHittable)
        let analytics = app.buttons["budget.analytics"]
        XCTAssertTrue(analytics.waitForExistence(timeout: 5))
        analytics.tap()
        XCTAssertTrue(app.staticTexts["Trajectory Curve"].waitForExistence(timeout: 5))
        capture(app, "Analytics from Budget")
        selectTab("Goals", in: app)
        XCTAssertFalse(app.buttons["Add transaction"].isHittable)
        openSettings(in: app)
        XCTAssertFalse(app.buttons["Add transaction"].isHittable)
        XCTAssertFalse(app.buttons["Spending Analytics"].exists)
        capture(app, "Concise Settings")
        let shortcuts = app.buttons["Apple Pay Shortcuts"]
        reveal(shortcuts, in: app); shortcuts.tap()
        XCTAssertTrue(app.staticTexts["shortcuts.captureDescription"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Add transaction"].isHittable)
        capture(app, "Shortcut capture explanation")
        app.buttons["Learn more about Shortcut capture"].tap()
        XCTAssertTrue(app.navigationBars["Shortcut capture"].waitForExistence(timeout: 5))
        capture(app, "Optional Shortcut details")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openSettingsDetail("reset", in: app)
        let reset = app.buttons["settings.clearAll"]
        reveal(reset, in: app)
        XCTAssertTrue(reset.isHittable)
        XCTAssertFalse(app.buttons["Add transaction"].isHittable)
        capture(app, "Reset without floating button")
        let resetHelp = app.buttons["Learn more about Reset Harbor"]
        reveal(resetHelp, in: app); resetHelp.tap()
        XCTAssertTrue(app.navigationBars["Reset Harbor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Pending Apple Pay captures'")).firstMatch.exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reset.tap()
        XCTAssertTrue(app.alerts["Clear all Harbor data?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        selectTab("Activity", in: app)
        XCTAssertTrue(app.staticTexts["Whole Foods Market"].waitForExistence(timeout: 5))
    }
    // Exercise the shared header, dark search, icon destinations and persisted default currency.
    @MainActor func testActivityHeaderDarkSearchAndIconNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        openSettings(in: app)
        let appearance = app.segmentedControls["settings.appearance"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 10))
        appearance.buttons["Dark"].tap()
        XCTAssertFalse(app.textFields["profile.name"].exists)
        let currency = app.buttons["report.currency"]
        reveal(currency, in: app)
        XCTAssertTrue(currency.label.contains("Default currency"))
        currency.tap(); app.buttons["USD"].tap()
        selectTab("Activity", in: app)
        XCTAssertFalse(app.buttons["report.currency"].exists)
        let search = app.textFields["activity.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        let previous = app.buttons["Previous month"]
        XCTAssertLessThanOrEqual(search.frame.maxX, previous.frame.minX + 1)
        XCTAssertLessThan(abs(search.frame.midY - previous.frame.midY), 8)
        capture(app, "Activity dark search and month header")
        search.tap(); search.typeText("Whole Foods\n")
        XCTAssertTrue(app.staticTexts["Whole Foods Market"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Blue Bottle Coffee"].exists)
        capture(app, "Readable dark search results")
        app.buttons["Clear search"].tap()
        previous.tap()
        XCTAssertTrue(app.staticTexts["No transactions found"].waitForExistence(timeout: 5))
        app.buttons["Next month"].tap()
        XCTAssertTrue(app.staticTexts["Whole Foods Market"].waitForExistence(timeout: 5))
        app.buttons["navigation.home"].tap()
        XCTAssertTrue(app.staticTexts["TOTAL NET WORTH"].waitForExistence(timeout: 5))
        app.buttons["navigation.profile"].tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
        // The covered Home view remains in the accessibility tree while the modal is presented.
        XCTAssertFalse(app.buttons["Add transaction"].isHittable)
        capture(app, "Dedicated Profile")
        app.buttons["profile.done"].tap()
        app.terminate(); app.launchArguments = ["-ui-testing"]; app.launch()
        openSettings(in: app)
        reveal(currency, in: app)
        XCTAssertTrue(currency.label.contains("USD"))
    }
    // Every reporting screen follows the one Settings preference instead of duplicating its picker.
    @MainActor func testReportingCurrencyOnlyInSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["TOTAL NET WORTH"].waitForExistence(timeout: 10))
        for title in ["Home", "Activity", "Categories", "Budget", "Goals"] {
            app.tabBars.buttons[title].tap()
            XCTAssertFalse(app.buttons["report.currency"].exists, title)
        }
        selectTab("Budget", in: app)
        app.buttons["budget.analytics"].tap()
        XCTAssertTrue(app.navigationBars["Spending Analytics"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["report.currency"].exists)
        capture(app, "Analytics without currency dropdown")
        openSettings(in: app)
        let currency = app.buttons["report.currency"]
        reveal(currency, in: app)
        XCTAssertTrue(currency.isHittable)
        XCTAssertTrue(currency.label.contains("Default currency"))
    }
    // A single tap completes payment, survives editing/relaunch, and creates exactly one Activity row.
    @MainActor func testMarkPaidCompletesImmediatelyAndPersists() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        openSettings(in: app)
        XCTAssertTrue(app.buttons["Recurring Bills"].waitForExistence(timeout: 10))
        app.buttons["Recurring Bills"].tap()
        let mark = app.buttons["bill.markPaid.Spotify Family"]
        XCTAssertTrue(mark.waitForExistence(timeout: 5)); mark.tap()
        let paid = app.descendants(matching: .any)["bill.paid.Spotify Family"]
        XCTAssertTrue(paid.waitForExistence(timeout: 5))
        XCTAssertFalse(mark.exists)
        XCTAssertFalse(app.buttons["Record payment"].exists)
        XCTAssertTrue(app.staticTexts["bill.paymentDetails.Spotify Family"].label.contains("Next due"))
        capture(app, "Bill payment complete after one tap")
        let edit = app.buttons["bill.edit.Spotify Family"]
        reveal(edit, in: app); edit.tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(paid.waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = ["-ui-testing"]; app.launch()
        openSettings(in: app); app.buttons["Recurring Bills"].tap()
        XCTAssertTrue(paid.waitForExistence(timeout: 5))
        XCTAssertFalse(mark.exists)
        capture(app, "Paid bill after relaunch")
        selectTab("Home", in: app)
        reveal(app.staticTexts["Upcoming Bills"], in: app)
        capture(app, "Paid status on Home bill tiles")
        selectTab("Activity", in: app)
        let search = app.textFields["activity.search"]
        search.tap(); search.typeText("Spotify\n")
        XCTAssertTrue(app.staticTexts["Spotify Family"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "Spotify Family").count, 1)
        capture(app, "Single recorded bill payment in Activity")
    }
    // A month with no pending reviews must show zero without silently clearing other months' flags.
    @MainActor func testBriefingReviewCountMatchesActivityMonth() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        let briefing = app.staticTexts["home.briefing"]
        XCTAssertTrue(briefing.waitForExistence(timeout: 10))
        XCTAssertTrue(briefing.label.contains("3 transactions need review this month"))
        app.buttons["Previous month"].tap()
        XCTAssertTrue(briefing.label.contains("All reviewed this month"))
        capture(app, "Monthly briefing with no pending reviews")
        selectTab("Activity", in: app)
        app.buttons["Needs Review"].tap()
        XCTAssertTrue(app.staticTexts["0 transactions"].waitForExistence(timeout: 5))
        app.buttons["Notifications"].tap()
        let total = app.staticTexts["notifications.reviewCount"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(total.label.contains("3 transactions need review across all months"))
        capture(app, "Explicit all-month review inbox")
        app.buttons["Done"].tap()
        app.buttons["Next month"].tap()
        XCTAssertTrue(app.staticTexts["3 transactions"].waitForExistence(timeout: 5))
        app.buttons["navigation.home"].tap()
        XCTAssertTrue(briefing.label.contains("3 transactions need review this month"))
    }
    // Taps within a List must reach one arrow/action, and changing months must restore monthly usage.
    @MainActor func testManageCategoriesMonthArrowsAndIndependentButtons() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch(); openSettings(in: app)
        openSettingsDetail("categories", in: app)
        let manage = app.buttons["Manage categories"]
        XCTAssertTrue(manage.waitForExistence(timeout: 10)); manage.tap()
        let month = app.staticTexts["month.selected"]
        XCTAssertTrue(month.waitForExistence(timeout: 5))
        let initial = month.label
        app.buttons["Previous month"].tap()
        XCTAssertNotEqual(month.label, initial)
        XCTAssertTrue(app.staticTexts["No categories used this month. Record or import transactions to get started."].exists)
        XCTAssertFalse(app.buttons["categories.edit.Groceries"].exists)
        app.buttons["Next month"].tap()
        XCTAssertEqual(month.label, initial)
        let groceries = app.buttons["categories.edit.Groceries"]
        reveal(groceries, in: app)
        XCTAssertTrue(groceries.isHittable)
        // The label's trailing whitespace is a hit target too, without triggering Merge.
        groceries.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Edit Budget"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        let merge = app.buttons["categories.merge.Groceries"]
        reveal(merge, in: app); merge.tap()
        XCTAssertTrue(app.navigationBars["Merge Categories"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        for _ in 0..<10 { if app.buttons["Previous month"].isHittable { break }; app.swipeDown() }
        toggleSavedCategories(in: app)
        XCTAssertEqual(app.switches["categories.showSaved"].value as? String, "1")
        app.buttons["Previous month"].tap()
        XCTAssertEqual(app.switches["categories.showSaved"].value as? String, "0")
        XCTAssertFalse(groceries.exists)
        capture(app, "Manage categories empty month after one tap")
        app.buttons["Next month"].tap()
        reveal(groceries, in: app)
        capture(app, "Transaction-derived monthly categories")
    }
    // Exercise common toolbar/sheet buttons across every tab without repeated taps or financial edits.
    @MainActor func testPrimaryButtonsRespondAcrossTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["navigation.profile"].waitForExistence(timeout: 10))
        for title in ["Home", "Activity", "Categories", "Budget", "Goals"] {
            app.tabBars.buttons[title].tap()
            app.buttons["navigation.profile"].tap()
            XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5), title)
            app.buttons["profile.done"].tap()
            app.buttons["navigation.home"].tap()
            XCTAssertTrue(app.staticTexts["TOTAL NET WORTH"].waitForExistence(timeout: 5), title)
        }
        app.buttons["Notifications"].tap()
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        for title in ["Home", "Activity"] {
            app.tabBars.buttons[title].tap()
            app.buttons["Add transaction"].tap()
            XCTAssertTrue(app.textFields["transaction.merchant"].waitForExistence(timeout: 5), title)
            app.buttons["Cancel"].tap()
        }
        openSettings(in: app)
        openSettingsDetail("categories", in: app)
        app.buttons["Manage categories"].tap()
        app.buttons["Review category cleanup"].tap()
        XCTAssertTrue(app.navigationBars["Review Categories"].waitForExistence(timeout: 10))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Manage Categories"].waitForExistence(timeout: 5))
    }
    // The manual actions must confirm success/empty results at the tapped location, even on repeat.
    @MainActor func testShortcutActionsShowLocalCompletionFeedback() throws {
        let app = XCUIApplication()
        // This fixture creates only a held capture, guaranteeing an empty active inbox without touching real data.
        app.launchArguments = ["-ui-testing", "-reset-ui-testing", "-ui-testing-held-capture"]
        app.launch(); openSettings(in: app)
        let shortcuts = app.buttons["Apple Pay Shortcuts"]
        reveal(shortcuts, in: app); shortcuts.tap()
        let check = app.buttons["shortcuts.checkCapture"]
        reveal(check, in: app); check.tap()
        let result = app.staticTexts["shortcuts.checkResult"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "label == %@", "No new captures found."), evaluatedWith: result)
        waitForExpectations(timeout: 5)
        capture(app, "Capture check empty result beside button")
        let refresh = app.buttons["shortcuts.refreshAccounts"]
        reveal(refresh, in: app)
        XCTAssertTrue(refresh.isEnabled); refresh.tap()
        let refreshed = app.staticTexts["shortcuts.refreshResult"]
        XCTAssertTrue(refreshed.waitForExistence(timeout: 5))
        let finished = NSPredicate(format: "label == %@", "Account choices refreshed (3).")
        expectation(for: finished, evaluatedWith: refreshed)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(refresh.isEnabled)
        capture(app, "Account refresh confirmation beside button")
        refresh.tap()
        expectation(for: finished, evaluatedWith: refreshed)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(refresh.isEnabled)
        // Checking active captures must not release a held purchase or silently approve it.
        let held = app.buttons["Release this capture for import"]
        reveal(held, in: app)
        XCTAssertTrue(held.isHittable)
    }
    @MainActor private func assertProfileName(_ expected: String, in app: XCUIApplication) {
        // All persistence and migration checks follow the person icon to personal details.
        app.buttons["navigation.profile"].tap()
        let name = app.textFields["profile.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, expected)
        app.buttons["profile.done"].tap()
    }
    // iOS exposes both a labelled container and the actual native switch; target the switch itself.
    @MainActor private func toggleSavedCategories(in app: XCUIApplication) {
        let row = app.switches["categories.showSaved"]
        let control = row.switches.firstMatch
        if control.exists { control.tap() } else { row.tap() }
    }
    // Settings now lives in Profile; close that sheet before selecting another root destination.
    @MainActor private func selectTab(_ title: String, in app: XCUIApplication) {
        for _ in 0..<6 {
            if app.buttons["profile.done"].exists || app.tabBars.buttons[title].isHittable { break }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists { back.tap() } else { break }
        }
        if app.buttons["profile.done"].exists { app.buttons["profile.done"].tap() }
        app.tabBars.buttons[title].tap()
    }
    @MainActor private func openSettings(in app: XCUIApplication) {
        // Detail pages can replace the root header; return to that header before opening Profile.
        for _ in 0..<6 {
            if app.buttons["profile.done"].exists || app.buttons["navigation.profile"].isHittable { break }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists { back.tap() } else { break }
        }
        if app.buttons["navigation.profile"].isHittable { app.buttons["navigation.profile"].tap() }
        if app.buttons["profile.settings"].exists { app.buttons["profile.settings"].tap() }
    }
    // Returning to a tab retains its stack; unwind only until the requested Settings destination is available.
    @MainActor private func openSettingsDetail(_ route: String, in app: XCUIApplication) {
        if route == "categories", app.buttons["Manage categories"].exists { return }
        openSettings(in: app)
        let titles = ["accounts": "Accounts", "categories": "Categories", "imports": "Imports & reconciliation", "reset": "Reset Harbor"]
        // The Categories root remains behind the Profile sheet; its title is not a Settings destination.
        if route != "categories", let title = titles[route], app.navigationBars[title].exists { return }
        let link = app.buttons["settings." + route]
        for _ in 0..<5 {
            if link.exists { break }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists { back.tap() } else { break }
        }
        reveal(link, in: app)
        XCTAssertTrue(link.isHittable)
        link.tap()
    }
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 { if element.isHittable { return }; app.swipeUp() }
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
