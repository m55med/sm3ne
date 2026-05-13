import 'package:flutter/services.dart';

/// Centralized haptic-feedback helpers so the entire app emits consistent
/// intensities for the same kind of event. Using these wrappers keeps the
/// vocabulary intentional — every call site says "what happened" rather
/// than picking an `HapticFeedback.*` flavor ad-hoc.
class Haptics {
  Haptics._();

  /// Light tap — neutral confirmation (button press, simple toggle).
  static Future<void> tap() => HapticFeedback.lightImpact();

  /// Distinct success cue — copy, share, save, redeem coupon.
  static Future<void> success() => HapticFeedback.mediumImpact();

  /// Heavier cue for destructive or boundary actions — delete, logout,
  /// long-press menus.
  static Future<void> heavy() => HapticFeedback.heavyImpact();

  /// Error cue — validation failed, network down, permission denied.
  static Future<void> error() => HapticFeedback.vibrate();

  /// Selection-style cue — picking an item from a list or slider tick.
  static Future<void> selection() => HapticFeedback.selectionClick();
}
