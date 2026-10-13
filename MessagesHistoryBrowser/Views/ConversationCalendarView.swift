//
//  ConversationCalendarView.swift
//  MessagesHistoryBrowser
//
//  Calendar of the displayed conversation's activity: one spot per day with
//  messages, sized by how many were exchanged. Clicking a day scrolls the
//  conversation to that day's first message.
//

import SwiftUI
import CoreData

// Collapsible pane hosting the calendar, with a clickable separator bar
// that hides or shows it.
struct ConversationCalendarPane: View {
    @ObservedObject var viewModel: ContentViewModel

    @AppStorage("showConversationCalendar") private var isCalendarShown = true

    var body: some View {
        VStack(spacing: 0) {
            CalendarPaneSeparator(isExpanded: $isCalendarShown)

            if isCalendarShown {
                ConversationCalendarView(viewModel: viewModel)
                    .frame(height: ConversationCalendarView.paneHeight)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .clipped()
    }
}

// Thin separator bar between the conversation and the calendar; clicking it
// toggles the calendar.
private struct CalendarPaneSeparator: View {
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 9, weight: .semibold))
                Text("Calendar")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { if isExpanded { Divider() } }
        .help(isExpanded ? "Hide Calendar" : "Show Calendar")
    }
}

// Per-day summary of the displayed conversation.
private struct DayActivity {
    var messageCount: Int
    // First item of the day, used as the conversation scroll target.
    var firstItemID: NSManagedObjectID
}

struct ConversationCalendarView: View {
    @ObservedObject var viewModel: ContentViewModel

    static let paneHeight: CGFloat = 170

    private static let cellSize: CGFloat = 22

    // Keyed by the start of each day (in the current calendar).
    @State private var activityByDay: [Date: DayActivity] = [:]
    // First day of each month spanned by the conversation, oldest first.
    @State private var months: [Date] = []
    @State private var maxDailyCount = 1
    @State private var selectedDay: Date?

    private let calendar = Calendar.current

    var body: some View {
        Group {
            if months.isEmpty {
                Text("No messages")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 20) {
                            ForEach(months, id: \.self) { month in
                                monthView(for: month)
                                    .id(month)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    // Most recent activity is the most relevant: start at the end.
                    .onAppear {
                        scrollToLatestMonth(proxy)
                    }
                    .onChange(of: months) {
                        scrollToLatestMonth(proxy)
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            rebuildActivity(from: viewModel.currentMessages)
        }
        .onChange(of: viewModel.currentMessages) { _, newItems in
            rebuildActivity(from: newItems)
        }
    }

    private func scrollToLatestMonth(_ proxy: ScrollViewProxy) {
        guard let last = months.last else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(last, anchor: .trailing)
        }
    }

    // MARK: - Month grid

    private func monthView(for month: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.caption.bold())

            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .frame(width: Self.cellSize, height: 14)
                    }
                }

                ForEach(Array(weeks(of: month).enumerated()), id: \.offset) { _, week in
                    GridRow {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                            if let day = day {
                                dayCell(for: day)
                            } else {
                                Color.clear
                                    .frame(width: Self.cellSize, height: Self.cellSize)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(for day: Date) -> some View {
        let dayNumber = calendar.component(.day, from: day)

        if let activity = activityByDay[day] {
            Button {
                selectedDay = day
                viewModel.conversationScrollTarget = activity.firstItemID
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(spotOpacity(for: activity.messageCount)))
                        .frame(width: spotDiameter(for: activity.messageCount),
                               height: spotDiameter(for: activity.messageCount))
                    if selectedDay == day {
                        Circle()
                            .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    }
                    Text("\(dayNumber)")
                        .font(.system(size: 9))
                        .foregroundColor(.primary)
                }
                .frame(width: Self.cellSize, height: Self.cellSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(day.formatted(date: .abbreviated, time: .omitted)): \(activity.messageCount) item\(activity.messageCount == 1 ? "" : "s")")
        } else {
            Text("\(dayNumber)")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.6))
                .frame(width: Self.cellSize, height: Self.cellSize)
        }
    }

    // Spots grow with the day's message count, on a log scale so a handful
    // of very busy days doesn't make every other day a pinprick.
    private func spotDiameter(for count: Int) -> CGFloat {
        let minDiameter: CGFloat = 8
        let maxDiameter = Self.cellSize - 2
        guard maxDailyCount > 1 else { return maxDiameter }
        let ratio = log(Double(count)) / log(Double(maxDailyCount))
        return minDiameter + (maxDiameter - minDiameter) * CGFloat(ratio)
    }

    private func spotOpacity(for count: Int) -> Double {
        guard maxDailyCount > 1 else { return 0.6 }
        let ratio = log(Double(count)) / log(Double(maxDailyCount))
        return 0.3 + 0.5 * ratio
    }

    // Very short weekday symbols, ordered starting from the locale's first weekday.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    // The month's days laid out in weeks of 7, padded with nil before the
    // first day and after the last.
    private func weeks(of month: Date) -> [[Date?]] {
        guard let dayRange = calendar.range(of: .day, in: .month, for: month) else { return [] }

        let weekday = calendar.component(.weekday, from: month)
        let leadingBlanks = (weekday - calendar.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for dayOffset in 0..<dayRange.count {
            days.append(calendar.date(byAdding: .day, value: dayOffset, to: month))
        }
        while days.count % 7 != 0 {
            days.append(nil)
        }

        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<$0 + 7]) }
    }

    // MARK: - Activity

    // Groups the displayed items by day. currentMessages is in chronological
    // order, so the first item seen for a day is that day's first item.
    private func rebuildActivity(from items: [ChatItem]) {
        var activity: [Date: DayActivity] = [:]
        var maxCount = 1

        for item in items {
            let day = calendar.startOfDay(for: item.date)
            if var existing = activity[day] {
                existing.messageCount += 1
                maxCount = max(maxCount, existing.messageCount)
                activity[day] = existing
            } else {
                activity[day] = DayActivity(messageCount: 1, firstItemID: item.objectID)
            }
        }

        var monthStarts: [Date] = []
        if let firstDay = activity.keys.min(), let lastDay = activity.keys.max(),
           let firstMonth = calendar.dateInterval(of: .month, for: firstDay)?.start,
           let lastMonth = calendar.dateInterval(of: .month, for: lastDay)?.start {
            var month = firstMonth
            while month <= lastMonth {
                monthStarts.append(month)
                guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
                month = next
            }
        }

        activityByDay = activity
        maxDailyCount = maxCount
        months = monthStarts
        if let selectedDay = selectedDay, activity[selectedDay] == nil {
            self.selectedDay = nil
        }
    }
}
