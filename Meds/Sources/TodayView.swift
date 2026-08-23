import SwiftData
import SwiftUI

struct TodayView: View {
    @Query(sort: \Medication.createdAt) private var medications: [Medication]
    @Query private var schedules: [DoseSchedule]
    @Query private var doseEvents: [DoseEvent]
    @Query private var inventoryEvents: [InventoryEvent]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var savingDoseIDs: Set<String> = []
    @State private var showingSaveError = false
    let onAdd: () -> Void

    private var activeMedications: [Medication] {
        medications.filter { !$0.isArchived }
    }

    private var todaysDoses: [(Medication, ScheduledDose)] {
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: .now)
        let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? .now
        return activeMedications.flatMap { medication in
            ScheduleEngine.doses(
                schedules: schedules,
                medicationID: medication.id,
                from: start,
                through: end,
                calendar: calendar
            ).map { (medication, $0) }
        }
        .sorted { $0.1.date < $1.1.date }
    }

    private var completedCount: Int {
        todaysDoses.filter { status(for: $0.1) != nil }.count
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    header
                    if activeMedications.isEmpty {
                        EmptyStateCard(
                            symbol: "viewfinder",
                            title: "Start with a label",
                            message: "Scan a medication or enter it manually. You will review every detail before it is saved.",
                            actionTitle: "Add Medication",
                            action: onAdd
                        )
                    } else if todaysDoses.isEmpty {
                        EmptyStateCard(
                            symbol: "checkmark.circle.fill",
                            title: "Nothing scheduled today",
                            message: "Your as-needed medications and full supply forecast are still available in Medications and Supply."
                        )
                    } else {
                        progressCard
                        ForEach(todaysDoses, id: \.1.id) { medication, dose in
                            DoseCard(
                                medication: medication,
                                dose: dose,
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(greeting)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
        }
        .padding(.top, 6)
    }

    private var greeting: String {
        let hour = Calendar.autoupdatingCurrent.component(.hour, from: .now)
        return switch hour {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    private var progressCard: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 14) {
                    progressGauge
                    progressCopy
                }
            } else {
                HStack(spacing: 14) {
                    progressGauge
                    progressCopy
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(18)
        .cardSurface()
        .animation(reduceMotion ? nil : .medsSpring, value: completedCount)
    }

    private var progressGauge: some View {
        ZStack {
            Circle().stroke(AppTheme.accent.opacity(0.12), lineWidth: 7)
            Circle()
                .trim(from: 0, to: todaysDoses.isEmpty ? 0 : Double(completedCount) / Double(todaysDoses.count))
                .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(completedCount)/\(todaysDoses.count)")
                .font(.caption.weight(.bold))
                .minimumScaleFactor(0.55)
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .padding(4)
                .background(Color(red: 0.035, green: 0.22, blue: 0.29), in: Capsule())
        }
        .frame(width: 58, height: 58)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(completedCount) of \(todaysDoses.count) scheduled doses logged")
    }

    private var progressCopy: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(completedCount == todaysDoses.count ? "All logged" : "Today’s routine")
                .font(.headline)
            Text(completedCount == todaysDoses.count ? "You have accounted for every scheduled dose." : "\(todaysDoses.count - completedCount) scheduled \(todaysDoses.count - completedCount == 1 ? "dose" : "doses") remaining.")
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func status(for dose: ScheduledDose) -> DoseEventStatus? {
        doseEvents.first {
            $0.scheduleID == dose.scheduleID &&
            $0.scheduledAt.map { abs($0.timeIntervalSince(dose.date)) < 60 } == true
        }?.status
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
            let plan = NotificationPlanBuilder.make(
                medication: medication,
                schedules: schedules,
                inventoryEvents: inventoryEvents,
                doseEvents: doseEvents.filter { $0.id != event.id } + [event]
            )
            Task { await NotificationService.shared.replaceNotifications(for: plan) }
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
    let status: DoseEventStatus?
    let onTaken: () -> Void
    let onSkipped: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            cardContent(now: context.date)
        }
    }

    private func cardContent(now: Date) -> some View {
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

                    Button(action: onTaken) {
                        Label("Taken", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
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
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-force-overdue-dose-state") {
            return .overdue
        }
#endif
        return ScheduleEngine.timingState(for: dose.date, now: now)
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
