import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Local SQLite queue for stock movements — factory-floor connectivity is
/// unreliable, so a movement is written here first (always succeeds
/// instantly) and synced to Supabase in the background. Visible live in
/// Android Studio's Database Inspector while the app runs.
///
/// sqflite only ships a native implementation for Android/iOS — every
/// method here is a no-op on web/desktop instead of throwing, so testing on
/// those platforms still works, just without the offline queue.
class StockOfflineQueueService {
  static Database? _db;

  bool get _supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<Database> get _database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'stock_offline_queue.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) => db.execute('''
        CREATE TABLE pending_movements (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          stock_id INTEGER NOT NULL,
          movement_type TEXT NOT NULL,
          quantity INTEGER NOT NULL,
          movement_date TEXT NOT NULL,
          note TEXT,
          created_at TEXT NOT NULL,
          synced INTEGER NOT NULL DEFAULT 0
        )
      '''),
    );
  }

  Future<int> enqueue({
    required int stockId,
    required String movementType,
    required int quantity,
    required DateTime movementDate,
    String? note,
  }) async {
    if (!_supported) return -1;
    final db = await _database;
    return db.insert('pending_movements', {
      'stock_id': stockId,
      'movement_type': movementType,
      'quantity': quantity,
      'movement_date': movementDate.toIso8601String().substring(0, 10),
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
      'synced': 0,
    });
  }

  Future<void> markSynced(int id) async {
    if (!_supported || id < 0) return;
    final db = await _database;
    await db.update(
      'pending_movements',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Used when a queued entry turns out to be a real data conflict (e.g.
  // stock would go below zero) rather than a connectivity problem —
  // retrying it forever would never succeed.
  Future<void> remove(int id) async {
    if (!_supported || id < 0) return;
    final db = await _database;
    await db.delete('pending_movements', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, Object?>>> getPending() async {
    if (!_supported) return const [];
    final db = await _database;
    return db.query(
      'pending_movements',
      where: 'synced = 0',
      orderBy: 'created_at ASC',
    );
  }

  Future<int> pendingCount() async {
    if (!_supported) return 0;
    final db = await _database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM pending_movements WHERE synced = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
