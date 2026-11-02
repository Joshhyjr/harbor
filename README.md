# Harbor for iPhone

Harbor is a local-first personal finance app for iPhone, built with SwiftUI. Track accounts and transactions, plan monthly budgets, manage recurring bills, and work toward savings goals with encrypted local storage and portable backups.

## At a glance

- **Native iOS:** SwiftUI, Swift Charts, and system file import/export; iOS 17 or later.
- **Local workflow:** no backend, bank connection, or API keys required.
- **Reviewable imports:** CSV and PDF statement previews, duplicate handling, and monthly reconciliation.
- **Personal planning:** categories, budgets, spending forecasts, savings goals, and opt-in reminders.
- **Optional integrations:** user-configured Apple Pay Shortcuts and on-device Apple Intelligence categorization on supported devices.

## Repository layout

| Path | Contents |
| --- | --- |
| `Harbor/` | SwiftUI app, assets, and core finance logic |
| `Harbor.xcodeproj/` | iPhone app project and shared Harbor scheme |
| `HarborTests/` | Core tests and fictional import fixtures |
| `HarborUITests/` | App UI tests |
| `samples/` | Fictional example transactions |
| `scripts/` | Local development utilities |
| `harbor_*/` | Original design exports and references |
| `VALIDATION.md` | Historical validation notes and known limits |

## Quick test

On macOS with the Swift toolchain installed, run `swift test` from this directory for the core test suite. Use Xcode's **Product → Test** with an iPhone simulator for app UI tests. See the detailed validation commands below. Local build products and generated validation artifacts are excluded from Git.

Native SwiftUI implementation of the five supplied Harbor designs, for iOS 17 and later. The original HTML and reference images are preserved in their export folders.

## Run

1. Open `Harbor.xcodeproj` in Xcode.
2. Select the **Harbor** scheme and an iPhone simulator, then Run (⌘R).
3. For a physical iPhone, choose your development team in **Signing & Capabilities**, select your connected device, and Run. Device signing and App Store distribution are not configured.

Harbor includes a blue sailboat Home Screen icon in its asset catalog. Regenerate it locally with `swift scripts/generate_app_icon.swift`.

No third-party packages, API keys, network connection, or web runtime are required. The app uses native navigation, tab bars, sheets, date/account pickers, Files import/export, share sheets, SF Symbols, and Swift Charts. Harbor's supplied palette and card treatments are retained with system fonts and safe-area handling.

## Working flows

The bottom bar is **Home · Activity · Categories · Budget · Goals**. Open the person icon on any tab for **Profile → Settings**; Done returns to the main tabs.

- **Home:** net worth from account balances, monthly income/outflow/budget remaining, ledger-based briefing and daily chart, upcoming bills, budget summaries, recent transaction editing.
- **Activity:** add, edit, delete, search by merchant/category/note, month/account/category filters, needs-review filter, and confirmable batch review of visible results.
- **Categories:** colorful category cards, selected-month spending and transaction counts in the default reporting currency, name search, and an explicit All saved collection. Tap a card for its transactions and Edit category to customize its name/icon. New category creates a saved category; Organize opens reviewed cleanup and merging tools. Budget controls remain available in an optional editor section.
- **Budget:** Current spending and Forecasted Spending tabs, an info sheet explaining predictions, a forecast trajectory and projected budget comparison, per-category limits and custom categories, monthly spending, on-track/near-limit/exceeded filters. Limits repeat monthly; editing a limit also changes historical comparisons.
- **Goals:** create/edit/delete goals, choose a funding account, set target/date/priority, allocate or release funds, and filter completed/high-priority/in-progress goals.
- **Analytics:** daily/cumulative/prior-month recorded-spending views, weekly totals, category share/currency amount toggle, native report sharing. Forecasts live in Budget → Forecasted Spending.
- **Settings (from Profile):** reviewed CSV/PDF transaction imports, account creation and opening-balance editing, recurring bill management, Face ID/device-passcode app lock, encrypted portable backup export/restore with legacy JSON support, and confirmed removal of demo data. Edit the profile name directly in Profile.
- **Bills:** discover recurring payments from CSV/PDF imports and existing local history in Settings → Recurring Bills. Review the evidence and confirm once to match future imported payments. Weekly, fortnightly, monthly, quarterly, and annual schedules are supported. Marking paid manually records one expense dated today and advances by the selected schedule; import matching advances the reminder using the imported expense. This does not send money.
- **Notifications:** calculated in-app review, budget, and bill reminders.

The first launch uses clearly labelled sample data. Use **Settings → Start fresh with my own data**, then add an account before recording transactions. Sample dates follow the current month so the examples remain usable.

## Appearance and reset

Open **Settings → Appearance** to choose **System** (the default), **Light**, or **Dark**. The choice persists locally and applies to the app, sheets, and lock screen. System tracks device appearance changes.

**Settings → Clear all data** requires confirmation and atomically replaces the ledger with an empty non-demo ledger. It removes accounts, transactions, categories and budget limits, goals, bills, and profile details. Export a backup first if needed. Appearance, app lock, and previously exported files are retained. This differs from the demo-only **Start fresh with my own data**, which keeps budget categories. Clearing is disabled during data recovery; restore a valid backup first.

## Categories and Apple Intelligence

Find **Top Categories** near the top of **Settings → Spending Analytics**, or use **Home → Top spending categories**. It ranks only recorded spending for the selected month and reporting currency. Zero-use categories, income, and linked transfers are excluded; an empty month shows an explanation. Tap a category to edit its name, icon, or budget.

Imports automatically reuse equivalent category labels, including Gas & Fuel / Car Maintenance → Transport and Health & Pharmacy → Health. Stable import identities preserve your preferred names on later imports. Reviewed merchant history takes priority when enough examples agree. Clear statement labels come next; unresolved descriptions can use Apple's **on-device Foundation Models** on iOS 26+ when Apple Intelligence and the current language are supported and the model is ready. Harbor passes only the description, source label, and direction to that model, with a bounded list of existing/standard categories. No amounts, balances, account names, cloud sessions, API keys, or network fallback are used. Suggestions cannot change transaction amounts, dates, directions, or transfer links. Uncertain or failed model requests retain the source label. Clear statement categories, reviewed merchant matches, explicit category corrections, and accepted on-device suggestions save without review flags. Unknown categories and transfer ambiguities stay flagged. Editing a category in the preview overrides automation.

Tap a category card in **Budget → Current spending** to see its transactions for the selected month, with dates, accounts, amounts, and review status. **Edit budget** remains available inside this view; tap a transaction to edit or recategorise it. Spending and income are shown separately, and linked transfers are excluded.

Categories follow actual use in each selected month. Home and Budget show only categories with non-transfer spending that month; Activity filters and Manage categories show categories used by that month's transactions. An empty month has no category cards. Categories from earlier months, saved names/icons, and budget limits remain stored and reusable; **Show all saved categories** in Manage categories provides explicit access. Existing saved budget limits still contribute to the total allocation even when their category is hidden for the month. Automatic categorisation in Manage categories applies only to the selected month and reporting currency. Renaming a saved category still updates that shared identity; correcting a transaction changes its assignment and therefore its month's category list.

Category choices offered to the model are suggestions, not pre-created records. Imports create only categories required by selected, saved rows. The transaction editor accepts a **New category name (optional)** override, reuses an existing equivalent category when possible, and saves a new category atomically with its transaction. A cancelled/failed save adds nothing. Manual names take priority over model suggestions. Users can still explicitly create an unused saved category or plan a budget; it stays out of monthly spending cards until used.

**Settings → Manage categories** supports renaming, merging, **Review category cleanup**, and **Auto-categorise unreviewed transactions**. Existing-ledger operations show a concrete preview before applying. Cleanup merges equivalent labels and removes unused categories with zero budgets; unused budgeted categories are retained. Merges preserve balances and add budget limits, and future imports reuse merged identities. Custom names survive cleanup. Automatic suggestions protect reviewed transactions and explicit manual category corrections. Applying a clear suggestion also clears its review flag; the preview lists these changes. On unlock, Harbor clears old blanket import flags when deterministic category evidence is clear, while retaining ambiguous and explicitly manually flagged records. Automatically cleared rows are excluded from human-reviewed merchant training. Back up first if you may want to undo a merge. The transaction editor also has **Suggest category**; a new suggested category is saved only with the transaction, and you can change the picker or cancel.

A model suggestion is not a calibrated confidence score or guaranteed classification. Availability and fallback status appear in Settings and the import preview. The current implementation bounds model work to 20 unique unresolved merchant/category combinations per operation/account and skips model requests when the category choice list exceeds 40; remaining rows stay reviewable. Financial validation remains deterministic.

## Transaction imports

Open **Settings → Import CSV or PDF**, choose a file from Files, and review it before saving. Choose an existing account to append records or create an account with an editable opening balance. A statement with at least three transactions that all match exactly one saved account selects that account automatically. If multiple accounts match, choose the correct one. Creating a new account with any matching transactions requires explicitly enabling **Create a separate account despite matching transactions**; otherwise saving is blocked. This prevents a repeat statement from silently counting another opening balance and ledger in net worth. Closing balances remain reconciliation information, not separate deposits. For statements with running balances, the opening balance is inferred from the complete statement; adjust it if you deselect rows. Existing account opening balances are never overwritten. You can edit each candidate's date, description, direction, amount, category, and note, or exclude it. No records change until **Import → Save import** succeeds. Imports use the same validated, atomic, encrypted save path as manual changes.

Equivalent source categories are reused automatically, and Apple on-device suggestions may simplify unfamiliar labels in the preview. Manual overrides take priority. Known combined labels include: Housing & Utilities → Utilities (entries named Rent → Rent), Dining & Cafes → Dining, Personal & Wellness → Health, Entertainment & Subscriptions → Entertainment, and Uncategorized → Other. Your renamed category identities are reused; new categories use **automatic budgets** when prior-month history is available. Categories with no usable history or an explicitly disabled limit are excluded from near-limit/over-budget alerts. Only uncertain transactions and transfer ambiguities are marked for review. If Harbor is showing sample records, the preview offers an off-by-default option to remove all current accounts, transactions, goals, and bills (including manual additions made in demo mode) before saving; existing budget categories remain.

CSV accepts UTF-8 (including BOM), quoted commas/quotes, multiline fields, CRLF, and LF. Required columns are `Date` (`YYYY-MM-DD`) and `Description` (or `Merchant`/`Payee`), plus either `Debit` and `Credit`, `Money Out` and `Money In`, or signed `Amount` (each accepts a supported currency-code suffix, such as `(USD)` or `(GBP)`) (negative expenses, positive income). Optional columns include `Category`, `Memo`/`Note`, `Payment Method`, `Balance`/`Running Balance` (with an optional currency-code suffix), and `Currency` (one supported ISO code per statement). Rows must be oldest to newest. Malformed rows, ambiguous amounts, fractional cents, or inconsistent balances reject the entire file. Limits: 25 MB, 10,000 transactions, 100 CSV columns, 10,000 UTF-8 bytes per field.

PDF support includes two validated table families. Separate-column statements support `Date Description Category Method Money In Money Out Balance`, dates such as `01 Jan` with month/year headings, wrapped descriptions, continuation pages, and summary pages with declared counts/opening/closing balances. Published monthly counts/totals and the full running-balance chain are reconciled. The original monthly layout remains supported: an explicit currency marker or confirmation in the import preview, month/year headings, opening balances, Date / Description / Category / Money Out / Money In / Balance columns, and cumulative `entries shown` footers. PDFKit reads table positions rather than trusting text order; running balances, monthly page counts, and summary totals are reconciled. Scanned pages use Apple's on-device Vision OCR and the same checks. Unreadable financial cells, missing pages, locked PDFs, and other layouts are rejected with a request for CSV; this is not a universal bank-statement parser. On iOS 26+, unfamiliar layouts can fall back to on-device Vision `RecognizeDocumentsRequest`. It finds table cells, recognizes common date/payee/debit/credit/amount/balance headings, and routes the result through the same deterministic validation. Written-month or ISO dates are accepted; ambiguous numeric dates are rejected. Every fallback page must contain a recognizable transaction table: unknown summary-only pages or missing financial controls may still require a supported layout/CSV. A failed financial reconciliation in a known layout is never overridden by OCR. Older iOS versions retain the validated PDFKit/Vision text paths. This remains broader format support rather than a universal PDF guarantee. PDF limit: 100 pages. Low-quality or watermarked scans may be rejected even when their original text PDF imports successfully.

Possible duplicates match occurrences of account, local calendar date, normalized description, amount, and direction. They start unchecked. Choose the **same account** when importing PDF after CSV, and check the preview: legitimate identical purchases can be selected manually. Selecting a different account intentionally allows separate records. The app reads source documents locally and saves only chosen transaction fields; it does not upload documents or execute document text.

The two supplied fictional files are kept under `HarborTests/Fixtures` as test-only resources; they are not bundled into the iOS application. They contain the same 407 transactions, CAD $27,871.84 income, $23,225.31 expenses, $2,846.55 opening, and $7,493.08 closing balance.

## Automatic category budgets

Unset and newly created categories automatically use the integer-cent average of spending in the previous three completed calendar months, using only months with recorded non-transfer activity in the category's currency. A category absent from an observed month contributes zero; a month with no recorded activity is skipped. With one or two observed months, that smaller sample is used and labeled. Income and linked transfers never become budget spending. Incomplete source history can understate the estimate. The selected month never contributes to its own limit, and future selections cannot use the unfinished current month.

Home, Budget, category details, Settings, analytics exports, and current-month alerts use the same monthly calculation. Estimates refresh on imports, edits, month changes, and app foregrounding. The calculations stay on device and do not rewrite saved transaction amounts or manual limits. Existing positive limits stay manual. Open **Edit budget → Automatic budget** to opt a category in or out; a manual zero explicitly disables its limit. Automatic/manual choices persist in encrypted storage and portable backups, while estimated amounts are derived from the restored history. At 100% used a piggy bank is full; over-budget spending keeps the bank full and displays the actual percentage.

## Local spending forecast

Open **Budget → Forecasted Spending** and select **October 2026** (or another current/future month). Tap the **ⓘ** button beside the forecast heading for a plain-language explanation. Switch to **Current spending** for recorded expenses and category budget editing. The **Month-end forecast** card updates whenever imported or manually edited ledger records change. The estimated cumulative trajectory appears below the forecast automatically. Expand **Forecast by category** for projected category totals or **Model details** for historical checks.

The model runs entirely on device using Swift arithmetic. No Apple Intelligence hardware, language model, API, network, or new permissions are required. It does not train a generative model or upload financial records. Forecasts are derived in memory and do not alter the ledger, budgets, balances, or backup format.

The engine uses up to six prior calendar months that contain records; it requires at least two. A visibly truncated first month (first recorded transaction after day 1) is excluded. Missing months are excluded rather than interpreted as zero spending. Imported months are assumed complete: Harbor cannot infer account or statement coverage from transaction dates alone. The current partial month is never used to train a future-month estimate.

Recent-weighted and equal-weight monthly profiles are compared using rolling historical checks when at least four months are available. Each check trains on earlier months only, starting with two training months. The better profile supplies per-category amounts on historical payment days, clamping day 31 to the target month's last day. The current forecast combines recorded spending through the latest recorded transaction day with estimated spending after that day; it does not multiply an early rent payment across every remaining day. When the selected month has no records, it produces a history-only estimate and explicitly flags the missing coverage. Future-dated records are excluded. Bill reminders are not added separately because historical payments already contribute to the profile; new bills and changed schedules may therefore be missed.

The planning band uses the largest of 20% of predicted remaining spending, average historical remaining-spend deviation, and full-month historical mean absolute error. It is **not a calibrated confidence interval**. Historical checks help choose the weights and are not an independent accuracy guarantee; they do not measure mid-month accuracy. The model does not estimate seasonality, inflation, new recurring bills, or unrecorded transactions.

With the supplied **fictional April–September 2026 dataset**, as of October 15 with no October records, the estimate is **CAD $3,921.96**, with a **$3,137.57–$4,706.35** planning range. Four historical model-selection checks give **$144.71** average absolute error, versus **$171.07** for the previous-month-total baseline. These are fixture results, not a personal spending claim or measured October outcome. The fixtures remain test-only resources and are not loaded automatically in the shipping app.

## October example transactions

`samples/October-2026-examples.csv` contains **16 fictional transactions dated October 1–14, 2026**: two payroll deposits, rent, Spotify/Netflix/iCloud subscriptions, restaurant meals, DoorDash/Uber Eats, groceries, transit, drinks with friends, and a movie. Every memo begins with `Fictional October example:`. Expenses total **$2,039.47**, and payroll totals **$4,373.44**. No real purchases, subscriptions, or payments are executed.

These examples were appended to the current simulator's **Imported chequing** ledger, preserving existing transactions and budgets. With the April–September history, they update the October estimate to **$3,134.45** with a **$2,915.45–$3,353.45** planning range, as of October 15. Payroll affects account balance and income, not the expense forecast.

For another device, import the CSV through **Settings → Import CSV or PDF** into the existing statement account. Possible duplicates are unchecked by default. The sample file is not bundled into the shipping app or added on ordinary launches.

For local development only, Debug builds accept `-append-october-examples -example-account 'Imported chequing'` after `scripts/stage_import_fixtures.py` stages the file in simulator Documents. This explicit action requires normal unlock/load, validates the labelled October sample set, skips duplicates, and saves through the same encrypted path. It does not reset the ledger or change app lock. A local `Harbor-October-examples-result.json` receipt records append/duplicate counts and forecast totals; Release builds exclude the action.

## Financial and storage behavior

Amounts are integer minor units with two decimal places. Supported currencies are CAD, USD, GBP, EUR, AUD, NZD, CHF, SGD, and HKD. Explicit ISO codes in CSV headings/currency columns and PDFs are detected automatically; £/€ identify GBP/EUR. A bare dollar sign requires currency confirmation. Mixed currencies within one statement, unsupported currencies, or importing into an account of another currency are rejected. Existing accounts keep their units; changing their name does not convert money. Accounts have opening balances plus recorded credits minus debits. Negative opening balances can represent liabilities. Bank linking, exchange rates/conversion, investment market prices, automatic round-ups, background goal funding, push notifications, and cloud sync are outside this implementation.

Home shows balances separately by currency. Select **Report totals in** on Home, Budget, Analytics, or More to view a single currency. Budgets, forecasts, charts, goals totals, and shared reports stay in that currency; category limits are currency-specific. Activity can list multiple currencies, but its totals remain separated. Version-1 CAD backups remain readable; currency and transfer records use version 2. Saving import history or statement comparisons uses version 3 so older builds reject those ledgers instead of silently dropping the new records. The current app reads versions 1, 2, and 3.

Goals earmark existing account funds without changing net worth. Combined allocations cannot exceed the funding account balance. A transaction/account edit that would consume reserved savings is rejected until the allocation is reduced. Deleting a goal releases its earmark and does not move money.

Records are validated, encrypted with CryptoKit AES-256-GCM and a fresh nonce per save, and written atomically with iOS complete file protection. The 256-bit key is stored in Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and iCloud synchronization disabled. Keys are never stored in the ledger or UserDefaults. Existing native JSON ledgers migrate automatically: Harbor commits encrypted records before deleting its legacy plaintext file. Browser data from the earlier web app is not migrated or modified.

Enable **Settings → Security → Face ID / device passcode lock** to require system authentication at launch and after backgrounding. Face ID, Touch ID, and device-passcode fallback use LocalAuthentication. Enabling and disabling the lock both require authentication; a configured device passcode is required. Cancelled or failed authentication leaves Harbor locked. Records load only after unlocking, and published records are cleared on backgrounding when app lock is enabled. Inactive windows are covered for app-switcher privacy, including open editors. The app-lock setting is stored in device-only Keychain. App lock is an application access gate; the encryption key's Keychain accessibility is tied to the device being unlocked, rather than a biometric access-control requirement.

Unreadable ciphertext, invalid records, and missing encryption keys enter recovery mode without overwriting existing files with demo data. A confirmed, valid JSON restore can replace records and provision a missing key. Harbor's encrypted ledger is excluded from device backups because its device-only key cannot migrate to a different device.

**Settings → Backups and recovery** defaults to an AES-256-GCM encrypted `.harborbackup` file. Generate a recovery key, save it separately, and re-enter it before export. Each export has its own random 256-bit key, independent of the device key. Harbor cannot recover a lost recovery key. Backups include the saved ledger, not pending Apple Pay captures, device keys, or app-lock settings. The export screen counts excluded pending files. Restore validates and previews the backup before confirmed replacement; invalid keys or damaged files leave records unchanged. Existing pending captures are quarantined for individual review in Apple Pay settings. Legacy JSON restores remain supported. **Export unencrypted JSON** is a separate explicit action: anyone with that file can read it. Face ID does not protect exported files, shared reports, or screenshots. There is no bank connection or cloud sync.

Apple framework references: [LocalAuthentication](https://developer.apple.com/documentation/localauthentication/logging-a-user-into-your-app-with-face-id-or-touch-id), [device-only Keychain accessibility](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly).

Explicit outgoing **TRANSFER TO SAVINGS** entries are shown in the import preview with **Track transfers in savings** enabled. Before saving, choose an existing account in the same currency, or let Harbor create/reuse a linked Savings account for the source and transfer reference. It records a balanced withdrawal/credit pair and excludes both from spending, income, forecasts, and recurring-bill discovery. A unique matching destination transfer credit is linked instead of duplicated. Later savings statements can match generated credits by date, direction, amount, and explicit transfer evidence. Ambiguous matches remain for review.

A newly created savings account starts at zero and reflects only observed imported transfers; it is not a claim about the complete bank balance. Use an opening balance or the destination statement to reconcile the rest. For history imported before this update, open **Settings → Attach existing savings transfers**, review the withdrawals, and confirm. Source transaction IDs and source balances are preserved. Editing a linked transfer's amount/date updates both sides; deleting removes both. Currency/account/direction changes cannot turn one side into an unbalanced movement. Repeating an already linked selection is rejected.

With the supplied expanded fixture, chequing stays **CAD $4,760.47**, linked savings receives **$2,850.00**, and living expenses are **$49,443.69**. The original cash-debit total remains **$52,293.69**; the difference is movement between accounts, not consumption. Other ambiguous transfers and currency conversions are not inferred automatically.

## Recurring bills and simple categories

Harbor automatically checks CSV/PDF imports, captured purchases, and existing unlocked history. Explicit iCloud, Apple Music, Netflix, Spotify, and other supported service descriptions use **Subscription**, preserving manual corrections and reviewed category preferences. Apple Intelligence can suggest Subscription for unfamiliar descriptions when available; generic Apple store/payment descriptions do not establish a subscription. Dates and amounts are always checked deterministically. Three to six clear, regularly spaced payments with amounts within 20% of the minimum in Rent, Utilities, Insurance, or Subscription create an automatic bill. No spending is added. Other recurring candidates prompt for review in **Settings → Recurring Bills**. A recognised subscription with insufficient schedule history is added immediately with a visibly estimated monthly schedule and a focused **Review schedule** prompt; it does not match future payments until the cadence is confirmed or established by history. A later unexpected payment date or amount on a detected bill prompts another check instead of silently changing the reminder. Review prompts also appear in the Notifications inbox. Edited bills remain authoritative; deleting a bill suppresses rediscovery for that merchant/account.

Confirmed bills match newly imported expenses by account, description, expected date (within two days for weekly/fortnightly or five days for longer schedules), and amount (within 20% of the observed range). Matching links the existing imported expense, updates the bill amount, and advances one occurrence; it never creates another expense. Ambiguous matches, substantially different amounts, and missing cycles stay for manual review. Month-end dates retain their billing day across short months. Variable amounts are supported when historical amounts remain within 50% of the median. Merchant descriptions that change meaningfully may require a manually created bill. Detection is local and deterministic; no bank connection or cloud AI is used.

Older bills and backups remain monthly and manual. Enable **Match payments from imports** in a bill editor to opt in, using its name as the matching description. The same editor lets you change recurrence or disable matching. CSV/PDF duplicate review still applies before saving.

New sample data uses flat categories: Rent, Utilities, Groceries, Dining, Transport, Entertainment, Health, Shopping, and Other. To clean an existing ledger, choose **Settings → Simplify combined categories** and confirm. Known combined labels merge into their simple equivalents; merged limits add together so the total budget stays unchanged. Explicit entries/bills named Rent move out of Utilities. A newly created Rent category starts in automatic mode; its monthly estimate follows the reassigned recorded history. Existing positive manual limits remain fixed. Custom labels and ambiguous housing descriptions remain available for manual review. Cleanup preserves account balances and transaction IDs and is safe to repeat.

## Verification

Model and encryption checks:

```sh
swift test
```

Native simulator build:

```sh
xcodebuild -project Harbor.xcodeproj -scheme Harbor \
  -sdk iphonesimulator -configuration Debug \
  -derivedDataPath /tmp/harbor-derived CODE_SIGNING_ALLOWED=NO build
```

Before native UI checks, stage the fictional import documents in the booted simulator's Files folder (after building):

```sh
python3 scripts/stage_import_fixtures.py --device booted \
  --app /tmp/harbor-derived/Build/Products/Debug-iphonesimulator/Harbor.app
```

Native UI checks (select that installed simulator):

```sh
xcodebuild -project Harbor.xcodeproj -scheme Harbor \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath /tmp/harbor-derived CODE_SIGN_IDENTITY=- test
```

Simulator runs require local ad-hoc signing (`CODE_SIGN_IDENTITY=-`) for Keychain entitlements; unsigned builds compile but cannot open the app vault. UI tests use a separate debug-only ledger and Keychain namespace, never the normal app ledger. Screenshots are attached to the Xcode test results. See `VALIDATION.md` for the checks actually run and their limits.

## Apple Pay Shortcuts

Optional **Apple Pay purchase alerts** can be enabled from the Notifications bell or Settings → Apple Pay Shortcuts. Permission is requested only when the switch is enabled. Local alerts confirm **Purchase captured** after the encrypted inbox save and **Transaction added** after a new ledger entry is saved on unlock. Already-processed captures do not generate another added alert. Notification failures do not undo a purchase or cause the Shortcut to fail. Alerts omit amounts, merchants, and account details; iOS Focus and notification settings control presentation. The switch is off by default, and alerts use no server or push service.

## Reminders and daily check-ins

Open the **Notifications bell → Reminders & alerts** to enable failures, bills, review items, or daily check-ins independently. Each category starts off and requests system permission only when explicitly enabled. The shared reminder time defaults to 7 p.m. in the device's local timezone. Immediate failures/capture confirmations and milestone celebrations do not wait for that time.

Bills use confirmed schedules saved in Harbor: one digest per date the day before and on the due date, with one overdue digest refreshed on the next visit. Uncertain detected schedules must be reviewed first. Daily review/check-in reminders cover the next seven days and combine into one message when both are enabled. Bill reminders cover the next 30 days; the earliest 48 requests reserve space for immediate alerts. Opening or updating the unlocked ledger replaces outdated schedules, including paid, deleted, or rescheduled bills and cleared review work. Reminders do not confirm bank payments, detect missed Wallet triggers, or run bank monitoring. Without reopening Harbor, scheduled messages can become stale and eventually stop. Budgets remain in-app alerts.

Ledger load/save errors, failed capture actions, pending capture imports, and statement parser failures retain their detailed in-app errors and can send a generic local alert. Failure alerts are grouped to at most one per 15 minutes, with a generic timestamped notice in Notifications that can be cleared. Notification delivery failures never roll back records or trigger another failure notification. No financial details are placed in notification payloads.

**Home → Your daily check-in** and the Notifications screen share one daily review action. After reviewing activity, unresolved items, and upcoming bills, tap **Complete daily check-in**. One check-in per local calendar day increases the streak. Repeated taps and moving the clock backwards earn nothing. Missing a day starts a new streak while preserving the best streak and lifetime check-ins. Milestones are 3, 7, 14, 30, 60, 100, and 365 days; newly earned milestones can notify when daily check-in alerts are enabled. Opening Harbor or making a purchase does not earn progress. Demo records cannot earn personal progress. History is saved inside the encrypted ledger and portable backups; old ledgers load with no invented check-ins. Notification preferences stay on this device.

Harbor remembers the account chosen in this Settings screen on this device, including after restarting the app. Choose another account or “Choose an account” to change or clear it. Removing that account or clearing all Harbor data clears the selection. Each Wallet automation still uses the account configured in Apple Shortcuts.

Open Settings → Apple Pay Shortcuts and enable the encrypted capture inbox. Choose the Harbor account associated with your Wallet card. Enabling the inbox publishes account names and currencies to the app’s on-device Shortcut account picker; it exposes no balances. In Apple Shortcuts, create a Transaction / Wallet personal automation for that card, select Run Immediately, and add **Capture Apple Pay purchase** from Harbor. Map Amount and Merchant from Shortcut Input, choose the named Harbor account (its currency is used automatically). Existing shortcuts using Account ID and Currency continue to work. Leave Purchase date empty to use the capture time. Create a separate automation for each card.

The action requires an unlocked iPhone and writes only to a separate encrypted local inbox. Purchases join the ledger after Harbor unlocks; uncertain categories need review. Settings displays pending failures and permits correcting their destination account. Currency mismatches remain pending; no exchange conversion occurs. Locked-device failures are visible in Shortcuts and require another attempt. App installation does not create the automation, and this does not capture physical-card purchases or bank history. Test your card with a real purchase before relying on capture. Statement matching covers exact merchant/date/amount matches; changed posted details require review.

### Capture reconciliation and reset

Setup distinguishes an enabled encrypted inbox from a verified received capture. Use a small labelled test capture and delete that test ledger entry afterward. Named account choices can be refreshed from Apple Pay settings after account changes. Wallet automation creation remains a user action in Shortcuts; online Apple Pay checkout and complete capture coverage are not promised. Captures import after unlock or active app return, with separate imported/already-processed/failure counts.

CSV/PDF preview offers one-to-one Apple Pay reconciliation within the same account and currency. Unique exact matches default to confirmation; nearby dates, changed merchants, and final amount changes require explicit matching using the link control (within three days). Confirmation preserves transaction identity, original capture details, notes, and manual categories; it updates posted merchant/date/amount without adding another expense. Duplicate statement imports match the posted entry. Identical purchases are never collapsed automatically.

Clear all data disables capture before deleting active and held inbox files, removes capture credentials and account options, and reports partial failures. It retains the main app-lock preference and appearance. Restore holds pre-existing pending files outside the automatic drain; release captures individually only after reviewing their destination against the restored ledger.

If a held purchase's account is missing after restore, use **Change destination account** to choose an account in the purchase currency. Harbor saves the correction in the encrypted held file. The purchase stays held, including after restarting, until you choose **Release this capture for import**. Changing destinations never converts currency.


## Import history and monthly reconciliation

**Settings → Import history** lists completed CSV/PDF imports saved in this version. Each encrypted receipt includes the filename (without its source path), import time, account/currency at import, transaction date range, available statement balances, and counts of rows added, matched to existing Apple Pay purchases, skipped as duplicates, or left unchecked. Linked savings transfers can create two ledger entries from one source row. Receipts link to entries still present in the ledger and remain intact after later edits/deletions. Earlier imports are not reconstructed or labelled retroactively.

A duplicate-only preview on an existing account offers **Record skipped import**. Confirming saves a receipt without adding transactions or changing balances. Cancelling an import or failing validation saves neither rows nor a receipt. Source documents are not copied into the ledger.

**Settings → Monthly reconciliation** compares an account's recorded balance through a selected statement closing day with the balance you enter from the statement. Opening balance plus all account movements through that day supplies Harbor's balance; later transactions and other accounts/currencies are excluded. Linked transfers count as account movements. Use Harbor's sign convention (debt is negative). The difference is Harbor minus statement. A matching total does not prove every transaction has matched: unconfirmed Apple Pay purchases remain visible for review.

From an import receipt, **Compare account balance** prefills the available closing balance and last transaction date. Confirm the actual closing date on your statement; it may differ from the last purchase date. Missing history, an incorrect opening balance, pending items, or a different closing date can explain a discrepancy. Harbor never inserts a balancing transaction or adjusts your opening balance automatically.

**Save comparison** records the statement balance and closing day. Reopening recalculates against the current ledger, so later corrections can reveal a new difference. Saving again for the same account/day replaces that comparison instead of creating duplicates. Import history and saved comparisons stay in the encrypted ledger and portable backups; the first save of either requires schema version 3. Back up before installing this build, and use an updated Harbor build to open a version-3 ledger or backup.
