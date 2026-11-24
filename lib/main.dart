import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

// =============================================================================
// 1. DATA MODELS
// =============================================================================

class InventoryItem {
  final String id;
  final String name;
  final double price;
  final int stock;
  final int lowStockThreshold;

  InventoryItem({
    required this.id,
    required this.name,
    required this.price,
    required this.stock,
    required this.lowStockThreshold,
  });

  bool get isLowStock => stock <= lowStockThreshold;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'price': price,
        'stock': stock,
        'lowStockThreshold': lowStockThreshold,
      };

  factory InventoryItem.fromMap(Map<String, dynamic> data, [String? docId]) {
    return InventoryItem(
      id: docId ?? data['id'] ?? const Uuid().v4(),
      name: data['name'] ?? '',
      price: (data['price'] ?? 0).toDouble(),
      stock: (data['stock'] ?? 0).toInt(),
      lowStockThreshold: (data['lowStockThreshold'] ?? 5).toInt(),
    );
  }

  factory InventoryItem.fromDoc(DocumentSnapshot doc) {
    final raw = doc.data();
    final data =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return InventoryItem.fromMap(data, doc.id);
  }
}

class AttachedItem {
  final String itemId;
  final String name;
  final double price;
  final int qty;

  AttachedItem({
    required this.itemId,
    required this.name,
    required this.price,
    required this.qty,
  });

  double get total => price * qty;

  Map<String, dynamic> toMap() => {
        'itemId': itemId,
        'name': name,
        'price': price,
        'qty': qty,
      };

  factory AttachedItem.fromMap(Map<String, dynamic> map) => AttachedItem(
        itemId: map['itemId'] ?? '',
        name: map['name'] ?? '',
        price: (map['price'] ?? 0).toDouble(),
        qty: (map['qty'] ?? 1).toInt(),
      );
}

class ExpenseRecord {
  final String id;
  final String title;
  final double amount;
  final DateTime timestamp;

  ExpenseRecord({
    required this.id,
    required this.title,
    required this.amount,
    required this.timestamp,
  });

  Map<String, dynamic> toMap({bool forLocal = false}) => {
        'id': id,
        'title': title,
        'amount': amount,
        'timestamp': forLocal
            ? timestamp.toIso8601String()
            : Timestamp.fromDate(timestamp),
      };

  factory ExpenseRecord.fromMap(Map<String, dynamic> data, [String? docId]) {
    DateTime parsedTime = DateTime.now();
    final rawTime = data['timestamp'];
    if (rawTime is Timestamp) {
      parsedTime = rawTime.toDate();
    } else if (rawTime is String) {
      parsedTime = DateTime.tryParse(rawTime) ?? DateTime.now();
    }

    return ExpenseRecord(
      id: docId ?? data['id'] ?? const Uuid().v4(),
      title: data['title'] ?? '',
      amount: (data['amount'] ?? 0).toDouble(),
      timestamp: parsedTime,
    );
  }

  factory ExpenseRecord.fromDoc(DocumentSnapshot doc) {
    final raw = doc.data();
    final data =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return ExpenseRecord.fromMap(data, doc.id);
  }
}

class GamingTable {
  final String id;
  final String name;
  final double hourlyRate;
  final String type;
  final String status;
  final DateTime? lastStartTime;
  final int accumulatedSeconds;
  final List<AttachedItem> attachedItems;
  final String guestNotes;

  GamingTable({
    required this.id,
    required this.name,
    required this.hourlyRate,
    this.type = 'gaming',
    required this.status,
    this.lastStartTime,
    required this.accumulatedSeconds,
    required this.attachedItems,
    this.guestNotes = '',
  });

  int get currentElapsedSeconds {
    if (type == 'normal') return 0;
    if (status == 'running' && lastStartTime != null) {
      final diff = DateTime.now().difference(lastStartTime!).inSeconds;
      return accumulatedSeconds + (diff > 0 ? diff : 0);
    }
    return accumulatedSeconds;
  }

  double get currentTimeCost =>
      type == 'normal' ? 0.0 : (currentElapsedSeconds / 3600.0) * hourlyRate;

  double get attachedDrinksCost =>
      attachedItems.fold(0.0, (sum, item) => sum + item.total);

  double get grandTotal => currentTimeCost + attachedDrinksCost;

  String get formattedDuration {
    if (type == 'normal') return 'قعدة عادية';
    final totalSecs = currentElapsedSeconds;
    final hrs = (totalSecs ~/ 3600).toString().padLeft(2, '0');
    final mins = ((totalSecs % 3600) ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSecs % 60).toString().padLeft(2, '0');
    return '$hrs:$mins:$secs';
  }

  Map<String, dynamic> toMap({bool forLocal = false}) => {
        'id': id,
        'name': name,
        'hourlyRate': hourlyRate,
        'type': type,
        'status': status,
        'lastStartTime': lastStartTime == null
            ? null
            : (forLocal
                ? lastStartTime!.toIso8601String()
                : Timestamp.fromDate(lastStartTime!)),
        'accumulatedSeconds': accumulatedSeconds,
        'attachedItems': attachedItems.map((e) => e.toMap()).toList(),
        'guestNotes': guestNotes,
      };

  factory GamingTable.fromMap(Map<String, dynamic> data, [String? docId]) {
    final rawList = data['attachedItems'] as List<dynamic>? ?? [];
    DateTime? parsedStart;
    final rawStart = data['lastStartTime'];
    if (rawStart is Timestamp) {
      parsedStart = rawStart.toDate();
    } else if (rawStart is String) {
      parsedStart = DateTime.tryParse(rawStart);
    }

    return GamingTable(
      id: docId ?? data['id'] ?? const Uuid().v4(),
      name: data['name'] ?? '',
      hourlyRate: (data['hourlyRate'] ?? 0.0).toDouble(),
      type: data['type'] ?? 'gaming',
      status: data['status'] ?? 'idle',
      lastStartTime: parsedStart,
      accumulatedSeconds: (data['accumulatedSeconds'] ?? 0).toInt(),
      attachedItems: rawList
          .map((e) => AttachedItem.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      guestNotes: data['guestNotes'] ?? '',
    );
  }

  factory GamingTable.fromDoc(DocumentSnapshot doc) {
    final raw = doc.data();
    final data =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return GamingTable.fromMap(data, doc.id);
  }
}

class SaleRecord {
  final String id;
  final String type;
  final String label;
  final double timeRevenue;
  final double drinksRevenue;
  final double totalRevenue;
  final int playedSeconds;
  final List<AttachedItem> soldItems;
  final DateTime timestamp;
  final bool isClosed;

  SaleRecord({
    required this.id,
    required this.type,
    this.label = 'فاتورة بيع مباشر',
    required this.timeRevenue,
    required this.drinksRevenue,
    required this.totalRevenue,
    required this.playedSeconds,
    required this.soldItems,
    required this.timestamp,
    this.isClosed = false,
  });

  Map<String, dynamic> toMap({bool forLocal = false}) => {
        'id': id,
        'type': type,
        'label': label,
        'timeRevenue': timeRevenue,
        'drinksRevenue': drinksRevenue,
        'totalRevenue': totalRevenue,
        'playedSeconds': playedSeconds,
        'soldItems': soldItems.map((e) => e.toMap()).toList(),
        'timestamp': forLocal
            ? timestamp.toIso8601String()
            : Timestamp.fromDate(timestamp),
        'isClosed': isClosed,
      };

  factory SaleRecord.fromMap(Map<String, dynamic> data, [String? docId]) {
    final rawItems = data['soldItems'] as List<dynamic>? ?? [];
    DateTime parsedTime = DateTime.now();
    final rawTime = data['timestamp'];
    if (rawTime is Timestamp) {
      parsedTime = rawTime.toDate();
    } else if (rawTime is String) {
      parsedTime = DateTime.tryParse(rawTime) ?? DateTime.now();
    }

    final typeStr = data['type'] ?? 'drinks_only';
    return SaleRecord(
      id: docId ?? data['id'] ?? const Uuid().v4(),
      type: typeStr,
      label: data['label'] ??
          (typeStr == 'drinks_only' ? 'فاتورة بيع مباشر' : 'فاتورة ترابيزة'),
      timeRevenue: (data['timeRevenue'] ?? 0).toDouble(),
      drinksRevenue: (data['drinksRevenue'] ?? 0).toDouble(),
      totalRevenue: (data['totalRevenue'] ?? 0).toDouble(),
      playedSeconds: (data['playedSeconds'] ?? 0).toInt(),
      soldItems: rawItems
          .map((e) => AttachedItem.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      timestamp: parsedTime,
      isClosed: data['isClosed'] ?? false,
    );
  }

  factory SaleRecord.fromDoc(DocumentSnapshot doc) {
    final raw = doc.data();
    final data =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return SaleRecord.fromMap(data, doc.id);
  }
}

class ClosedDaySummary {
  final String id;
  final String dateLabel;
  final double drinksRevenue;
  final double tablesRevenue;
  final double expensesTotal;
  final double grandTotal;
  final DateTime closedAt;

  ClosedDaySummary({
    required this.id,
    required this.dateLabel,
    required this.drinksRevenue,
    required this.tablesRevenue,
    this.expensesTotal = 0.0,
    required this.grandTotal,
    required this.closedAt,
  });

  Map<String, dynamic> toMap({bool forLocal = false}) => {
        'id': id,
        'dateLabel': dateLabel,
        'drinksRevenue': drinksRevenue,
        'tablesRevenue': tablesRevenue,
        'expensesTotal': expensesTotal,
        'grandTotal': grandTotal,
        'closedAt': forLocal
            ? closedAt.toIso8601String()
            : Timestamp.fromDate(closedAt),
      };

  factory ClosedDaySummary.fromMap(Map<String, dynamic> data, [String? docId]) {
    DateTime parsedTime = DateTime.now();
    final rawTime = data['closedAt'];
    if (rawTime is Timestamp) {
      parsedTime = rawTime.toDate();
    } else if (rawTime is String) {
      parsedTime = DateTime.tryParse(rawTime) ?? DateTime.now();
    }

    return ClosedDaySummary(
      id: docId ?? data['id'] ?? const Uuid().v4(),
      dateLabel: data['dateLabel'] ?? '',
      drinksRevenue: (data['drinksRevenue'] ?? 0).toDouble(),
      tablesRevenue:
          (data['tablesRevenue'] ?? (data['billiardRevenue'] ?? 0)).toDouble(),
      expensesTotal: (data['expensesTotal'] ?? 0).toDouble(),
      grandTotal: (data['grandTotal'] ?? 0).toDouble(),
      closedAt: parsedTime,
    );
  }

  factory ClosedDaySummary.fromDoc(DocumentSnapshot doc) {
    final raw = doc.data();
    final data =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return ClosedDaySummary.fromMap(data, doc.id);
  }
}

class AuditLog {
  final String id;
  final String title;
  final String message;
  final String beforeVal;
  final String afterVal;
  final String deviceId;
  final DateTime timestamp;

  AuditLog({
    required this.id,
    required this.title,
    required this.message,
    required this.beforeVal,
    required this.afterVal,
    required this.deviceId,
    required this.timestamp,
  });

  Map<String, dynamic> toMap({bool forLocal = false}) => {
        'id': id,
        'title': title,
        'message': message,
        'beforeVal': beforeVal,
        'afterVal': afterVal,
        'deviceId': deviceId,
        'timestamp': forLocal
            ? timestamp.toIso8601String()
            : Timestamp.fromDate(timestamp),
      };

  factory AuditLog.fromMap(Map<String, dynamic> data, [String? docId]) {
    DateTime parsedTime = DateTime.now();
    final rawTime = data['timestamp'];
    if (rawTime is Timestamp) {
      parsedTime = rawTime.toDate();
    } else if (rawTime is String) {
      parsedTime = DateTime.tryParse(rawTime) ?? DateTime.now();
    }

    return AuditLog(
      id: docId ?? data['id'] ?? const Uuid().v4(),
      title: data['title'] ?? '',
      message: data['message'] ?? '',
      beforeVal: data['beforeVal'] ?? '',
      afterVal: data['afterVal'] ?? '',
      deviceId: data['deviceId'] ?? '',
      timestamp: parsedTime,
    );
  }

  factory AuditLog.fromDoc(DocumentSnapshot doc) {
    final raw = doc.data();
    final data =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return AuditLog.fromMap(data, doc.id);
  }
}

// =============================================================================
// 2. NOTIFICATION SERVICE
// =============================================================================

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  Future<void> init() async {}

  Future<void> showEgyptianAlert({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      SystemSound.play(SystemSoundType.alert);
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1D2331),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF00C896), width: 1.5),
          ),
          duration: const Duration(seconds: 3),
          content: Row(
            children: [
              const Icon(Icons.notifications_active, color: Color(0xFF00C896)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00C896))),
                    Text(body, style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } catch (_) {}
  }
}

// =============================================================================
// 3. CLOUD SYNC SERVICE (Firebase Firestore: real-time + offline-safe writes)
// =============================================================================

class SyncStatus {
  final bool cloudReady;
  final bool online;
  final int pendingWrites;
  final bool syncing;
  final String? lastError;

  const SyncStatus({
    required this.cloudReady,
    required this.online,
    required this.pendingWrites,
    required this.syncing,
    this.lastError,
  });

  bool get isSynced =>
      cloudReady && online && pendingWrites == 0 && !syncing;

  bool get hasUnsynced => pendingWrites > 0 || syncing;
}

class _PendingOp {
  final String collection;
  final String docId;
  final Map<String, dynamic>? data;
  final bool merge;
  int attempts;

  _PendingOp({
    required this.collection,
    required this.docId,
    this.data,
    this.merge = true,
    this.attempts = 0,
  });

  Map<String, dynamic> toJson() => {
        'c': collection,
        'd': docId,
        'data': data,
        'merge': merge,
        'a': attempts,
      };

  factory _PendingOp.fromJson(Map<String, dynamic> j) => _PendingOp(
        collection: j['c'] as String,
        docId: j['d'] as String,
        data: j['data'] == null
            ? null
            : Map<String, dynamic>.from(j['data'] as Map),
        merge: j['merge'] as bool? ?? true,
        attempts: j['a'] as int? ?? 0,
      );
}

class FirestoreService {
  FirebaseFirestore? _db;
  FirebaseAuth? _auth;
  bool useCloud = false;
  late SharedPreferences _prefs;
  late String deviceId;
  bool _isInitialAuditLoad = true;
  bool _seedChecked = false;
  bool _seeding = false;
  bool _listenersStarted = false;
  bool _firebaseReady = false;
  bool _cloudInitializing = false;

  final List<_PendingOp> _outbox = [];
  final List<Map<String, dynamic>> _deadLetters = [];
  // Documents with local edits not yet acknowledged by Firestore. Incoming
  // snapshots are overlaid with these so a stale cached snapshot can never
  // visually replace an offline edit before it is uploaded.
  final Map<String, Map<String, Map<String, dynamic>?>> _pendingDocs = {};
  bool _flushing = false;
  bool _online = true;
  String? _lastError;

  final _tablesCtrl = StreamController<List<GamingTable>>.broadcast();
  final _invCtrl = StreamController<List<InventoryItem>>.broadcast();
  final _salesCtrl = StreamController<List<SaleRecord>>.broadcast();
  final _expensesCtrl = StreamController<List<ExpenseRecord>>.broadcast();
  final _closedDaysCtrl = StreamController<List<ClosedDaySummary>>.broadcast();
  final _logsCtrl = StreamController<List<AuditLog>>.broadcast();
  final _statusCtrl = StreamController<SyncStatus>.broadcast();

  List<GamingTable> _localTables = [];
  List<InventoryItem> _localInv = [];
  List<SaleRecord> _localSales = [];
  List<ExpenseRecord> _localExpenses = [];
  List<ClosedDaySummary> _localClosedDays = [];
  List<AuditLog> _localLogs = [];

  SyncStatus get currentSyncStatus => SyncStatus(
        cloudReady: useCloud,
        online: _online,
        pendingWrites: _outbox.length,
        syncing: _flushing,
        lastError: _lastError,
      );

  Stream<SyncStatus> streamSyncStatus() => _statusCtrl.stream;

  Future<void> initAndSeed({required bool firebaseReady}) async {
    _prefs = await SharedPreferences.getInstance();
    String? storedId = _prefs.getString('device_instance_id');
    if (storedId == null) {
      storedId = const Uuid().v4();
      await _prefs.setString('device_instance_id', storedId);
    }
    deviceId = storedId;

    // The mirror must be loaded first: rebuilding the pending-write overlay
    // from disk needs the full local documents to fill in partial updates.
    _loadLocalMirror();
    _loadOutbox();
    _loadDeadLetters();
    _watchConnectivity();

    _firebaseReady = firebaseReady;
    if (firebaseReady) {
      await _initCloud();
    }

    Timer.periodic(const Duration(seconds: 30), (_) {
      if (_online) _resumeSync();
    });

    _emitStatus();
  }

  Future<void> _initCloud() async {
    if (_cloudInitializing || useCloud || !_firebaseReady) return;
    _cloudInitializing = true;
    try {
      _db ??= FirebaseFirestore.instance;
      try {
        _db!.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );
      } catch (_) {}

      _auth ??= FirebaseAuth.instance;
      if (_auth!.currentUser == null) {
        await _auth!.signInAnonymously().timeout(const Duration(seconds: 25));
      }

      useCloud = true;
      _lastError = null;
      // Listen and replay the outbox immediately; seeding the cloud from the
      // local mirror is done in the background so a slow network cannot delay
      // the app from becoming usable.
      _startCloudListeners();
      _kick();
      unawaited(_seedCloudIfEmpty());
    } catch (e) {
      // Offline at first launch (no cached anonymous user yet) lands here.
      // It is retried automatically as soon as connectivity comes back.
      _lastError = _friendlyError(e);
    } finally {
      _cloudInitializing = false;
      _emitStatus();
    }
  }

  void _watchConnectivity() {
    try {
      Connectivity().checkConnectivity().then((results) {
        _online = results.any((r) => r != ConnectivityResult.none);
        _emitStatus();
        _resumeSync();
      }).catchError((_) {});

      Connectivity().onConnectivityChanged.listen((results) {
        _online = results.any((r) => r != ConnectivityResult.none);
        _emitStatus();
        _resumeSync();
      });
    } catch (_) {}
  }

  // Called whenever the device (re)gains a network connection.
  void _resumeSync() {
    if (!_online) return;
    if (!useCloud) {
      // Firebase may have failed to initialise while offline (for example on
      // the very first launch, before an anonymous user was cached).
      if (_firebaseReady) unawaited(_initCloud());
      return;
    }
    unawaited(_seedCloudIfEmpty());
    _kick();
  }

  Future<void> _seedCloudIfEmpty() async {
    if (_seedChecked || _seeding || _db == null || !useCloud) return;
    _seeding = true;
    try {
      final tablesSnap = await _db!
          .collection('tables')
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 15));
      if (tablesSnap.metadata.isFromCache) return;
      _seedChecked = true;

      if (tablesSnap.docs.isEmpty) {
        for (final t in _localTables) {
          await _enqueue('tables', t.id, t.toMap(forLocal: true),
              merge: false);
        }
      }

      if (await _isCollectionEmpty('inventory')) {
        for (final item in _localInv) {
          await _enqueue('inventory', item.id, item.toMap(), merge: false);
        }
      }

      if (await _isCollectionEmpty('sales')) {
        for (final sale in _localSales) {
          await _enqueue('sales', sale.id, sale.toMap(forLocal: true),
              merge: false);
        }
      }

      if (await _isCollectionEmpty('expenses')) {
        for (final expense in _localExpenses) {
          await _enqueue('expenses', expense.id,
              expense.toMap(forLocal: true),
              merge: false);
        }
      }

      if (await _isCollectionEmpty('closed_days')) {
        for (final day in _localClosedDays) {
          await _enqueue('closed_days', day.id, day.toMap(forLocal: true),
              merge: false);
        }
      }

      if (await _isCollectionEmpty('audit_logs')) {
        for (final log in _localLogs.take(200)) {
          await _enqueue('audit_logs', log.id, log.toMap(forLocal: true),
              merge: false);
        }
      }

      _kick();
    } catch (_) {
    } finally {
      _seeding = false;
    }
  }

  Future<bool> _isCollectionEmpty(String name) async {
    final snap = await _db!
        .collection(name)
        .limit(1)
        .get()
        .timeout(const Duration(seconds: 15));
    if (snap.metadata.isFromCache) return false;
    return snap.docs.isEmpty;
  }

  void _startCloudListeners() {
    if (_listenersStarted) return;
    _listenersStarted = true;
    _db!
        .collection('tables')
        .snapshots(includeMetadataChanges: true)
        .listen((snap) {
      if (snap.docs.isEmpty &&
          snap.metadata.isFromCache &&
          _localTables.isNotEmpty) {
        return;
      }
      _localTables =
          _withPending(snap, 'tables', (d, id) => GamingTable.fromMap(d, id));
      _persistMirror();
      _tablesCtrl.add(List.from(_localTables));
    }, onError: _onCloudError);

    _db!
        .collection('inventory')
        .snapshots(includeMetadataChanges: true)
        .listen((snap) {
      if (snap.docs.isEmpty && snap.metadata.isFromCache && _localInv.isNotEmpty) {
        return;
      }
      _localInv =
          _withPending(snap, 'inventory', (d, id) => InventoryItem.fromMap(d, id));
      _persistMirror();
      _invCtrl.add(List.from(_localInv));
    }, onError: _onCloudError);

    _db!
        .collection('sales')
        .snapshots(includeMetadataChanges: true)
        .listen((snap) {
      if (snap.docs.isEmpty &&
          snap.metadata.isFromCache &&
          _localSales.isNotEmpty) {
        return;
      }
      _localSales =
          _withPending(snap, 'sales', (d, id) => SaleRecord.fromMap(d, id));
      _persistMirror();
      _salesCtrl.add(_localSales.where((s) => !s.isClosed).toList());
    }, onError: _onCloudError);

    _db!
        .collection('expenses')
        .snapshots(includeMetadataChanges: true)
        .listen((snap) {
      if (snap.docs.isEmpty &&
          snap.metadata.isFromCache &&
          _localExpenses.isNotEmpty) {
        return;
      }
      _localExpenses =
          _withPending(snap, 'expenses', (d, id) => ExpenseRecord.fromMap(d, id));
      _persistMirror();
      _expensesCtrl.add(List.from(_localExpenses));
    }, onError: _onCloudError);

    _db!
        .collection('closed_days')
        .orderBy('closedAt', descending: true)
        .snapshots(includeMetadataChanges: true)
        .listen((snap) {
      if (snap.docs.isEmpty &&
          snap.metadata.isFromCache &&
          _localClosedDays.isNotEmpty) {
        return;
      }
      _localClosedDays = _withPending(
          snap, 'closed_days', (d, id) => ClosedDaySummary.fromMap(d, id));
      _persistMirror();
      _closedDaysCtrl.add(List.from(_localClosedDays));
    }, onError: _onCloudError);

    _db!
        .collection('audit_logs')
        .orderBy('timestamp', descending: true)
        .limit(200)
        .snapshots(includeMetadataChanges: true)
        .listen((snap) {
      if (snap.docs.isEmpty &&
          snap.metadata.isFromCache &&
          _localLogs.isNotEmpty) {
        return;
      }
      _localLogs =
          _withPending(snap, 'audit_logs', (d, id) => AuditLog.fromMap(d, id));
      _persistMirror();
      _logsCtrl.add(List.from(_localLogs));

      if (_isInitialAuditLoad) {
        if (snap.metadata.isFromCache) return;
        _isInitialAuditLoad = false;
        return;
      }
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        if (change.doc.metadata.hasPendingWrites) continue;
        final log = AuditLog.fromDoc(change.doc);
        if (log.deviceId == deviceId) continue;
        NotificationService().showEgyptianAlert(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title: log.title,
          body: log.message,
        );
      }
    }, onError: _onCloudError);
  }

  void _onCloudError(Object e) {
    _lastError = _friendlyError(e);
    _emitStatus();
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('permission-denied')) {
      return 'صلاحيات Firestore مرفوضة - راجع قواعد الأمان';
    }
    if (s.contains('unavailable')) return 'السحابة غير متاحة حالياً';
    if (s.contains('network-request-failed')) return 'لا يوجد اتصال بالإنترنت';
    if (s.contains('operation-not-allowed')) {
      return 'التحقق المجهول غير مُفعّل - فعّله من Firebase Authentication';
    }
    if (s.contains('invalid-api-key') || s.contains('API key not valid')) {
      return 'مفتاح Firebase غير صحيح - راجع firebase_options.dart';
    }
    if (s.contains('configuration-not-found')) {
      return 'Firebase غير مُفعّل - راجع إعدادات المشروع';
    }
    return s.length > 180 ? '${s.substring(0, 180)}...' : s;
  }

  // ---------------------------------------------------------------------------
  // Durable outbox: every change is saved locally first, then pushed to cloud.
  // ---------------------------------------------------------------------------

  Future<void> _enqueue(String collection, String docId,
      Map<String, dynamic>? data,
      {bool merge = true}) async {
    _rememberPending(collection, docId, data);
    _outbox.add(_PendingOp(
      collection: collection,
      docId: docId,
      data: data,
      merge: merge,
    ));
    await _persistOutbox();
    _emitStatus();
  }

  void _rememberPending(
      String collection, String docId, Map<String, dynamic>? data) {
    final docs = _pendingDocs.putIfAbsent(collection, () => {});
    if (data == null) {
      docs[docId] = null;
      return;
    }
    // Snapshots that do not contain this document yet (offline create, or a
    // document added after the last cache update) are rebuilt from the full
    // local copy, otherwise a partial update such as {"stock": 5} would show
    // an item with no name or price.
    final full = _fullLocalDoc(collection, docId);
    final merged = full == null
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{...full, ...data};
    final previous = docs[docId];
    docs[docId] =
        previous == null ? merged : <String, dynamic>{...previous, ...merged};
  }

  Map<String, dynamic>? _fullLocalDoc(String collection, String docId) {
    switch (collection) {
      case 'tables':
        for (final e in _localTables) {
          if (e.id == docId) return e.toMap(forLocal: true);
        }
      case 'inventory':
        for (final e in _localInv) {
          if (e.id == docId) return e.toMap();
        }
      case 'sales':
        for (final e in _localSales) {
          if (e.id == docId) return e.toMap(forLocal: true);
        }
      case 'expenses':
        for (final e in _localExpenses) {
          if (e.id == docId) return e.toMap(forLocal: true);
        }
      case 'closed_days':
        for (final e in _localClosedDays) {
          if (e.id == docId) return e.toMap(forLocal: true);
        }
      case 'audit_logs':
        for (final e in _localLogs) {
          if (e.id == docId) return e.toMap(forLocal: true);
        }
    }
    return null;
  }

  void _forgetPending(String collection, String docId) {
    final docs = _pendingDocs[collection];
    if (docs == null) return;
    docs.remove(docId);
    if (docs.isEmpty) _pendingDocs.remove(collection);
  }

  /// Merge the not-yet-uploaded local edits into a cloud snapshot. New local
  /// documents are placed first (the app always shows newest first), deleted
  /// ones are removed, and partial updates are merged over the cloud values.
  List<T> _withPending<T>(
    QuerySnapshot<Map<String, dynamic>> snap,
    String collection,
    T Function(Map<String, dynamic> data, String id) build,
  ) {
    final cloud = <String, Map<String, dynamic>>{};
    final order = <String>[];
    for (final doc in snap.docs) {
      cloud[doc.id] = Map<String, dynamic>.from(doc.data());
      order.add(doc.id);
    }

    final pending = _pendingDocs[collection];
    if (pending == null || pending.isEmpty) {
      return [for (final id in order) build(cloud[id]!, id)];
    }

    final added = <String>[];
    pending.forEach((id, data) {
      if (data == null) {
        cloud.remove(id);
        order.remove(id);
      } else if (cloud.containsKey(id)) {
        cloud[id] = {...cloud[id]!, ...data};
      } else {
        cloud[id] = Map<String, dynamic>.from(data);
        added.add(id);
      }
    });

    return [
      for (final id in added.reversed) build(cloud[id]!, id),
      for (final id in order)
        if (cloud.containsKey(id)) build(cloud[id]!, id),
    ];
  }

  void _kick() {
    unawaited(_flushOutbox());
  }

  Future<void> _flushOutbox() async {
    if (!useCloud || _db == null || _flushing || _outbox.isEmpty) return;
    // While offline the queue stays on disk. `connectivity_plus` kicks it
    // again the moment a connection returns.
    if (!_online) return;
    _flushing = true;
    try {
      while (_outbox.isNotEmpty) {
        final op = _outbox.first;
        try {
          final doc = _db!.collection(op.collection).doc(op.docId);
          if (op.data == null) {
            await doc.delete().timeout(const Duration(seconds: 20));
          } else if (op.merge) {
            await doc
                .set(_toFirestoreData(op.data!), SetOptions(merge: true))
                .timeout(const Duration(seconds: 20));
          } else {
            await doc
                .set(_toFirestoreData(op.data!))
                .timeout(const Duration(seconds: 20));
          }
          _outbox.removeAt(0);
          if (!_outbox.any((o) =>
              o.collection == op.collection && o.docId == op.docId)) {
            _forgetPending(op.collection, op.docId);
          }
          await _persistOutbox();
          _emitStatus();
        } catch (e) {
          _lastError = _friendlyError(e);
          if (_isPermanentError(e)) {
            op.attempts++;
            if (op.attempts >= 5) {
              // Rejected repeatedly (e.g. by security rules). Move it aside
              // so it cannot block the rest of the queue, but keep it on
              // disk instead of throwing the user's data away.
              _deadLetters.add(op.toJson());
              _outbox.removeAt(0);
              await _persistDeadLetters();
              await _persistOutbox();
              _emitStatus();
              continue;
            }
          }
          // Network / timeout / unavailable: keep the operation queued and
          // end this pass. The 30s timer and the connectivity listener will
          // retry it.
          break;
        }
      }
      if (_outbox.isEmpty && _lastError != null) {
        _lastError = null;
      }
    } finally {
      _flushing = false;
      _emitStatus();
    }
  }

  bool _isPermanentError(Object e) {
    final s = e.toString();
    return s.contains('permission-denied') ||
        s.contains('invalid-argument') ||
        s.contains('failed-precondition') ||
        s.contains('out-of-range');
  }

  static const _timestampKeys = {
    'timestamp',
    'closedAt',
    'lastStartTime',
    'updatedAt',
    'createdAt',
  };

  Map<String, dynamic> _toFirestoreData(Map<String, dynamic> data) {
    final out = <String, dynamic>{};
    data.forEach((k, v) => out[k] = _convertValue(k, v));
    return out;
  }

  dynamic _convertValue(String key, dynamic v) {
    if (v == null) return null;
    if (_timestampKeys.contains(key)) {
      if (v is Timestamp) return v;
      if (v is DateTime) return Timestamp.fromDate(v);
      if (v is String) {
        final d = DateTime.tryParse(v);
        if (d != null) return Timestamp.fromDate(d);
      }
    }
    if (v is Map) return _toFirestoreData(Map<String, dynamic>.from(v));
    if (v is List) {
      return v
          .map((e) =>
              e is Map ? _toFirestoreData(Map<String, dynamic>.from(e)) : e)
          .toList();
    }
    return v;
  }

  Future<void> _persistOutbox() async {
    try {
      await _prefs.setString(
          'pending_writes', jsonEncode(_outbox.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  void _loadOutbox() {
    try {
      final raw = _prefs.getString('pending_writes');
      if (raw == null) return;
      final list = jsonDecode(raw) as List;
      _outbox
        ..clear()
        ..addAll(list
            .map((e) => _PendingOp.fromJson(Map<String, dynamic>.from(e))));
      _pendingDocs.clear();
      for (final op in _outbox) {
        _rememberPending(op.collection, op.docId, op.data);
      }
    } catch (_) {
      _outbox.clear();
    }
  }

  Future<void> _persistDeadLetters() async {
    try {
      await _prefs.setString('dead_writes', jsonEncode(_deadLetters));
    } catch (_) {}
  }

  void _loadDeadLetters() {
    try {
      final raw = _prefs.getString('dead_writes');
      if (raw == null) return;
      final list = jsonDecode(raw) as List;
      _deadLetters
        ..clear()
        ..addAll(list.map((e) => Map<String, dynamic>.from(e)));
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Local mirror (instant startup + durable fallback when cloud is unreachable)
  // ---------------------------------------------------------------------------

  void _loadLocalMirror() {
    final tRaw = _prefs.getString('local_tables');
    if (tRaw != null) {
      try {
        final list = jsonDecode(tRaw) as List;
        _localTables = list
            .map((e) => GamingTable.fromMap(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {}
    }
    if (_localTables.isEmpty) {
      _localTables = [
        GamingTable(
            id: 'billiard',
            name: 'ترابيزة البلياردو',
            hourlyRate: 60.0,
            type: 'gaming',
            status: 'idle',
            accumulatedSeconds: 0,
            attachedItems: []),
        GamingTable(
            id: 'pingpong',
            name: 'ترابيزة البينج بونج',
            hourlyRate: 45.0,
            type: 'gaming',
            status: 'idle',
            accumulatedSeconds: 0,
            attachedItems: []),
        GamingTable(
            id: 'table_normal_1',
            name: 'ترابيزة قعدة عادية 1',
            hourlyRate: 0.0,
            type: 'normal',
            status: 'idle',
            accumulatedSeconds: 0,
            attachedItems: []),
      ];
    }

    final iRaw = _prefs.getString('local_inv');
    if (iRaw != null) {
      try {
        final list = jsonDecode(iRaw) as List;
        _localInv = list
            .map((e) => InventoryItem.fromMap(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {}
    }
    if (_localInv.isEmpty) {
      _localInv = [
        InventoryItem(
            id: '1',
            name: 'شاي',
            price: 15.0,
            stock: 100,
            lowStockThreshold: 15),
        InventoryItem(
            id: '2',
            name: 'قهوة تركي',
            price: 25.0,
            stock: 60,
            lowStockThreshold: 10),
        InventoryItem(
            id: '3',
            name: 'نسكافيه',
            price: 30.0,
            stock: 45,
            lowStockThreshold: 10),
        InventoryItem(
            id: '4',
            name: 'بيبسي',
            price: 20.0,
            stock: 50,
            lowStockThreshold: 12),
        InventoryItem(
            id: '5',
            name: 'مية معدنية',
            price: 10.0,
            stock: 80,
            lowStockThreshold: 20),
      ];
    }

    final sRaw = _prefs.getString('local_sales');
    if (sRaw != null) {
      try {
        final list = jsonDecode(sRaw) as List;
        _localSales = list
            .map((e) => SaleRecord.fromMap(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {}
    }

    final eRaw = _prefs.getString('local_expenses');
    if (eRaw != null) {
      try {
        final list = jsonDecode(eRaw) as List;
        _localExpenses = list
            .map((e) => ExpenseRecord.fromMap(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {}
    }

    final cRaw = _prefs.getString('local_closed_days');
    if (cRaw != null) {
      try {
        final list = jsonDecode(cRaw) as List;
        _localClosedDays = list
            .map((e) => ClosedDaySummary.fromMap(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {}
    }

    final lRaw = _prefs.getString('local_logs');
    if (lRaw != null) {
      try {
        final list = jsonDecode(lRaw) as List;
        _localLogs = list
            .map((e) => AuditLog.fromMap(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {}
    }

    _emitAll();
  }

  Future<void> _persistMirror() async {
    try {
      await _prefs.setString('local_tables',
          jsonEncode(_localTables.map((e) => e.toMap(forLocal: true)).toList()));
      await _prefs.setString(
          'local_inv', jsonEncode(_localInv.map((e) => e.toMap()).toList()));
      await _prefs.setString('local_sales',
          jsonEncode(_localSales.map((e) => e.toMap(forLocal: true)).toList()));
      await _prefs.setString(
          'local_expenses',
          jsonEncode(
              _localExpenses.map((e) => e.toMap(forLocal: true)).toList()));
      await _prefs.setString(
          'local_closed_days',
          jsonEncode(
              _localClosedDays.map((e) => e.toMap(forLocal: true)).toList()));
      await _prefs.setString('local_logs',
          jsonEncode(_localLogs.map((e) => e.toMap(forLocal: true)).toList()));
    } catch (_) {}
  }

  void _saveLocal() {
    unawaited(_persistMirror());
    _emitAll();
  }

  void _emitAll() {
    _tablesCtrl.add(List.from(_localTables));
    _invCtrl.add(List.from(_localInv));
    _salesCtrl.add(_localSales.where((s) => !s.isClosed).toList());
    _expensesCtrl.add(List.from(_localExpenses));
    _closedDaysCtrl.add(List.from(_localClosedDays));
    _logsCtrl.add(List.from(_localLogs));
  }

  void _emitStatus() {
    if (!_statusCtrl.isClosed) _statusCtrl.add(currentSyncStatus);
  }

  void forceSyncNow() {
    // Put previously rejected writes back in the queue so a manual retry can
    // recover them after the security rules / config have been fixed.
    if (_deadLetters.isNotEmpty) {
      for (final raw in _deadLetters) {
        try {
          final op = _PendingOp.fromJson(Map<String, dynamic>.from(raw));
          op.attempts = 0;
          _outbox.add(op);
          _rememberPending(op.collection, op.docId, op.data);
        } catch (_) {}
      }
      _deadLetters.clear();
      unawaited(_persistDeadLetters());
      unawaited(_persistOutbox());
    }

    if (!useCloud) {
      unawaited(_initCloud().then((_) {
        _emitStatus();
        _kick();
      }));
      return;
    }
    unawaited(_seedCloudIfEmpty());
    _kick();
  }

  List<GamingTable> get currentTables => List.from(_localTables);
  List<InventoryItem> get currentInventory => List.from(_localInv);
  List<SaleRecord> get currentSales =>
      _localSales.where((s) => !s.isClosed).toList();
  List<ExpenseRecord> get currentExpenses => List.from(_localExpenses);
  List<ClosedDaySummary> get currentClosedDays => List.from(_localClosedDays);
  List<AuditLog> get currentLogs => List.from(_localLogs);

  Stream<List<GamingTable>> streamTables() => _tablesCtrl.stream;
  Stream<List<InventoryItem>> streamInventory() => _invCtrl.stream;
  Stream<List<SaleRecord>> streamTodaySales() => _salesCtrl.stream;
  Stream<List<ExpenseRecord>> streamTodayExpenses() => _expensesCtrl.stream;
  Stream<List<ClosedDaySummary>> streamClosedDays() => _closedDaysCtrl.stream;
  Stream<List<AuditLog>> streamAuditLogs() => _logsCtrl.stream;

  Future<void> _recordAudit(
      {required String title,
      required String message,
      required String beforeVal,
      required String afterVal}) async {
    final log = AuditLog(
        id: const Uuid().v4(),
        title: title,
        message: message,
        beforeVal: beforeVal,
        afterVal: afterVal,
        deviceId: deviceId,
        timestamp: DateTime.now());
    _localLogs.insert(0, log);
    _saveLocal();

    await _enqueue('audit_logs', log.id, log.toMap(forLocal: true),
        merge: false);
    _kick();
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  // ريست / تصفير فواتير الشيفت الحالي فقط مع إرجاع الأصناف للمخزن
  Future<void> resetCurrentShiftInvoices() async {
    final activeSales = _localSales.where((s) => !s.isClosed).toList();
    final restoredStock = <String, int>{};

    for (final sale in activeSales) {
      for (final item in sale.soldItems) {
        final iIdx = _localInv.indexWhere((i) => i.id == item.itemId);
        if (iIdx >= 0) {
          final newStock = _localInv[iIdx].stock + item.qty;
          _localInv[iIdx] = InventoryItem(
            id: _localInv[iIdx].id,
            name: _localInv[iIdx].name,
            price: _localInv[iIdx].price,
            stock: newStock,
            lowStockThreshold: _localInv[iIdx].lowStockThreshold,
          );
          restoredStock[_localInv[iIdx].id] = newStock;
        }
      }
    }

    _localSales.removeWhere((s) => !s.isClosed);
    _saveLocal();

    for (final entry in restoredStock.entries) {
      await _enqueue('inventory', entry.key, {'stock': entry.value});
    }
    for (final sale in activeSales) {
      await _enqueue('sales', sale.id, null);
    }
    _kick();

    await _recordAudit(
      title: 'ريست فواتير الشيفت',
      message: 'تم تصفير كافة فواتير الشيفت الحالي وإرجاع الكميات للمخزن',
      beforeVal: 'فواتير نشطة',
      afterVal: '0 فاتورة',
    );
  }

  // ريست / تصفير الشهر بالكامل (تصفير سجل الأيام المتقفلة)
  Future<void> resetMonthHistory() async {
    final ids = _localClosedDays.map((e) => e.id).toList();
    _localClosedDays.clear();
    _saveLocal();

    for (final id in ids) {
      await _enqueue('closed_days', id, null);
    }
    _kick();

    await _recordAudit(
      title: 'ريست حسابات الشهر',
      message: 'تم تصفير سجل الأيام المتقفلة لبدء شهر جديد',
      beforeVal: 'أيام سابقة',
      afterVal: 'شهر جديد (0.0)',
    );
  }

  Future<void> addDailyExpense(
      {required String title, required double amount}) async {
    final expense = ExpenseRecord(
      id: const Uuid().v4(),
      title: title,
      amount: amount,
      timestamp: DateTime.now(),
    );
    _localExpenses.insert(0, expense);
    _saveLocal();

    await _enqueue('expenses', expense.id, expense.toMap(forLocal: true),
        merge: false);
    _kick();

    await _recordAudit(
      title: 'مصروف يومي جديد',
      message: 'تم إضافة مصروف [$title] بقيمة ${amount.toStringAsFixed(1)} ج.م',
      beforeVal: 'خصم مصاريف',
      afterVal: '-${amount.toStringAsFixed(1)} ج.م',
    );
  }

  Future<void> deleteDailyExpense(ExpenseRecord expense) async {
    _localExpenses.removeWhere((e) => e.id == expense.id);
    _saveLocal();

    await _enqueue('expenses', expense.id, null);
    _kick();

    await _recordAudit(
      title: 'حذف مصروف يومي',
      message:
          'تم حذف مصروف [${expense.title}] (${expense.amount.toStringAsFixed(1)} ج.م)',
      beforeVal: '-${expense.amount.toStringAsFixed(1)} ج.م',
      afterVal: 'ملغي',
    );
  }

  Future<void> addNewTable(
      {required String name,
      required String type,
      required double hourlyRate}) async {
    final newId = const Uuid().v4();
    final table = GamingTable(
        id: newId,
        name: name,
        hourlyRate: hourlyRate,
        type: type,
        status: 'idle',
        accumulatedSeconds: 0,
        attachedItems: []);
    _localTables.add(table);
    _saveLocal();

    await _enqueue('tables', newId, table.toMap(forLocal: true), merge: false);
    _kick();

    await _recordAudit(
        title: 'إضافة ترابيزة',
        message: 'تم إضافة ترابيزة [$name]',
        beforeVal: 'غير موجودة',
        afterVal: 'متاحة');
  }

  Future<void> deleteTable(GamingTable table) async {
    _localTables.removeWhere((t) => t.id == table.id);
    _saveLocal();

    await _enqueue('tables', table.id, null);
    _kick();

    await _recordAudit(
        title: 'حذف ترابيزة',
        message: 'تم حذف ترابيزة [${table.name}]',
        beforeVal: 'موجودة',
        afterVal: 'محذوفة');
  }

  Future<void> updateTableDetails(GamingTable table, String newName,
      String newType, double newRate) async {
    final idx = _localTables.indexWhere((t) => t.id == table.id);
    if (idx >= 0) {
      _localTables[idx] = GamingTable(
          id: table.id,
          name: newName,
          hourlyRate: newRate,
          type: newType,
          status: table.status,
          lastStartTime: table.lastStartTime,
          accumulatedSeconds: table.accumulatedSeconds,
          attachedItems: table.attachedItems,
          guestNotes: table.guestNotes);
      _saveLocal();
    }
    await _enqueue('tables', table.id,
        {'name': newName, 'type': newType, 'hourlyRate': newRate});
    _kick();
  }

  Future<void> startTableTimer(GamingTable table) async {
    if (table.type == 'normal') return;
    final now = DateTime.now();
    final idx = _localTables.indexWhere((t) => t.id == table.id);
    if (idx >= 0) {
      _localTables[idx] = GamingTable(
          id: table.id,
          name: table.name,
          hourlyRate: table.hourlyRate,
          type: table.type,
          status: 'running',
          lastStartTime: now,
          accumulatedSeconds: table.accumulatedSeconds,
          attachedItems: table.attachedItems,
          guestNotes: table.guestNotes);
      _saveLocal();
    }
    await _enqueue('tables', table.id, {
      'status': 'running',
      'lastStartTime': now.toIso8601String(),
    });
    _kick();

    await _recordAudit(
        title: 'تشغيل وقت: ${table.name}',
        message: 'تم بدء الوقت على ${table.name}',
        beforeVal: 'متوقفة',
        afterVal: 'شغالة الآن');
  }

  Future<void> pauseTableTimer(GamingTable table) async {
    if (table.type == 'normal') return;
    final totalElapsed = table.currentElapsedSeconds;
    final idx = _localTables.indexWhere((t) => t.id == table.id);
    if (idx >= 0) {
      _localTables[idx] = GamingTable(
          id: table.id,
          name: table.name,
          hourlyRate: table.hourlyRate,
          type: table.type,
          status: 'paused',
          lastStartTime: null,
          accumulatedSeconds: totalElapsed,
          attachedItems: table.attachedItems,
          guestNotes: table.guestNotes);
      _saveLocal();
    }
    await _enqueue('tables', table.id, {
      'status': 'paused',
      'lastStartTime': null,
      'accumulatedSeconds': totalElapsed,
    });
    _kick();
  }

  Future<void> updateTableGuestNotes(String tableId, String notes) async {
    final idx = _localTables.indexWhere((t) => t.id == tableId);
    if (idx >= 0) {
      final table = _localTables[idx];
      _localTables[idx] = GamingTable(
          id: table.id,
          name: table.name,
          hourlyRate: table.hourlyRate,
          type: table.type,
          status: table.status,
          lastStartTime: table.lastStartTime,
          accumulatedSeconds: table.accumulatedSeconds,
          attachedItems: table.attachedItems,
          guestNotes: notes);
      _saveLocal();
    }
    await _enqueue('tables', tableId, {'guestNotes': notes});
    _kick();
  }

  Future<void> updateTableAttachedItems(
      GamingTable table, List<AttachedItem> newItems) async {
    final stockUpdates = <String, int>{};

    for (final oldItem in table.attachedItems) {
      final iIdx = _localInv.indexWhere((i) => i.id == oldItem.itemId);
      if (iIdx >= 0) {
        final newStock = _localInv[iIdx].stock + oldItem.qty;
        _localInv[iIdx] = InventoryItem(
          id: _localInv[iIdx].id,
          name: _localInv[iIdx].name,
          price: _localInv[iIdx].price,
          stock: newStock,
          lowStockThreshold: _localInv[iIdx].lowStockThreshold,
        );
        stockUpdates[_localInv[iIdx].id] = newStock;
      }
    }
    for (final newItem in newItems) {
      final iIdx = _localInv.indexWhere((i) => i.id == newItem.itemId);
      if (iIdx >= 0) {
        final newStock =
            (_localInv[iIdx].stock - newItem.qty).clamp(0, 999999);
        _localInv[iIdx] = InventoryItem(
          id: _localInv[iIdx].id,
          name: _localInv[iIdx].name,
          price: _localInv[iIdx].price,
          stock: newStock,
          lowStockThreshold: _localInv[iIdx].lowStockThreshold,
        );
        stockUpdates[_localInv[iIdx].id] = newStock;
      }
    }

    final idx = _localTables.indexWhere((t) => t.id == table.id);
    if (idx >= 0) {
      _localTables[idx] = GamingTable(
          id: table.id,
          name: table.name,
          hourlyRate: table.hourlyRate,
          type: table.type,
          status: table.status,
          lastStartTime: table.lastStartTime,
          accumulatedSeconds: table.accumulatedSeconds,
          attachedItems: newItems,
          guestNotes: table.guestNotes);
      _saveLocal();
    }

    for (final entry in stockUpdates.entries) {
      await _enqueue('inventory', entry.key, {'stock': entry.value});
    }
    await _enqueue(
        'tables', table.id, {'attachedItems': newItems.map((e) => e.toMap()).toList()});
    _kick();
  }

  Future<void> attachDrinksToTable(
      GamingTable table, Map<InventoryItem, int> selectedDrinks) async {
    final updatedList = List<AttachedItem>.from(table.attachedItems);
    final stockUpdates = <String, int>{};

    for (final entry in selectedDrinks.entries) {
      final item = entry.key;
      final qty = entry.value;
      final newStock = (item.stock - qty).clamp(0, 999999);

      final iIdx = _localInv.indexWhere((i) => i.id == item.id);
      if (iIdx >= 0) {
        _localInv[iIdx] = InventoryItem(
            id: item.id,
            name: item.name,
            price: item.price,
            stock: newStock,
            lowStockThreshold: item.lowStockThreshold);
        stockUpdates[item.id] = newStock;
      }

      final existingIndex =
          updatedList.indexWhere((element) => element.itemId == item.id);
      if (existingIndex >= 0) {
        final existing = updatedList[existingIndex];
        updatedList[existingIndex] = AttachedItem(
            itemId: existing.itemId,
            name: existing.name,
            price: existing.price,
            qty: existing.qty + qty);
      } else {
        updatedList.add(AttachedItem(
            itemId: item.id, name: item.name, price: item.price, qty: qty));
      }
    }

    final tIdx = _localTables.indexWhere((t) => t.id == table.id);
    if (tIdx >= 0) {
      _localTables[tIdx] = GamingTable(
          id: table.id,
          name: table.name,
          hourlyRate: table.hourlyRate,
          type: table.type,
          status: table.status,
          lastStartTime: table.lastStartTime,
          accumulatedSeconds: table.accumulatedSeconds,
          attachedItems: updatedList,
          guestNotes: table.guestNotes);
    }
    _saveLocal();

    for (final entry in stockUpdates.entries) {
      await _enqueue('inventory', entry.key, {'stock': entry.value});
    }
    await _enqueue('tables', table.id,
        {'attachedItems': updatedList.map((e) => e.toMap()).toList()});
    _kick();
  }

  Future<SaleRecord> endAndCheckoutTable(GamingTable table) async {
    final elapsedSecs = table.currentElapsedSeconds;
    final timeCost = table.currentTimeCost;
    final drinksCost = table.attachedDrinksCost;
    final total = timeCost + drinksCost;

    final sale = SaleRecord(
      id: const Uuid().v4(),
      type: table.type == 'normal' ? 'normal_checkout' : 'gaming_checkout',
      label: 'فاتورة ${table.name}',
      timeRevenue: timeCost,
      drinksRevenue: drinksCost,
      totalRevenue: total,
      playedSeconds: elapsedSecs,
      soldItems: List<AttachedItem>.from(table.attachedItems),
      timestamp: DateTime.now(),
      isClosed: false,
    );

    _localSales.insert(0, sale);
    final idx = _localTables.indexWhere((t) => t.id == table.id);
    if (idx >= 0) {
      _localTables[idx] = GamingTable(
          id: table.id,
          name: table.name,
          hourlyRate: table.hourlyRate,
          type: table.type,
          status: 'idle',
          lastStartTime: null,
          accumulatedSeconds: 0,
          attachedItems: [],
          guestNotes: '');
    }
    _saveLocal();

    await _enqueue('sales', sale.id, sale.toMap(forLocal: true), merge: false);
    await _enqueue('tables', table.id, {
      'status': 'idle',
      'lastStartTime': null,
      'accumulatedSeconds': 0,
      'attachedItems': <Map<String, dynamic>>[],
      'guestNotes': '',
    });
    _kick();

    await _recordAudit(
        title: 'حساب ترابيزة',
        message: 'حساب ${table.name} بمبلغ ${total.toStringAsFixed(1)} ج.م',
        beforeVal: 'Hold',
        afterVal: 'تم التحصيل');
    return sale;
  }

  Future<void> checkoutDirectPos(Map<InventoryItem, int> cart) async {
    double totalDrinks = 0;
    final List<AttachedItem> soldItems = [];
    final stockUpdates = <String, int>{};

    for (final entry in cart.entries) {
      final item = entry.key;
      final qty = entry.value;
      totalDrinks += item.price * qty;
      soldItems.add(AttachedItem(
          itemId: item.id, name: item.name, price: item.price, qty: qty));
      final newStock = (item.stock - qty).clamp(0, 999999);

      final idx = _localInv.indexWhere((i) => i.id == item.id);
      if (idx >= 0) {
        _localInv[idx] = InventoryItem(
            id: item.id,
            name: item.name,
            price: item.price,
            stock: newStock,
            lowStockThreshold: item.lowStockThreshold);
        stockUpdates[item.id] = newStock;
      }
    }

    final sale = SaleRecord(
        id: const Uuid().v4(),
        type: 'drinks_only',
        label: 'فاتورة بيع مباشر',
        timeRevenue: 0,
        drinksRevenue: totalDrinks,
        totalRevenue: totalDrinks,
        playedSeconds: 0,
        soldItems: soldItems,
        timestamp: DateTime.now(),
        isClosed: false);
    _localSales.insert(0, sale);
    _saveLocal();

    for (final entry in stockUpdates.entries) {
      await _enqueue('inventory', entry.key, {'stock': entry.value});
    }
    await _enqueue('sales', sale.id, sale.toMap(forLocal: true), merge: false);
    _kick();

    await _recordAudit(
        title: 'فاتورة بيع مباشر',
        message:
            'تم تسجيل بيع مباشر بمبلغ ${totalDrinks.toStringAsFixed(1)} ج.م',
        beforeVal: 'سلة جديدة',
        afterVal: '${totalDrinks.toStringAsFixed(1)} ج.م');
  }

  Future<void> updateSaleRecord(
      SaleRecord oldSale, List<AttachedItem> updatedItems) async {
    final oldTotal = oldSale.totalRevenue;
    final stockUpdates = <String, int>{};

    for (final oldItem in oldSale.soldItems) {
      final iIdx = _localInv.indexWhere((i) => i.id == oldItem.itemId);
      if (iIdx >= 0) {
        final newStock = _localInv[iIdx].stock + oldItem.qty;
        _localInv[iIdx] = InventoryItem(
          id: _localInv[iIdx].id,
          name: _localInv[iIdx].name,
          price: _localInv[iIdx].price,
          stock: newStock,
          lowStockThreshold: _localInv[iIdx].lowStockThreshold,
        );
        stockUpdates[_localInv[iIdx].id] = newStock;
      }
    }

    for (final newItem in updatedItems) {
      final iIdx = _localInv.indexWhere((i) => i.id == newItem.itemId);
      if (iIdx >= 0) {
        final newStock =
            (_localInv[iIdx].stock - newItem.qty).clamp(0, 999999);
        _localInv[iIdx] = InventoryItem(
          id: _localInv[iIdx].id,
          name: _localInv[iIdx].name,
          price: _localInv[iIdx].price,
          stock: newStock,
          lowStockThreshold: _localInv[iIdx].lowStockThreshold,
        );
        stockUpdates[_localInv[iIdx].id] = newStock;
      }
    }

    final newDrinksRev =
        updatedItems.fold<double>(0.0, (sum, item) => sum + item.total);
    final newTotalRev = oldSale.timeRevenue + newDrinksRev;
    final shouldDelete = updatedItems.isEmpty && oldSale.timeRevenue <= 0;

    final sIdx = _localSales.indexWhere((s) => s.id == oldSale.id);
    if (sIdx >= 0) {
      if (shouldDelete) {
        _localSales.removeAt(sIdx);
      } else {
        _localSales[sIdx] = SaleRecord(
          id: oldSale.id,
          type: oldSale.type,
          label: oldSale.label,
          timeRevenue: oldSale.timeRevenue,
          drinksRevenue: newDrinksRev,
          totalRevenue: newTotalRev,
          playedSeconds: oldSale.playedSeconds,
          soldItems: updatedItems,
          timestamp: oldSale.timestamp,
          isClosed: oldSale.isClosed,
        );
      }
    }

    _saveLocal();

    for (final entry in stockUpdates.entries) {
      await _enqueue('inventory', entry.key, {'stock': entry.value});
    }
    if (shouldDelete) {
      await _enqueue('sales', oldSale.id, null);
    } else {
      await _enqueue('sales', oldSale.id, {
        'drinksRevenue': newDrinksRev,
        'totalRevenue': newTotalRev,
        'soldItems': updatedItems.map((e) => e.toMap()).toList(),
      });
    }
    _kick();

    await _recordAudit(
      title: 'تعديل فاتورة (${oldSale.label})',
      message:
          'تم تعديل الفاتورة من ${oldTotal.toStringAsFixed(1)} إلى ${newTotalRev.toStringAsFixed(1)} ج.م',
      beforeVal: '${oldTotal.toStringAsFixed(1)} ج.م',
      afterVal: '${newTotalRev.toStringAsFixed(1)} ج.م',
    );
  }

  Future<void> deleteSaleRecord(SaleRecord sale) async {
    final stockUpdates = <String, int>{};

    for (final item in sale.soldItems) {
      final iIdx = _localInv.indexWhere((i) => i.id == item.itemId);
      if (iIdx >= 0) {
        final newStock = _localInv[iIdx].stock + item.qty;
        _localInv[iIdx] = InventoryItem(
          id: _localInv[iIdx].id,
          name: _localInv[iIdx].name,
          price: _localInv[iIdx].price,
          stock: newStock,
          lowStockThreshold: _localInv[iIdx].lowStockThreshold,
        );
        stockUpdates[_localInv[iIdx].id] = newStock;
      }
    }

    _localSales.removeWhere((s) => s.id == sale.id);
    _saveLocal();

    for (final entry in stockUpdates.entries) {
      await _enqueue('inventory', entry.key, {'stock': entry.value});
    }
    await _enqueue('sales', sale.id, null);
    _kick();

    await _recordAudit(
      title: 'حذف فاتورة (${sale.label})',
      message:
          'تم حذف فاتورة بقيمة ${sale.totalRevenue.toStringAsFixed(1)} ج.م وإرجاع الكميات للمخزن',
      beforeVal: '${sale.totalRevenue.toStringAsFixed(1)} ج.م',
      afterVal: 'محذوفة',
    );
  }

  Future<void> closeCurrentDayAndReset({
    required double drinksRev,
    required double tableRev,
    required double expensesTotal,
    required double grandTotal,
  }) async {
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    double extraTableRev = 0;
    double extraDrinks = 0;
    final resetTables = <String>[];

    for (int i = 0; i < _localTables.length; i++) {
      final t = _localTables[i];
      if (t.currentElapsedSeconds > 0 || t.attachedItems.isNotEmpty) {
        extraTableRev += t.currentTimeCost;
        extraDrinks += t.attachedDrinksCost;
        resetTables.add(t.id);
        _localTables[i] = GamingTable(
            id: t.id,
            name: t.name,
            hourlyRate: t.hourlyRate,
            type: t.type,
            status: 'idle',
            lastStartTime: null,
            accumulatedSeconds: 0,
            attachedItems: [],
            guestNotes: '');
      }
    }

    final finalDrinks = drinksRev + extraDrinks;
    final finalTables = tableRev + extraTableRev;
    final finalNetTotal = (finalDrinks + finalTables) - expensesTotal;

    final summary = ClosedDaySummary(
      id: const Uuid().v4(),
      dateLabel: dateStr,
      drinksRevenue: finalDrinks,
      tablesRevenue: finalTables,
      expensesTotal: expensesTotal,
      grandTotal: finalNetTotal,
      closedAt: now,
    );

    final saleIds = _localSales.map((s) => s.id).toList();
    final expenseIds = _localExpenses.map((e) => e.id).toList();

    if (finalDrinks + finalTables > 0 || expensesTotal > 0) {
      _localClosedDays.insert(0, summary);
    }
    _localSales.clear();
    _localExpenses.clear();
    _saveLocal();

    if (finalDrinks + finalTables > 0 || expensesTotal > 0) {
      await _enqueue(
          'closed_days', summary.id, summary.toMap(forLocal: true),
          merge: false);
    }
    for (final tableId in resetTables) {
      await _enqueue('tables', tableId, {
        'status': 'idle',
        'lastStartTime': null,
        'accumulatedSeconds': 0,
        'attachedItems': <Map<String, dynamic>>[],
        'guestNotes': '',
      });
    }
    for (final id in saleIds) {
      await _enqueue('sales', id, null);
    }
    for (final id in expenseIds) {
      await _enqueue('expenses', id, null);
    }
    _kick();

    await _recordAudit(
        title: 'تقفيل اليوم - Joker Cafe',
        message:
            'تم تقفيل حسابات يوم $dateStr بصافي ${finalNetTotal.toStringAsFixed(1)} ج.م (بعد خصم مصاريف ${expensesTotal.toStringAsFixed(1)})',
        beforeVal: '${finalNetTotal.toStringAsFixed(1)} ج.م',
        afterVal: '0.0 ج.م (شيفت جديد)');
  }

  Future<void> addNewInventoryItem(
      {required String name,
      required double price,
      required int stock,
      required int threshold}) async {
    final newItem = InventoryItem(
        id: const Uuid().v4(),
        name: name,
        price: price,
        stock: stock,
        lowStockThreshold: threshold);
    _localInv.add(newItem);
    _saveLocal();

    await _enqueue('inventory', newItem.id, newItem.toMap(), merge: false);
    _kick();
  }

  Future<void> updateItemPrice(InventoryItem item, double newPrice) async {
    final idx = _localInv.indexWhere((i) => i.id == item.id);
    if (idx >= 0) {
      _localInv[idx] = InventoryItem(
          id: item.id,
          name: item.name,
          price: newPrice,
          stock: item.stock,
          lowStockThreshold: item.lowStockThreshold);
      _saveLocal();
    }
    await _enqueue('inventory', item.id, {'price': newPrice});
    _kick();
  }

  Future<void> updateItemStock(InventoryItem item, int newStock) async {
    final idx = _localInv.indexWhere((i) => i.id == item.id);
    if (idx >= 0) {
      _localInv[idx] = InventoryItem(
          id: item.id,
          name: item.name,
          price: item.price,
          stock: newStock,
          lowStockThreshold: item.lowStockThreshold);
      _saveLocal();
    }
    await _enqueue('inventory', item.id, {'stock': newStock});
    _kick();
  }

  Future<void> deleteInventoryItem(InventoryItem item) async {
    _localInv.removeWhere((i) => i.id == item.id);
    _saveLocal();
    await _enqueue('inventory', item.id, null);
    _kick();
  }
}


// =============================================================================
// 4. MAIN ENTRY POINT & UI
// =============================================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  bool firebaseReady = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseReady = true;
  } catch (_) {
    firebaseReady = false;
  }

  await NotificationService().init();
  final firestoreService = FirestoreService();
  await firestoreService.initAndSeed(firebaseReady: firebaseReady);

  runApp(CafeAdminApp(firestoreService: firestoreService));
}

class CafeAdminApp extends StatelessWidget {
  final FirestoreService firestoreService;
  const CafeAdminApp({super.key, required this.firestoreService});

  @override
  Widget build(BuildContext context) {
    final cairoTheme = GoogleFonts.cairoTextTheme(ThemeData.dark().textTheme);

    return MaterialApp(
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      title: 'Joker Cafe',
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [Locale('ar', 'EG')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF12161F),
        cardColor: const Color(0xFF1D2331),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00C896),
          secondary: Color(0xFFFFB300),
          error: Color(0xFFFF5252),
        ),
        textTheme: cairoTheme,
      ),
      builder: (context, child) {
        return Directionality(textDirection: TextDirection.rtl, child: child!);
      },
      home: AdminDashboardShell(db: firestoreService),
    );
  }
}

class AdminDashboardShell extends StatefulWidget {
  final FirestoreService db;
  const AdminDashboardShell({super.key, required this.db});

  @override
  State<AdminDashboardShell> createState() => _AdminDashboardShellState();
}

class _AdminDashboardShellState extends State<AdminDashboardShell> {
  int _selectedIndex = 0;
  final Map<String, int> _posCart = {};

  void _showManualSyncDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('المزامنة السحابية - Joker Cafe'),
        content: StreamBuilder<SyncStatus>(
          initialData: widget.db.currentSyncStatus,
          stream: widget.db.streamSyncStatus(),
          builder: (context, statusSnap) {
            final status = statusSnap.data ?? widget.db.currentSyncStatus;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cloudRow(
                  icon: status.cloudReady ? Icons.cloud_done : Icons.cloud_off,
                  color: status.cloudReady
                      ? const Color(0xFF00C896)
                      : Colors.orangeAccent,
                  label: 'قاعدة البيانات السحابية',
                  value: status.cloudReady ? 'متصل بـ Firebase' : 'غير متصل',
                ),
                const SizedBox(height: 8),
                _cloudRow(
                  icon: status.online ? Icons.wifi : Icons.wifi_off,
                  color: status.online
                      ? const Color(0xFF00C896)
                      : Colors.orangeAccent,
                  label: 'الإنترنت',
                  value: status.online ? 'متاح' : 'غير متاح',
                ),
                const SizedBox(height: 8),
                _cloudRow(
                  icon: status.pendingWrites == 0
                      ? Icons.check_circle
                      : Icons.cloud_upload,
                  color: status.pendingWrites == 0
                      ? const Color(0xFF00C896)
                      : Colors.amber,
                  label: 'عمليات في انتظار الرفع',
                  value: '${status.pendingWrites}',
                ),
                if (status.pendingWrites > 0) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'التعديلات دي محفوظة على الجهاز وهتترفع لوحدها أول ما الإنترنت يرجع.',
                    style: TextStyle(fontSize: 12, color: Colors.amber),
                  ),
                ],
                if (status.lastError != null) ...[
                  const SizedBox(height: 10),
                  Text(status.lastError!,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.orangeAccent)),
                ],
                const Divider(height: 22),
                const Text(
                  'كل الأجهزة المسجلة على نفس مشروع Firebase بتشوف نفس البيانات لحظياً. أي تعديل بيتحفظ محلياً الأول، ولو النت قطع بيرجع يترفع لوحده أول ما الاتصال يرجع.',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              widget.db.forceSyncNow();
              Navigator.pop(dialogCtx);
            },
            child: const Text('مزامنة الآن'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C896),
                foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('تمام'),
          ),
        ],
      ),
    );
  }

  Widget _cloudRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        Text(value,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GamingTable>>(
      initialData: widget.db.currentTables,
      stream: widget.db.streamTables(),
      builder: (context, tablesSnap) {
        return StreamBuilder<List<InventoryItem>>(
          initialData: widget.db.currentInventory,
          stream: widget.db.streamInventory(),
          builder: (context, invSnap) {
            return StreamBuilder<List<SaleRecord>>(
              initialData: widget.db.currentSales,
              stream: widget.db.streamTodaySales(),
              builder: (context, salesSnap) {
                return StreamBuilder<List<ExpenseRecord>>(
                  initialData: widget.db.currentExpenses,
                  stream: widget.db.streamTodayExpenses(),
                  builder: (context, expSnap) {
                    return StreamBuilder<List<AuditLog>>(
                      initialData: widget.db.currentLogs,
                      stream: widget.db.streamAuditLogs(),
                      builder: (context, logsSnap) {
                        return StreamBuilder<SyncStatus>(
                          initialData: widget.db.currentSyncStatus,
                          stream: widget.db.streamSyncStatus(),
                          builder: (context, statusSnap) {
                            final tables = tablesSnap.data ?? [];
                            final inventory = invSnap.data ?? [];
                            final sales = salesSnap.data ?? [];
                            final expenses = expSnap.data ?? [];
                            final logs = logsSnap.data ?? [];
                            final syncStatus = statusSnap.data ??
                                widget.db.currentSyncStatus;

                            final grossRevenue = sales.fold<double>(
                                0.0, (sum, s) => sum + s.totalRevenue);
                            final totalExpenses = expenses.fold<double>(
                                0.0, (sum, e) => sum + e.amount);
                            final netTodayTotal = grossRevenue - totalExpenses;

                            return LayoutBuilder(
                              builder: (context, constraints) {
                                final isWideDesktop = constraints.maxWidth >= 900;

                                return Scaffold(
                                  appBar: AppBar(
                                    backgroundColor: const Color(0xFF181E2C),
                                    title: Row(
                                      children: [
                                        const Icon(Icons.theater_comedy,
                                            color: Color(0xFF00C896)),
                                        const SizedBox(width: 10),
                                        const Expanded(
                                          child: Text('Joker Cafe - لوحة التحكم',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold)),
                                        ),
                                        InkWell(
                                          onTap: _showManualSyncDialog,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 5),
                                            decoration: BoxDecoration(
                                              color: syncStatus.isSynced
                                                  ? Colors.green
                                                      .withValues(alpha: 0.2)
                                                  : Colors.orange
                                                      .withValues(alpha: 0.2),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                  color: syncStatus.isSynced
                                                      ? const Color(0xFF00C896)
                                                      : Colors.orangeAccent),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  syncStatus.isSynced
                                                      ? Icons.cloud_done
                                                      : (syncStatus.cloudReady
                                                          ? Icons.cloud_upload
                                                          : Icons.cloud_off),
                                                  size: 16,
                                                  color: syncStatus.isSynced
                                                      ? const Color(0xFF00C896)
                                                      : Colors.orangeAccent,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  syncStatus.isSynced
                                                      ? 'متزامن'
                                                      : (!syncStatus.cloudReady
                                                          ? 'غير متصل'
                                                          : (!syncStatus.online
                                                              ? (syncStatus
                                                                          .pendingWrites >
                                                                      0
                                                                  ? 'أوفلاين - ${syncStatus.pendingWrites} بالانتظار'
                                                                  : 'أوفلاين')
                                                              : 'جارٍ الرفع (${syncStatus.pendingWrites})')),
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: syncStatus.isSynced
                                                        ? const Color(0xFF00C896)
                                                        : Colors.orangeAccent,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.teal
                                                .withValues(alpha: 0.2),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                                color: const Color(0xFF00C896)),
                                          ),
                                          child: Text(
                                            'صافي الشيفت: ${netTodayTotal.toStringAsFixed(1)} ج.م',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF00C896)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  body: isWideDesktop
                                      ? _buildWindowsDesktopView(tables,
                                          inventory, sales, expenses, logs)
                                      : _buildAndroidMobileView(tables,
                                          inventory, sales, expenses, logs),
                                  bottomNavigationBar: isWideDesktop
                                      ? null
                                      : NavigationBar(
                                          selectedIndex: _selectedIndex,
                                          onDestinationSelected: (idx) =>
                                              setState(() => _selectedIndex = idx),
                                          destinations: const [
                                            NavigationDestination(
                                                icon: Icon(Icons.table_bar),
                                                label: 'الترابيزات'),
                                            NavigationDestination(
                                                icon: Icon(Icons.point_of_sale),
                                                label: 'الكاشير'),
                                            NavigationDestination(
                                                icon: Icon(Icons.inventory_2),
                                                label: 'المخزن'),
                                            NavigationDestination(
                                                icon: Icon(Icons.bar_chart),
                                                label: 'تقفيل اليوم'),
                                            NavigationDestination(
                                                icon: Icon(Icons.history),
                                                label: 'التعديلات'),
                                          ],
                                        ),
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildWindowsDesktopView(
      List<GamingTable> tables,
      List<InventoryItem> inventory,
      List<SaleRecord> sales,
      List<ExpenseRecord> expenses,
      List<AuditLog> logs) {
    final desktopIndex = _selectedIndex > 4 ? 0 : _selectedIndex;
    return Row(
      children: [
        NavigationRail(
          selectedIndex: desktopIndex,
          onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
          extended: true,
          backgroundColor: const Color(0xFF181E2C),
          destinations: const [
            NavigationRailDestination(
                icon: Icon(Icons.dashboard_customize),
                label: Text('الترابيزات')),
            NavigationRailDestination(
                icon: Icon(Icons.point_of_sale), label: Text('الكاشير')),
            NavigationRailDestination(
                icon: Icon(Icons.inventory_2), label: Text('المخزن')),
            NavigationRailDestination(
                icon: Icon(Icons.assessment),
                label: Text('تقفيل اليوم والمصاريف')),
            NavigationRailDestination(
                icon: Icon(Icons.history), label: Text('سجل العمليات')),
          ],
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Builder(
            builder: (context) {
              switch (desktopIndex) {
                case 0:
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                          flex: 5,
                          child: _buildTablesSection(tables, inventory)),
                      const VerticalDivider(width: 1),
                      Expanded(
                          flex: 5,
                          child: _buildPosSection(inventory, tables, sales)),
                    ],
                  );
                case 1:
                  return _buildPosSection(inventory, tables, sales);
                case 2:
                  return _buildInventorySection(inventory);
                case 3:
                  return _buildReportsSection(sales, expenses, logs);
                case 4:
                  return _buildAuditLogsSection(logs);
                default:
                  return const SizedBox.shrink();
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAndroidMobileView(
      List<GamingTable> tables,
      List<InventoryItem> inventory,
      List<SaleRecord> sales,
      List<ExpenseRecord> expenses,
      List<AuditLog> logs) {
    switch (_selectedIndex) {
      case 0:
        return _buildTablesSection(tables, inventory);
      case 1:
        return _buildPosSection(inventory, tables, sales);
      case 2:
        return _buildInventorySection(inventory);
      case 3:
        return _buildReportsSection(sales, expenses, logs);
      case 4:
        return _buildAuditLogsSection(logs);
      default:
        return _buildTablesSection(tables, inventory);
    }
  }

  Widget _buildTablesSection(
      List<GamingTable> tables, List<InventoryItem> inventory) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('إدارة الترابيزات',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C896),
                  foregroundColor: Colors.black),
              onPressed: _showAddTableDialog,
              icon: const Icon(Icons.add),
              label: const Text('إضافة ترابيزة'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...tables.map((table) => _TableCardWidget(
              key: ValueKey('card_${table.id}'),
              table: table,
              inventory: inventory,
              db: widget.db,
              onEditTable: () => _showEditTableDialog(table),
              onDeleteTable: () => _confirmDeleteTable(table),
              onAttachDrinks: () => _showAttachDrinksDialog(table, inventory),
              onEditItems: () => _showEditTableItemsDialog(table, inventory),
              onCheckout: () => _confirmTableCheckout(table),
            )),
      ],
    );
  }

  Widget _buildPosSection(List<InventoryItem> inventory,
      List<GamingTable> tables, List<SaleRecord> sales) {
    double cartTotal = 0;
    final Map<InventoryItem, int> resolvedCart = {};
    for (final item in inventory) {
      if (_posCart.containsKey(item.id) && _posCart[item.id]! > 0) {
        final q = _posCart[item.id]!;
        resolvedCart[item] = q;
        cartTotal += item.price * q;
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('الكاشير والبيع المباشر',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 175,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.95,
          ),
          itemCount: inventory.length,
          itemBuilder: (context, index) {
            final item = inventory[index];
            final qtyInCart = _posCart[item.id] ?? 0;

            return InkWell(
              onTap: item.stock > qtyInCart
                  ? () => setState(() => _posCart[item.id] = qtyInCart + 1)
                  : null,
              borderRadius: BorderRadius.circular(12),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                      color: qtyInCart > 0
                          ? const Color(0xFF00C896)
                          : Colors.white12,
                      width: 2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('مخزن: ${item.stock}',
                          style: const TextStyle(
                              fontSize: 10, color: Colors.white60)),
                      Text(item.name,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center),
                      Text('${item.price} ج.م',
                          style: const TextStyle(
                              color: Color(0xFF00C896),
                              fontWeight: FontWeight.bold)),
                      if (qtyInCart > 0)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            InkWell(
                              onTap: () => setState(() {
                                if (qtyInCart <= 1) {
                                  _posCart.remove(item.id);
                                } else {
                                  _posCart[item.id] = qtyInCart - 1;
                                }
                              }),
                              child: const Icon(Icons.remove_circle,
                                  color: Colors.orangeAccent, size: 22),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Text('$qtyInCart',
                                  style: const TextStyle(
                                      color: Colors.amber,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15)),
                            ),
                            InkWell(
                              onTap: item.stock > qtyInCart
                                  ? () => setState(
                                      () => _posCart[item.id] = qtyInCart + 1)
                                  : null,
                              child: const Icon(Icons.add_circle,
                                  color: Color(0xFF00C896), size: 22),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        if (resolvedCart.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: const Color(0xFF181E2C),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF00C896))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('إجمالي السلة: ${cartTotal.toStringAsFixed(1)} ج.م',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    TextButton.icon(
                      onPressed: () => setState(() => _posCart.clear()),
                      icon: const Icon(Icons.delete_sweep,
                          color: Colors.redAccent, size: 18),
                      label: const Text('تفريغ السلة',
                          style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00C896),
                          foregroundColor: Colors.black),
                      onPressed: () async {
                        await widget.db.checkoutDirectPos(resolvedCart);
                        setState(() => _posCart.clear());
                      },
                      icon: const Icon(Icons.check_circle),
                      label: const Text('بيع مباشر كاشير',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    ...tables.map((t) => OutlinedButton(
                          onPressed: () async {
                            await widget.db
                                .attachDrinksToTable(t, resolvedCart);
                            setState(() => _posCart.clear());
                          },
                          child: Text('إضافة لـ ${t.name} (Hold)'),
                        )),
                  ],
                ),
              ],
            ),
          ),
        ],
        const Divider(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('فواتير الشيفت (تعديل / حذف / ريست):',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            if (sales.isNotEmpty)
              TextButton.icon(
                onPressed: _confirmResetShiftInvoicesDialog,
                icon: const Icon(Icons.restart_alt,
                    color: Colors.orangeAccent, size: 18),
                label: const Text('ريست الفواتير',
                    style: TextStyle(color: Colors.orangeAccent)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (sales.isEmpty)
          const Text('مفيش فواتير مسجلة في الشيفت الحالي لسه.',
              style: TextStyle(color: Colors.white60))
        else
          ...sales.map((sale) {
            final itemsSummary = sale.soldItems.isEmpty
                ? 'حساب وقت فقط'
                : sale.soldItems.map((e) => '${e.name} × ${e.qty}').join(' ، ');
            final timeStr = intl.DateFormat('hh:mm a').format(sale.timestamp);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading:
                    const Icon(Icons.receipt_long, color: Color(0xFF00C896)),
                title: Text(
                  '${sale.label} - ${sale.totalRevenue.toStringAsFixed(1)} ج.م  ($timeStr)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(itemsSummary),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.amberAccent),
                      tooltip: 'تعديل الفاتورة',
                      onPressed: () => _showEditSaleDialog(sale, inventory),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.redAccent),
                      tooltip: 'حذف الفاتورة وإرجاع المخزن',
                      onPressed: () => _confirmDeleteSaleDialog(sale),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  void _confirmResetShiftInvoicesDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('ريست / تصفير فواتير الشيفت'),
        content: const Text(
            'هل تريد مسح جميع فواتير الشيفت الحالي وإرجاع الكميات المباعة للمخزن؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await widget.db.resetCurrentShiftInvoices();
            },
            child: const Text('نعم، ريست الفواتير'),
          ),
        ],
      ),
    );
  }

  void _showEditSaleDialog(SaleRecord sale, List<InventoryItem> inventory) {
    final List<AttachedItem> editableItems = List.from(sale.soldItems);

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('تعديل ${sale.label}'),
          content: SizedBox(
            width: 420,
            height: 340,
            child: Column(
              children: [
                if (inventory.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة صنف آخر للفاتورة'),
                      onPressed: () {
                        final firstInv = inventory.first;
                        setDialogState(() {
                          final existingIdx = editableItems
                              .indexWhere((e) => e.itemId == firstInv.id);
                          if (existingIdx >= 0) {
                            final ex = editableItems[existingIdx];
                            editableItems[existingIdx] = AttachedItem(
                              itemId: ex.itemId,
                              name: ex.name,
                              price: ex.price,
                              qty: ex.qty + 1,
                            );
                          } else {
                            editableItems.add(AttachedItem(
                              itemId: firstInv.id,
                              name: firstInv.name,
                              price: firstInv.price,
                              qty: 1,
                            ));
                          }
                        });
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: editableItems.isEmpty
                      ? const Center(
                          child: Text(
                              'لا توجد أصناف في الفاتورة (سيتم حفظ التعديل تلقائياً)'))
                      : ListView.builder(
                          itemCount: editableItems.length,
                          itemBuilder: (context, index) {
                            final item = editableItems[index];
                            return ListTile(
                              title: Text(item.name),
                              subtitle: Text(
                                  'السعر: ${item.price} ج.م | الإجمالي: ${item.total.toStringAsFixed(1)} ج.م'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                        Icons.remove_circle_outline,
                                        color: Colors.orange),
                                    onPressed: () {
                                      setDialogState(() {
                                        if (item.qty > 1) {
                                          editableItems[index] = AttachedItem(
                                            itemId: item.itemId,
                                            name: item.name,
                                            price: item.price,
                                            qty: item.qty - 1,
                                          );
                                        } else {
                                          editableItems.removeAt(index);
                                        }
                                      });
                                    },
                                  ),
                                  Text('${item.qty}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline,
                                        color: Colors.green),
                                    onPressed: () {
                                      setDialogState(() {
                                        editableItems[index] = AttachedItem(
                                          itemId: item.itemId,
                                          name: item.name,
                                          price: item.price,
                                          qty: item.qty + 1,
                                        );
                                      });
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red),
                                    onPressed: () {
                                      setDialogState(() {
                                        editableItems.removeAt(index);
                                      });
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C896),
                  foregroundColor: Colors.black),
              onPressed: () async {
                Navigator.pop(dialogCtx);
                await widget.db.updateSaleRecord(sale, editableItems);
              },
              child: const Text('حفظ تعديل الفاتورة'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteSaleDialog(SaleRecord sale) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('حذف الفاتورة'),
        content: Text(
            'هل تريد حذف هذه الفاتورة (${sale.totalRevenue.toStringAsFixed(1)} ج.م) وإرجاع الكميات للمخزن؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await widget.db.deleteSaleRecord(sale);
            },
            child: const Text('نعم، حذف الفاتورة'),
          ),
        ],
      ),
    );
  }

  Widget _buildInventorySection(List<InventoryItem> inventory) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('إدارة المخزن',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ElevatedButton(
              onPressed: _showAddInventoryDialog,
              child: const Text('إضافة صنف'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...inventory.map((item) => Card(
              child: ListTile(
                title: Text(item.name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle:
                    Text('السعر: ${item.price} ج.م | المخزن: ${item.stock}'),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () => _showEditPriceDialog(item),
                      child: const Text('السعر'),
                    ),
                    OutlinedButton(
                      onPressed: () => _showEditStockDialog(item),
                      child: const Text('الكمية'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.redAccent),
                      onPressed: () => widget.db.deleteInventoryItem(item),
                    ),
                  ],
                ),
              ),
            )),
      ],
    );
  }

  Widget _buildReportsSection(
      List<SaleRecord> sales, List<ExpenseRecord> expenses, List<AuditLog> logs) {
    double drinksRev = 0;
    double tableRev = 0;
    for (final s in sales) {
      drinksRev += s.drinksRevenue;
      tableRev += s.timeRevenue;
    }
    final totalIncome = drinksRev + tableRev;
    final totalExpenses =
        expenses.fold<double>(0.0, (sum, e) => sum + e.amount);
    final netTotal = totalIncome - totalExpenses;

    return StreamBuilder<List<ClosedDaySummary>>(
      initialData: widget.db.currentClosedDays,
      stream: widget.db.streamClosedDays(),
      builder: (context, closedSnap) {
        final closedDays = closedSnap.data ?? [];
        final monthTotal = closedDays.fold<double>(
                0.0, (sum, day) => sum + day.grandTotal) +
            netTotal;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: const Color(0xFF1D2331),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text('ملخص الشيفت والمصاريف اليومية',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00C896))),
                    const SizedBox(height: 10),
                    Text('إيراد المشاريب: ${drinksRev.toStringAsFixed(1)} ج.م'),
                    Text('إيراد الترابيزات: ${tableRev.toStringAsFixed(1)} ج.م'),
                    Text('إجمالي الإيرادات: ${totalIncome.toStringAsFixed(1)} ج.م',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                        'إجمالي المصاريف اليومية: -${totalExpenses.toStringAsFixed(1)} ج.م',
                        style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold)),
                    const Divider(),
                    Text(
                        'الصافي بعد خصم المصاريف: ${netTotal.toStringAsFixed(1)} ج.م',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber)),
                    const SizedBox(height: 6),
                    Text(
                        'إجمالي الشهر الحالي: ${monthTotal.toStringAsFixed(1)} ج.م',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.cyanAccent)),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber.shade700,
                              foregroundColor: Colors.black),
                          onPressed: _showAddExpenseDialog,
                          icon: const Icon(Icons.money_off),
                          label: const Text('إضافة مصروف يومي',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white),
                          onPressed: () => _confirmCloseDayDialog(
                              drinksRev, tableRev, totalExpenses, netTotal),
                          icon: const Icon(Icons.lock_clock),
                          label: const Text('تقفيل اليوم وتصفير الشيفت'),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.redAccent),
                          onPressed: _confirmResetMonthDialog,
                          icon: const Icon(Icons.calendar_month),
                          label: const Text('ريست الشهر'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('مصاريف اليوم (تُخصم من المجمل):',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: _showAddExpenseDialog,
                  icon: const Icon(Icons.add, color: Colors.amber),
                  label: const Text('مصروف جديد',
                      style: TextStyle(color: Colors.amber)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (expenses.isEmpty)
              const Text('مفيش مصاريف مسجلة النهاردة.',
                  style: TextStyle(color: Colors.white60))
            else
              ...expenses.map((exp) => Card(
                    color: const Color(0xFF1D2331),
                    child: ListTile(
                      leading: const Icon(Icons.remove_circle,
                          color: Colors.redAccent),
                      title: Text(exp.title,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                          intl.DateFormat('hh:mm a').format(exp.timestamp)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('-${exp.amount.toStringAsFixed(1)} ج.م',
                              style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.white54),
                            onPressed: () =>
                                widget.db.deleteDailyExpense(exp),
                          ),
                        ],
                      ),
                    ),
                  )),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('سجل الأيام السابقة المتقفلة:',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                if (closedDays.isNotEmpty)
                  TextButton.icon(
                    onPressed: _confirmResetMonthDialog,
                    icon: const Icon(Icons.delete_forever,
                        color: Colors.redAccent, size: 18),
                    label: const Text('تصفير الشهر',
                        style: TextStyle(color: Colors.redAccent)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (closedDays.isEmpty)
              const Text('مفيش أيام اتقفلت لسه.')
            else
              ...closedDays.map((day) => Card(
                    color: const Color(0xFF1D2331),
                    child: ListTile(
                      title: Text(day.dateLabel,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.cyanAccent)),
                      subtitle: Text(
                          'مشاريب: ${day.drinksRevenue.toStringAsFixed(0)} | ترابيزات: ${day.tablesRevenue.toStringAsFixed(0)} | مصاريف: -${day.expensesTotal.toStringAsFixed(0)}'),
                      trailing: Text('${day.grandTotal.toStringAsFixed(1)} ج.م',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF00C896))),
                    ),
                  )),
          ],
        );
      },
    );
  }

  void _confirmResetMonthDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('ريست / تصفير حسابات الشهر'),
        content: const Text(
            'هل أنت متأكد من تصفير سجل الأيام المتقفلة للشهر الحالي؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await widget.db.resetMonthHistory();
            },
            child: const Text('نعم، ريست الشهر'),
          ),
        ],
      ),
    );
  }

  void _showAddExpenseDialog() {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('إضافة مصروف يومي'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'بيان المصروف (مثال: ثلج، بن، صيانة، نظافة)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'المبلغ (ج.م)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade700,
                foregroundColor: Colors.black),
            onPressed: () async {
              final title = titleCtrl.text.trim();
              final amount = double.tryParse(amountCtrl.text) ?? 0.0;
              if (title.isEmpty || amount <= 0) return;
              Navigator.pop(dialogCtx);
              await widget.db.addDailyExpense(title: title, amount: amount);
            },
            child: const Text('خصم من المجمل',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditLogsSection(List<AuditLog> logs) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        return Card(
          child: ListTile(
            title: Text(log.title),
            subtitle: Text(log.message),
          ),
        );
      },
    );
  }

  void _showAddTableDialog() {
    final nameCtrl = TextEditingController();
    final rateCtrl = TextEditingController(text: '50');
    String typeVal = 'normal';

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إضافة ترابيزة جديدة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'اسم الترابيزة (مثال: ترابيزة 2 أو بلياردو 2)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('نوع الترابيزة:', style: TextStyle(fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('ترابيزة عادية (قعدات)'),
                      selected: typeVal == 'normal',
                      selectedColor: const Color(0xFF00C896),
                      labelStyle: TextStyle(
                        color: typeVal == 'normal' ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (_) =>
                          setDialogState(() => typeVal = 'normal'),
                    ),
                    ChoiceChip(
                      label: const Text('ترابيزة ألعاب (بساعة)'),
                      selected: typeVal == 'gaming',
                      selectedColor: const Color(0xFF00C896),
                      labelStyle: TextStyle(
                        color: typeVal == 'gaming' ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (_) =>
                          setDialogState(() => typeVal = 'gaming'),
                    ),
                  ],
                ),
                if (typeVal == 'gaming') ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: rateCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'سعر الساعة (ج.م)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C896),
                foregroundColor: Colors.black,
              ),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final rate = typeVal == 'gaming'
                    ? (double.tryParse(rateCtrl.text) ?? 50.0)
                    : 0.0;
                if (name.isEmpty) return;
                Navigator.pop(dialogCtx);
                await widget.db.addNewTable(
                  name: name,
                  type: typeVal,
                  hourlyRate: rate,
                );
              },
              child: const Text('إضافة الترابيزة',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditTableDialog(GamingTable table) {
    final nameCtrl = TextEditingController(text: table.name);
    final rateCtrl =
        TextEditingController(text: table.hourlyRate.toStringAsFixed(0));
    String typeVal = table.type;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('تعديل بيانات: ${table.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم الترابيزة',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('ترابيزة عادية'),
                      selected: typeVal == 'normal',
                      selectedColor: const Color(0xFF00C896),
                      labelStyle: TextStyle(
                        color: typeVal == 'normal' ? Colors.black : Colors.white,
                      ),
                      onSelected: (_) =>
                          setDialogState(() => typeVal = 'normal'),
                    ),
                    ChoiceChip(
                      label: const Text('ترابيزة ألعاب'),
                      selected: typeVal == 'gaming',
                      selectedColor: const Color(0xFF00C896),
                      labelStyle: TextStyle(
                        color: typeVal == 'gaming' ? Colors.black : Colors.white,
                      ),
                      onSelected: (_) =>
                          setDialogState(() => typeVal = 'gaming'),
                    ),
                  ],
                ),
                if (typeVal == 'gaming') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: rateCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'سعر الساعة (ج.م)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final rate = typeVal == 'gaming'
                    ? (double.tryParse(rateCtrl.text) ?? 0.0)
                    : 0.0;
                if (name.isEmpty) return;
                Navigator.pop(dialogCtx);
                await widget.db.updateTableDetails(table, name, typeVal, rate);
              },
              child: const Text('حفظ التعديل'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteTable(GamingTable table) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('حذف الترابيزة: ${table.name}'),
        content: const Text('هل أنت متأكد من حذف هذه الترابيزة نهائياً؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await widget.db.deleteTable(table);
            },
            child: const Text('نعم، حذف'),
          ),
        ],
      ),
    );
  }

  void _showAttachDrinksDialog(
      GamingTable table, List<InventoryItem> inventory) {
    final Map<InventoryItem, int> tempSelection = {};
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('إضافة مشاريب (Hold) لـ ${table.name}'),
          content: SizedBox(
            width: 400,
            height: 300,
            child: ListView(
              children: inventory.map((item) {
                final count = tempSelection[item] ?? 0;
                return ListTile(
                  title: Text('${item.name} (${item.price} ج.م)'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: count > 0
                            ? () => setDialogState(
                                () => tempSelection[item] = count - 1)
                            : null,
                      ),
                      Text('$count'),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: item.stock > count
                            ? () => setDialogState(
                                () => tempSelection[item] = count + 1)
                            : null,
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                tempSelection.removeWhere((_, v) => v <= 0);
                Navigator.pop(dialogCtx);
                if (tempSelection.isNotEmpty) {
                  await widget.db.attachDrinksToTable(table, tempSelection);
                }
              },
              child: const Text('تأكيد (تفضيل Hold)'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditTableItemsDialog(
      GamingTable table, List<InventoryItem> inventory) {
    final List<AttachedItem> editableItems = List.from(table.attachedItems);

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('تعديل طلبات وفاتورة: ${table.name}'),
          content: SizedBox(
            width: 400,
            height: 300,
            child: editableItems.isEmpty
                ? const Center(
                    child: Text('مفيش مشاريب مضافة للترابيزة دي حالياً.'))
                : ListView.builder(
                    itemCount: editableItems.length,
                    itemBuilder: (context, index) {
                      final item = editableItems[index];
                      return ListTile(
                        title: Text(item.name),
                        subtitle: Text(
                            'السعر: ${item.price} ج.م | الإجمالي: ${item.total.toStringAsFixed(0)}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline,
                                  color: Colors.orange),
                              onPressed: () {
                                setDialogState(() {
                                  if (item.qty > 1) {
                                    editableItems[index] = AttachedItem(
                                        itemId: item.itemId,
                                        name: item.name,
                                        price: item.price,
                                        qty: item.qty - 1);
                                  } else {
                                    editableItems.removeAt(index);
                                  }
                                });
                              },
                            ),
                            Text('${item.qty}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline,
                                  color: Colors.green),
                              onPressed: () {
                                setDialogState(() {
                                  editableItems[index] = AttachedItem(
                                      itemId: item.itemId,
                                      name: item.name,
                                      price: item.price,
                                      qty: item.qty + 1);
                                });
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                setDialogState(() {
                                  editableItems.removeAt(index);
                                });
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogCtx);
                await widget.db.updateTableAttachedItems(table, editableItems);
              },
              child: const Text('حفظ التعديلات'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmTableCheckout(GamingTable table) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('حساب الترابيزة - ${table.name}'),
        content: Text(
            'الإجمالي المطلوب: ${table.grandTotal.toStringAsFixed(2)} ج.م',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('رجوع')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await widget.db.endAndCheckoutTable(table);
            },
            child: const Text('تأكيد التحصيل وتصفير الترابيزة'),
          ),
        ],
      ),
    );
  }

  void _confirmCloseDayDialog(
      double dRev, double tRev, double expensesTotal, double netTotal) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('تقفيل اليوم'),
        content: Text(
            'هل تريد تقفيل اليوم بصافي ${netTotal.toStringAsFixed(1)} ج.م (بعد خصم مصاريف ${expensesTotal.toStringAsFixed(1)} ج.م) وتصفير الشيفت؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await widget.db.closeCurrentDayAndReset(
                drinksRev: dRev,
                tableRev: tRev,
                expensesTotal: expensesTotal,
                grandTotal: netTotal,
              );
            },
            child: const Text('نعم، قفّل'),
          ),
        ],
      ),
    );
  }

  void _showAddInventoryDialog() {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final stockCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('إضافة صنف'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'اسم الصنف')),
            TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'السعر')),
            TextField(
                controller: stockCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'الكمية')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final price = double.tryParse(priceCtrl.text) ?? 0;
              final stock = int.tryParse(stockCtrl.text) ?? 0;
              if (name.isNotEmpty && price > 0) {
                Navigator.pop(dialogCtx);
                await widget.db.addNewInventoryItem(
                    name: name, price: price, stock: stock, threshold: 5);
              }
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }

  void _showEditPriceDialog(InventoryItem item) {
    final ctrl = TextEditingController(text: item.price.toStringAsFixed(1));
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('تعديل سعر: ${item.name}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              final val = double.tryParse(ctrl.text);
              if (val != null && val > 0) {
                Navigator.pop(dialogCtx);
                await widget.db.updateItemPrice(item, val);
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _showEditStockDialog(InventoryItem item) {
    final ctrl = TextEditingController(text: item.stock.toString());
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('تعديل الكمية: ${item.name}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              final val = int.tryParse(ctrl.text);
              if (val != null && val >= 0) {
                Navigator.pop(dialogCtx);
                await widget.db.updateItemStock(item, val);
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 5. ISOLATED TABLE CARD WIDGET (ANTI-LAG)
// =============================================================================

class _TableCardWidget extends StatefulWidget {
  final GamingTable table;
  final List<InventoryItem> inventory;
  final FirestoreService db;
  final VoidCallback onEditTable;
  final VoidCallback onDeleteTable;
  final VoidCallback onAttachDrinks;
  final VoidCallback onEditItems;
  final VoidCallback onCheckout;

  const _TableCardWidget({
    super.key,
    required this.table,
    required this.inventory,
    required this.db,
    required this.onEditTable,
    required this.onDeleteTable,
    required this.onAttachDrinks,
    required this.onEditItems,
    required this.onCheckout,
  });

  @override
  State<_TableCardWidget> createState() => _TableCardWidgetState();
}

class _TableCardWidgetState extends State<_TableCardWidget> {
  late TextEditingController _notesCtrl;
  Timer? _debounceTimer;
  Timer? _localTimer;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _notesCtrl = TextEditingController(text: widget.table.guestNotes);
    _syncTickerState();
  }

  @override
  void didUpdateWidget(covariant _TableCardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isTyping && widget.table.guestNotes != _notesCtrl.text) {
      _notesCtrl.text = widget.table.guestNotes;
    }
    if (oldWidget.table.status != widget.table.status ||
        oldWidget.table.type != widget.table.type) {
      _syncTickerState();
    }
  }

  void _syncTickerState() {
    _localTimer?.cancel();
    if (widget.table.type == 'gaming' && widget.table.status == 'running') {
      _localTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _localTimer?.cancel();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _onNotesChanged(String val) {
    _isTyping = true;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 600), () async {
      await widget.db.updateTableGuestNotes(widget.table.id, val);
      _isTyping = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final table = widget.table;
    final isNormal = table.type == 'normal';
    final isRunning = table.status == 'running';
    final statusColor = isNormal
        ? Colors.purpleAccent
        : (isRunning ? const Color(0xFF00C896) : Colors.grey);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: statusColor.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                          isNormal
                              ? Icons.table_restaurant
                              : Icons.sports_esports,
                          color: statusColor,
                          size: 26),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(table.name,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Chip(
                      label: Text(isNormal
                          ? 'ترابيزة عادية'
                          : 'ساعة: ${table.hourlyRate.toStringAsFixed(0)} ج.م'),
                      backgroundColor: statusColor.withValues(alpha: 0.2),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.edit,
                          size: 20, color: Colors.blueAccent),
                      tooltip: 'تعديل بيانات الترابيزة',
                      onPressed: widget.onEditTable,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 20, color: Colors.redAccent),
                      tooltip: 'حذف الترابيزة',
                      onPressed: widget.onDeleteTable,
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                if (!isNormal)
                  _metricColumn('الوقت', table.formattedDuration, statusColor),
                if (!isNormal)
                  _metricColumn(
                      'حساب الوقت',
                      '${table.currentTimeCost.toStringAsFixed(1)} ج.م',
                      Colors.white),
                _metricColumn(
                    'حساب المشاريب (Hold)',
                    '${table.attachedDrinksCost.toStringAsFixed(1)} ج.م',
                    Colors.amber),
                _metricColumn(
                    'الإجمالي',
                    '${table.grandTotal.toStringAsFixed(1)} ج.م',
                    const Color(0xFF00C896)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              onChanged: _onNotesChanged,
              decoration: InputDecoration(
                labelText: 'أسماء الأشخاص / الملاحظات',
                hintText: 'اكتب أسماء الأشخاص...',
                prefixIcon: const Icon(Icons.person, color: Color(0xFF00C896)),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: Colors.black26,
              ),
              maxLines: 2,
            ),
            if (table.attachedItems.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: table.attachedItems
                    .map((item) => ActionChip(
                          avatar: const Icon(Icons.edit, size: 14),
                          label: Text(
                              '${item.name} × ${item.qty} (${item.total.toStringAsFixed(0)} ج.م)'),
                          backgroundColor:
                              Colors.amber.shade900.withValues(alpha: 0.4),
                          onPressed: widget.onEditItems,
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!isNormal) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00C896),
                        foregroundColor: Colors.black),
                    onPressed: isRunning
                        ? null
                        : () => widget.db.startTableTimer(table),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('تشغيل'),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade700,
                        foregroundColor: Colors.black),
                    onPressed: isRunning
                        ? () => widget.db.pauseTableTimer(table)
                        : null,
                    icon: const Icon(Icons.pause),
                    label: const Text('إيقاف'),
                  ),
                ],
                OutlinedButton.icon(
                  onPressed: widget.onAttachDrinks,
                  icon: const Icon(Icons.local_cafe),
                  label: const Text('إضافة مشاريب (Hold)'),
                ),
                if (table.attachedItems.isNotEmpty)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orangeAccent),
                    onPressed: widget.onEditItems,
                    icon: const Icon(Icons.edit_note),
                    label: const Text('تعديل الطلبات'),
                  ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white),
                  onPressed: (table.currentElapsedSeconds > 0 ||
                          table.attachedItems.isNotEmpty)
                      ? widget.onCheckout
                      : null,
                  icon: const Icon(Icons.receipt),
                  label: const Text('إنهاء وحساب'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.white70)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}
