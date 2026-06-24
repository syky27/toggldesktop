import 'package:flutter/material.dart';

/// Day calendar view (FP-46): day grid with drag-to-move and edge-resize,
/// create/edit, and split-at-midnight — mirroring the `calendarview` added on
/// the Redmine fork. Scaffolded here; the interactive grid lands in FP-46.
class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Center(child: Text('Calendar — day grid (FP-46)')),
    );
  }
}
