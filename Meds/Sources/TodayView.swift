import StoreKit
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

enum TimeOfDayGreeting {
    /// Four bands, not three. Evening used to be the fallback, so every hour before
    /// five in the morning was greeted as evening. Three in the morning is a real
    /// hour to be awake and giving a dose in a house like the one this was built
    /// for, and it should be met with the right words.
    static func text(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let hour = calendar.component(.hour, from: date)
        return switch hour {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        case 18..<22: "Good evening"
        default: "Good night"
        }
    }
}

struct TodayView: View {
    @Query(sort: \Medication.createdAt) private var medications: [Medication]
    @Query private var schedules: [DoseSchedule]
    @Query private var doseEvents: [DoseEvent]
    @Query private var inventoryEvents: [InventoryEvent]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @State private var savingDoseIDs: Set<String> = []
    @State private var showingSaveError = false
    @State private var showingAlreadyLogged = false
    @State private var alreadyLoggedMessage = ""
    @State private var showingLogAllConfirmation = false
    /// Set aside for the rest of the day rather than forever: someone who tracks
    /// supply without logging every dose should not be nagged permanently, and
    /// someone who simply has not caught up yet should be asked again tomorrow.
    @AppStorage("missedDosesSetAsideOn") private var missedDosesSetAsideOn = ""
    /// Finished courses whose card was set aside, one per course.
    @AppStorage(FinishedCourseNotice.setAsideKey) private var finishedCoursesSetAside = ""
    @State private var showingArchiveError = false
    @AppStorage(QuickCountPrompt.setAsideKey) private var quickCountSetAside = Data()
    @AppStorage(QuickCountPrompt.tapKey) private var quickCountTapped = Data()
    /// The card asks the reminder's question, so it follows the reminder's
    /// switch in Settings.
    @AppStorage(NotificationPlanOptions.weeklyCountCheckKey) private var weeklyCountCheck = true
    @State private var countRequest: CountCorrection.Request?
    @State private var showingCountSaveError = false
    let onAdd: () -> Void

    private static let missedDoseLookbackDays = 2
    private static let missedDoseRowLimit = 3

    private var activeMedications: [Medication] {
        medications.filter { !$0.isArchived }
    }

    private func todaysDoses(now: Date) -> [(Medication, ScheduledDose)] {
        activeMedications.flatMap { medication in
            ScheduleEngine.doses(
                schedules: schedules,
                medicationID: medication.id,
                onDayOf: now
            ).map { (medication, $0) }
        }
        .sorted { $0.1.date < $1.1.date }
    }

    /// Scheduled doses from the two days before today that were never logged. Today
    /// used to end at midnight, so an evening dose nobody confirmed simply vanished
    /// and there was no screen left that could answer "did last night happen?". The
    /// supply ledger has the same gap: an unlogged dose reads as an unspent one, so
    /// the forecast quietly runs long until someone corrects the count by hand.
    private func missedDoses(now: Date) -> [(Medication, ScheduledDose)] {
        let calendar = Calendar.autoupdatingCurrent
        let startOfToday = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -Self.missedDoseLookbackDays, to: startOfToday) else {
            return []
        }
        return activeMedications.flatMap { medication in
            ScheduleEngine.doses(
                schedules: schedules,
                medicationID: medication.id,
                from: start,
                through: startOfToday.addingTimeInterval(-1),
                calendar: calendar
            )
            .filter { ScheduleEngine.loggedStatus(for: $0, in: doseEvents) == nil }
            .map { (medication, $0) }
        }
        .sorted { $0.1.date > $1.1.date }
    }

    private func completedCount(in doses: [(Medication, ScheduledDose)]) -> Int {
        doses.filter { status(for: $0.1) != nil }.count
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let doses = todaysDoses(now: now)
        return ZStack {
            CanvasBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    header(now: now)
                    notificationBanner
                    plannedThroughNotice(now: now)
                    pickupsCard(now: now)
                    // Catching up before counting: a dose logged after a
                    // count comes off the number the count set. The two
                    // stay together, since the count's card points at the
                    // missed doses above it; archiving can wait below them.
                    missedDosesCard(now: now)
                    quickCountCard(now: now)
                    finishedCourseCards(now: now)
                    if activeMedications.isEmpty {
                        EmptyStateCard(
                            symbol: "viewfinder",
                            title: "Start with a label",
                            message: "Scan a medication or enter it manually. You will review every detail before it is saved.",
                            actionTitle: "Add Medication",
                            action: onAdd
                        )
                    } else if doses.isEmpty {
                        EmptyStateCard(
                            symbol: "checkmark.circle.fill",
                            title: "Nothing scheduled today",
                            message: "Your as-needed medications and full supply forecast are still available in Medications and Supply."
                        )
                    } else {
                        progressCard(doses: doses)
                        logAllDueButton(doses: doses, now: now)
                        ForEach(doseGroups(in: doses), id: \.person) { person, groupedDoses in
                            if !person.isEmpty || doseGroups(in: doses).count > 1 {
                                Text(person.isEmpty ? "Not assigned to anyone" : "For \(person)")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            ForEach(groupedDoses, id: \.1.id) { medication, dose in
                                DoseCard(
                                    medication: medication,
                                    dose: dose,
                                    now: now,
                                    status: status(for: dose),
                                    onTaken: { record(dose, for: medication, status: .taken) },
                                    onSkipped: { record(dose, for: medication, status: .skipped) }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 104)
            }
        }
        .navigationTitle("Today")
        .alert("Couldn't Log Dose", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This dose wasn't logged. Try again.")
        }
        .alert("Already Logged", isPresented: $showingAlreadyLogged) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alreadyLoggedMessage)
        }
        .alert("Couldn't Archive", isPresented: $showingArchiveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nothing was changed. Try again.")
        }
        .sheet(item: $countRequest) { request in
            CorrectCountSheet(request: request) { showingCountSaveError = true }
        }
        .alert("Couldn't Save Count", isPresented: $showingCountSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your count wasn't saved. Try again.")
        }
    }

    /// The weekly count check's question, here for as long as it stands: a
    /// count moves the last count's date and the card goes with it.
    @ViewBuilder
    private func quickCountCard(now: Date) -> some View {
        if weeklyCountCheck, let prompt = QuickCountPrompt.make(
            medications: medications,
            schedules: schedules,
            inventoryEvents: inventoryEvents,
            doseEvents: doseEvents,
            setAside: QuickCountPrompt.decodeSetAside(quickCountSetAside),
            tapped: QuickCountPrompt.decodeTap(quickCountTapped),
            now: now
        ) {
            // The doses the missed-doses card lists, as it lists them.
            let missed = missedDosesSetAsideOn == dayKey(now) ? [] : missedDoses(now: now)
            QuickCountCard(
                prompt: prompt,
                catchUpNote: QuickCountPrompt.catchUpNote(for: prompt.medicationID, missedDoseMedicationIDs: missed.map(\.0.id)),
                onCount: {
                    guard let medication = medications.first(where: { $0.id == prompt.medicationID }) else { return }
                    countRequest = CountCorrection.Request(medication: medication, forecast: prompt.forecast)
                },
                onNotNow: {
                    quickCountSetAside = QuickCountPrompt.encodeSetAside(
                        QuickCountPrompt.settingAside(prompt.medicationID, at: .now, in: QuickCountPrompt.decodeSetAside(quickCountSetAside))
                    )
                }
            )
        }
    }

    /// The day's doses under the person each is for, when the household names
    /// more than one; one group and no headers otherwise. Order within a group
    /// stays by time.
    private func doseGroups(in doses: [(Medication, ScheduledDose)]) -> [(person: String, doses: [(Medication, ScheduledDose)])] {
        let names = Set(doses.map { $0.0.personName.trimmingCharacters(in: .whitespaces) })
        guard names.count > 1 else { return [("", doses)] }
        let ordered = names.sorted { lhs, rhs in
            if lhs.isEmpty { return false }
            if rhs.isEmpty { return true }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        return ordered.map { person in
            (person, doses.filter { $0.0.personName.trimmingCharacters(in: .whitespaces) == person })
        }
    }

    /// Refills under way: what to pick up, and what is still expected. The
    /// pharmacy trip is the other thing this app exists to remember.
    @ViewBuilder
    private func pickupsCard(now: Date) -> some View {
        let inProgress = activeMedications
            .filter { $0.refillStatus != .none }
            .sorted { ($0.refillStatusDate ?? .distantFuture) < ($1.refillStatusDate ?? .distantFuture) }
            .map { medication in
                let forecast = ForecastEngine.forecast(
                    medication: medication,
                    schedules: schedules,
                    inventoryEvents: inventoryEvents,
                    doseEvents: doseEvents,
                    now: now
                )
                return (medication, forecast, SupplyAttention(medication: medication, forecast: forecast, now: now).needsAttention)
            }
        // A refill that has run late, or supply that has run too low to wait
        // for it, is not "on its way" as far as anyone should be told.
        let needingAttention = inProgress.filter { $0.2 }
        if !inProgress.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Group {
                    if !needingAttention.isEmpty {
                        Label(
                            Self.refillAttentionTitle(
                                refillsToCheck: needingAttention.filter { !$0.1.needsCount }.count,
                                countsNeeded: needingAttention.filter { $0.1.needsCount }.count
                            ),
                            systemImage: "exclamationmark.circle.fill"
                        )
                        .foregroundStyle(.orange)
                    } else {
                        Label(inProgress.count == 1 ? "A refill is on its way" : "\(inProgress.count) refills are on their way", systemImage: "bag.fill")
                    }
                }
                .font(.headline)
                ForEach(inProgress, id: \.0.id) { medication, forecast, needsAttention in
                    // Side by side at the largest sizes, the name and the status
                    // column squeezed each other until words broke mid-word,
                    // the warning among them; stacked, as the missed-dose rows
                    // and Supply's rows are, each keeps the card's width.
                    let stacked = dynamicTypeSize.isAccessibilitySize
                    let rowLayout = stacked
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
                    rowLayout {
                        Text(medication.displayName)
                            .font(.subheadline.weight(.semibold))
                        if !stacked { Spacer(minLength: 8) }
                        VStack(alignment: stacked ? .leading : .trailing, spacing: 2) {
                            if needsAttention {
                                Text(SupplyAttention.line(for: forecast))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                            Text(RefillStatusText.line(for: medication, now: now) ?? "")
                                .font(.subheadline)
                                .foregroundStyle(medication.refillStatus == .ready && !needsAttention ? AppTheme.accent : .secondary)
                        }
                        .multilineTextAlignment(stacked ? .leading : .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("Add the refill on the medication's page when it is in hand.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .cardSurface()
        }
    }

    @ViewBuilder
    private var notificationBanner: some View {
        let state = NotificationHealth.shared.state
        if state != .fine {
            NotificationHealthBanner(
                state: state,
                onAllow: {
                    Task {
                        _ = try? await UNUserNotificationCenter.current()
                            .requestAuthorization(options: [.alert, .sound, .badge])
                        await replanNotifications()
                    }
                },
                onOpenSettings: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                },
                onRetry: { Task { await replanNotifications() } }
            )
        }
    }

    /// Reminders for a course or a schedule starting soon are planned a day
    /// at a time, and only as far as the cap allows. When that runs out
    /// within a few days, the way to keep them coming is to open the app.
    @ViewBuilder
    private func plannedThroughNotice(now: Date) -> some View {
        if let day = NotificationHealth.shared.plannedThroughNotice(now: now) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("Reminders are planned through \(day.formatted(.dateTime.weekday(.wide).month(.wide).day())). Open Meds Ahead before then to keep them coming.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("planned-through-notice")
        }
    }

    private func replanNotifications() async {
        let plans = NotificationPlanBuilder.makeAll(
            medications: medications,
            schedules: schedules,
            inventoryEvents: inventoryEvents,
            doseEvents: doseEvents
        )
        await NotificationService.shared.replaceAllNotifications(for: plans)
    }

    private func dayKey(_ date: Date) -> String {
        let parts = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    /// A day label a person reads the way they'd say it out loud.
    private func missedDoseLabel(_ date: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInYesterday(date) { return "Yesterday, \(time)" }
        return "\(date.formatted(.dateTime.weekday(.wide))), \(time)"
    }

    @ViewBuilder
    private func missedDosesCard(now: Date) -> some View {
        let missed = missedDosesSetAsideOn == dayKey(now) ? [] : missedDoses(now: now)
        if !missed.isEmpty {
            let shown = Array(missed.prefix(Self.missedDoseRowLimit))
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        missed.count == 1 ? "One dose isn't logged" : "\(missed.count) doses aren't logged",
                        systemImage: "clock.badge.questionmark"
                    )
                    .font(.headline)
                    Text("From the last two days. Logging what happened keeps your supply count honest.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Catching up is secondary to the day in front of you, so each entry
                // stays one line tall and the day's own doses keep the screen.
                ForEach(shown, id: \.1.id) { medication, dose in
                    let rowLayout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 9))
                        : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
                    rowLayout {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(medication.displayName)
                                .font(.subheadline.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(missedDoseLabel(dose.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 8) {
                            Button("Skip") { record(dose, for: medication, status: .skipped) }
                                .buttonStyle(.bordered)
                                .frame(minHeight: 44)
                                .accessibilityLabel("Skip \(medication.displayName) from \(missedDoseLabel(dose.date))")
                            Button("Taken") { record(dose, for: medication, status: .taken) }
                                .buttonStyle(.borderedProminent)
                                .foregroundStyle(AppTheme.onAccent)
                                .frame(minHeight: 44)
                                .accessibilityLabel("Mark \(medication.displayName) from \(missedDoseLabel(dose.date)) taken")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if dose.id != shown.last?.1.id { Divider() }
                }

                if missed.count > shown.count {
                    Text(Self.moreMissedText(missed.count - shown.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Not Now") { missedDosesSetAsideOn = dayKey(now) }
                    .font(.subheadline)
                    .accessibilityHint("Hides these until tomorrow")
            }
            .padding(18)
            .cardSurface()
        }
    }

    /// A course that finished in the last few days, with the archive the
    /// detail screen's menu offers. Set aside, it stays on Today and Supply
    /// as it is.
    @ViewBuilder
    private func finishedCourseCards(now: Date) -> some View {
        let items = FinishedCourseNotice.items(
            medications: activeMedications,
            schedules: schedules,
            inventoryEvents: inventoryEvents,
            doseEvents: doseEvents,
            setAside: FinishedCourseNotice.setAside(in: finishedCoursesSetAside),
            now: now
        )
        ForEach(items) { item in
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(FinishedCourseNotice.title(for: item), systemImage: "checkmark.circle")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Archive it to take it off Today and Supply. Its history is kept, and you can restore it from Medications.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                let buttonLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 10))
                    : AnyLayout(HStackLayout(spacing: 10))
                buttonLayout {
                    Button {
                        finishedCoursesSetAside = FinishedCourseNotice.adding(
                            FinishedCourseNotice.key(medicationID: item.medicationID, end: item.end),
                            to: finishedCoursesSetAside
                        )
                    } label: {
                        Text("Not Now").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityHint("Keeps \(item.displayName) as it is")
                    .accessibilityIdentifier("finished-course-not-now")
                    Button {
                        archive(item)
                    } label: {
                        Text("Archive").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(AppTheme.onAccent)
                    .controlSize(.large)
                    .accessibilityLabel("Archive \(item.displayName)")
                    .accessibilityIdentifier("finished-course-archive")
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("finished-course-card")
        }
    }

    private func archive(_ item: FinishedCourseNotice.Item) {
        guard let medication = medications.first(where: { $0.id == item.medicationID }) else { return }
        do {
            try FinishedCourseNotice.archive(medication, in: modelContext)
            Task { await replanNotifications() }
        } catch {
            modelContext.rollback()
            showingArchiveError = true
        }
    }

    /// The line under the missed doses the card has no room to list.
    static func moreMissedText(_ count: Int) -> String {
        "\(count.counted("more is", plural: "more are")) waiting in each medication's history."
    }

    /// The refill card's heading when something on it needs someone, in the
    /// words of the reason. A count needed is not a refill gone wrong: the
    /// refill may be right on time while nobody knows what is left to wait
    /// with, and "A refill needs checking" points at the pharmacy when what
    /// is needed is a count at home.
    static func refillAttentionTitle(refillsToCheck: Int, countsNeeded: Int) -> String {
        var parts: [String] = []
        if refillsToCheck > 0 {
            parts.append(refillsToCheck == 1 ? "a refill needs checking" : "\(refillsToCheck) refills need checking")
        }
        if countsNeeded > 0 {
            parts.append(countsNeeded == 1 ? "a count is needed" : "\(countsNeeded) counts are needed")
        }
        let title = parts.joined(separator: " and ")
        return title.prefix(1).uppercased() + title.dropFirst()
    }

    private func header(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(TimeOfDayGreeting.text(for: now))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
        }
        .padding(.top, 6)
    }

    private func progressCard(doses: [(Medication, ScheduledDose)]) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 14) {
                    progressGauge(doses: doses)
                    progressCopy(doses: doses)
                }
            } else {
                HStack(spacing: 14) {
                    progressGauge(doses: doses)
                    progressCopy(doses: doses)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(18)
        .cardSurface()
        .animation(reduceMotion ? nil : .medsSpring, value: completedCount(in: doses))
    }

    private func progressGauge(doses: [(Medication, ScheduledDose)]) -> some View {
        let completed = completedCount(in: doses)
        return ZStack {
            Circle().stroke(AppTheme.accent.opacity(0.12), lineWidth: 7)
            Circle()
                .trim(from: 0, to: doses.isEmpty ? 0 : Double(completed) / Double(doses.count))
                .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(completed)/\(doses.count)")
                .font(.caption.weight(.bold))
                .minimumScaleFactor(0.55)
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .padding(4)
                .background(Color(red: 0.035, green: 0.22, blue: 0.29), in: Capsule())
                .accessibilityHidden(true)
        }
        .frame(width: 58, height: 58)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(completed) of \(doses.count) scheduled doses logged")
    }

    private func progressCopy(doses: [(Medication, ScheduledDose)]) -> some View {
        let completed = completedCount(in: doses)
        return VStack(alignment: .leading, spacing: 3) {
            Text(completed == doses.count ? "All logged" : "Today’s routine")
                .font(.headline)
            Text(completed == doses.count ? "You have accounted for every scheduled dose." : "\(doses.count - completed) scheduled \(doses.count - completed == 1 ? "dose" : "doses") remaining.")
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dueDoses(in doses: [(Medication, ScheduledDose)], now: Date) -> [(Medication, ScheduledDose)] {
        doses.filter {
            status(for: $0.1) == nil && ScheduleEngine.timingState(for: $0.1.date, now: now) != .upcoming
        }
    }

    /// With several medications due at once, per-card logging is a tap per bottle.
    /// One reviewed action logs the whole tray; each dose is still recorded
    /// individually and can be removed from its medication's history.
    @ViewBuilder
    private func logAllDueButton(doses: [(Medication, ScheduledDose)], now: Date) -> some View {
        let due = dueDoses(in: doses, now: now)
        if due.count >= 2 {
            Button {
                showingLogAllConfirmation = true
            } label: {
                Label("Mark all \(due.count) due doses taken", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(AppTheme.accent)
            .accessibilityIdentifier("log-all-due")
            .confirmationDialog(
                "Mark \(due.count) due doses as taken?",
                isPresented: $showingLogAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Mark All Taken") { recordAllDue() }
            } message: {
                Text("Each dose is logged at its scheduled time. You can remove any log from that medication's history.")
            }
        }
    }

    private func recordAllDue(now: Date = .now) {
        let pending = dueDoses(in: todaysDoses(now: now), now: now)
            .filter { !savingDoseIDs.contains($0.1.id) }
        guard !pending.isEmpty else { return }
        savingDoseIDs.formUnion(pending.map(\.1.id))
        defer { savingDoseIDs.subtract(pending.map(\.1.id)) }

        var newEvents: [DoseEvent] = []
        do {
            for (medication, dose) in pending {
                // A dose the widget logged may still look due in these arrays.
                guard try !DoseLogGuard.isLogged(dose, in: modelContext) else { continue }
                let event = DoseEvent(
                    medicationID: medication.id,
                    scheduleID: dose.scheduleID,
                    scheduledAt: dose.date,
                    doseQuantity: dose.quantity,
                    status: .taken
                )
                modelContext.insert(event)
                newEvents.append(event)
            }
            guard !newEvents.isEmpty else {
                alreadyLoggedMessage = "The widget or a reminder has already logged these doses. Nothing more was recorded."
                showingAlreadyLogged = true
                return
            }
            try modelContext.save()
            let newIDs = Set(newEvents.map(\.id))
            let plans = NotificationPlanBuilder.makeAll(
                medications: medications,
                schedules: schedules,
                inventoryEvents: inventoryEvents,
                doseEvents: doseEvents.filter { !newIDs.contains($0.id) } + newEvents
            )
            Task { await NotificationService.shared.replaceAllNotifications(for: plans) }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            considerReviewRequest(newlyLogged: newIDs)
        } catch {
            modelContext.rollback()
            showingSaveError = true
        }
    }

    private func status(for dose: ScheduledDose) -> DoseEventStatus? {
        ScheduleEngine.loggedStatus(for: dose, in: doseEvents)
    }

    private func record(_ dose: ScheduledDose, for medication: Medication, status: DoseEventStatus) {
        guard self.status(for: dose) == nil, !savingDoseIDs.contains(dose.id) else { return }
        savingDoseIDs.insert(dose.id)
        defer { savingDoseIDs.remove(dose.id) }
        do {
            // The widget may have logged this dose where these arrays cannot see it
            // yet. The card still offers it, so a tap that writes nothing says why.
            guard try !DoseLogGuard.isLogged(dose, in: modelContext) else {
                alreadyLoggedMessage = "The widget or a reminder has already logged this dose. Nothing more was recorded."
                showingAlreadyLogged = true
                return
            }
            let event = DoseEvent(
                medicationID: medication.id,
                scheduleID: dose.scheduleID,
                scheduledAt: dose.date,
                doseQuantity: dose.quantity,
                status: status
            )
            modelContext.insert(event)
            try modelContext.save()
            let plans = NotificationPlanBuilder.makeAll(
                medications: medications,
                schedules: schedules,
                inventoryEvents: inventoryEvents,
                doseEvents: doseEvents.filter { $0.id != event.id } + [event]
            )
            Task { await NotificationService.shared.replaceAllNotifications(for: plans) }
            UINotificationFeedbackGenerator().notificationOccurred(status == .taken ? .success : .warning)
            if status == .taken { considerReviewRequest(newlyLogged: [event.id]) }
        } catch {
            modelContext.rollback()
            showingSaveError = true
        }
    }

    /// A dose just logged is the moment the app has been useful. The policy
    /// decides whether it is also a fair moment to ask for a rating, and the ask
    /// waits for the card to settle so the system sheet never lands on the tap.
    private func considerReviewRequest(newlyLogged: Set<UUID>) {
        let takenDoses = doseEvents.filter { $0.status == .taken && !newlyLogged.contains($0.id) }.count + newlyLogged.count
        guard ReviewRequestCoordinator.shared.shouldRequestReview(takenDoses: takenDoses) else { return }
        ReviewRequestCoordinator.shared.recordRequest()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            requestReview()
        }
    }
}

private struct DoseCard: View {
    let medication: Medication
    let dose: ScheduledDose
    let now: Date
    let status: DoseEventStatus?
    let onTaken: () -> Void
    let onSkipped: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 15) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .top, spacing: 12) {
                        MedicationGlyph(medication: medication)
                        timeBlock(now: now)
                        Spacer(minLength: 0)
                    }
                    Text(medication.displayName)
                        .font(.headline)
                    Text(doseLine)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 13) {
                    MedicationGlyph(medication: medication)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(medication.displayName)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(doseLine)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 8)
                    timeBlock(now: now)
                }
            }

            if let status {
                HStack {
                    Label(status == .taken ? "Taken" : "Skipped", systemImage: status == .taken ? "checkmark.circle.fill" : "forward.end.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(status == .taken ? AppTheme.accent : .primary)
                    Spacer()
                    Text("Logged")
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
                .frame(minHeight: 42)
            } else {
                let buttonLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 10))
                    : AnyLayout(HStackLayout(spacing: 10))
                buttonLayout {
                    Button(action: onSkipped) {
                        Label("Skip", systemImage: "forward.end")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityLabel("Skip \(medication.displayName)")

                    Button(action: onTaken) {
                        Label("Taken", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(AppTheme.onAccent)
                    .controlSize(.large)
                    .accessibilityLabel("Mark \(medication.displayName) taken")
                }
            }
        }
        .padding(17)
        .cardSurface()
        .accessibilityElement(children: .contain)
    }

    private func timeBlock(now: Date) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(dose.date, style: .time)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            if status == nil {
                Label(timingTitle(now: now), systemImage: timingSymbol(now: now))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(timingColor(now: now))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func timingState(now: Date) -> DoseTimingState {
        ScheduleEngine.timingState(for: dose.date, now: now)
    }

    private func timingTitle(now: Date) -> String {
        switch timingState(now: now) {
        case .upcoming: "Upcoming"
        case .due: "Due"
        case .overdue: "Overdue"
        }
    }

    private func timingSymbol(now: Date) -> String {
        switch timingState(now: now) {
        case .upcoming: "clock"
        case .due: "clock.fill"
        case .overdue: "exclamationmark.circle.fill"
        }
    }

    private func timingColor(now: Date) -> Color {
        switch timingState(now: now) {
        case .upcoming: .secondary
        case .due: AppTheme.accent
        case .overdue: .orange
        }
    }

    private var doseLine: String {
        let quantity = medication.form.quantityText(dose.quantity)
        return medication.strength.isEmpty ? quantity : "\(quantity) · \(medication.strength)"
    }
}
