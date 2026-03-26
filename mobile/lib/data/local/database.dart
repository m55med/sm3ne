import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDatabase {
  static Database? _db;

  static Future<Database> get instance async {
    _db ??= await _init();
    return _db!;
  }

  static Future<Database> _init() async {
    final path = join(await getDatabasesPath(), 'bisawtak.db');
    return openDatabase(
      path,
      version: 1,
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
            created_at TEXT NOT NULL
          )
        ''');
      },
    );
  }
}
