import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:bisawtak/config/constants.dart';

/// TEMPORARY remote logger that fires-and-forgets short tagged messages to
/// the backend `/diag/log` endpoint so we can SEE what the device is doing
/// during the share-intent flow without needing Console.app + a cable.
///
/// REMOVE this file (and the diag endpoint + its callers) once the share
/// bug is closed. Each message also goes to `dart:developer.log` so local
/// debugging still works.
class RemoteLogger {
  RemoteLogger._();

  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 4);

  /// Fire-and-forget. Never throws. Logs locally even if the network fails.
  static void log(String tag, String message) {
    developer.log(message, name: tag);
    unawaited(_post(tag, message));
  }

  static Future<void> _post(String tag, String message) async {
    try {
      final uri = Uri.parse('${AppConstants.apiBaseUrl}/diag/log');
      final req = await _client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      // Truncate aggressively to respect the backend's 500-char cap.
      final safeTag = tag.length > 40 ? tag.substring(0, 40) : tag;
      final safeMsg = message.length > 480 ? '${message.substring(0, 480)}…' : message;
      req.write(
        '{"tag":${_jsonString(safeTag)},"msg":${_jsonString(safeMsg)}}',
      );
      final resp = await req.close().timeout(const Duration(seconds: 5));
      await resp.drain<void>();
    } catch (_) {
      // Diag logs are best-effort; swallow all errors so they never disrupt
      // user-facing flows.
    }
  }

  static String _jsonString(String s) {
    final escaped = s
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
    return '"$escaped"';
  }
}
