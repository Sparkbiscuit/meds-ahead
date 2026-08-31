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
    @State private var savingDoseIDs: Set<String> = []
    @State private var showingSaveError = false
    @State private var showingLogAllConfirmation = false
    /// Set aside for the rest of the day rather than forever: someone who tracks
    /// supply without logging every dose should not be nagged permanently, and
    /// someone who simply has not caught up yet should be asked again tomorrow.
    @AppStorage("missedDosesSetAsideOn") private var missedDosesSetAsideOn = ""
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
                    missedDosesCard(now: now)
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
                        ForEach(doses, id: \.1.id) { medication, dose in
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
                                .frame(minHeight: 44)
                                .accessibilityLabel("Mark \(medication.displayName) from \(missedDoseLabel(dose.date)) taken")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if dose.id != shown.last?.1.id { Divider() }
                }

                if missed.count > shown.count {
                    Text("\(missed.count - shown.count) more are waiting in each medication's history.")
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
        for (medication, dose) in pending {
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
        do {
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
        let event = DoseEvent(
            medicationID: medication.id,
            scheduleID: dose.scheduleID,
            scheduledAt: dose.date,
            doseQuantity: dose.quantity,
            status: status
        )
        modelContext.insert(event)
        do {
            try modelContext.save()
            let plans = NotificationPlanBuilder.makeAll(
                medications: medications,
                schedules: schedules,
                inventoryEvents: inventoryEvents,
                doseEvents: doseEvents.filter { $0.id != event.id } + [event]
            )
            Task { await NotificationService.shared.replaceAllNotifications(for: plans) }
            UINotificationFeedbackGenerator().notificationOccurred(status == .taken ? .success : .warning)
        } catch {
            modelContext.rollback()
            showingSaveError = true
        }
        savingDoseIDs.remove(dose.id)
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
        let quantity = "\(dose.quantity.medicationQuantityText) \(medication.form.unitName)\(dose.quantity == 1 ? "" : "s")"
        return medication.strength.isEmpty ? quantity : "\(quantity) · \(medication.strength)"
    }
}
