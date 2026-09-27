import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/sos_packet.dart';

class SosDatabase {
  SosDatabase._();

  static final SosDatabase instance = SosDatabase._();
  static Database? _database;

  static Future<void> _ensureInitialized() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  Future<Database> get database async {
    await _ensureInitialized();
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'crisismesh.db');

    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sos_outbox (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            message TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            voiceTranscript TEXT,
            latitude REAL,
            longitude REAL,
            photoPath TEXT,
            deviceId TEXT NOT NULL,
            relayMode TEXT NOT NULL,
            status TEXT NOT NULL,
            clientEventId TEXT,
            retryCount INTEGER NOT NULL DEFAULT 0,
            lastAttemptAt TEXT,
            remoteId INTEGER
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE sos_outbox ADD COLUMN clientEventId TEXT');
          await db.execute(
            'ALTER TABLE sos_outbox ADD COLUMN retryCount INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute('ALTER TABLE sos_outbox ADD COLUMN lastAttemptAt TEXT');
          await db.execute('ALTER TABLE sos_outbox ADD COLUMN remoteId INTEGER');
          await db.update(
            'sos_outbox',
            {'status': 'pending'},
            where: 'status = ?',
            whereArgs: ['queued'],
          );
        }
      },
    );
  }

  Future<int> insertPacket(SosPacket packet) async {
    final db = await database;
    final rowId = await db.insert(
      'sos_outbox',
      packet.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return rowId;
  }

  Future<List<SosPacket>> fetchPendingPackets() async {
    final db = await database;
    final rows = await db.query(
      'sos_outbox',
      where: 'status IN (?, ?)',
      whereArgs: ['pending', 'failed'],
      orderBy: 'createdAt ASC',
    );

    return rows.map(SosPacket.fromDbMap).toList();
  }

  Future<void> resetSendingPackets() async {
    final db = await database;
    await db.update(
      'sos_outbox',
      {'status': 'pending'},
      where: 'status = ?',
      whereArgs: ['sending'],
    );
  }

  Future<SosPacket> markSending(SosPacket packet) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    final retryCount = packet.retryCount + 1;
    await db.update(
      'sos_outbox',
      {
        'status': 'sending',
        'retryCount': retryCount,
        'lastAttemptAt': now,
      },
      where: 'id = ?',
      whereArgs: [packet.id],
    );
    return packet.copyWith(
      status: 'sending',
      retryCount: retryCount,
      lastAttemptAt: now,
    );
  }

  Future<void> markSent(int id, {int? remoteId}) async {
    final db = await database;
    await db.update(
      'sos_outbox',
      {'status': 'sent', 'remoteId': remoteId},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markFailed(int id) async {
    final db = await database;
    await db.update(
      'sos_outbox',
      {'status': 'failed'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
