import 'package:flutter/material.dart';

import '../theme/tube_theme.dart';

/// Scoped to the study screens: keep the app identity while giving small action
/// text enough contrast on the dark surfaces and a visible keyboard focus ring.
class TubeIntelligenceTheme extends StatelessWidget {
  const TubeIntelligenceTheme({super.key, required this.builder});
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final color = base.brightness == Brightness.dark
        ? TubeTheme.accentLight
        : const Color(0xFFAC0010);
    final focus = WidgetStateProperty.resolveWith<BorderSide?>(
      (states) => states.contains(WidgetState.focused)
          ? BorderSide(color: color, width: 2)
          : null,
    );
    return Theme(
      data: base.copyWith(
        colorScheme: base.colorScheme.copyWith(primary: color),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: color)
              .copyWith(side: focus),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(foregroundColor: color)
              .copyWith(side: focus),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: TubeTheme.accent,
            foregroundColor: Colors.white,
          ).copyWith(side: focus),
        ),
        inputDecorationTheme: base.inputDecorationTheme.copyWith(
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: color, width: 2),
          ),
        ),
      ),
      child: Builder(builder: builder),
    );
  }
}
