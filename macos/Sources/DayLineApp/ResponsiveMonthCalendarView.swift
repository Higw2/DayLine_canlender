import SwiftUI
import DayLineCore

private struct MonthCalendarWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct ResponsiveMonthCalendarView: View {
    @Binding var selectedDate: Date
    let accent: Color
    let fontScale: Double

    @State private var displayedMonth: Date
    @State private var availableWidth: CGFloat = 0

    private let calendar: Calendar

    init(selectedDate: Binding<Date>, accent: Color, fontScale: Double) {
        _selectedDate = selectedDate
        self.accent = accent
        self.fontScale = fontScale
        let calendar = MonthGridLayout.chineseCalendar()
        self.calendar = calendar
        _displayedMonth = State(initialValue: MonthGridLayout.monthStart(for: selectedDate.wrappedValue, calendar: calendar))
    }

    var body: some View {
        let cellWidth = max(1, availableWidth) / CGFloat(MonthGridLayout.columns)
        let cellHeight = MonthGridLayout.rowHeight(cellWidth: cellWidth, fontScale: CGFloat(fontScale))

        VStack(spacing: 8 * fontScale) {
            monthHeader
            weekdayHeader
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 0), count: MonthGridLayout.columns),
                spacing: 0
            ) {
                ForEach(MonthGridLayout.dates(forMonth: displayedMonth, calendar: calendar), id: \.self) { date in
                    dayCell(date, height: cellHeight)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: MonthCalendarWidthKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(MonthCalendarWidthKey.self) { availableWidth = $0 }
        .onChange(of: selectedDate) { newValue in
            let month = MonthGridLayout.monthStart(for: newValue, calendar: calendar)
            if !calendar.isDate(month, equalTo: displayedMonth, toGranularity: .month) {
                displayedMonth = month
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button("‹") { changeMonth(by: -1) }
                .buttonStyle(.bordered)
                .accessibilityLabel("上个月")
            Spacer()
            Text(displayedMonth, format: .dateTime.year().month(.wide))
                .font(.system(size: 15 * fontScale, weight: .semibold))
            Spacer()
            Button("›") { changeMonth(by: 1) }
                .buttonStyle(.bordered)
                .accessibilityLabel("下个月")
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { weekday in
                Text(weekday)
                    .font(.system(size: 11 * fontScale, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(_ date: Date, height: CGFloat) -> some View {
        let inDisplayedMonth = calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        return Button {
            selectedDate = calendar.startOfDay(for: date)
            displayedMonth = MonthGridLayout.monthStart(for: date, calendar: calendar)
        } label: {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 13 * fontScale, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(inDisplayedMonth ? 1 : 0.42))
                .frame(maxWidth: .infinity, minHeight: height)
                .background(isSelected ? accent : .clear, in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    if isToday && !isSelected {
                        RoundedRectangle(cornerRadius: 6).stroke(accent, lineWidth: 1.5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityDateText(date))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func changeMonth(by offset: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: offset, to: displayedMonth)!
    }

    private func accessibilityDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日EEEE"
        return formatter.string(from: date)
    }
}
