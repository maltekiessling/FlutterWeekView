import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_week_view/src/controller/day_view.dart';
import 'package:flutter_week_view/src/event.dart';
import 'package:flutter_week_view/src/styles/day_bar.dart';
import 'package:flutter_week_view/src/styles/day_view.dart';
import 'package:flutter_week_view/src/styles/hours_column.dart';
import 'package:flutter_week_view/src/utils/event_grid.dart';
import 'package:flutter_week_view/src/utils/hour_minute.dart';
import 'package:flutter_week_view/src/utils/scroll.dart';
import 'package:flutter_week_view/src/utils/utils.dart';
import 'package:flutter_week_view/src/widgets/day_bar.dart';
import 'package:flutter_week_view/src/widgets/hours_column.dart';
import 'package:flutter_week_view/src/widgets/zoomable_header_widget.dart';

/// A (scrollable) day view which is able to display events, zoom and un-zoom and more !
class DayView extends ZoomableHeadersWidget<DayViewStyle, DayViewController> {
  /// The events.
  final List<FlutterWeekViewEvent> events;

  /// The day view date.
  final DateTime date;

  /// The day bar style.
  final DayBarStyle dayBarStyle;

  /// Creates a new day view instance.
  DayView({
    List<FlutterWeekViewEvent> events,
    @required DateTime date,
    DayViewStyle style,
    HoursColumnStyle hoursColumnStyle,
    DayBarStyle dayBarStyle,
    DayViewController controller,
    bool inScrollableWidget,
    HourMinute minimumTime,
    HourMinute maximumTime,
    HourMinute initialTime,
    bool scrollToCurrentTime,
    bool userZoomable,
    HoursColumnTapCallback onHoursColumnTappedDown,
    DayBarTapCallback onDayBarTappedDown,
  })  : assert(date != null),
        date = date.yearMonthDay,
        events = events ?? [],
        dayBarStyle = dayBarStyle ?? DayBarStyle.fromDate(date: date),
        super(
          style: style ?? DayViewStyle.fromDate(date: date),
          hoursColumnStyle: hoursColumnStyle ?? const HoursColumnStyle(),
          controller: controller ?? DayViewController(),
          inScrollableWidget: inScrollableWidget ?? true,
          minimumTime: minimumTime ?? HourMinute.MIN,
          maximumTime: maximumTime ?? HourMinute.MAX,
          initialTime: initialTime ?? HourMinute.MIN,
          scrollToCurrentTime: scrollToCurrentTime ?? true,
          userZoomable: userZoomable ?? true,
          onHoursColumnTappedDown: onHoursColumnTappedDown,
          onDayBarTappedDown: onDayBarTappedDown,
        );

  @override
  State<StatefulWidget> createState() => _DayViewState();
}

/// The day view state.
class _DayViewState extends ZoomableHeadersWidgetState<DayView> {
  /// Contains all events draw properties.
  final Map<FlutterWeekViewEvent, EventDrawProperties> eventsDrawProperties = HashMap();

  /// The flutter week view events.
  List<FlutterWeekViewEvent> events;

  @override
  void initState() {
    super.initState();
    scheduleScrolls();
    reset();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(createEventsDrawProperties);
      }
    });
  }

  @override
  void didUpdateWidget(DayView oldWidget) {
    super.didUpdateWidget(oldWidget);

    reset();
    createEventsDrawProperties();
  }

  @override
  Widget build(BuildContext context) {
    Widget mainWidget = createMainWidget();
    if (widget.style.headerSize > 0 || widget.hoursColumnStyle.width > 0) {
      mainWidget = Stack(
        children: [
          mainWidget,
          Positioned(
            top: 0,
            left: widget.hoursColumnStyle.width,
            right: 0,
            child: DayBar.fromHeadersWidgetState(
              parent: widget,
              date: widget.date,
              style: widget.dayBarStyle,
              width: double.infinity,
            ),
          ),
          Container(
            height: widget.style.headerSize,
            width: widget.hoursColumnStyle.width,
            color: widget.dayBarStyle.color,
          ),
        ],
      );
    }

    if (!isZoomable) {
      return mainWidget;
    }

    return GestureDetector(
      onScaleStart: (_) => widget.controller.scaleStart(),
      onScaleUpdate: widget.controller.scaleUpdate,
      child: mainWidget,
    );
  }

  @override
  void onZoomFactorChanged(DayViewController controller, ScaleUpdateDetails details) {
    super.onZoomFactorChanged(controller, details);

    if (mounted) {
      setState(createEventsDrawProperties);
    }
  }

  @override
  DayViewStyle get currentDayViewStyle => widget.style;

  @override
  bool get shouldScrollToCurrentTime => super.shouldScrollToCurrentTime && Utils.sameDay(widget.date);

  /// Creates the main widget, with a hours column and an events column.
  Widget createMainWidget() {
    List<Widget> children = eventsDrawProperties.entries.map((entry) => entry.value.createWidget(context, widget, entry.key)).toList();
    if (widget.hoursColumnStyle.width > 0) {
      children.add(Positioned(
        top: 0,
        left: 0,
        child: HoursColumn.fromHeadersWidgetState(parent: this),
      ));
    }

    if (Utils.sameDay(widget.date) && widget.minimumTime.atDate(widget.date).isBefore(DateTime.now()) && widget.maximumTime.atDate(widget.date).isAfter(DateTime.now())) {
      if (widget.style.currentTimeRuleColor != null && widget.style.currentTimeRuleHeight > 0) {
        children.add(createCurrentTimeRule());
      }

      if (widget.style.currentTimeCircleColor != null && widget.style.currentTimeCircleRadius > 0) {
        children.add(createCurrentTimeCircle());
      }
    }

    Widget mainWidget = SizedBox(
      height: calculateHeight(),
      child: Stack(children: children..insert(0, createBackground())),
    );

    if (verticalScrollController != null) {
      mainWidget = NoGlowBehavior.noGlow(
        child: SingleChildScrollView(
          controller: verticalScrollController,
          child: mainWidget,
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(top: widget.style.headerSize),
      child: mainWidget,
    );
  }

  /// Creates the background widgets that should be added to a stack.
  Widget createBackground() => Positioned.fill(
        child: CustomPaint(
          painter: widget.style.createBackgroundPainter(
            dayView: widget,
            topOffsetCalculator: calculateTopOffset,
          ),
        ),
      );

  /// Creates the horizontal rule in the day view column, positioned at the current time of the day.
  Widget createCurrentTimeRule() => Positioned(
        top: calculateTopOffset(HourMinute.now()),
        left: widget.hoursColumnStyle.width,
        right: 0,
        child: Container(
          height: widget.style.currentTimeRuleHeight,
          color: widget.style.currentTimeRuleColor,
        ),
      );

  /// Creates the current time circle, shown along with the horizontal rule in the day view column.
  Widget createCurrentTimeCircle() => Positioned(
        top: calculateTopOffset(HourMinute.now()) - widget.style.currentTimeCircleRadius,
        right: widget.style.currentTimeCirclePosition == CurrentTimeCirclePosition.right ? 0 : null,
        left: widget.style.currentTimeCirclePosition == CurrentTimeCirclePosition.left ? widget.hoursColumnStyle.width : null,
        child: Container(
          height: widget.style.currentTimeCircleRadius * 2,
          width: widget.style.currentTimeCircleRadius * 2,
          decoration: BoxDecoration(
            color: widget.style.currentTimeCircleColor,
            shape: BoxShape.circle,
          ),
        ),
      );

  /// Resets the events positioning.
  void reset() {
    eventsDrawProperties.clear();
    events = List.of(widget.events)..sort();
  }

  /// Creates the events draw properties and add them to the current list.
  void createEventsDrawProperties() {
    EventGrid eventsGrid = EventGrid();
    for (FlutterWeekViewEvent event in List.of(events)) {
      EventDrawProperties drawProperties = eventsDrawProperties[event] ?? EventDrawProperties(widget, event);
      if (!drawProperties.shouldDraw) {
        events.remove(event);
        continue;
      }

      drawProperties.calculateTopAndHeight(calculateTopOffset);
      if (drawProperties.left == null || drawProperties.width == null) {
        eventsGrid.add(drawProperties);
      }

      eventsDrawProperties[event] = drawProperties;
    }

    if (eventsGrid.drawPropertiesList.isNotEmpty) {
      double eventsColumnWidth = (context.findRenderObject() as RenderBox).size.width - widget.hoursColumnStyle.width;
      eventsGrid.processEvents(widget.hoursColumnStyle.width, eventsColumnWidth);
    }
  }
}