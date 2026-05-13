import 'package:flutter/material.dart';

/// Centralized design tokens for the Bisawtak app.
///
/// All spacing, radii, elevations, durations and semantic brand colors must
/// be consumed from these classes rather than hardcoded in widgets. This is
/// the single source of truth — change a value here and the whole app
/// follows.

class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

class AppRadius {
  AppRadius._();
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;
}

class AppElevation {
  AppElevation._();
  static const double flat = 0;
  static const double card = 1;
  static const double raised = 2;
  static const double modal = 8;
}

class AppDuration {
  AppDuration._();
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 300);
}

/// Brand-level semantic colors injected as a `ThemeExtension`. Read via
/// `Theme.of(context).extension<BrandColors>()!.recordingRed` so they
/// switch correctly between light and dark.
@immutable
class BrandColors extends ThemeExtension<BrandColors> {
  final Color recordingRed;
  final Color successGreen;
  final Color warningAmber;
  final Color discountBadge;
  final Color infoBlue;
  final Color premiumGold;

  const BrandColors({
    required this.recordingRed,
    required this.successGreen,
    required this.warningAmber,
    required this.discountBadge,
    required this.infoBlue,
    required this.premiumGold,
  });

  static const BrandColors light = BrandColors(
    recordingRed: Color(0xFFE53935),
    successGreen: Color(0xFF2ECC71),
    warningAmber: Color(0xFFFFA000),
    discountBadge: Color(0xFFD32F2F),
    infoBlue: Color(0xFF1976D2),
    premiumGold: Color(0xFFF9A825),
  );

  static const BrandColors dark = BrandColors(
    recordingRed: Color(0xFFEF5350),
    successGreen: Color(0xFF4CDB8B),
    warningAmber: Color(0xFFFFB74D),
    discountBadge: Color(0xFFEF5350),
    infoBlue: Color(0xFF64B5F6),
    premiumGold: Color(0xFFFFD54F),
  );

  @override
  BrandColors copyWith({
    Color? recordingRed,
    Color? successGreen,
    Color? warningAmber,
    Color? discountBadge,
    Color? infoBlue,
    Color? premiumGold,
  }) {
    return BrandColors(
      recordingRed: recordingRed ?? this.recordingRed,
      successGreen: successGreen ?? this.successGreen,
      warningAmber: warningAmber ?? this.warningAmber,
      discountBadge: discountBadge ?? this.discountBadge,
      infoBlue: infoBlue ?? this.infoBlue,
      premiumGold: premiumGold ?? this.premiumGold,
    );
  }

  @override
  BrandColors lerp(ThemeExtension<BrandColors>? other, double t) {
    if (other is! BrandColors) return this;
    return BrandColors(
      recordingRed: Color.lerp(recordingRed, other.recordingRed, t)!,
      successGreen: Color.lerp(successGreen, other.successGreen, t)!,
      warningAmber: Color.lerp(warningAmber, other.warningAmber, t)!,
      discountBadge: Color.lerp(discountBadge, other.discountBadge, t)!,
      infoBlue: Color.lerp(infoBlue, other.infoBlue, t)!,
      premiumGold: Color.lerp(premiumGold, other.premiumGold, t)!,
    );
  }
}

/// Convenience extension so widgets can write `context.brand.recordingRed`
/// instead of the verbose lookup.
extension BrandColorsX on BuildContext {
  BrandColors get brand =>
      Theme.of(this).extension<BrandColors>() ?? BrandColors.light;
}

/// Returns the chevron icon that points "forward" relative to the current
/// reading direction — `chevron_left` in RTL, `chevron_right` in LTR.
/// Flutter does not auto-mirror these glyphs.
IconData forwardChevron(BuildContext context) {
  return Directionality.of(context) == TextDirection.rtl
      ? Icons.chevron_left
      : Icons.chevron_right;
}
