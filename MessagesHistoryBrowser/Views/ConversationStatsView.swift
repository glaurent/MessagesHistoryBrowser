//
//  ConversationStatsView.swift
//  MessagesHistoryBrowser
//
//  Bar chart of a conversation's message count per day, week or month,
//  shown in its own window ("Show Conversation Stats").
//

import SwiftUI
import Charts
import CoreData

enum StatsGranularity: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"

    var id: Self { self }

    var calendarComponent: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }

    // Approximate width of the visible part of the chart, in seconds; older
    // periods are reached by scrolling.
    var visibleDomainLength: TimeInterval {
        let day: TimeInterval = 24 * 3600
        switch self {
        case .day: return 90 * day
        case .week: return 52 * 7 * day
        case .month: return 36 * 31 * day
        }
    }
}

// Messages sent and received on one day. Plain values, so the window holds
// no managed objects a re-import could delete from under it.
private struct DailyCount: Sendable {
    let day: Date
    var sent: Int
    var received: Int
}

private struct ChartBar: Identifiable {
    let periodStart: Date
    let sender: String
    let count: Int

    var id: String { "\(periodStart.timeIntervalSinceReferenceDate)-\(sender)" }
}

private enum StatsLoadState {
    case loading
    case unavailable
    case loaded(contactName: String, days: [DailyCount])
}

struct ConversationStatsView: View {
    static let windowID = "conversationStats"

    // URI representation of the contact's NSManagedObjectID, the window's value.
    let contactURI: URL?

    @State private var loadState = StatsLoadState.loading
    @AppStorage("conversationStatsGranularity") private var granularity = StatsGranularity.week

    private static let meLabel = "Me"

    var body: some View {
        Group {
            switch loadState {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unavailable:
                Text("This conversation is no longer available.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let contactName, let days):
                statsContent(contactName: contactName, days: days)
                    .navigationTitle("Stats – \(contactName)")
            }
        }
        .frame(minWidth: 500, minHeight: 320)
        .task(id: contactURI) {
            loadState = await Self.loadDailyCounts(contactURI: contactURI)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func statsContent(contactName: String, days: [DailyCount]) -> some View {
        let bars = Self.bars(from: days, granularity: granularity, contactName: contactName)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                summary(days: days)
                Spacer()
                Picker("Messages per", selection: $granularity) {
                    ForEach(StatsGranularity.allCases) { granularity in
                        Text(granularity.rawValue).tag(granularity)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            if bars.isEmpty {
                Text("No messages")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chart(bars: bars, contactName: contactName)
                    // Rebuilt per granularity so the initial scroll position
                    // (the most recent periods) is applied again.
                    .id(granularity)
            }
        }
        .padding()
    }

    private func summary(days: [DailyCount]) -> some View {
        let sent = days.reduce(0) { $0 + $1.sent }
        let received = days.reduce(0) { $0 + $1.received }
        let busiest = days.max { ($0.sent + $0.received) < ($1.sent + $1.received) }

        return VStack(alignment: .leading, spacing: 2) {
            Text("\(sent + received) messages: \(sent) sent, \(received) received")
                .font(.headline)
            if let first = days.first, let last = days.last {
                Text("\(first.day.formatted(date: .abbreviated, time: .omitted)) – \(last.day.formatted(date: .abbreviated, time: .omitted)), \(days.count) active days")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let busiest = busiest {
                Text("Busiest day: \(busiest.day.formatted(date: .abbreviated, time: .omitted)) (\(busiest.sent + busiest.received) messages)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func chart(bars: [ChartBar], contactName: String) -> some View {
        let unit = granularity.calendarComponent
        let firstPeriod = bars.first?.periodStart ?? Date()
        let lastPeriod = bars.last?.periodStart ?? Date()
        let span = lastPeriod.timeIntervalSince(firstPeriod)

        // Only scroll when the conversation spans more than the visible
        // window; start scrolled to the most recent periods.
        let visibleLength = min(granularity.visibleDomainLength, span + granularity.visibleDomainLength / 20)
        let initialX = max(firstPeriod, lastPeriod.addingTimeInterval(-visibleLength * 0.95))

        return Chart(bars) { bar in
            BarMark(
                x: .value("Period", bar.periodStart, unit: unit),
                y: .value("Messages", bar.count)
            )
            .foregroundStyle(by: .value("Sender", bar.sender))
        }
        .chartForegroundStyleScale(domain: [Self.meLabel, contactName],
                                   range: [Color.accentColor, Color.gray])
        .chartLegend(position: .top, alignment: .leading)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: visibleLength)
        .chartScrollPosition(initialX: initialX)
    }

    // MARK: - Data

    // Groups the daily counts into one bar per period and sender.
    private static func bars(from days: [DailyCount], granularity: StatsGranularity, contactName: String) -> [ChartBar] {
        let calendar = Calendar.current
        var sentByPeriod: [Date: Int] = [:]
        var receivedByPeriod: [Date: Int] = [:]

        for day in days {
            let periodStart = calendar.dateInterval(of: granularity.calendarComponent, for: day.day)?.start ?? day.day
            sentByPeriod[periodStart, default: 0] += day.sent
            receivedByPeriod[periodStart, default: 0] += day.received
        }

        let periods = Set(sentByPeriod.keys).union(receivedByPeriod.keys).sorted()
        var bars: [ChartBar] = []
        for period in periods {
            if let sent = sentByPeriod[period], sent > 0 {
                bars.append(ChartBar(periodStart: period, sender: meLabel, count: sent))
            }
            if let received = receivedByPeriod[period], received > 0 {
                bars.append(ChartBar(periodStart: period, sender: contactName, count: received))
            }
        }
        return bars
    }

    // Counts the contact's messages per day on a background context, fetching
    // only the date and direction of each message rather than whole objects.
    private static func loadDailyCounts(contactURI: URL?) async -> StatsLoadState {
        guard let contactURI = contactURI else { return .unavailable }

        let context = MOCController.sharedInstance.workerContext()
        return await context.perform {
            guard let coordinator = context.persistentStoreCoordinator,
                  let contactID = coordinator.managedObjectID(forURIRepresentation: contactURI),
                  let contact = try? context.existingObject(with: contactID) as? ChatContact else {
                return .unavailable
            }

            let request = NSFetchRequest<NSDictionary>(entityName: ChatMessage.EntityName)
            request.resultType = .dictionaryResultType
            request.predicate = NSPredicate(format: "%K == %@", ChatMessage.Attributes.contact.rawValue, contact)
            request.propertiesToFetch = [ChatMessage.Attributes.date.rawValue, ChatMessage.Attributes.isFromMe.rawValue]
            request.sortDescriptors = [NSSortDescriptor(key: ChatMessage.Attributes.dateNanoseconds.rawValue, ascending: true)]

            guard let rows = try? context.fetch(request) else { return .unavailable }

            let calendar = Calendar.current
            var days: [DailyCount] = []
            for row in rows {
                guard let date = row[ChatMessage.Attributes.date.rawValue] as? Date else { continue }
                let isFromMe = (row[ChatMessage.Attributes.isFromMe.rawValue] as? Bool) ?? false
                let day = calendar.startOfDay(for: date)

                // Rows are in date order, so a day's messages are contiguous.
                if days.last?.day != day {
                    days.append(DailyCount(day: day, sent: 0, received: 0))
                }
                if isFromMe {
                    days[days.count - 1].sent += 1
                } else {
                    days[days.count - 1].received += 1
                }
            }

            return .loaded(contactName: contact.name, days: days)
        }
    }
}
