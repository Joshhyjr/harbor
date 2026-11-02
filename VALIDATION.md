# Budget category transaction drill-down — October 17, 2026

- Budget category cards now open Category transactions for the selected month instead of opening the limit editor directly. The view reads the live category identity, lists related non-transfer transactions in date order with dates/accounts/amounts/review status, and shows expense spending, the saved budget limit, and income separately when present. Filtering retains the selected month and category currency.
- Edit budget opens the existing native category editor; tapping a transaction opens the existing transaction editor. Category and transaction edits continue through the existing validated encrypted save path. No persistence schema or calculation changes were introduced.
- Native build passed. Signed simulator UI test testBudgetCategoryShowsRelatedTransactions passed on the isolated debug ledger: Groceries showed exactly Whole Foods Market and Farm Boy Organic, excluded Blue Bottle Coffee, and opened the correct budget and transaction editors before returning to Budget. Final UI test compiled the final source. Log: `/tmp/harbor-category-transactions-ui.log`; result: `/tmp/harbor-review-derived/Logs/Test/Test-Harbor-2026.10.17_14-28-18--0300.xcresult`. Source whitespace check passed. No physical iPhone installation or verification performed.

---

# Categories follow monthly transactions — October 17, 2026

- Home Budget Health and Current spending in Budget now list only categories used by non-transfer expenses in the selected month/currency. Activity category filters use categories present in the selected month's non-transfer transactions. Empty months have no category cards. Home also omits the empty fixed-height category grid.
- Manage categories defaults to the selected month's used categories and offers Show all saved categories for explicit access to unused saved plans. Month controls and per-month transaction counts make the scope visible. The categorisation action checks only unreviewed, non-transfer, non-manually-corrected records in the selected month and reporting currency; reviewed history and explicit manual corrections remain authoritative.
- Monthly membership is derived from transactions without duplicating category identities, deleting history, or altering balances, saved names/icons, limits, or forecast calculations. Existing saved limits, including hidden unused ones, still contribute to the overall monthly allocation; Budget explains this and links to saved-category management. Explicit manual creation of an unused category/budget remains available.
- Model options remain virtual; preparing suggestions creates no saved categories. The transaction editor now accepts New category name (optional). This manual choice overrides the suggested/picked category, reuses an equivalent saved identity where possible, and saves a new category only atomically with the transaction. Cancelling or failing a save does not create it. Accounts are required, but pre-creating budget categories is no longer required for the first transaction.
- Full core run: **88 tests, 87 passed, 1 skipped, zero failures**. The existing generic grocery live-model smoke test abstained; the live subscription test passed. Three new tests cover month/currency/direction isolation, user reassignment, retained unused budget limits, virtual options with deferred creation, and transfer-only exclusion. After preserving existing category ordering, these three tests passed again. Logs: `/tmp/harbor-monthly-tests.log`, `/tmp/harbor-monthly-focused.log`.
- Native simulator build passed. Two focused native UI behaviors passed using the isolated debug ledger: testTransactionCreatesOnlyUserChosenCategory verified an iCloud Subscription suggestion overridden by Cloud storage, creation of only the selected category, and encrypted relaunch persistence; testMonthlyCategoriesHideUnusedSavedCategories verified active/empty month switching and explicit saved-category access. Logs: `/tmp/harbor-monthly-ui.log` (user override case), `/tmp/harbor-monthly-ui-verified.log` (final monthly/saved view case). Initial saved-toggle attempts tapped iOS's labelled switch container rather than its native switch; the test helper now targets the actual control. The final signed simulator test compiled the final UI source.
- Existing category cleanup, saved-budget editing, and Home grid test expectations were adjusted for the new visibility policy. The full older UI suite was not rerun. No physical iPhone installation or verification was performed.

---

# Automatic subscriptions and recurring bills — October 17, 2026

- Added the Subscription category and explicit service recognition, including APPLE ICLOUD+, Apple Music, Netflix, and Spotify. Renamed category identities, manual category corrections, and reviewed merchant preferences remain authoritative. Generic Apple processor descriptions alone do not prove a subscription, even if a model suggests one. Apple Foundation Models can propose Subscription from unfamiliar descriptions using the existing bounded on-device classification path; recurrence dates and amounts remain deterministic.
- Automatically track three to six clear, regular payments in Rent, Utilities, Insurance, or Subscription when the amount range stays within 20% of the minimum. Account-scoped service identities group explicit iCloud description variants. Discovery links existing expenses without adding spending or changing category budget limits, balances, transaction amounts, or transfer links. Reminders are not separately added to spending forecasts.
- A named subscription with insufficient cadence history gets a bill immediately, categorised as Subscription, with a visibly estimated monthly schedule and a focused Review schedule prompt. Matching is disabled until the user confirms the schedule or sufficient payment history establishes it. Later unexpected payments on detected bills prompt review rather than silently settling/changing the reminder. Bills and Notifications show the unresolved prompts. Saved user edits remain authoritative; deleting a reminder suppresses rediscovery and preserves its expenses.
- Discovery runs through CSV/PDF import, Apple Pay capture, existing non-demo ledger unlock, and normal validated store updates. Optional bill metadata and account-scoped dismissals round-trip in encrypted ledgers/backups; old backups retain their defaults.
- Final full core run: **85 tests, 84 passed, 1 skipped, zero failures**. The pre-existing fictional grocery model smoke test abstained and skipped; the new live Apple subscription test passed and returned Subscription for the fictional Apple iCloud+ storage input. Tests cover original 407-row CSV/PDF iCloud history, canonical service matching, one-charge prompts, automatic cadence refinement, later amount-change prompts, generic Apple ambiguity, manual corrections, suppression/persistence, and unchanged financial arithmetic. Log: `/tmp/harbor-recurring-tests-final.log`.
- Native simulator build passed. Two focused native UI flows passed on iPhone 18 Pro / iOS 27 using the isolated debug ledger: automatic iCloud Subscription classification with six matched payments and encrypted relaunch; single-charge schedule prompt, explicit confirmation, and no repeat prompt after relaunch. Logs: `/tmp/harbor-recurring-ui.log` (automatic-history case passed), `/tmp/harbor-recurring-ui-confirmed.log` (final schedule case passed). Initial schedule test attempts exposed a missing currency marker in the synthetic fixture and retained Settings scroll position in test navigation; both test setup issues were corrected.
- Screenshots in `output/auto-recurring-bills/` verify the iCloud category and automatic tracking. No physical iPhone installation or verification was performed. Live model smoke evidence is from this Mac, not proof of model availability or accuracy on the target iPhone. This is local reminder tracking, not payment automation or a bank connection.

---

# Clear transaction review flags — October 17, 2026

- New CSV/PDF records no longer receive a blanket review flag. Clear standard statement labels (including renamed identities), reviewed merchant evidence, manual category corrections, and accepted on-device suggestions can clear review. Unknown categories, ambiguous transfers/card payments, conflicting standard income/expense labels, and stale model evidence remain flagged. Model evidence is bound to the merchant, direction, and selected category.
- Existing non-demo ledgers are reassessed after normal unlock/load through the encrypted atomic save path. This clears supported old flags without changing transaction categories, amounts, dates, accounts, or links. Explicit manually flagged records and linked transfers are retained. The category action previews both category and approval-only changes before applying.
- Optional automatic-review provenance preserves older backup compatibility and excludes automatically approved rows from human-reviewed merchant training. Explicit bulk user confirmation removes that provenance; Apple Pay automatic categorisation records it too.
- Full core suite: **76 tests passed**, zero failures/skips, including live Apple Foundation Models classification of the fictional supermarket as Groceries. The subsequently added unfamiliar-label/direction regression also passed independently. Logs: `/tmp/harbor-review-full-tests.log`, `/tmp/harbor-review-extra-test.log`.
- Native simulator build passed. Signed native UI test **testClearCategoryReviewFlagsPersist passed** on iPhone 18 Pro / iOS 27. It previewed three approval-only changes, applied them, relaunched, and verified the Needs review switch was off. Tests used the isolated debug ledger. Log: `/tmp/harbor-review-ui.log`; result: `/tmp/harbor-review-derived/Logs/Test/Test-Harbor-2026.10.17_13-44-15--0300.xcresult`.
- Initial sandboxed checks could not access Apple OCR/model services or SwiftUI macro plugins; reruns with normal local service access passed. No physical iPhone installation or verification was performed. Existing device records change only when this updated app is run there. On-device suggestions remain model judgments rather than an accuracy guarantee.

---

# Apple on-device categorisation and top categories — October 15, 2026

- Top Categories now appears before detailed charts in Analytics and has a direct Home link. It ranks positive spending for the selected month/currency, excluding income and linked transfers. Empty months show an explanation; exports use the same ranking. Full-row touch targets open the category editor.
- Integrated `SystemLanguageModel` and guided `@Generable` output through Apple's Foundation Models framework, gated to iOS/macOS 26+ with availability/language checks. No cloud model, Private Cloud Compute session, network fallback, credential, or remote API was added. Model input contains only a bounded merchant description, source category, direction, and existing/standard category options. Generated indices are independently validated. The model cannot change monetary/date/account/transfer fields.
- Import preview automatically categorises from reviewed merchant evidence, clear statement aliases/descriptions, then the on-device model for unresolved descriptions. Manual category edits override this. Renamed categories retain stable import identities; merges retain previous identities. Imported suggestions stay unreviewed and do not teach the history rule. Model work is limited to 20 unique unresolved combinations per account/operation and 40 category choices; remaining/uncertain/error rows retain their source labels.
- Added Manage Categories with rename/edit, same-currency merge, concrete cleanup preview, and suggestions for existing unreviewed records. Cleanup merges equivalent labels and removes unused zero-budget categories, preserving referenced categories, custom names/icons, balances, and budget totals. Budgeted unused categories are deliberately retained. Reviewed/manual transaction assignments are protected from automatic reclassification. Preview application rejects a changed ledger snapshot. Manual forms have Suggest category and save a proposed new category only with the transaction.
- **59 core tests passed**, zero failures/skips, including seven categorisation tests for alias/renamed-category reuse, manual overrides, reviewed-history precedence and currency separation, merge/reference/budget invariants, ranked spending excluding zero/income/transfers/other currencies, generated-index validation, and a live model smoke test. The actual Apple on-device model on this Mac classified the fictional `Local Grocery Supermarket` input as `Groceries`; this is a single smoke check, not a category-accuracy benchmark. An earlier model request abstained, exercising the fallback.
- **2 focused native UI tests passed**, zero failures: `testCategoryAnalyticsRenameAndCleanup` and `testUSDImportSavingsAndReporting`. Covered actual-spending ranking, custom rename, cleanup cancellation/application, manual-form suggestion/cancellation, Files CSV import with category preparation, USD reporting, balanced savings transfers, and encrypted relaunch persistence. The USD fixture retained source 995.00, savings 250.00, total USD 1,245.00, with CAD separate. Destructive/financial UI checks used only the isolated test ledger.
- Final signed simulator build passed after the final custom-icon preservation and manual-proposal currency checks. Eight screenshots exported to `output/category-screenshots/`; visually reviewed ranking, category management, and the manual suggestion form. Simulator reports Apple Intelligence available; the UI test's Rent suggestion uses the deterministic fallback path. Live model generation was directly verified on the Mac, not on a physical iPhone.

Evidence: `/tmp/harbor-categories-core-final.log`, `/tmp/harbor-categories-complete.log`, `/tmp/harbor-categories-complete.xcresult`, `/tmp/harbor-categories-final-build.log`.

Limits: no physical-device installation/publication or full older UI-suite rerun. Model results remain suggestions requiring review, and runtime availability varies by device/language/settings/model readiness. Existing user records were not silently migrated or reclassified. Rebuild/run the iPhone app to use the updated source.

---

# Settings, appearance, and clear all data — October 15, 2026

- Replaced the fifth tab’s More label with Settings; existing profile, accounts, security, imports, backups, analytics, and bill tools remain accessible there.
- System (default), Light, and Dark use a locally saved preference independent of the ledger. Native color-scheme inheritance applies across tabs, forms, and the lock screen. Shared surfaces, text, icons, and filters adapt; navy hero cards retain pale labels and progress bars.
- Clear all data requires an explicit destructive confirmation and uses the validated, atomic encrypted save path. It removes the profile and entire ledger, including categories/limits. It writes a non-demo empty ledger, preventing sample reseeding on relaunch. Appearance, app lock, encryption key, and exported files are retained. Recovery mode blocks deletion.
- **52 core tests passed**, zero failures: `swift test --scratch-path /tmp/harbor-settings-swift`. Log: `/tmp/harbor-settings-core.log`.
- **Final signed simulator build and focused native UI test passed**, zero failures, on iPhone 18 Pro / iOS 27. Test: `HarborUITests/testAppearanceAndClearAllData`. Verified System default, Dark/Light switching, saved Dark after relaunch, return to System, cancel without deleting, confirmed populated-ledger reset, empty profile/accounts/transactions/budgets/goals/bills after relaunch, and repeat reset in non-demo mode. Every destructive test used the debug-only isolated ledger and preference key.
- Nine screenshots exported to `output/settings-screenshots/`; visually checked Light/Dark Settings, Dark Home/Activity/Budget/Goals and transaction form, and reset result. Visual review caught and corrected a low-contrast hero label before the final passing run.

Evidence: `/tmp/harbor-settings-verified.log`, `/tmp/harbor-settings-derived/Logs/Test/Test-Harbor-2026.10.15_16-50-37--0300.xcresult`.

Limits: simulator verification, not a physical-device run or publication. The full existing UI suite was not rerun. System uses SwiftUI’s native inherited appearance; changing the device appearance while the app is open and lock-screen appearance were not separately automated. No user financial records were cleared.

---

# Currency, linked savings, and adaptive Vision PDF import — October 15, 2026

- **52 core tests pass**, zero failures. Added native-currency detection/mismatch/mixed-currency rejection; separate account/report/budget/forecast totals; balanced savings pairs; account reuse; preservation of source IDs and balances; duplicate savings protection; destination-credit reconciliation; paired edits/deletes; version-1 CAD backup compatibility and version-2 schema protection; adaptive recognized-table mapping and ambiguous-date/balance rejection. Existing finance/import/PDF/OCR/encryption/forecast/recurring/account-protection checks pass.
- **Live Apple Vision document recognition passes** on the unfamiliar fictional GBP table: posting-date/payee/paid-out/paid-in/balance columns, 3 rows, GBP 100 opening, 20 income, 15 spending, 105 closing. This calls `RecognizeDocumentsRequest` through the actual PDF fallback, not mocked OCR. Processing is local; iOS/macOS 26+ is required for that fallback.
- **2 focused native UI tests pass**, zero failures: Files USD import → detected currency → new linked Savings account → separated USD reporting → encrypted relaunch; Files unfamiliar GBP PDF → actual Vision recognition → GBP account save. USD example: source 995, savings 250, combined USD 1,245, spending 255; CAD demo balances are displayed separately. Screenshots exported and visually reviewed in `output/currency-savings-screenshots/`. A final formatting refinement uses a single ISO currency label instead of repeating USD and US$.
- Expanded 683-row CSV/PDF fixture with savings tracking reconciles source **CAD $4,760.47**, savings **$2,850.00**, 18 linked transfer entries, **$49,443.69** consumption spending, and 683 duplicate source-row matches. Retrospective attachment preserves all source IDs/balances and cannot repeat an already linked selection. Tests use isolated fixtures/ledgers; existing normal saved records are not silently recategorized or transferred.
- Final signed simulator build passes and was installed/launched normally with the data container retained. Backup schema 2 prevents old CAD-only builds from interpreting multi-currency or linked-transfer records; schema-1 CAD data remains readable. No cloud OCR, exchange-rate API, conversion, or bank integration was added.

Evidence: `/tmp/harbor-multicurrency-tests.log`, `/tmp/harbor-multicurrency-build.log`, `/tmp/harbor-multicurrency-ui.log`, `/tmp/harbor-multicurrency-ui.xcresult`.

Limits: simulator verification, not a physical-iPhone run or publication. Nine currencies with two decimal places are supported; mixed/unsupported currencies and ambiguous symbols/dates require resolution rather than guesses. Existing-account currencies are immutable. An auto-created savings account tracks observed movements only, not an assumed complete bank balance. The Vision fallback still requires recognizable transaction tables on every page; unfamiliar summary-only pages remain unsupported. The complete older native UI suite was not rerun. Older USD-rejection fixture was updated to unsupported JPY because USD is now intentionally supported.

---

# Expanded CSV/PDF formats — October 15, 2026

- Tested the two newly supplied fictional files, preserved as test-only `ExpandedTransactions.csv` and `ExpandedStatement.pdf` fixtures. CSV headings Money In (CAD), Money Out (CAD), and Running Balance (CAD) now map correctly. Separate-column PDF tables support day/month names, month/year headings, wrapped descriptions, continuation pages, and independently reconciled summary/month totals.
- **41 core tests pass**, zero failures. Both formats contain **683 transactions**: opening **$3,850.25**, deposits **$53,203.91**, total debits **$52,293.69**, closing **$4,760.47**. All 683 PDF rows match CSV date, description, amount, direction, category, running balance, and payment-method suffix. CSV extra notes are preserved; the PDF does not contain every CSV memo. Importing CSV into a new test account yields the exact closing balance; all 683 PDF rows are detected as duplicates. Removing a continuation or final PDF page fails reconciliation. Original PDF/OCR/import/encryption/forecast/recurrence/account-protection tests pass too.
- **1 native Files-import test passes**, zero failures: new CSV preview/save, possible-transfer notice, new 30-page PDF preview, automatic existing-account selection, all 683 duplicates unchecked, Save disabled. Signed simulator build passes, installed and launched normally with saved data retained. Tests use the isolated debug ledger/Keychain namespace. Screenshots exported to `output/expanded-import-screenshots/`; source PDF summary/table pages rendered and visually inspected.
- The new PDF distinguishes **$49,443.69 living expenses** from **$2,850.00 savings withdrawals**. Harbor's current expense/income model treats the latter as expenses; cash-flow balances reconcile, but spending includes savings transfers. The preview now warns about possible savings/transfers. This change does not add transfer accounting or automatically infer internal account movements.

Evidence: `/tmp/harbor-expanded-tests.log`, `/tmp/harbor-expanded-build.log`, `/tmp/harbor-expanded-ui.log`, `/tmp/harbor-expanded-ui.xcresult`.

Limits: not a universal CSV/PDF parser. CSV still requires recognizable columns, ISO dates, CAD amounts, and oldest-first ordering. New PDF support covers the inspected table family; unrecognized layouts/dates, unsupported currencies, and unclear financial cells still fail safely. Text-only new-layout pages were tested; original-layout clean/watermarked OCR regression tests pass, but no scanned version of the new 30-page format was tested. No physical-iPhone run or publication; rebuild in Xcode to update a device. No user source files or normal saved transactions were edited.

---

# Duplicate-statement account protection — October 15, 2026

- **38 core tests pass**, zero failures. Added regression checks that a repeated PDF matches the existing CSV account, creating a new account from overlapping transactions fails atomically unless explicitly overridden, separate accounts with identical histories remain ambiguous, and partial/small matches never automatically choose an account.
- New imports scan for overlaps across accounts before destination selection. A unique full match with at least three transactions selects the existing account and leaves duplicate rows unchecked. Choosing Create new account with overlap requires an explicit separate-account toggle; the shared import save path enforces that choice too. CSV/PDF closing balances remain reconciliation information, never separate deposits.
- Existing duplicate accounts are preserved. This change prevents accidental repeats; it does not infer which saved account should be deleted or merge user records.

**1 focused native CSV → PDF repeat import test passes**, zero failures: automatic existing-account selection, new-account warning/disabled save without explicit override, duplicate rows unchecked on return to existing account, and unchanged saved account balance after relaunch. Native test/build passes; final signed app installed and launched normally on the existing simulator. Screenshots exported to `output/repeat-statement-screenshots/`. No existing duplicate accounts were removed.

Evidence: `/tmp/harbor-repeat-statement-tests.log`, `/tmp/harbor-repeat-statement-ui-3.log`, `/tmp/harbor-repeat-statement-ui-3.xcresult`. Native import warning verification uses the isolated debug ledger/Keychain namespace and the fictional CSV/PDF fixtures. Initial native test attempts needed scrolling adjustments for the account picker and the saved-account row after relaunch.

---

# Recurring bills and simple categories — October 15, 2026

- **36 core tests pass**, zero failures: three-payment recognition across five cadences; variable amounts; insufficient/irregular, same-day, future, income, and cross-account rejection; confirmation without changing balances; chronological import matching without extra expenses; ambiguous/out-of-window rejection; month-end anchors; backward-compatible backups; repeatable category cleanup preserving balances, IDs, bill references, and aggregate budgets. Supplied 407-row CSV and PDF produce identical recurring suggestions and amount ranges. Existing PDF/OCR, encryption, import reconciliation, and forecast checks pass.
- **2 focused native UI tests pass**, zero failures: CSV import → evidence review → confirmed recurring bill → encrypted saved-ledger reopen; and explicit combined-category cleanup → merged Utilities limit retained. First recurring UI attempt failed because More retained its scroll position; corrected test navigation and passed on rerun.
- **Signed simulator build passes** using Xcode 27.0 and iPhone 18 Pro / iOS 27.0. Screenshot attachments exported to `output/recurring-bills-screenshots/` and visually inspected: evidence dates/amounts, tracked bill status, and simplified budget form are readable.
- Final signed app installed on the existing simulator and launched normally without test or sample-append flags. Installation retained its data container.
- Existing ledgers are not automatically recategorized. More → Simplify combined categories requires explicit confirmation. Known aliases simplify during new imports. Existing category limits are retained or summed on merges; newly separated Rent starts at zero for manual budget allocation. Normal app records were not used for destructive test actions; UI tests use the existing isolated debug ledger/Keychain namespace.

Evidence: `/tmp/harbor-recurring-tests.log`, `/tmp/harbor-recurring-ui-2.log`, `/tmp/harbor-recurring-ui-2.xcresult`, `/tmp/harbor-recurring-final-build.log`.

Limits: no physical-device verification or publication; the entire native UI suite was not rerun. Detection needs at least three matching expenses. Changed merchant descriptions, missing cycles, ambiguous matches, and unusually large amount changes require manual review. CSV/PDF inputs still follow the existing supported-layout and validation requirements. UI verification covers suggestion/confirmation/persistence; future-import matching is covered by core integration tests.

---

# Budget tabs and October examples — October 15, 2026

- Added **16 labelled fictional October 1–14 examples** to the current simulator's **Imported chequing** ledger, preserving the 407 historical records and existing budget limits. Final local receipt confirms **423 transactions**, **0 added / 16 duplicates skipped** on repeat, October spending **$2,039.47**, and month-end forecast **$3,134.45**. The first append saved all 16; this was an authorized current-ledger change, separate from isolated UI testing.
- **29 core tests pass**, zero failures. The new example test checks historical record preservation, 16 duplicate matches, two payroll deposits, October totals, and recalculated forecast/curve consistency. The test's first attempt used a UTC month-start with a local-calendar total; corrected the date to local October before passing.
- **1 focused native Budget UI test passes**, zero failures: history import, sample append in the isolated debug ledger, Current spending total, Forecasted Spending total, the ⓘ explanation sheet, automatic forecast trajectory, saved-ledger reopen, and duplicate-safe repeat. Screenshots were exported and visually inspected in `output/budget-forecast-screenshots/`.
- **Final signed simulator build passes** and was installed while preserving the current ledger. The supplemental append action is Debug-only, explicit, requires normal unlock/load and an exact account name, and goes through existing duplicate checks, financial validation, and encrypted persistence. Normal launches do not append examples.
- Forecast removed from Spending Analytics and placed under **Budget → Forecasted Spending**; recorded category budget editing remains under **Current spending**. Model details are expandable, and the info sheet explains the prediction, payroll treatment, privacy, and uncertainty.

Evidence: `/tmp/harbor-budget-tests.log`, `/tmp/harbor-budget-ui.log`, `/tmp/harbor-budget-ui.xcresult`, `/tmp/harbor-budget-final-build.log`, and `output/budget-forecast-screenshots/current-ledger-receipt.json`.

Limits: simulator verification only; no physical-device run or publication. The complete existing native UI suite was not rerun. Native computer-use capture was unavailable; UI verification used the app's Xcode test target and its screenshot attachments.

---

# Forecast verification — October 15, 2026

- **28 Swift package tests pass**, zero failures, including **8 forecast tests** covering history-only October prediction, already-paid rent, category/curve reconciliation, future record exclusion, current-month training exclusion, sparse/truncated history, historical/future months, month-end day clamping, ledger immutability, and the supplied 407-row fixture. Existing import/PDF/OCR/encryption/model checks also pass. Apple's Vision OCR tests required execution outside the filesystem sandbox.
- **Native simulator build and test build pass** with Xcode 27.0, iOS 27.0, iPhone 18 Pro. The final test build also compiles a guard that skips the October-specific UI scenario after October has completed.
- **1 focused native UI test passes**, zero failures: Files CSV import into the isolated debug ledger, explicit removal of demo transactions, navigation to October Analytics, assertion of CAD $3,921.96, and selection of the Forecast chart. Two earlier attempts exposed test setup issues (scroll direction and tapping the sample-replacement switch); the final test verifies switch state before saving.
- Screenshots visually inspected: `output/forecast-screenshots/October-forecast.png` and `October-trajectory.png`. They show the history-only estimate, planning range, local model notes, missing-October coverage warning, and dashed cumulative trajectory.
- Fixture result: **CAD $3,921.96**, planning range **$3,137.57–$4,706.35**. Four rolling model-selection checks: mean absolute error **$144.71**, versus **$171.07** for the prior-month-total baseline. These use fictional April–September data, not a measured October outcome or independently calibrated accuracy.

Evidence: `/tmp/harbor-forecast-tests.log`, `/tmp/harbor-forecast-ui-final.log`, `/tmp/harbor-forecast-ui-final.xcresult`, `/tmp/harbor-forecast-final-build.log`.

Limits: no physical-device test or publication; the complete pre-existing UI suite was not rerun. No Apple Foundation Models integration is claimed: the numerical model uses local Swift arithmetic and works without Apple Intelligence. Missing statement coverage, new bills, seasonality, and changing behavior remain forecast limitations. Test fixtures are not bundled into the shipping app; the normal saved ledger was not changed by the isolated UI test.

---

# App icon verification — October 15, 2026

Added an opaque 1024 × 1024 sailboat app icon, included its asset catalog in app resources, and selected `AppIcon` for Debug and Release. Native simulator build passed; the compiled Info.plist declares `CFBundleIcons` / `CFBundlePrimaryIcon` / `AppIcon`, and generated Home Screen PNGs are present. The source icon was visually inspected. Build log: `/private/tmp/harbor-icon-build.log`. Physical-iPhone installation remains unverified.

---

# Import verification — October 15, 2026

- **20 model/encryption/import tests passed**, zero failures. The actual supplied fictional CSV and original 19-page PDF produce the same **407 transactions**: every date, description, category, amount, direction, and running balance agrees. Totals: deposits **CAD $27,871.84**, withdrawals **$23,225.31**, opening **$2,846.55**, closing **$7,493.08**. Log: `/private/tmp/harbor-import-tests.log`.
- Import tests cover quoted/multiline/BOM CSV, exact cents, invalid dates/currencies/quoting/column widths, broken running balances, ordering, field/row/column limits including EOF boundaries, occurrence-aware duplicate checks across CSV and PDF, account balances, zero-budget categories, explicit sample replacement, and atomic rejection when savings allocations would be violated.
- On-device OCR successfully reads and reconciles a clean image-only statement. An image-only derivative of the supplied April pages obscures a balance under its watermark and is **rejected**, rather than reconstructing or guessing a transaction. The original supplied text PDF imports all 407 rows successfully.
- **5 native UI tests passed** on iPhone 18 Pro / iOS 27.0, including system Files → CSV preview → confirmation → encrypted save → PDF preview with all 407 possible duplicates unchecked → relaunch with the correct account balance. Existing transaction, budget, goal, bill, legacy-encryption migration, and locked-launch regressions also passed. Results: `/private/tmp/harbor-import-final.xcresult`; log: `/private/tmp/harbor-import-final.log`.
- The final default-preservation change was verified in a fresh native import test: demo-mode replacement starts off, requires an explicit toggle plus confirmation, and the CSV/PDF duplicate and encrypted-relaunch flow passes. Results: `/private/tmp/harbor-import-confirmation.xcresult`; log: `/private/tmp/harbor-import-confirmation.log`.
- Actual CSV/PDF import preview screenshots were visually inspected for native layout, readable totals, and disabled saving when zero transactions are selected. Fictional fixture documents are test-only SwiftPM resources and are not bundled in the shipping app. `scripts/stage_import_fixtures.py` stages them in Simulator Files for reproducible UI checks.

## Import verification limits

The PDF adapter supports the documented monthly CAD statement layout, not arbitrary bank templates. Scans must be legible enough for exact balance/count reconciliation; watermarks or OCR errors may cause rejection and require CSV. Duplicate matching is advisory and scoped to the chosen account; users can select legitimate repeated purchases. Physical-device OCR performance, iCloud/third-party document-provider behavior, all accessibility sizes, low-memory conditions, and backgrounding during an active import have not been exercised. Source files stay on device and are not uploaded; the parser treats all document text as data.

---

# Security verification — October 15, 2026

- **12 model/encryption tests passed**, including AES-GCM round trips, randomized ciphertext, wrong-key rejection, ciphertext/header tampering, truncation, and the existing financial invariants. Log: `/private/tmp/harbor-security-swift.log`.
- **4 native UI tests passed** on iPhone 18 Pro / iOS 27.0: legacy JSON migration and relaunch, locked-launch access gating and persistence, transaction creation/editing/relaunch with encrypted storage, and budget/goal/bill flows. Results: `/private/tmp/harbor-security-signed-ui.xcresult`; log: `/private/tmp/harbor-security-signed-ui.log`.
- Simulator testing uses actual Keychain access with local ad-hoc signing. An unsigned test run was rejected by Keychain with missing entitlements; Harbor stayed locked. Use `CODE_SIGN_IDENTITY=-` for simulator tests, rather than disabling signing.
- Encryption and app lock have separate roles: the ledger key is available only while the device is unlocked; optional LocalAuthentication gates Harbor's UI and loading of financial records. The key is not bound to biometric enrollment.

## Remaining device checks

Successful Face ID/Touch ID/device-passcode authentication, cancellation/lockout/fallback behavior, enabling/disabling the setting, backgrounding during authentication, privacy snapshots with an editor or share sheet open, real-device file protection, backup exclusion, and recovery after Keychain loss require physical-device verification. Migration UI tests verify record preservation and encrypted relaunch; they do not independently inspect deletion of the legacy file. Exported backups remain plaintext JSON and must be stored somewhere trusted.

---

# Verification — October 14, 2026

## Passed

- Native iOS Simulator build with Xcode 27.0, arm64, signing disabled, deployment target iOS 17.0.
- **10 Foundation financial-model tests**, zero failures: exact cent parsing, transaction edit/delete effects, per-month totals, goal/net-worth separation, combined allocation limits, reserved-funds protection, atomic bill payment and due-date advancement, backup round trip, invalid references/versions/duplicate identifiers, and extreme imported balances.
- **2 native UI tests** on iPhone 18 Pro / iOS 27.0, zero failures:
  - Add a transaction, find it in Activity, terminate/relaunch and confirm persistence, edit its amount and confirm the ledger value; navigate Home, Activity, Budget, Goals, and Analytics; open budget and goal editors.
  - Create a budget category, create a savings goal, mark a recurring bill paid, and find its newly recorded expense in Activity search.
- Screenshots captured from the actual running native app for all five primary screens. Visual inspection covers Harbor card/palette treatment, readable financial values, native tab/navigation controls, and safe-area layout. Selected filters were adjusted to keep readable contrast.
- UI tests use an isolated debug ledger. The simulator app was subsequently launched without testing arguments for manual review.

## Evidence

- Final native test results: `/private/tmp/harbor-ui-final.xcresult` (includes screenshots).
- Native test/build log: `/private/tmp/harbor-ui-final.log`.
- Model test log: `/private/tmp/harbor-tests-final.log`.
- Exported screenshots: `output/final-screenshots/Home.png`, `Activity.png`, `Budget.png`, `Goals.png`, `Analytics.png` (generated output is ignored by Git).

## Verification limits

Physical devices, older iOS runtimes, all accessibility text-size settings, landscape layouts, and App Store signing/distribution were not tested. JSON encoding/decoding and validation were tested; the system Files/iCloud backup picker and report share destinations were not exercised end to end. The app implements manual local records; bank connections, transfers, cloud sync, automatic funding/round-ups, Apple Pay imports, and push delivery are not implemented.

The reference screens remain unchanged. The native app follows their visual language using system fonts, SF Symbols, and current iOS chrome; it is not a pixel-identical HTML wrapper.

# Local workflow and portable recovery — October 17, 2026

- Added authenticated, versioned AES-256-GCM `.harborbackup` files with independently generated 256-bit recovery keys, explicit key re-entry, fresh nonces, bounded reads, validated restore previews, and retained legacy JSON compatibility. Keys and decrypted backup state are ephemeral; clipboard copies are device-local with a two-minute expiry. Registered the backup document type with Files.
- Added named Shortcuts account entities, explicit metadata publication when enabling capture, guided Wallet configuration, verified-receipt status, and separate imported/already-processed/error counts. Legacy Account ID parameters remain supported. Setup never creates a Wallet automation on the user's behalf.
- Added optional capture provenance and statement-confirmation metadata. Unique exact one-to-one statement matches default to confirming existing purchases; other matches require explicit selection within three calendar days and the same account/currency. Duplicate target selections and stale targets fail atomically. Original capture, transaction ID, notes, and category corrections survive reconciliation and manual edits. Editing a preview match clears and deselects it rather than silently creating duplicate spending.
- Reset disables capture before removing active/held inbox files and capture credentials. Failures report whether disabling succeeded. Restore quarantines old pending files before ledger replacement; held entries require individual release or deletion and unreadable files remain visible.
- Final core suite: **71 tests passed, zero failures/skips**, including backup round-trip/fresh-key recovery, wrong keys, fresh ciphertext, tampering, unsupported/malformed/oversized data, legacy JSON, reconciliation identity/category/amount/date behavior, ambiguity, currency/account isolation, repeated statement detection, editor provenance, and unreadable-file quarantine preservation. Live OCR and Apple-model smoke checks passed in this run. Initial sandbox-only OCR failures were resolved by running with system-service access; no OCR implementation changes were made.
- Signed simulator build succeeds. Native UI checks pass for recovery-key confirmation gating and cancellation, guided setup, locked launch/relaunch privacy, and complete reset with appearance retention. Tests use an isolated ledger and Keychain namespace, with fictional Files fixtures only.
- Physical Wallet triggers, locked-device behavior, legacy automation execution, and the named account picker inside the real Shortcuts app still need physical-iPhone verification. Storage-full/Keychain-error recovery paths were reviewed but not fault-injected on a device. Full encrypted Files export/save was not exercised by UI automation; encryption bytes and export preparation were tested separately.

Core evidence: `/tmp/harbor-final-core.log`. Simulator evidence: `/tmp/harbor-ui-tests.log`, `/tmp/harbor-restore-ui.log`, `/tmp/harbor-final-ui.log`, `/tmp/harbor-complete-ui.log`, and Xcode results under `/tmp/harbor-secure-build/Logs/Test/`.

- Final focused UI run: **2 tests passed** for backup setup/cancellation and encrypted Files restore. Wrong-key feedback was verified, tapping outside the iOS popover cancels and clears decrypted preview state without replacement, confirmed restore persisted after relaunch. Separate locked-launch and full-reset UI checks also passed. Final focused result: `/tmp/harbor-secure-build/Logs/Test/Test-Harbor-2026.10.17_11-14-50--0300.xcresult`. Earlier failing attempts exposed test navigation/scrolling assumptions and popover cancellation cleanup, all corrected before this passing run.

- Final signed build: `/tmp/harbor-final-build.log` (`BUILD SUCCEEDED`). Passing setup and restore screenshots were exported and visually inspected; durable copies are in `output/security-workflow-screenshots/`. No Plaid integration, server, cloud storage, production installation, or publication was added.

## Harbor 2.0 home and profile update — October 17, 2026

- Home places compact month navigation beside the greeting and removes the Home reporting-currency picker, raising the net-worth card. Currency selection remains available in Settings and reports.
- Upcoming bills use horizontally scrollable square tiles. Budget Health uses a horizontally scrollable two-row square grid, with all categories reachable and navigation to Budget retained. Squares scale with Dynamic Type.
- Weekly Spending replaces daily pace on Home. Every column, including zero spending, opens a daily summary with category totals, purchases, daily average and highest-spending day. Calendar weeks follow the device calendar; boundary weeks include only days within the selected month. Expense totals retain integer cents and exclude transfers, income and other currencies.
- Name editing supports keyboard Done and Save name, rejects blank/unchanged saves, dismisses the keyboard and shows a native confirmation alert only after persistence succeeds.
- Validation: signed iOS Simulator build passed; all 73 core tests passed (including two new weekly aggregation tests); two focused simulator UI tests passed for weekly drill-down, name confirmation/relaunch persistence, horizontal budget scrolling and navigation. Test records: `work/HomeChanges.xcresult`, `work/HomeGrid.xcresult`; core results: `work/tests-verified.log`.
- Exported simulator screenshots were visually inspected for header placement, summary, confirmation and square grids. Initial sandbox runs blocked SwiftUI compiler plugins and OCR services; reruns with local service access passed.
- Physical iPhone installation and on-device verification were not performed for this update.

## Harbor 2.0 Settings and navigation improvements — October 17, 2026

- The floating transaction button is shown only on Home and Activity. Settings, Budget, and Goals no longer show it.
- Spending Analytics is reached from Budget instead of Settings. Existing analytics navigation tests use the new destination.
- Apple Pay Shortcuts has its own Transaction capture section, separate from Accounts. Its introduction states that a Shortcut supplies purchase details; Harbor does not connect a bank or read Wallet transaction history directly.
- Settings, recurring bills, savings review, category management, backups, and Shortcut setup use shorter descriptions with optional Learn more screens. Recovery-key warnings stay visible. Reset keeps its permanent-deletion warning and explicit confirmation of deleted records, pending captures, disabled capture, and retained preferences/exported files.
- Signed simulator builds passed. Two focused UI tests passed: Settings navigation/optional help/reset cancellation, and encrypted backup setup/cancellation plus Shortcut setup navigation. Results: `work/SettingsImprovements.xcresult` and `work/SettingsBackupCheck.xcresult`.
- Exported screenshots from the Settings test were visually inspected for concise copy, capture explanation, and reset access without the floating button. Changed-file whitespace checks passed. No financial calculations or storage behavior changed; core tests were not rerun for this UI-only update.
- This update has not been installed or verified on a physical iPhone.

## Harbor 2.0 Activity header, Profile, and default currency — October 17, 2026

- Activity puts search first with the same compact month selector on the right as Home. Its reporting-currency picker is removed; separate currency labels on transaction totals remain to distinguish native balances.
- Search uses an outlined surface, adaptive opaque placeholder colors, primary typed text, a clear button, and keyboard submission that dismisses the keyboard. A visual check caught and corrected an initially dim system-styled placeholder.
- The Harbor icon returns to Home and resets its navigation stack. The person icon opens a dedicated Profile sheet instead of Settings; name editing, successful-save confirmation, and relaunch persistence are retained.
- Settings has no Profile section. Its standalone Currency section labels the existing preference Default currency. That preference supplies reports and new account defaults; it does not convert or change existing account currencies.
- Simulator builds passed. The Activity test passed on the final build, covering header positioning, search filtering/clearing, month changes, icon destinations, modal interaction, and default-currency persistence (`work/ActivityContrastFinal.xcresult`). The moved Profile save and relaunch test passed in `work/ActivityProfile.xcresult`; an unrelated assertion in the Activity test initially checked a covered button's existence rather than its interactivity, and passed after correction (`work/ActivityHeaderVerified.xcresult`).
- Final Dark Mode screenshots were exported and visually inspected, including the empty placeholder. Changed-file whitespace checks passed. Existing migration, restore, and reporting UI tests now follow the relocated controls; those full fixture flows were not rerun. Financial models and storage behavior were unchanged; core tests were not rerun for this UI update.
- No physical iPhone installation or on-device verification was performed.

## Harbor 2.0 category simplification completion and reporting currency — October 17, 2026

- Simplification availability is derived by comparing the validated cleanup result with the saved ledger. It is not a per-session or device flag: an unchanged ledger cannot be repeatedly simplified, and new cleanup work can make the action available again after imports, edits, or restoration.
- A successful cleanup replaces the action with an animated checkmark confirmation and a local Total budget preserved message. Reduce Motion uses a fade. Reopening Settings or relaunching shows Categories up to date without another actionable cleanup button. Confirmation rechecks availability before writing.
- Budget and Spending Analytics no longer show reporting-currency pickers. The only reporting picker call site is Default currency in Settings. Account/statement currency metadata remains part of its Settings-based setup/import flows.
- Signed simulator build and two focused UI tests passed (`work/SimplificationOnce.xcresult`): report-picker absence across tabs and Analytics, Settings availability, meaningful cleanup, preserved Utilities budget, and completed state after relaunch. Exported confirmation screenshots were visually inspected.
- All 74 core tests passed (`work/simplification-core.log`), including new coverage for availability before/after cleanup, unchanged repeated execution, encoded/decoded persistence, and new cleanup work. Changed-file whitespace checks passed.
- No physical iPhone installation or on-device validation was performed.

## Harbor 2.0 one-tap Mark paid — October 17, 2026

- Mark paid now immediately records one expense and advances the recurring reminder. The extra Record payment dialog is removed. Only successful persistence replaces the action with a Paid checkmark, paid date, and next due date. Home bill tiles display the same paid status.
- Optional lastPaidAt receipt metadata preserves old bill/backup decoding. Editing a reminder retains its receipt. Completion remains visible until the next due day, with same-day protection for overdue catch-up payments. The next recurring occurrence remains payable when due; no bank payment is initiated by this bookkeeping action.
- Payment writes check both saved completion and the tapped due date before changing balances, preventing stale/double taps from creating another expense. Validation failure retains the original ledger and completion state.
- All 79 core tests passed (`work/mark-paid-core.log`), including payment atomicity, duplicate/stale occurrence rejection, completion backup round-trip, next recurrence, and legacy decoding.
- Signed simulator build and focused payment UI test passed (`work/MarkPaidVerified.xcresult`): one-tap completion without a second dialog, retained completion after editing/relaunch, Home paid badge, and exactly one matching Activity transaction. Exported bill-manager and Home screenshots were visually inspected. An initial UI test compile error in its count assertion was corrected before the passing run.
- Changed-file whitespace checks passed. No physical iPhone installation or on-device verification was performed.

## Harbor 2.0 monthly briefing review scope — October 17, 2026

- Home's financial briefing now counts needsReview entries in the selected month, across accounts/currencies, matching Activity's month scope before its optional search/account/category filters. Zero is stated explicitly as No transactions need review this month.
- Notifications retains the full-ledger count and labels it across all months, with instructions to select a month in Activity. No review flags, categories, or amounts are changed by this display correction.
- Signed simulator build and focused UI regression test passed (`work/MonthlyReviewCount.xcresult`). The test verifies a seeded month with three reviews, a different month showing zero in both Home and Activity, three remaining all-month reviews in Notifications, and the original three flags still present when returning to their month.
- Changed-file whitespace checks passed. Core/model code was unchanged; core tests were not rerun. No physical iPhone installation or access to the user's saved ledger was performed, so the specific 567 transactions have not been inspected.
# Apple Pay account selection persistence — October 19, 2026

- The Apple Pay Shortcuts Settings picker saves its account UUID locally, validates it against the current ledger, and clears it after account removal or a successful full reset. UI tests use a separate preference key.
- Signed simulator build and `HarborUITests/testApplePayAccountChoicePersists` passed on iPhone 18 Pro / iOS 27: initial empty choice, selection retained after navigation and relaunch, replacement retained after relaunch, and explicit clearing retained after relaunch. One test, zero failures.
- Evidence: `/tmp/harbor-account-choice-final.log` and `/tmp/harbor-account-choice-derived/Logs/Test/Test-Harbor-2026.10.19_11-47-45--0300.xcresult`.
- Limits: no physical-iPhone installation or Wallet automation changes. Account deletion and full-reset invalidation were inspected in code but not separately exercised by this focused test.

# Apple Pay reconciliation and held-account recovery — October 19, 2026

- User reports a successful real Apple Pay capture on their iPhone. This is user-reported device evidence; no new physical-device run or installation was performed here.
- Fixed held-purchase recovery after backup restore: a missing destination account can be changed to an existing same-currency account without releasing the purchase. Reassignment replaces the encrypted file atomically, preserves its UUID, rejects wrong currencies and files outside the selected inbox, and remains quarantined until explicit release. Active pending choices also show only same-currency accounts.
- Full core suite completed: 92 tests executed, 91 passed, one skipped, zero failures. The skipped live Apple model test abstained on fictional input. New regression cases cover same-amount genuine purchases, statement confirmation across a month boundary with changed merchant/amount, repeat statement detection, capture retry after encrypted reload and portable backup recovery, missing-account reassignment, currency rejection without mutation, and explicit release from quarantine. Log: `/tmp/harbor-reconciliation-full.log`.
- Signed simulator build and two focused UI tests passed on iPhone 18 Pro / iOS 27: `testApplePayAccountChoicePersists` and `testHeldApplePayAccountRecovery`. Verified held destination correction across restart, explicit release, one Activity entry after another restart, and saved setup selection. Log: `/tmp/harbor-reconciliation-ui-final.log`. Initial build hit a SwiftUI type-checking limit; extracting the recovery section resolved it before the passing run.
- Limits: automated checks use fictional isolated data. No user's real statement was reconciled against their real capture; no fresh-install restore on a second physical device, full older UI suite, bank integration, cloud sync, or deployment was performed. Failed independent Shortcut executions still have independent capture IDs; stable-ID idempotency protects replay of the same saved capture, not arbitrary duplicate manual runs.


## Harbor 2.0 button responsiveness and monthly category management — October 19, 2026

- Full and compact month arrows use independent borderless button styling. Full controls inside List/Form rows no longer rely on automatic row-wide button behavior; compact arrows have 44-point targets. Category edit and merge labels have separate full-width, 44-point minimum hit areas.
- Manage Categories builds one selected-month transaction-count dictionary instead of scanning the ledger per category row. Its default list includes categories used by non-transfer transactions across all account currencies, including persisted on-device model assignments. It retains income categories, manual choices, and saved budgets. Show all saved categories remains available; month changes reset that override to make monthly membership clear.
- Category auto-suggestion preparation processes each account in its own currency context. Changing months or leaving cancels the pending view task and invalidates its request token so old results cannot appear for a new selection. Cleanup previews are built/validated off the UI actor, with a busy indicator and the existing stale-ledger guard before application.
- Simplification eligibility is cached when the ledger changes rather than cloning and validating the ledger repeatedly during Settings rendering. Financial arithmetic, encryption and normal atomic persistence are unchanged.
- Core suite: 92 tests executed, 91 passed, 1 skipped, zero failures (`work/category-month-oct19-core.log`). The live Apple model abstained on its fictional-merchant test, triggering its explicit availability/abstention skip; deterministic monthly counts cover persisted automatic assignments across currencies.
- Signed simulator builds and four UI tests passed: independent month arrows/edit/merge targets, saved-category visibility, simplification/budget/relaunch behavior (`work/CategoryMonthOctober19.xcresult`), and single-tap Profile/Home navigation across all five tabs plus notifications, transaction entry/cancel, and asynchronous cleanup preview/cancel (`work/PrimaryButtonsOctober19.xcresult`). Category screenshots were exported and visually inspected. Changed-file whitespace checks passed.
- These checks cover shared controls and primary flows, not every possible screen/data combination. Physical iPhone behavior and latency against the user's populated ledger remain unverified; this update has not been installed on the phone.
# Separate-install backup recovery and app-update preservation — October 19, 2026

- Used two dedicated iPhone 18 Pro / iOS 27 simulators with independent app containers and Keychains. All records and recovery keys were fictional QA data. No normal user ledger, physical iPhone, or Wallet automation was changed.
- The source simulator migrated a legacy JSON test ledger, selected Dark appearance and a named Shortcut account, and exported an encrypted backup through the real Files interface. Installed the newer local app binary over the prior local build without resetting its container. The profile, appearance, and Shortcut account remained selected; the encrypted ledger was byte-for-byte unchanged, and the migrated plaintext file was absent. The prior/current executable SHA-256 values differ and are recorded in `output/backup-recovery-verification/summary.json`.
- On the separate destination simulator, the actual source export with a wrong recovery key and a deliberately corrupted copy with the correct key both failed validation. Neither offered ledger replacement. The original destination ciphertext remained byte-for-byte unchanged after the failed attempts and relaunch.
- Restored the valid source export through Files, recovery-key entry, validation, and explicit Replace records confirmation. Relaunched and exported the restored ledger through Files. The destination retained its local System appearance rather than inheriting the source phone's Dark preference. Native decoding and Equatable comparison proved source, post-update, and restored exports contain identical persisted fields: 3 accounts, 10 transactions, 9 categories, 4 goals, and 2 bills, with the same IDs, references, and balance inputs.
- Four distinct focused UI tests passed: `testBackupSourceExportForDeviceMigration`, `testBackupSourceSurvivesAppUpdate`, `testBackupDestinationRejectsWrongKeyAndDamage`, and `testBackupDestinationRestoreAndExport`. Initial test-only Files navigation/timing issues were corrected; the final restore/export helper also passed a rerun with the intended filename. No production behavior changes were required.
- Full core suite with actual exported artifacts staged: 93 executed, 92 passed, one skipped, zero failures. The live Apple merchant model abstained on fictional input; backup verification did not skip. A final focused native audit also passed against the last correctly named export. Test source comments document fixture/environment requirements; destination tests skip when their synthetic migration key is not supplied.
- Evidence: `/tmp/harbor-backup-source.xcresult`, `/tmp/harbor-backup-update.xcresult`, `/tmp/harbor-backup-destination-final.xcresult`, `/tmp/harbor-backup-export-verified.xcresult`, `/tmp/harbor-backup-core-verified.log`, `/tmp/harbor-backup-export-audit-final.log`. Sanitized durable receipt: `output/backup-recovery-verification/summary.json`. Fictional exports and keys remain only in temporary QA artifacts; the durable receipt contains no recovery keys or full ledger.
- Limits: this verifies replacement by the tested current build, not every future release or unknown schema migration. No physical-device transfer, iCloud/third-party Files provider, enabled Face ID upgrade, full older UI-suite run, or production installation was tested. Backup exclusions (device keys, app lock, appearance, Shortcut account preferences, and pending captures) remain intentional.


## Harbor 2.0 Shortcut action feedback and responsiveness — October 19, 2026

- Check for received capture and Refresh account choices in Shortcuts now have independent borderless, 44-point-minimum button rows, pending labels/spinners, busy guards, and result/error text beside the action. Empty checks explicitly say No new captures found. Account refresh confirms the number of choices written; disabled setup explains that capture must first be enabled.
- Manual capture checks yield between purchases rather than holding the UI through an entire queue. A shared main-actor import helper preserves atomic ledger save before inbox deletion, stable-ID duplicate handling, pending-file retention on failure, and lock/recovery guards. A shared drain-in-progress guard prevents overlapping manual/automatic consumption. Account metadata writes remain serialized on the main actor.
- Held captures are scanned on screen entry, avoiding a redundant scan during every manual verification refresh. The held recovery row also now explicitly separates Release, Delete, and destination actions: testing exposed the automatic List button style firing more than one row action. The recovery test now rejects an Unable to save alert after release.
- Signed simulator build and both final UI tests passed (`work/ShortcutActionsFinal.xcresult`): visible empty-check result, repeated account-refresh success, held captures retained during checking, held destination reassignment across relaunch, release without a spurious delete/error, and exactly one persisted Activity entry. The result screenshots were visually inspected (`work/shortcut-action-feedback-screenshots`).
- Core suite: 93 executed, 91 passed, 2 skipped, zero failures (`work/shortcut-action-feedback-core.log`). Skips were the optional device-migration-export fixture check and the live Apple model abstaining on a fictional merchant. Changed-file whitespace checks passed.
- Physical iPhone capture-trigger delivery, Shortcuts picker cache refresh, and performance against the user's actual capture queue remain unverified. No phone installation was performed.
# Import history and monthly balance reconciliation — October 19, 2026

- Added Settings → Import history and Monthly reconciliation. Successful CSV/PDF imports now save an immutable receipt atomically with their selected financial entries. Receipts retain only source filename (no original path/document), timestamp, account/currency snapshot, date range, available statement balances, row counts, and entry IDs. Counts distinguish added rows, matched Apple Pay purchases, skipped duplicates, and unchecked rows; linked savings rows can create two entry IDs. Later edits/deletions do not rewrite history, and earlier imports are not fabricated retroactively.
- Duplicate-only imports on an existing account can explicitly record a skipped-import receipt without adding transactions or changing balances. Cancellation and failed imports save neither a receipt nor partial financial rows. Explicit demo replacement/reset clears the corresponding history.
- Monthly reconciliation calculates opening balance plus all native-currency account movements through the selected closing day, using an exclusive next-day cutoff. Future movements and other accounts are excluded; linked transfers are included. The screen shows Harbor minus statement, exposes unconfirmed Apple Pay and closing-month transaction drill-downs, and never inserts an adjustment. The last purchase date suggested by a receipt must be checked against the actual statement date. A matching total is not a claim that every transaction is confirmed.
- Saved comparisons retain the civil closing day and entered statement balance. Current differences recalculate after edits; saving the same account/day updates one comparison. Reopening chooses the most recently compared available account in its recorded currency. This fixes a usability gap found during QA where choosing the first account hid another account's saved comparison. Saving dismisses the keyboard; detailed explanations are under Learn more.
- Optional metadata keeps old ledgers readable. New receipts/checks require schema version 3, so older builds reject rather than silently discard them. The current app reads versions 1–3. Ordinary edits, savings operations, imports, and restore preserve the required version. Histories and comparisons are included in encrypted portable backups, with existing encryption/key access unchanged.
- Full core suite: **104 executed, 103 passed, one skipped, zero failures** (`/tmp/harbor-statements-core-verified.log`). The live Apple merchant model abstained on fictional input; backup and feature tests ran. Eleven new core tests cover parsed CSV receipts, partial/duplicate-only imports, failed-save atomicity, matching captures, linked transfers, cutoff/date/currency isolation, edits/upserts, portable backup/legacy compatibility, invalid metadata, provisional captures despite equal balances, and recent-account fallback after deletion/currency mismatch.
- Signed native build and **three distinct UI tests passed** on the dedicated iPhone 18 Pro / iOS 27 simulator: `testDuplicateOnlyImportSavesReceipt`, `testImportHistoryAndMonthlyReconciliationPersist`, and `testCSVImportThenPDFDuplicatePreview`. The new flows verify real Files import, 3 added rows, 3 skipped rows on repeat, encrypted history/comparison persistence, a $1 difference, editing the underlying purchase to recalculate a match, and ordinary editor access. The existing 407-row CSV/PDF regression verifies duplicate preview, separate-account guarding, and unchanged CAD $7,493.08 after relaunch. Test-only scrolling corrections resolved initial selector failures; the final build's CSV/PDF and reconciliation rerun succeeded.
- Evidence: `/tmp/harbor-statements-ui-verified.xcresult` (final two-test passing rerun), `/tmp/harbor-statements-ui-final.xcresult` (passed duplicate-receipt test; contains an earlier unrelated scrolling failure subsequently fixed), `/tmp/harbor-statements-last-build.log`. Screenshots in `output/statement-history-screenshots/` were exported from the running native app and visually inspected. `verification.json` summarizes the checks without real user data. Changed-source whitespace check passed.
- Limits: fictional isolated simulator data, not a physical-iPhone installation or populated-device performance test. The full older UI suite was not rerun. Reconciliation relies on the entered opening/closing balances, correct closing date/sign convention, and complete recorded history; it does not infer missing bank transactions or reconcile against a live bank. Existing iPhone data was not modified. Use an updated Harbor build to open a version-3 ledger/backup.


# Home Budget Health category taps — October 19, 2026

- Each Home Budget Health tile now opens the selected category’s monthly transaction detail, including transaction editing and Edit budget. View all continues to open Budget.
- Signed simulator build and both focused UI tests passed: Home horizontal-grid tap/detail/dismiss flow and existing Budget category transaction/editing regression (`work/HomeBudgetClick.xcresult`, `work/home-budget-click.log`). No physical iPhone installation was performed.
