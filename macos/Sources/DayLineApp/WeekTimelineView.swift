import SwiftUI
import DayLineCore

/// Seven day columns share one vertical scroll position. The date header stays
/// visible when scrolling through the hours and follows any horizontal scroll.
struct WeekTimelineView: View {
    @ObservedObject var model: DayLineModel
    let delete: (CalendarEvent) -> Void

    var body: some View {
        GeometryReader { proxy in
            let days = WeekTimelineLayout.days(containing: model.selectedDay)
            // Also accommodate macOS's "always show scroll bars" preference:
            // the final day's actions must not sit beneath a vertical scroller.
            let scrollerSpace: CGFloat = 16
            let dayWidth = WeekTimelineLayout.columnWidth(availableWidth: proxy.size.width - scrollerSpace, events: model.events, days: days, fontScale: model.settings.fontScale)
            let contentWidth = WeekTimelineLayout.timeAxisWidth + dayWidth * 7
            let totalWidth = contentWidth + scrollerSpace
            let scrollsHorizontally = totalWidth > proxy.size.width + 1
            ScrollView(.horizontal, showsIndicators: scrollsHorizontally) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("时间").font(.caption).foregroundStyle(.secondary)
                            .frame(width: WeekTimelineLayout.timeAxisWidth)
                        ForEach(Array(days.enumerated()), id: \.element) { index, day in
                            Button { model.selectedDay = day } label: {
                                VStack(spacing: 3) {
                                    Text(["周一", "周二", "周三", "周四", "周五", "周六", "周日"][index]).font(.system(size: 12 * model.settings.fontScale, weight: .semibold))
                                    Text(day, format: .dateTime.month().day()).font(.system(size: 11 * model.settings.fontScale))
                                }
                                .frame(width: dayWidth, height: 48 * model.settings.fontScale)
                                .background(Calendar.current.isDate(day, inSameDayAs: model.selectedDay) ? Color(hex: model.settings.themeColor).opacity(0.2) : Color.clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("选择\(day.formatted(.dateTime.year().month().day().weekday()))")
                            .overlay(alignment: .leading) { Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 0.5) }
                        }
                        Color.clear.frame(width: scrollerSpace)
                    }
                    .frame(height: 48 * model.settings.fontScale)
                    .background(.regularMaterial)
                    Divider()
                    ScrollView(.vertical) {
                        HStack(spacing: 0) {
                            ForEach(Array(days.enumerated()), id: \.element) { index, day in
                                TimelineRepresentable(
                                    day: day, events: model.events, color: model.settings.themeColor, fontScale: model.settings.fontScale,
                                    bgColor: model.settings.bgColor, bgOpacity: model.settings.bgOpacity, bgImagePath: model.settings.bgImagePath, bgType: model.settings.bgType,
                                    open: { model.editing = $0; model.showingEditor = true },
                                    delete: delete,
                                    newRange: { start, end in
                                        model.selectedDay = Calendar.current.startOfDay(for: start)
                                        model.presentNewEvent((start, end))
                                    },
                                    resize: { model.resize($0, to: $1) },
                                    complete: { model.complete($0) },
                                    showsTimeAxis: index == 0,
                                    compactMode: true
                                )
                                .frame(width: dayWidth + (index == 0 ? WeekTimelineLayout.timeAxisWidth : 0), height: 1440)
                                .background(Calendar.current.isDateInToday(day) ? Color(hex: model.settings.themeColor).opacity(0.05) : Color.clear)
                                .accessibilityLabel("\(day.formatted(.dateTime.year().month().day().weekday()))时间线")
                            }
                        }
                        .frame(width: contentWidth, height: 1440, alignment: .topLeading)
                    }
                }
                .frame(width: totalWidth, height: max(0, proxy.size.height - (scrollsHorizontally ? scrollerSpace : 0)), alignment: .top)
            }
        }
    }
}
