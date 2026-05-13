import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// Wraps a [child] and renders a thin offline banner at the top
/// whenever device connectivity is lost.
class ConnectivityBanner extends StatefulWidget {
  final Widget child;
  const ConnectivityBanner({super.key, required this.child});

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner> {
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _check();
    _sub = Connectivity().onConnectivityChanged.listen(_handle);
  }

  Future<void> _check() async {
    try {
      final result = await Connectivity().checkConnectivity();
      _handle(result);
    } catch (_) {
      // If the plugin fails, assume online so we don't false-flag.
    }
  }

  void _handle(List<ConnectivityResult> results) {
    final offline = results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    if (offline != _offline && mounted) {
      setState(() => _offline = offline);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: _offline ? 28 : 0,
          color: scheme.error,
          alignment: Alignment.center,
          child: _offline
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off, color: scheme.onError, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'لا يوجد اتصال بالإنترنت',
                      style: TextStyle(
                        color: scheme.onError,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              : null,
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}

/// Helper that returns whether the device currently has connectivity.
Future<bool> hasInternetConnection() async {
  try {
    final results = await Connectivity().checkConnectivity();
    return results.isNotEmpty && results.any((r) => r != ConnectivityResult.none);
  } catch (_) {
    return true; // Best-effort; don't block users on plugin failure.
  }
}
