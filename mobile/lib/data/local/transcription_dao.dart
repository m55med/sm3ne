import 'package:sqflite/sqflite.dart';

import 'package:bisawtak/data/local/database.dart';
import 'package:bisawtak/data/models/transcription.dart';

class TranscriptionDao {
  Future<int> insert(Transcription t) async {
    final db = await LocalDatabase.instance;
    return db.insert('transcriptions', t.toMap());
  }

  /// Re-inserts a previously-deleted [Transcription] preserving its
  /// original row id. Used by the Undo action on the result screen so the
  /// restored row keeps its identity (matters for callers that already hold
  /// the id, e.g. open detail screens, deep links).
  Future<int> insertWithId(Transcription t) async {
    if (t.id == null) {
      return insert(t);
    }
    final db = await LocalDatabase.instance;
    final map = t.toMap()..['id'] = t.id;
    // ConflictAlgorithm.replace resolves a PRIMARY KEY (id) clash, but NOT the
    // UNIQUE(server_request_id) index added in v3. If a background history-sync
    // re-inserted a row with this server_request_id during the Undo window, a
    // plain insert here would throw. Clear any colliding row first, in a single
    // transaction, so Undo always restores the row with its original id.
    return db.transaction((txn) async {
      final sid = t.serverRequestId;
      if (sid != null) {
        await txn.delete(
          'transcriptions',
          where: 'server_request_id = ? AND id != ?',
          whereArgs: [sid, t.id],
        );
      }
      return txn.insert(
        'transcriptions',
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<List<Transcription>> getAll() async {
    final db = await LocalDatabase.instance;
    final maps = await db.query('transcriptions', orderBy: 'created_at DESC');
    return maps.map(Transcription.fromMap).toList();
  }

  Future<List<Transcription>> search(String query) async {
    final db = await LocalDatabase.instance;
    final maps = await db.query(
      'transcriptions',
      where: 'text LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'created_at DESC',
    );
    return maps.map(Transcription.fromMap).toList();
  }

  Future<Transcription?> getById(int id) async {
    final db = await LocalDatabase.instance;
    final maps = await db.query('transcriptions', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Transcription.fromMap(maps.first);
  }

  Future<int> delete(int id) async {
    final db = await LocalDatabase.instance;
    return db.delete('transcriptions', where: 'id = ?', whereArgs: [id]);
  }

  /// Persists the cached Arabic [translation] for a row so re-opening the
  /// result reuses it instead of calling (and re-charging) the translate API.
  Future<int> updateTranslation(int id, String translation) async {
    final db = await LocalDatabase.instance;
    return db.update(
      'transcriptions',
      {'translation': translation},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Removes every locally cached transcription. Used on logout / account
  /// switch to prevent the next user from seeing the previous user's data.
  Future<int> deleteAll() async {
    final db = await LocalDatabase.instance;
    return db.delete('transcriptions');
  }

  Future<int> count() async {
    final db = await LocalDatabase.instance;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM transcriptions');
    return result.first['count'] as int;
  }

  /// Returns the set of `server_request_id` values already present locally.
  /// Used by history-sync to skip rows the device already has (whether the
  /// row was created on this device or restored on a previous sync), so a
  /// restored metadata-only row never shadows a full local row that has the
  /// real transcript text.
  Future<Set<int>> existingServerRequestIds() async {
    final db = await LocalDatabase.instance;
    final maps = await db.query(
      'transcriptions',
      columns: ['server_request_id'],
      where: 'server_request_id IS NOT NULL',
    );
    return maps
        .map((m) => m['server_request_id'] as int?)
        .whereType<int>()
        .toSet();
  }

  /// Inserts history rows pulled from the server, skipping any whose
  /// `server_request_id` already exists locally. Runs in a single transaction
  /// and returns the number of rows actually inserted. Insert conflicts on the
  /// unique `server_request_id` index are ignored as a belt-and-suspenders
  /// guard against races with a concurrent live transcription.
  Future<int> mergeHistory(List<Transcription> rows) async {
    if (rows.isEmpty) return 0;
    final db = await LocalDatabase.instance;
    final existing = await existingServerRequestIds();
    var inserted = 0;
    await db.transaction((txn) async {
      for (final t in rows) {
        final sid = t.serverRequestId;
        if (sid == null || existing.contains(sid)) continue;
        await txn.insert(
          'transcriptions',
          t.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        existing.add(sid);
        inserted++;
      }
    });
    return inserted;
  }
}
