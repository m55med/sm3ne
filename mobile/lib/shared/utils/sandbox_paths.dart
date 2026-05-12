import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Returns true when [path] resolves inside one of the app's sandbox
/// directories (temporary, documents, support, or — on iOS — the shared
/// app-group container). Used to guard file paths received from deep links
/// or "Open with" intents against path-traversal attacks.
Future<bool> isPathInsideSandbox(String path) async {
  if (path.isEmpty) return false;

  // Reject any path containing a `..` segment.
  final normalized = p.normalize(path);
  final segments = p.split(normalized);
  if (segments.contains('..') || normalized.contains('..')) return false;

  final bases = <String>[];
  try {
    final tmp = await getTemporaryDirectory();
    bases.add(tmp.path);
  } catch (_) {}
  try {
    final docs = await getApplicationDocumentsDirectory();
    bases.add(docs.path);
  } catch (_) {}
  try {
    final supp = await getApplicationSupportDirectory();
    bases.add(supp.path);
  } catch (_) {}
  if (Platform.isIOS) {
    try {
      final cache = await getApplicationCacheDirectory();
      bases.add(cache.path);
    } catch (_) {}
    try {
      final libs = await getLibraryDirectory();
      bases.add(libs.path);
    } catch (_) {}
  }

  for (final base in bases) {
    final normalizedBase = p.normalize(base);
    if (p.isWithin(normalizedBase, normalized) ||
        p.equals(normalizedBase, normalized) ||
        normalized.startsWith(normalizedBase)) {
      return true;
    }
  }
  return false;
}

/// Allowed audio file extensions for share/open-with paths (lower-case, no dot).
const Set<String> kAllowedSharedAudioExtensions = {
  'm4a',
  'mp3',
  'wav',
  'ogg',
  'opus',
  'aac',
  'flac',
  'webm',
  'mp4',
};

bool hasAllowedAudioExtension(String path) {
  final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
  return kAllowedSharedAudioExtensions.contains(ext);
}
