import Foundation

/// "Why this date?" as a caregiver checks it against the bottle: the
/// forecast's own steps, one short line each, with the amount first so the
/// column adds up by eye. Worked out here rather than in the view so every
/// line, plural and state is tested; the view only lays them out.
enum WhyThisDateLedger {
    struct Line: Equatable {
        enum Kind: Equatable {
            /// Where the walk starts: the last count, or what stands for one.
            case start
            /// Something added or taken away since.
            case change
            /// The running number after the changes above it.
            case total
            /// What the schedule or the as-needed history uses.
            case use
            case courseEnd
            case conclusion
            case alert
        }

        let kind: Kind
        /// What the screen shows.
        let text: String
        /// A reason under it, when the line needs one.
        var detail: String? = nil
        /// The line as VoiceOver reads it: one full sentence, the signs said
        /// as words, since "minus" is not what a symbol beside a number is
        /// always read as.
        let spoken: String
        /// Wears the attention colour every other screen gives a count needed
        /// or an empty supply.
        var isWarning = false
    }

    /// `notificationsAllowed` is false while iOS will not deliver anything
    /// the app plans: permission refused, or never asked for.
    /// `courseRanOutFirst`, from `FinishedCourseNotice.ranOutFirst`, keeps
    /// a course whose supply ran short from being called finished here while
    /// the screen it was opened from names it by its last day.
    static func lines(
        for breakdown: ForecastBreakdown,
        isAsNeeded: Bool,
        isArchived: Bool = false,
        notificationsAllowed: Bool = true,
        courseRanOutFirst: Bool = false,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [Line] {
        let phrasing = Phrasing(
            breakdown: breakdown,
            isAsNeeded: isAsNeeded,
            isArchived: isArchived,
            notificationsAllowed: notificationsAllowed,
            courseRanOutFirst: courseRanOutFirst,
            calendar: calendar
        )
        return breakdown.steps.flatMap(phrasing.lines(for:))
    }

    /// "Oct 4 at 9:00 AM", in the calendar the forecast was made with.
    static func momentText(_ date: Date, calendar: Calendar) -> String {
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, calendar: calendar, timeZone: calendar.timeZone))
        return "\(ForecastEngine.dayText(date, calendar: calendar)) at \(time)"
    }

    private struct Phrasing {
        let breakdown: ForecastBreakdown
        let isAsNeeded: Bool
        let isArchived: Bool
        let notificationsAllowed: Bool
        let courseRanOutFirst: Bool
        let calendar: Calendar

        private var form: MedicationForm { breakdown.form }

        private func day(_ date: Date) -> String { ForecastEngine.dayText(date, calendar: calendar) }
        private func amount(_ quantity: Double) -> String { form.quantityText(quantity) }

        private func signed(_ quantity: Double) -> String {
            quantity < 0 ? "−\(amount(-quantity))" : "+\(amount(quantity))"
        }

        private func spokenSigned(_ quantity: Double) -> String {
            quantity < 0 ? "Minus \(amount(-quantity))" : "Plus \(amount(quantity))"
        }

        func lines(for step: ForecastBreakdown.Step) -> [Line] {
            switch step {
            case let .anchor(anchor): [start(anchor)]
            case let .refills(tally): [refills(tally)]
            case let .adjustment(adjustment): [self.adjustment(adjustment)]
            case let .taken(tally, fromHealth): [taken(tally, fromHealth: fromHealth)]
            case let .onRecord(balance): [onRecord(balance)]
            case let .assumed(tally, sinceRefill, leaves): assumed(tally, sinceRefill: sinceRefill, leaves: leaves)
            case let .use(use): [self.use(use)]
            case let .courseEnd(end): courseEnd(end)
            case let .conclusion(conclusion, explanation): [self.conclusion(conclusion, explanation: explanation)]
            case let .alert(alert): [self.alert(alert)]
            }
        }

        private func start(_ anchor: ForecastBreakdown.Anchor) -> Line {
            switch anchor.kind {
            case .openingCount:
                let text = "Started with \(amount(anchor.balance)) on \(day(anchor.date))"
                return Line(kind: .start, text: text, spoken: text + ".")
            case .count:
                let text = "Counted \(amount(anchor.balance)) on \(day(anchor.date))"
                return Line(kind: .start, text: text, spoken: text + ".")
            case .refillOntoEmpty:
                // The ledger's number after the refill, which is less than the
                // refill when more was logged than was on record before it.
                let text = "\(amount(anchor.balance)) after the refill on \(day(anchor.date))"
                return Line(
                    kind: .start,
                    text: text,
                    detail: "Nothing was on record before it.",
                    spoken: "\(text), when nothing was on record before it."
                )
            case .added:
                let text = "Nothing counted since it was added on \(day(anchor.date))"
                return Line(kind: .start, text: text, spoken: text + ".")
            }
        }

        private func refills(_ tally: ForecastBreakdown.Tally) -> Line {
            let refills = tally.count.counted("refill", plural: "refills")
            return Line(
                kind: .change,
                text: "\(signed(tally.quantity)) from \(refills)",
                spoken: "\(spokenSigned(tally.quantity)) from \(refills) since then."
            )
        }

        private func adjustment(_ adjustment: ForecastBreakdown.Adjustment) -> Line {
            let what = switch adjustment.reason {
            case .lost: "lost or damaged"
            case .discarded: "discarded"
            case .returned: "returned"
            case .openingCount, .refill, .correction: adjustment.reason.displayName.lowercased()
            }
            return Line(
                kind: .change,
                text: "\(signed(adjustment.quantity)) \(what)",
                spoken: "\(spokenSigned(adjustment.quantity)) \(what) since then."
            )
        }

        private func taken(_ tally: ForecastBreakdown.Tally, fromHealth: Int) -> Line {
            guard tally.count > 0 else {
                return Line(kind: .change, text: "No doses logged since then", spoken: "No doses logged as taken since then.")
            }
            let doses = tally.count.counted("logged dose", plural: "logged doses")
            let text = "\(signed(-tally.quantity)) from \(doses)" + (fromHealth > 0 ? " (\(fromHealth) from Apple Health)" : "")
            let health = switch fromHealth {
            case 0: ""
            case tally.count: tally.count == 1 ? ", from Apple Health" : ", all of them from Apple Health"
            default: ", \(fromHealth) of them from Apple Health"
            }
            let taken = tally.count.counted("dose", plural: "doses")
            return Line(
                kind: .change,
                text: text,
                spoken: "\(spokenSigned(-tally.quantity)) for \(taken) logged as taken since then\(health)."
            )
        }

        private func onRecord(_ balance: Double) -> Line {
            // The ledger can go below nothing when more was logged than was
            // counted; the forecast reads that as none, and so does this.
            guard balance >= -0.000_001 else {
                return Line(
                    kind: .total,
                    text: "= none on record",
                    detail: "More was logged as taken than was on record.",
                    spoken: "That comes to none on record: more was logged as taken than was on record."
                )
            }
            // "On hand" while the forecast assumes nothing, as the number
            // beside the date says it; "on record" once it does.
            let words = SupplyAttention.quantityWords(for: breakdown.forecast)
            return Line(
                kind: .total,
                text: "= \(amount(max(0, balance))) \(words)",
                spoken: "That comes to \(amount(max(0, balance))) \(words)."
            )
        }

        private func assumed(_ tally: ForecastBreakdown.Tally, sinceRefill: Bool, leaves: Double) -> [Line] {
            let doses = tally.count.counted("scheduled dose", plural: "scheduled doses")
            let since = sinceRefill ? "since the last refill" : "since the last count"
            let were = tally.count == 1 ? "wasn't logged" : "weren't logged"
            let change = Line(
                kind: .change,
                text: "\(signed(-tally.quantity)) from \(doses) not logged, assumed taken",
                spoken: "\(spokenSigned(-tally.quantity)) for \(doses) \(since) that \(were), assumed taken."
            )
            let total = leaves > 0.000_001
                ? Line(kind: .total, text: "= about \(amount(leaves)) left", spoken: "That leaves about \(amount(leaves)).")
                : Line(kind: .total, text: "= none left on record", spoken: "That leaves none of the supply on record.", isWarning: true)
            return [change, total]
        }

        /// "2 tablets a day", or a week's total with its daily share.
        private func rate(_ use: ForecastBreakdown.Use?) -> String {
            switch use {
            case let .daily(quantity)?: "\(amount(quantity)) a day"
            case let .weekly(quantity)?: "\(amount(quantity)) a week, about \(amount(quantity / 7)) a day"
            case let .asNeeded(rate)?: "about \(amount(rate.perDay)) a day"
            case nil: "nothing scheduled"
            }
        }

        private func use(_ use: ForecastBreakdown.Use) -> Line {
            switch use {
            case .daily, .weekly:
                // A taper's later steps are said beside today's amount, so the
                // amount left can be checked against the conclusion under it,
                // which was worked out over every step.
                let starts = breakdown.useStarts.map { " from \(day($0))" } ?? ""
                let now = breakdown.useChanges.isEmpty || !starts.isEmpty ? "" : " now"
                let text = "Uses \(rate(use))\(starts)\(now)"
                let steps = breakdown.useChanges.map { "\(rate($0.use)) from \(day($0.date))" }
                guard let last = steps.last else {
                    return Line(kind: .use, text: text, spoken: "The schedule uses \(rate(use))\(starts).")
                }
                let then = steps.count == 1 ? last : steps.dropLast().joined(separator: ", ") + " and " + last
                return Line(
                    kind: .use,
                    text: text,
                    detail: "Then \(then).",
                    spoken: "The schedule uses \(rate(use))\(starts)\(now), then \(then)."
                )
            case let .asNeeded(rate):
                // Over the history that exists, at most thirty days, which is
                // what the run-out date was divided out from.
                let doses = rate.doseCount.counted("dose", plural: "doses")
                let used = rate.windowDays == 1
                    ? "\(amount(rate.quantity)) in \(doses) today"
                    : "\(amount(rate.quantity)) in \(doses) over the last \(rate.windowDays) days, about \(amount(rate.perDay)) a day"
                return Line(kind: .use, text: "As needed: \(used)", spoken: "Taken as needed: \(used).")
            }
        }

        /// A finished course says its last day in its conclusion; saying it
        /// twice, a line apart, reads as two different days.
        private func courseEnd(_ end: Date) -> [Line] {
            if case .courseFinished = breakdown.conclusion { return [] }
            return [Line(
                kind: .courseEnd,
                text: "Last day of the course: \(day(end))",
                spoken: "The course's last day is \(day(end))."
            )]
        }

        private func conclusion(_ conclusion: ForecastBreakdown.Conclusion, explanation: String) -> Line {
            switch conclusion {
            case let .runsOut(date, _):
                let text = "Runs out around \(day(date))"
                guard let end = breakdown.courseEnd else {
                    return Line(kind: .conclusion, text: text, spoken: text + ".")
                }
                let before = "Before the course's last day, \(day(end))."
                return Line(kind: .conclusion, text: text, detail: before, spoken: "\(text), before the course's last day, \(day(end)).")
            case let .courseCovered(end, leftover):
                let text = leftover > 0.000_001
                    ? "Enough to finish the course on \(day(end)), with \(amount(leftover)) left"
                    : "Just enough to finish the course on \(day(end))"
                return Line(kind: .conclusion, text: text, spoken: text + ".")
            case let .courseFinished(end):
                var reason = "Nothing more is scheduled, so nothing needs a refill."
                if courseRanOutFirst {
                    reason = "The supply on record ran out before it. \(reason)"
                }
                let text = FinishedCourseNotice.endedText(day: day(end), ranOutFirst: courseRanOutFirst)
                return Line(kind: .conclusion, text: text, detail: reason, spoken: "\(text). \(reason)")
            case .countNeeded:
                let reason = "The doses nobody logged use up what's on record, so only a count can say what's left."
                return Line(kind: .conclusion, text: "Count needed", detail: reason, spoken: "Count needed. \(reason)", isWarning: true)
            case .outOfSupply:
                let text = SupplyAttention.line(for: breakdown.forecast)
                return Line(kind: .conclusion, text: text, spoken: text + ".", isWarning: true)
            case .unknown:
                // No schedule, too little as-needed history, or a supply that
                // outlasts the forecast; the forecast's explanation says which.
                let text = isAsNeeded && breakdown.use == nil ? "Not enough history yet" : "Timing unknown"
                return Line(kind: .conclusion, text: text, detail: explanation, spoken: "\(text). \(explanation)")
            }
        }

        private func alert(_ alert: ForecastBreakdown.Alert) -> Line {
            let moment = WhyThisDateLedger.momentText(alert.date, calendar: calendar)
            switch alert.state {
            case .planned:
                // A lead longer than the one chosen says why, in the words
                // the editor's lead-time stepper uses for it.
                let lead = SupplyAttention.lengthenedLeadNote(refillLeadDays: alert.chosenLeadDays, refillsRemaining: alert.needsPrescriber ? 0 : nil)
                    ?? "\(alert.leadDays.dayCountText) before it runs out."
                let text = "Low-supply alert on \(moment)"
                return undeliverable(Line(kind: .alert, text: text, detail: lead, spoken: "\(text). \(lead)"))
            case .passed:
                let text = "Low-supply alert was due \(moment)"
                let reason = "Already passed. Alerts aren't sent late."
                return Line(kind: .alert, text: text, detail: reason, spoken: "\(text). \(reason)")
            case let .pausedByRefill(checkAt):
                let text = "Low-supply alert paused while the refill is on its way"
                let detail = checkAt.map { "Checked again on \(WhyThisDateLedger.momentText($0, calendar: calendar))." }
                    ?? "It comes back if the refill runs two days late or supply gets very low."
                return undeliverable(Line(kind: .alert, text: text, detail: detail, spoken: "\(text). \(detail)"))
            case .off:
                let text = "Low-supply alert off"
                let reason = isArchived ? "This medication is archived." : "Refill reminders are off for this medication."
                return Line(kind: .alert, text: text, detail: reason, spoken: "\(text). \(reason)")
            }
        }

        /// An alert iOS will not deliver says so, beside the time it would
        /// have come: a date alone reads as a promise someone may wait on.
        private func undeliverable(_ line: Line) -> Line {
            guard !notificationsAllowed else { return line }
            let blocked = "It can't be sent until notifications are allowed for Meds Ahead."
            let detail = line.detail.map { "\($0) \(blocked)" } ?? blocked
            return Line(kind: line.kind, text: line.text, detail: detail, spoken: "\(line.text). \(detail)", isWarning: true)
        }
    }
}
