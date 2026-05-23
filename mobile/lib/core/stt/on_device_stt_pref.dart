import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-controlled toggle. Layered on top of [AppConstants.onDeviceSttEnabled]
/// (the build-time kill switch). Both must be true for on-device to be tried.
///
/// We keep this as a StateNotifier so the settings screen can toggle it and
/// the home screen reacts immediately on next recording without rebuild.
/// SharedPreferences key. Public so other layers (orchestrator) can read
/// the value directly without needing a Riverpod scope.
const String onDeviceSttPrefsKey = 'on_device_stt_enabled';

class OnDeviceSttPrefNotifier extends StateNotifier<bool> {
  OnDeviceSttPrefNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(onDeviceSttPrefsKey) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(onDeviceSttPrefsKey, value);
  }
}

final onDeviceSttPrefProvider =
    StateNotifierProvider<OnDeviceSttPrefNotifier, bool>((ref) {
  return OnDeviceSttPrefNotifier();
});
