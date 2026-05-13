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
    return db.insert(
      'transcriptions',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
}
