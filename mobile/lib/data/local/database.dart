import 'dart:async';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// App-wide singleton wrapper around the local sqflite database.
///
/// Uses a `Completer<Database>` lock to guarantee a single concurrent
/// `_init` call even when [instance] is awaited from multiple isolates of
/// async code at the same time (e.g. the first frame + a deep-link DAO call).
class LocalDatabase {
  static Completer<Database>? _pending;

  static Future<Database> get instance async {
    final existing = _pending;
    if (existing != null) return existing.future;

    final completer = Completer<Database>();
    _pending = completer;
    try {
      final db = await _init();
      completer.complete(db);
      return db;
    } catch (e, s) {
      completer.completeError(e, s);
      // Reset so a future call can retry init after a failure.
      _pending = null;
      rethrow;
    }
  }

  static Future<Database> _init() async {
    final path = join(await getDatabasesPath(), 'bisawtak.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE transcriptions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            server_request_id INTEGER,
            text TEXT NOT NULL,
            language TEXT,
            language_name TEXT,
            duration REAL,
            word_count INTEGER,
            char_count INTEGER,
            was_trimmed INTEGER DEFAULT 0,
            segments_json TEXT,
            source TEXT DEFAULT 'uploaded',
            source_app TEXT,
            original_filename TEXT,
            created_at TEXT NOT NULL,
            provider_used TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 → v2: track which engine produced each row so the UI can show
        // "via server" vs "on-device" and so we know what to migrate later.
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE transcriptions ADD COLUMN provider_used TEXT",
          );
        }
      },
    );
  }
}
