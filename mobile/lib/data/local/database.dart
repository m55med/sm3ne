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
      version: 4,
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
            provider_used TEXT,
            is_restored INTEGER DEFAULT 0,
            translation TEXT
          )
        ''');
        // Unique index on server_request_id so history-sync can upsert rows
        // pulled from the server without ever creating duplicates of a row
        // the device already has. NULL request ids (offline on-device rows
        // whose /transcriptions/log call failed) are exempt — SQLite treats
        // multiple NULLs as distinct in a UNIQUE index, which is what we want.
        await db.execute(
          'CREATE UNIQUE INDEX idx_txn_server_request_id '
          'ON transcriptions(server_request_id) '
          'WHERE server_request_id IS NOT NULL',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 → v2: track which engine produced each row so the UI can show
        // "via server" vs "on-device" and so we know what to migrate later.
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE transcriptions ADD COLUMN provider_used TEXT",
          );
        }
        // v2 → v3: history sync. `is_restored` flags rows rebuilt from the
        // server's metadata-only history (no transcript text) after a
        // reinstall, plus a unique index so the sync can upsert safely.
        if (oldVersion < 3) {
          await db.execute(
            "ALTER TABLE transcriptions ADD COLUMN is_restored INTEGER DEFAULT 0",
          );
          // CRITICAL: v2 never constrained server_request_id, so an existing
          // DB can legitimately hold duplicate non-null ids (a re-logged share,
          // an insert retried across an app kill, etc.). Creating the UNIQUE
          // index on top of duplicates would THROW, aborting the migration and
          // making openDatabase fail on every subsequent launch — the user's
          // entire local history would become permanently inaccessible. So we
          // de-dupe FIRST, keeping the richest row per id (longest text wins,
          // tie-broken by the smallest/oldest id) before adding the index.
          await db.execute('''
            DELETE FROM transcriptions
            WHERE server_request_id IS NOT NULL
              AND id NOT IN (
                SELECT id FROM transcriptions t
                WHERE t.server_request_id IS NOT NULL
                  AND NOT EXISTS (
                    SELECT 1 FROM transcriptions o
                    WHERE o.server_request_id = t.server_request_id
                      AND (
                        length(COALESCE(o.text, '')) > length(COALESCE(t.text, ''))
                        OR (length(COALESCE(o.text, '')) = length(COALESCE(t.text, ''))
                            AND o.id < t.id)
                      )
                  )
              )
          ''');
          await db.execute(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_txn_server_request_id '
            'ON transcriptions(server_request_id) '
            'WHERE server_request_id IS NOT NULL',
          );
        }
        // v3 → v4: cache the on-demand Arabic translation so re-opening a result
        // never re-charges a daily credit.
        if (oldVersion < 4) {
          await db.execute(
            "ALTER TABLE transcriptions ADD COLUMN translation TEXT",
          );
        }
      },
    );
  }
}
