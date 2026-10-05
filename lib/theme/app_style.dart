// ─────────────────────────────────────────────────────────────────────────
// HarBest design system — the ONE place that defines how the app looks.
//
// Change a value here and every page that uses it changes with it.
// Pages should never type a hex color, a font size, an icon or a corner
// radius directly: use AppColors / AppText / AppIcons / AppRadius / AppSpace.
// ─────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;

// ── COLORS ──
class AppColors {
  AppColors._();

  // Brand
  static const Color green = Color(0xFF7CB342);
  static const Color darkGreen = Color(0xFF445E29);
  static const Color deepGreen = Color(0xFF2D460E);
  static const Color navSelected = Color(0xFF0F1F04);

  // Surfaces
  static const Color background = Color(0xFFF2F2F7); // iOS grouped gray
  static const Color card = Colors.white;
  static const Color track = Color(0xFFE5E5EA); // empty bar / ring track
  static const Color outline = Color(0xFFE5E5EA);
  static const Color emphasisOutline = Color(0xFF676B62);
  static const Color divider = Color(0xFFE0E0E0);
  static const Color rowBackground = Color(0xFFF9F9F9); // expanded list rows

  // Text
  static const Color textPrimary = Colors.black87;
  static const Color textSecondary = Colors.black54;
  static const Color textTertiary = Colors.black45;
  static const Color onGreen = Colors.white;

  // Status
  static const Color optimal = Color(0xFF388E3C);
  static const Color healthy = Color(0xFF2E7D32);
  static const Color caution = Color(0xFFF9A825);
  static const Color critical = Color(0xFFD32F2F);
  static const Color destructive = Color(0xFFD32F2F);
  static const Color info = Color(0xFF1976D2);

  // Sign-in / sign-up screens (dark green background)
  static const Color authBackground = Color(0xFF2D5A27);
  static const Color authField = Color(0xFFD9D9D9); // text field fill
  static const Color fieldLight = Color(0xFFEDEDED); // text field on light pages
  static const Color authAccent = Color(0xFF7DB343); // links, button start
  static const Color authAccentDark = Color(0xFF4C7A2D); // button end
  static const Color onDarkError = Color(0xFFFF5252); // red text on dark green
  static const Color onDarkSuccess = Color(0xFF69F0AE); // green text on dark green
  static const Color disabledStart = Color(0xFFBDBDBD); // inactive button
  static const Color disabledEnd = Color(0xFF757575);
  static const Color brandOnDark = Color(0xFF619A32); // "HarBest" name on dark green
}

// ── SIZES ──
class AppRadius {
  AppRadius._();
  static const double card = 16;
  static const double button = 12;
  static const double field = 12;
  static const double dialog = 20;
  static const double header = 30;
  static const double snack = 14;
}

class AppSpace {
  AppSpace._();
  static const double page = 20; // left/right margin of every page
  static const double gap = 12; // between cards
  static const double section = 25; // between sections
  static const double cardGap = 16; // between stacked full-width cards
}

// ── SHADOWS ──
class AppShadows {
  AppShadows._();
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 2)),
  ];
}

// ── TEXT ──
class AppText {
  AppText._();

  // Title inside the green header
  static const TextStyle headerTitle = TextStyle(
    color: AppColors.onGreen,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );

  // Big heading of a section ("Sensor Overview")
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: AppColors.textPrimary,
  );

  // Title inside a content card ("Sensor Correlations")
  static const TextStyle cardTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: AppColors.textPrimary,
  );

  static const TextStyle subtitle = TextStyle(
    fontSize: 13,
    color: AppColors.textSecondary,
  );

  // Normal text inside rows and cards
  static const TextStyle body = TextStyle(
    fontSize: 15,
    color: AppColors.textPrimary,
  );

  static const TextStyle label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 11,
    color: AppColors.textTertiary,
  );

  // Sign-in / sign-up screens
  static const TextStyle authTitle = TextStyle(
    color: AppColors.onGreen,
    fontSize: 30,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle authSubtitle = TextStyle(
    color: Colors.white70,
    fontSize: 15,
  );

  static const TextStyle authBody = TextStyle(
    color: Color(0xD9FFFFFF), // white 85%
    fontSize: 15,
    height: 1.5,
  );
  static const TextStyle authHint = TextStyle(
    color: Color(0x99FFFFFF), // white 60%
    fontSize: 13,
    height: 1.5,
  );
  static const TextStyle onDarkMuted = TextStyle(
    color: Color(0xB3FFFFFF), // white 70%
    fontSize: 14,
  );

  static const TextStyle onDark = TextStyle(color: AppColors.onGreen);

  static const TextStyle onDarkUnderline = TextStyle(
    color: AppColors.onGreen,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    decoration: TextDecoration.underline,
    decorationColor: AppColors.onGreen,
    decorationThickness: 1.5,
  );

  // Welcome (landing) screen
  static const TextStyle welcomeBrand = TextStyle(
    color: AppColors.brandOnDark,
    fontSize: 30,
    fontWeight: FontWeight.bold,
    letterSpacing: 1.5,
  );
  static const TextStyle welcomeHeadline = TextStyle(
    color: AppColors.onGreen,
    fontSize: 42,
    fontWeight: FontWeight.w900,
  );
  static const TextStyle welcomeBody = TextStyle(
    color: Colors.white70,
    fontSize: 16,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle onDarkLink = TextStyle(
    color: AppColors.authAccent,
    fontWeight: FontWeight.bold,
    decoration: TextDecoration.underline,
    decorationColor: AppColors.authAccent,
    decorationThickness: 1.5,
  );

  static const TextStyle button = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );
}

// ── ICONS ──
// Every icon in the app comes from here, so "alerts" or "temperature" is the
// same icon on every page. To change one, change it here only.
class AppIcons {
  AppIcons._();

  // Navigation
  static const IconData home = CupertinoIcons.house_fill;
  static const IconData analytics = CupertinoIcons.chart_bar_alt_fill;
  static const IconData plant = CupertinoIcons.leaf_arrow_circlepath;
  static const IconData insights = CupertinoIcons.create_solid;
  static const IconData alerts = CupertinoIcons.bell_fill;

  // Actions
  static const IconData back = CupertinoIcons.chevron_back;
  static const IconData forward = CupertinoIcons.chevron_right;
  static const IconData expand = CupertinoIcons.chevron_down;
  static const IconData account = CupertinoIcons.person_crop_circle;
  static const IconData logout = CupertinoIcons.square_arrow_right;
  static const IconData lock = CupertinoIcons.lock;
  static const IconData shield = CupertinoIcons.shield;
  static const IconData refresh = CupertinoIcons.arrow_clockwise;
  static const IconData offline = CupertinoIcons.wifi_slash;
  static const IconData edit = CupertinoIcons.pencil;

  // Snack bar / feedback
  static const IconData success = CupertinoIcons.check_mark_circled_solid;
  static const IconData error = CupertinoIcons.exclamationmark_circle_fill;
  static const IconData info = CupertinoIcons.info_circle_fill;

  // Sensors
  static const IconData soilPh = CupertinoIcons.lab_flask;
  static const IconData moisture = CupertinoIcons.drop_fill;
  static const IconData temperature = CupertinoIcons.thermometer;
  static const IconData humidity = CupertinoIcons.cloud_drizzle_fill;
  static const IconData heatIndex = CupertinoIcons.sun_max_fill;
  static const IconData conductivity = CupertinoIcons.bolt_fill;
  static const IconData nitrogen = CupertinoIcons.circle_grid_hex_fill;
  static const IconData phosphorus = CupertinoIcons.largecircle_fill_circle;
  static const IconData potassium = CupertinoIcons.staroflife_fill;

  // growth stages + plant profile
  static const IconData growthGermination = CupertinoIcons.circle_grid_3x3_fill;
  static const IconData growthSeedling = CupertinoIcons.sunrise_fill;
  static const IconData growthVegetative = CupertinoIcons.tree;
  static const IconData growthHarvest = CupertinoIcons.scissors;
  static const IconData growthBolting = CupertinoIcons.sparkles;
  static const IconData timeline = CupertinoIcons.timelapse;
  static const IconData warning = CupertinoIcons.exclamationmark_triangle_fill;
  static const IconData tip = CupertinoIcons.lightbulb;
  static const IconData alertsOff = CupertinoIcons.bell_slash_fill;

  // forms
  static const IconData visible = CupertinoIcons.eye;
  static const IconData hidden = CupertinoIcons.eye_slash;
  static const IconData check = CupertinoIcons.check_mark_circled;
  static const IconData cancel = CupertinoIcons.xmark_circle_fill;
  static const IconData unchecked = CupertinoIcons.circle;
  static const IconData emailUnread = CupertinoIcons.envelope_badge;
  static const IconData photo = CupertinoIcons.photo;
  static const IconData close = CupertinoIcons.xmark;

  // account page
  static const IconData profile = CupertinoIcons.person_fill;
  static const IconData security = CupertinoIcons.lock_fill;
  static const IconData notifications = CupertinoIcons.bell_fill;
  static const IconData twoFactor = CupertinoIcons.shield_lefthalf_fill;
  static const IconData help = CupertinoIcons.question_circle_fill;
  static const IconData terms = CupertinoIcons.doc_text_fill;
  static const IconData aboutUs = CupertinoIcons.info_circle_fill;
  static const IconData mail = CupertinoIcons.mail;
  static const IconData phone = CupertinoIcons.phone_fill;
  static const IconData feedback = CupertinoIcons.chat_bubble_text_fill;
  static const IconData verified = CupertinoIcons.checkmark_seal_fill;
  static const IconData delete = CupertinoIcons.trash_fill;
}

// ── HEALTH LEVEL (Optimal / Caution / Critical) ──
// One definition of the three states, so a "Critical" tag is the same red,
// with the same wording, on every page.
enum HealthLevel { optimal, caution, critical }

extension HealthLevelX on HealthLevel {
  String get label => switch (this) {
        HealthLevel.optimal => 'Optimal',
        HealthLevel.caution => 'Caution',
        HealthLevel.critical => 'Critical',
      };

  Color get color => switch (this) {
        HealthLevel.optimal => AppColors.optimal,
        HealthLevel.caution => AppColors.caution,
        HealthLevel.critical => AppColors.critical,
      };
}

// ── APP THEME ──
// Used by MaterialApp in main.dart. Controls everything Flutter draws by
// default (dialogs, snack bars, text fields, buttons, transitions).
class AppTheme {
  AppTheme._();

  static ThemeData light() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.green),
      useMaterial3: true,
      fontFamily: 'Arial',
      scaffoldBackgroundColor: AppColors.background,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.snack),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
      ),
      // Flutter 3.27+ (CardThemeData / DialogThemeData)
      cardTheme: CardThemeData(
        color: AppColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 1.5,
        shadowColor: const Color(0x26000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.dialog),
        ),
      ),
      // Flutter 3.35+ (InputDecorationThemeData)
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: AppColors.card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: const BorderSide(color: AppColors.green, width: 1.5),
        ),
      ),
    );
  }
}

// iOS-style scrolling for every scrollable page: rubber-band bounce, and no
// Android glow/stretch effect on top of it.
class IosScrollBehavior extends MaterialScrollBehavior {
  const IosScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;
}