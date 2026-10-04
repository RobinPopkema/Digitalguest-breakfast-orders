import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

// Expressive styling on Flutter's accessible Material controls. No new runtime.
const expressiveDuration = Duration(milliseconds: 320);

class ExpressiveSize extends StatelessWidget {
  const ExpressiveSize({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => MediaQuery.disableAnimationsOf(context)
      ? child
      : AnimatedSize(
          duration: expressiveDuration,
          curve: const ExpressiveSpring(),
          alignment: Alignment.topCenter,
          child: child,
        );
}

class ExpressiveSpring extends Curve {
  const ExpressiveSpring();
  static final _spring = SpringSimulation(
    SpringDescription.withDampingRatio(mass: 1, stiffness: 500, ratio: 1),
    0,
    1,
    0,
  );
  @override
  double transformInternal(double t) => _spring.x(t * .45) / _spring.x(.45);
}

ThemeData breakfastTheme({
  bool reduceMotion = false,
  Brightness brightness = Brightness.light,
}) {
  final dark = brightness == Brightness.dark;
  Color tone(int light, int night) => Color(dark ? night : light);
  final colors =
      ColorScheme.fromSeed(
        seedColor: const Color(0xff0b647b),
        brightness: brightness,
      ).copyWith(
        primary: tone(0xff0b647b, 0xff96d3e8),
        onPrimary: tone(0xffffffff, 0xff003545),
        primaryContainer: tone(0xffd4eaf0, 0xff164b5e),
        onPrimaryContainer: tone(0xff0c344a, 0xffc9edfa),
        secondary: tone(0xff0b647b, 0xff96d3e8),
        onSecondary: tone(0xffffffff, 0xff003545),
        secondaryContainer: tone(0xffd4eaf0, 0xff164b5e),
        onSecondaryContainer: tone(0xff0c344a, 0xffc9edfa),
        tertiary: tone(0xff0b647b, 0xff96d3e8),
        onTertiary: tone(0xffffffff, 0xff003545),
        tertiaryContainer: tone(0xffd4eaf0, 0xff164b5e),
        onTertiaryContainer: tone(0xff0c344a, 0xffc9edfa),
        surface: tone(0xfff5f8fa, 0xff0d1c26),
        surfaceContainerLowest: tone(0xffffffff, 0xff12232f),
        surfaceContainerLow: tone(0xffedf3f6, 0xff182c3a),
        surfaceContainer: tone(0xffe4edf2, 0xff203544),
        surfaceContainerHigh: tone(0xffdce7ed, 0xff2a4252),
        onSurface: tone(0xff142f43, 0xffe2eef5),
        onSurfaceVariant: tone(0xff506473, 0xffb7cbd8),
        outlineVariant: tone(0xffcedce4, 0xff3c5666),
      );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    fontFamily: 'Segoe UI',
  );
  final motion = reduceMotion
      ? Duration.zero
      : const Duration(milliseconds: 180);
  final shape = WidgetStateProperty.resolveWith<OutlinedBorder>(
    (states) => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(
        states.contains(WidgetState.pressed) ? 12 : 28,
      ),
    ),
  );
  final buttons = ButtonStyle(
    animationDuration: motion,
    shape: shape,
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    iconSize: const WidgetStatePropertyAll(20),
    minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    ),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(
        fontFamily: 'Segoe UI',
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
  OutlineInputBorder fieldBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );
  return base.copyWith(
    scaffoldBackgroundColor: colors.surface,
    visualDensity: VisualDensity.compact,
    textTheme: base.textTheme.copyWith(
      headlineSmall: base.textTheme.headlineSmall!.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -.8,
      ),
      titleLarge: base.textTheme.titleLarge!.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -.4,
      ),
      titleMedium: base.textTheme.titleMedium!.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
      labelLarge: base.textTheme.labelLarge!.copyWith(
        fontWeight: FontWeight.w700,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: buttons),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: buttons.copyWith(
        backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerLowest),
        side: WidgetStatePropertyAll(BorderSide(color: colors.outlineVariant)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: buttons.copyWith(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        shape: shape,
        animationDuration: motion,
        minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        iconSize: const WidgetStatePropertyAll(20),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: colors.surfaceContainerLowest,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      isDense: true,
      filled: true,
      fillColor: colors.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: fieldBorder(colors.outlineVariant),
      enabledBorder: fieldBorder(colors.outlineVariant),
      focusedBorder: fieldBorder(colors.primary, 2),
      errorBorder: fieldBorder(colors.error),
      focusedErrorBorder: fieldBorder(colors.error, 2),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide.none,
      labelStyle: TextStyle(
        fontFamily: 'Segoe UI',
        color: colors.onSecondaryContainer,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: colors.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 6),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    tabBarTheme: TabBarThemeData(
      indicator: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: Colors.transparent,
      labelColor: colors.onSecondaryContainer,
      unselectedLabelColor: colors.onSurfaceVariant,
      labelStyle: const TextStyle(
        fontFamily: 'Segoe UI',
        fontWeight: FontWeight.w700,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dividerTheme: DividerThemeData(
      color: colors.outlineVariant.withValues(alpha: .6),
    ),
  );
}
