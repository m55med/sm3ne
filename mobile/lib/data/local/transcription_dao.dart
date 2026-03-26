import 'package:bisawtak/data/local/database.dart';
import 'package:bisawtak/data/models/transcription.dart';

class TranscriptionDao {
  Future<int> insert(Transcription t) async {
    final db = await LocalDatabase.instance;
    return db.insert('transcriptions', t.toMap());
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

  Future<int> count() async {
    final db = await LocalDatabase.instance;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM transcriptions');
    return result.first['count'] as int;
  }
}
