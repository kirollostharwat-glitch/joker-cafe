import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
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
    final data = doc.data() as Map<String, dynamic>? ?? {};
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

class GamingTable {
  final String id;
  final String name;
  final double hourlyRate;
  final String status; // 'idle', 'running', 'paused'
  final DateTime? lastStartTime;
  final int accumulatedSeconds;
  final List<AttachedItem> attachedItems;
  final String guestNotes; // خانة أسماء الأشخاص والملاحظات لكل ترابيزة

  GamingTable({
    required this.id,
    required this.name,
    required this.hourlyRate,
    required this.status,
    this.lastStartTime,
    required this.accumulatedSeconds,
    required this.attachedItems,
    this.guestNotes = '',
  });

  int get currentElapsedSeconds {
    if (status == 'running' && lastStartTime != null) {
      final diff = DateTime.now().difference(lastStartTime!).inSeconds;
      return accumulatedSeconds + (diff > 0 ? diff : 0);
    }
    return accumulatedSeconds;
  }

  double get currentTimeCost => (currentElapsedSeconds / 3600.0) * hourlyRate;

  double get attachedDrinksCost =>
      attachedItems.fold(0.0, (sum, item) => sum + item.total);

  double get grandTotal => currentTimeCost + attachedDrinksCost;

  String get formattedDuration {
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
      id: docId ?? data['id'] ?? 'billiard',
      name: data['name'] ?? '',
      hourlyRate: (data['hourlyRate'] ?? 50.0).toDouble(),
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
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return GamingTable.fromMap(data, doc.id);
  }
}

class SaleRecord {
  final String id;
  final String type;
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

    return SaleRecord(
      id: docId ?? data['id'] ?? const Uuid().v4(),
      type: data['type'] ?? 'drinks_only',
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
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return SaleRecord.fromMap(data, doc.id);
  }
}

class ClosedDaySummary {
  final String id;
  final String dateLabel;
  final double drinksRevenue;
  final double billiardRevenue;
  final double pingPongRevenue;
  final double grandTotal;
  final DateTime closedAt;

  ClosedDaySummary({
    required this.id,
    required this.dateLabel,
    required this.drinksRevenue,
    required this.billiardRevenue,
    required this.pingPongRevenue,
    required this.grandTotal,
    required this.closedAt,
  });

  Map<String, dynamic> toMap({bool forLocal = false}) => {
        'id': id,
        'dateLabel': dateLabel,
        'drinksRevenue': drinksRevenue,
        'billiardRevenue': billiardRevenue,
        'pingPongRevenue': pingPongRevenue,
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
      billiardRevenue: (data['billiardRevenue'] ?? 0).toDouble(),
      pingPongRevenue: (data['pingPongRevenue'] ?? 0).toDouble(),
      grandTotal: (data['grandTotal'] ?? 0).toDouble(),
      closedAt: parsedTime,
    );
  }

  factory ClosedDaySummary.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
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
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return AuditLog.fromMap(data, doc.id);
  }
}

// =============================================================================
// 2. CROSS-PLATFORM ALERT & SOUND NOTIFICATION SERVICE
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
          duration: const Duration(seconds: 4),
          content: Row(
            children: [
              const Icon(Icons.notifications_active, color: Color(0xFF00C896)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00C896),
                      ),
                    ),
                    Text(
                      body,
                      style: const TextStyle(color: Colors.white),
                    ),
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
// 3. HYBRID FIRESTORE + LOCAL OFFLINE SYNC SERVICE
// =============================================================================

class FirestoreService {
  FirebaseFirestore? _db;
  bool useCloud = false;
  late SharedPreferences _prefs;
  late String deviceId;
  bool _isInitialAuditLoad = true;

  final _tablesCtrl = StreamController<List<GamingTable>>.broadcast();
  final _invCtrl = StreamController<List<InventoryItem>>.broadcast();
  final _salesCtrl = StreamController<List<SaleRecord>>.broadcast();
  final _closedDaysCtrl = StreamController<List<ClosedDaySummary>>.broadcast();
  final _logsCtrl = StreamController<List<AuditLog>>.broadcast();

  List<GamingTable> _localTables = [];
  List<InventoryItem> _localInv = [];
  List<SaleRecord> _localSales = [];
  List<ClosedDaySummary> _localClosedDays = [];
  List<AuditLog> _localLogs = [];

  Future<void> initAndSeed({required bool firebaseReady}) async {
    _prefs = await SharedPreferences.getInstance();
    String? storedId = _prefs.getString('device_instance_id');
    if (storedId == null) {
      storedId = const Uuid().v4();
      await _prefs.setString('device_instance_id', storedId);
    }
    deviceId = storedId;

    if (firebaseReady) {
      try {
        _db = FirebaseFirestore.instance;
        _db!.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );
        useCloud = true;
      } catch (_) {
        useCloud = false;
      }
    }

    if (useCloud) {
      await _seedCloudDataIfNeeded();
      _listenToAuditLogsForNotifications();
    } else {
      _loadAndSeedLocalData();
    }
  }

  void _loadAndSeedLocalData() {
    final tRaw = _prefs.getString('local_tables');
    if (tRaw != null) {
      final list = jsonDecode(tRaw) as List;
      _localTables = list
          .map((e) => GamingTable.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } else {
      _localTables = [
        GamingTable(
          id: 'billiard',
          name: 'ترابيزة البلياردو',
          hourlyRate: 60.0,
          status: 'idle',
          accumulatedSeconds: 0,
          attachedItems: [],
        ),
        GamingTable(
          id: 'pingpong',
          name: 'ترابيزة البينج بونج',
          hourlyRate: 45.0,
          status: 'idle',
          accumulatedSeconds: 0,
          attachedItems: [],
        ),
      ];
    }

    final iRaw = _prefs.getString('local_inv');
    if (iRaw != null) {
      final list = jsonDecode(iRaw) as List;
      _localInv = list
          .map((e) => InventoryItem.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } else {
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
      final list = jsonDecode(sRaw) as List;
      _localSales = list
          .map((e) => SaleRecord.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    }

    final cRaw = _prefs.getString('local_closed_days');
    if (cRaw != null) {
      final list = jsonDecode(cRaw) as List;
      _localClosedDays = list
          .map((e) => ClosedDaySummary.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    }

    final lRaw = _prefs.getString('local_logs');
    if (lRaw != null) {
      final list = jsonDecode(lRaw) as List;
      _localLogs = list
          .map((e) => AuditLog.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    }

    _saveAndEmitLocal();
  }

  void _saveAndEmitLocal() {
    _prefs.setString(
        'local_tables',
        jsonEncode(
            _localTables.map((e) => e.toMap(forLocal: true)).toList()));
    _prefs.setString(
        'local_inv', jsonEncode(_localInv.map((e) => e.toMap()).toList()));
    _prefs.setString('local_sales',
        jsonEncode(_localSales.map((e) => e.toMap(forLocal: true)).toList()));
    _prefs.setString(
        'local_closed_days',
        jsonEncode(
            _localClosedDays.map((e) => e.toMap(forLocal: true)).toList()));
    _prefs.setString('local_logs',
        jsonEncode(_localLogs.map((e) => e.toMap(forLocal: true)).toList()));

    _tablesCtrl.add(List.from(_localTables));
    _invCtrl.add(List.from(_localInv));
    _salesCtrl.add(_localSales.where((s) => !s.isClosed).toList());
    _closedDaysCtrl.add(List.from(_localClosedDays));
    _logsCtrl.add(List.from(_localLogs));
  }

  Future<void> _seedCloudDataIfNeeded() async {
    try {
      final tablesSnap = await _db!.collection('tables').get();
      if (tablesSnap.docs.isEmpty) {
        await _db!.collection('tables').doc('billiard').set(GamingTable(
              id: 'billiard',
              name: 'ترابيزة البلياردو',
              hourlyRate: 60.0,
              status: 'idle',
              accumulatedSeconds: 0,
              attachedItems: [],
            ).toMap());

        await _db!.collection('tables').doc('pingpong').set(GamingTable(
              id: 'pingpong',
              name: 'ترابيزة البينج بونج',
              hourlyRate: 45.0,
              status: 'idle',
              accumulatedSeconds: 0,
              attachedItems: [],
            ).toMap());
      }
    } catch (_) {}
  }

  void _listenToAuditLogsForNotifications() {
    _db!
        .collection('audit_logs')
        .orderBy('timestamp', descending: true)
        .limit(20)
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
      if (_isInitialAuditLoad) {
        _isInitialAuditLoad = false;
        return;
      }

      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          if (change.doc.metadata.hasPendingWrites) continue;
          final log = AuditLog.fromDoc(change.doc);
          if (log.deviceId == deviceId) continue;

          NotificationService().showEgyptianAlert(
            id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            title: log.title,
            body: log.message,
          );
        }
      }
    });
  }

  Future<void> _recordAudit({
    required String title,
    required String message,
    required String beforeVal,
    required String afterVal,
  }) async {
    final log = AuditLog(
      id: const Uuid().v4(),
      title: title,
      message: message,
      beforeVal: beforeVal,
      afterVal: afterVal,
      deviceId: deviceId,
      timestamp: DateTime.now(),
    );

    if (useCloud) {
      await _db!.collection('audit_logs').add(log.toMap());
    } else {
      _localLogs.insert(0, log);
      _saveAndEmitLocal();
    }
  }

  Stream<List<GamingTable>> streamTables() {
    if (useCloud) {
      return _db!
          .collection('tables')
          .snapshots()
          .map((s) => s.docs.map(GamingTable.fromDoc).toList());
    }
    Future.microtask(() => _tablesCtrl.add(List.from(_localTables)));
    return _tablesCtrl.stream;
  }

  Stream<List<InventoryItem>> streamInventory() {
    if (useCloud) {
      return _db!
          .collection('inventory')
          .snapshots()
          .map((s) => s.docs.map(InventoryItem.fromDoc).toList());
    }
    Future.microtask(() => _invCtrl.add(List.from(_localInv)));
    return _invCtrl.stream;
  }

  Stream<List<SaleRecord>> streamTodaySales() {
    if (useCloud) {
      return _db!.collection('sales').snapshots().map((s) => s.docs
          .map(SaleRecord.fromDoc)
          .where((sale) => !sale.isClosed)
          .toList());
    }
    Future.microtask(
        () => _salesCtrl.add(_localSales.where((s) => !s.isClosed).toList()));
    return _salesCtrl.stream;
  }

  Stream<List<ClosedDaySummary>> streamClosedDays() {
    if (useCloud) {
      return _db!
          .collection('closed_days')
          .orderBy('closedAt', descending: true)
          .snapshots()
          .map((s) => s.docs.map(ClosedDaySummary.fromDoc).toList());
    }
    Future.microtask(() => _closedDaysCtrl.add(List.from(_localClosedDays)));
    return _closedDaysCtrl.stream;
  }

  Stream<List<AuditLog>> streamAuditLogs() {
    if (useCloud) {
      return _db!
          .collection('audit_logs')
          .orderBy('timestamp', descending: true)
          .limit(100)
          .snapshots()
          .map((s) => s.docs.map(AuditLog.fromDoc).toList());
    }
    Future.microtask(() => _logsCtrl.add(List.from(_localLogs)));
    return _logsCtrl.stream;
  }

  Future<void> startTableTimer(GamingTable table) async {
    if (useCloud) {
      await _db!.collection('tables').doc(table.id).update({
        'status': 'running',
        'lastStartTime': Timestamp.fromDate(DateTime.now()),
      });
    } else {
      final idx = _localTables.indexWhere((t) => t.id == table.id);
      if (idx >= 0) {
        _localTables[idx] = GamingTable(
          id: table.id,
          name: table.name,
          hourlyRate: table.hourlyRate,
          status: 'running',
          lastStartTime: DateTime.now(),
          accumulatedSeconds: table.accumulatedSeconds,
          attachedItems: table.attachedItems,
          guestNotes: table.guestNotes,
        );
        _saveAndEmitLocal();
      }
    }
    await _recordAudit(
      title: 'تنبيه ترابيزة: ${table.name}',
      message: 'تم تشغيل الوقت على ${table.name}',
      beforeVal: 'متوقفة',
      afterVal: 'شغالة الآن',
    );
  }

  Future<void> pauseTableTimer(GamingTable table) async {
    final totalElapsed = table.currentElapsedSeconds;
    if (useCloud) {
      await _db!.collection('tables').doc(table.id).update({
        'status': 'paused',
        'lastStartTime': null,
        'accumulatedSeconds': totalElapsed,
      });
    } else {
      final idx = _localTables.indexWhere((t) => t.id == table.id);
      if (idx >= 0) {
        _localTables[idx] = GamingTable(
          id: table.id,
          name: table.name,
          hourlyRate: table.hourlyRate,
          status: 'paused',
          lastStartTime: null,
          accumulatedSeconds: totalElapsed,
          attachedItems: table.attachedItems,
          guestNotes: table.guestNotes,
        );
        _saveAndEmitLocal();
      }
    }
    await _recordAudit(
      title: 'تنبيه ترابيزة: ${table.name}',
      message: 'تم إيقاف مؤقت لـ ${table.name}',
      beforeVal: 'شغالة',
      afterVal: 'إيقاف مؤقت (${table.formattedDuration})',
    );
  }

  Future<void> updateTableHourlyRate(GamingTable table, double newRate) async {
    final oldRate = table.hourlyRate;
    if (useCloud) {
      await _db!.collection('tables').doc(table.id).update({
        'hourlyRate': newRate,
      });
    } else {
      final idx = _localTables.indexWhere((t) => t.id == table.id);
      if (idx >= 0) {
        _localTables[idx] = GamingTable(
          id: table.id,
          name: table.name,
          hourlyRate: newRate,
          status: table.status,
          lastStartTime: table.lastStartTime,
          accumulatedSeconds: table.accumulatedSeconds,
          attachedItems: table.attachedItems,
          guestNotes: table.guestNotes,
        );
        _saveAndEmitLocal();
      }
    }
    await _recordAudit(
      title: 'تنبيه تعديل سعر الساعة',
      message:
          'تم تغيير سعر ساعة ${table.name} من ${oldRate.toStringAsFixed(0)} إلى ${newRate.toStringAsFixed(0)} ج.م',
      beforeVal: '${oldRate.toStringAsFixed(0)} ج.م',
      afterVal: '${newRate.toStringAsFixed(0)} ج.م',
    );
  }

  Future<void> updateTableGuestNotes(GamingTable table, String notes) async {
    if (useCloud) {
      await _db!.collection('tables').doc(table.id).update({
        'guestNotes': notes,
      });
    } else {
      final idx = _localTables.indexWhere((t) => t.id == table.id);
      if (idx >= 0) {
        _localTables[idx] = GamingTable(
          id: table.id,
          name: table.name,
          hourlyRate: table.hourlyRate,
          status: table.status,
          lastStartTime: table.lastStartTime,
          accumulatedSeconds: table.accumulatedSeconds,
          attachedItems: table.attachedItems,
          guestNotes: notes,
        );
        _saveAndEmitLocal();
      }
    }
  }

  Future<void> attachDrinksToTable(
      GamingTable table, Map<InventoryItem, int> selectedDrinks) async {
    final updatedList = List<AttachedItem>.from(table.attachedItems);

    for (final entry in selectedDrinks.entries) {
      final item = entry.key;
      final qty = entry.value;
      final newStock = (item.stock - qty).clamp(0, 999999);

      if (useCloud) {
        await _db!
            .collection('inventory')
            .doc(item.id)
            .update({'stock': newStock});
      } else {
        final iIdx = _localInv.indexWhere((i) => i.id == item.id);
        if (iIdx >= 0) {
          _localInv[iIdx] = InventoryItem(
            id: item.id,
            name: item.name,
            price: item.price,
            stock: newStock,
            lowStockThreshold: item.lowStockThreshold,
          );
        }
      }

      final existingIndex =
          updatedList.indexWhere((element) => element.itemId == item.id);
      if (existingIndex >= 0) {
        final existing = updatedList[existingIndex];
        updatedList[existingIndex] = AttachedItem(
          itemId: existing.itemId,
          name: existing.name,
          price: existing.price,
          qty: existing.qty + qty,
        );
      } else {
        updatedList.add(AttachedItem(
          itemId: item.id,
          name: item.name,
          price: item.price,
          qty: qty,
        ));
      }
    }

    if (useCloud) {
      await _db!.collection('tables').doc(table.id).update({
        'attachedItems': updatedList.map((e) => e.toMap()).toList(),
      });
    } else {
      final tIdx = _localTables.indexWhere((t) => t.id == table.id);
      if (tIdx >= 0) {
        _localTables[tIdx] = GamingTable(
          id: table.id,
          name: table.name,
          hourlyRate: table.hourlyRate,
          status: table.status,
          lastStartTime: table.lastStartTime,
          accumulatedSeconds: table.accumulatedSeconds,
          attachedItems: updatedList,
          guestNotes: table.guestNotes,
        );
      }
      _saveAndEmitLocal();
    }
  }

  Future<SaleRecord> endAndCheckoutTable(GamingTable table) async {
    final elapsedSecs = table.currentElapsedSeconds;
    final timeCost = table.currentTimeCost;
    final drinksCost = table.attachedDrinksCost;
    final total = timeCost + drinksCost;

    final sale = SaleRecord(
      id: const Uuid().v4(),
      type: table.id == 'billiard' ? 'billiard_checkout' : 'pingpong_checkout',
      timeRevenue: timeCost,
      drinksRevenue: drinksCost,
      totalRevenue: total,
      playedSeconds: elapsedSecs,
      soldItems: List<AttachedItem>.from(table.attachedItems),
      timestamp: DateTime.now(),
      isClosed: false,
    );

    if (useCloud) {
      await _db!.collection('sales').add(sale.toMap());
      await _db!.collection('tables').doc(table.id).update({
        'status': 'idle',
        'lastStartTime': null,
        'accumulatedSeconds': 0,
        'attachedItems': [],
        'guestNotes': '',
      });
    } else {
      _localSales.insert(0, sale);
      final idx = _localTables.indexWhere((t) => t.id == table.id);
      if (idx >= 0) {
        _localTables[idx] = GamingTable(
          id: table.id,
          name: table.name,
          hourlyRate: table.hourlyRate,
          status: 'idle',
          lastStartTime: null,
          accumulatedSeconds: 0,
          attachedItems: [],
          guestNotes: '',
        );
      }
      _saveAndEmitLocal();
    }

    await _recordAudit(
      title: 'حساب ترابيزة: ${table.name}',
      message:
          'تم إنهاء وحساب ${table.name} بإجمالي ${total.toStringAsFixed(1)} ج.م',
      beforeVal: table.formattedDuration,
      afterVal: 'تم التصفير (الحساب: ${total.toStringAsFixed(1)} ج.م)',
    );

    return sale;
  }

  Future<void> checkoutDirectPos(Map<InventoryItem, int> cart) async {
    double totalDrinks = 0;
    final List<AttachedItem> soldItems = [];

    for (final entry in cart.entries) {
      final item = entry.key;
      final qty = entry.value;
      totalDrinks += item.price * qty;

      soldItems.add(AttachedItem(
        itemId: item.id,
        name: item.name,
        price: item.price,
        qty: qty,
      ));

      final newStock = (item.stock - qty).clamp(0, 999999);
      if (useCloud) {
        await _db!
            .collection('inventory')
            .doc(item.id)
            .update({'stock': newStock});
      } else {
        final idx = _localInv.indexWhere((i) => i.id == item.id);
        if (idx >= 0) {
          _localInv[idx] = InventoryItem(
            id: item.id,
            name: item.name,
            price: item.price,
            stock: newStock,
            lowStockThreshold: item.lowStockThreshold,
          );
        }
      }
    }

    final sale = SaleRecord(
      id: const Uuid().v4(),
      type: 'drinks_only',
      timeRevenue: 0,
      drinksRevenue: totalDrinks,
      totalRevenue: totalDrinks,
      playedSeconds: 0,
      soldItems: soldItems,
      timestamp: DateTime.now(),
      isClosed: false,
    );

    if (useCloud) {
      await _db!.collection('sales').add(sale.toMap());
    } else {
      _localSales.insert(0, sale);
      _saveAndEmitLocal();
    }
  }

  Future<void> closeCurrentDayAndReset({
    required double drinksRev,
    required double billiardRev,
    required double pingPongRev,
    required double grandTotal,
  }) async {
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    double extraBilliard = 0;
    double extraPingPong = 0;
    double extraDrinks = 0;

    if (useCloud) {
      final tablesSnap = await _db!.collection('tables').get();
      for (final doc in tablesSnap.docs) {
        final t = GamingTable.fromDoc(doc);
        if (t.currentElapsedSeconds > 0 || t.attachedItems.isNotEmpty) {
          if (t.id == 'billiard') {
            extraBilliard += t.currentTimeCost;
          } else {
            extraPingPong += t.currentTimeCost;
          }
          extraDrinks += t.attachedDrinksCost;

          await doc.reference.update({
            'status': 'idle',
            'lastStartTime': null,
            'accumulatedSeconds': 0,
            'attachedItems': [],
            'guestNotes': '',
          });
        }
      }
    } else {
      for (int i = 0; i < _localTables.length; i++) {
        final t = _localTables[i];
        if (t.currentElapsedSeconds > 0 || t.attachedItems.isNotEmpty) {
          if (t.id == 'billiard') {
            extraBilliard += t.currentTimeCost;
          } else {
            extraPingPong += t.currentTimeCost;
          }
          extraDrinks += t.attachedDrinksCost;

          _localTables[i] = GamingTable(
            id: t.id,
            name: t.name,
            hourlyRate: t.hourlyRate,
            status: 'idle',
            lastStartTime: null,
            accumulatedSeconds: 0,
            attachedItems: [],
            guestNotes: '',
          );
        }
      }
    }

    final finalDrinks = drinksRev + extraDrinks;
    final finalBilliard = billiardRev + extraBilliard;
    final finalPingPong = pingPongRev + extraPingPong;
    final finalGrandTotal = finalDrinks + finalBilliard + finalPingPong;

    final summary = ClosedDaySummary(
      id: const Uuid().v4(),
      dateLabel: dateStr,
      drinksRevenue: finalDrinks,
      billiardRevenue: finalBilliard,
      pingPongRevenue: finalPingPong,
      grandTotal: finalGrandTotal,
      closedAt: now,
    );

    if (useCloud) {
      if (finalGrandTotal > 0) {
        await _db!.collection('closed_days').add(summary.toMap());
      }
      final allSalesSnap = await _db!.collection('sales').get();
      for (final doc in allSalesSnap.docs) {
        try {
          await doc.reference.delete();
        } catch (_) {
          await doc.reference.update({'isClosed': true});
        }
      }
    } else {
      if (finalGrandTotal > 0) {
        _localClosedDays.insert(0, summary);
      }
      _localSales.clear();
      _saveAndEmitLocal();
    }

    await _recordAudit(
      title: 'تنبيه تقفيل اليوم - Joker Cafe',
      message:
          'تم تقفيل حسابات يوم $dateStr بإجمالي ${finalGrandTotal.toStringAsFixed(1)} ج.م وتصفير الشيفت',
      beforeVal: '${finalGrandTotal.toStringAsFixed(1)} ج.م',
      afterVal: '0.0 ج.م (تم التصفير)',
    );
  }

  Future<void> addNewInventoryItem({
    required String name,
    required double price,
    required int stock,
    required int threshold,
  }) async {
    if (useCloud) {
      await _db!.collection('inventory').add({
        'name': name,
        'price': price,
        'stock': stock,
        'lowStockThreshold': threshold,
      });
    } else {
      _localInv.add(InventoryItem(
        id: const Uuid().v4(),
        name: name,
        price: price,
        stock: stock,
        lowStockThreshold: threshold,
      ));
      _saveAndEmitLocal();
    }
    await _recordAudit(
      title: 'إضافة صنف جديد للمخزن',
      message: 'تم إضافة [$name] بسعر $price ج.م وكمية $stock',
      beforeVal: 'غير موجود',
      afterVal: '$price ج.م ($stock قطعة)',
    );
  }

  Future<void> updateItemPrice(InventoryItem item, double newPrice) async {
    final oldPrice = item.price;
    if (useCloud) {
      await _db!
          .collection('inventory')
          .doc(item.id)
          .update({'price': newPrice});
    } else {
      final idx = _localInv.indexWhere((i) => i.id == item.id);
      if (idx >= 0) {
        _localInv[idx] = InventoryItem(
          id: item.id,
          name: item.name,
          price: newPrice,
          stock: item.stock,
          lowStockThreshold: item.lowStockThreshold,
        );
        _saveAndEmitLocal();
      }
    }
    await _recordAudit(
      title: 'تنبيه تعديل سعر',
      message:
          'تم تغيير سعر [${item.name}] من ${oldPrice.toStringAsFixed(1)} إلى ${newPrice.toStringAsFixed(1)} ج.م',
      beforeVal: '${oldPrice.toStringAsFixed(1)} ج.م',
      afterVal: '${newPrice.toStringAsFixed(1)} ج.م',
    );
  }

  Future<void> updateItemStock(InventoryItem item, int newStock) async {
    final oldStock = item.stock;
    if (useCloud) {
      await _db!
          .collection('inventory')
          .doc(item.id)
          .update({'stock': newStock});
    } else {
      final idx = _localInv.indexWhere((i) => i.id == item.id);
      if (idx >= 0) {
        _localInv[idx] = InventoryItem(
          id: item.id,
          name: item.name,
          price: item.price,
          stock: newStock,
          lowStockThreshold: item.lowStockThreshold,
        );
        _saveAndEmitLocal();
      }
    }
    await _recordAudit(
      title: 'تنبيه مخزن',
      message: 'تم تعديل كمية [${item.name}] من $oldStock إلى $newStock',
      beforeVal: '$oldStock',
      afterVal: '$newStock',
    );
  }

  Future<void> deleteInventoryItem(InventoryItem item) async {
    if (useCloud) {
      await _db!.collection('inventory').doc(item.id).delete();
    } else {
      _localInv.removeWhere((i) => i.id == item.id);
      _saveAndEmitLocal();
    }
    await _recordAudit(
      title: 'حذف صنف من المخزن',
      message: 'تم حذف الصنف [${item.name}] نهائياً من المخزن',
      beforeVal: '${item.stock} بالمخزن',
      afterVal: 'محذوف',
    );
  }
}

// =============================================================================
// 4. EXPORT SERVICE
// =============================================================================

class ExportService {
  static Future<void> exportDailyPdfReport({
    required List<SaleRecord> sales,
    required List<AuditLog> logs,
    required double drinksRev,
    required double billiardRev,
    required double pingPongRev,
    required double grandTotal,
    required Map<String, int> itemBreakdown,
  }) async {
    final pdf = pw.Document();
    final arabicFont = await PdfGoogleFonts.cairoRegular();
    final arabicBold = await PdfGoogleFonts.cairoBold();
    final dateStr = intl.DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicBold),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Joker Cafe - تقرير تقفيل الشيفت وحسابات اليوم',
                    style: pw.TextStyle(font: arabicBold, fontSize: 18)),
                pw.Text('التاريخ: $dateStr',
                    style: const pw.TextStyle(fontSize: 12)),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey700),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('إيراد المشاريب: ${drinksRev.toStringAsFixed(2)} ج.م'),
                pw.Text(
                    'إيراد البلياردو: ${billiardRev.toStringAsFixed(2)} ج.م'),
                pw.Text(
                    'إيراد البينج بونج: ${pingPongRev.toStringAsFixed(2)} ج.م'),
                pw.Divider(),
                pw.Text(
                  'الإجمالي الكلي: ${grandTotal.toStringAsFixed(2)} ج.م',
                  style: pw.TextStyle(font: arabicBold, fontSize: 16),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 18),
          pw.Text('تفاصيل المشاريب المباعة اليوم:',
              style: pw.TextStyle(font: arabicBold, fontSize: 14)),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: ['الكمية المباعة', 'اسم الصنف'],
            data: itemBreakdown.entries
                .map((e) => [e.value.toString(), e.key])
                .toList(),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'JokerCafe_Report_$dateStr.pdf',
    );
  }

  static Future<String> exportExcelReport({
    required List<SaleRecord> sales,
    required List<AuditLog> logs,
    required double drinksRev,
    required double billiardRev,
    required double pingPongRev,
    required double grandTotal,
    required Map<String, int> itemBreakdown,
  }) async {
    final excel = Excel.createExcel();
    final summarySheet = excel['ملخص اليوم'];
    excel.setDefaultSheet('ملخص اليوم');

    summarySheet.appendRow([
      TextCellValue('Joker Cafe - البند'),
      TextCellValue('القيمة (ج.م)'),
    ]);
    summarySheet.appendRow([
      TextCellValue('إيراد المشاريب'),
      DoubleCellValue(drinksRev),
    ]);
    summarySheet.appendRow([
      TextCellValue('إيراد البلياردو'),
      DoubleCellValue(billiardRev),
    ]);
    summarySheet.appendRow([
      TextCellValue('إيراد البينج بونج'),
      DoubleCellValue(pingPongRev),
    ]);
    summarySheet.appendRow([
      TextCellValue('الإجمالي الكلي'),
      DoubleCellValue(grandTotal),
    ]);

    final fileBytes = excel.save();
    if (fileBytes == null) throw Exception('فشل إنشاء ملف الإكسيل');

    final timestamp = intl.DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final fileName = 'JokerCafe_Report_$timestamp.xlsx';

    if (Platform.isWindows) {
      final downloadsDir = await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      final filePath = '${downloadsDir.path}\\$fileName';
      final file = File(filePath);
      await file.writeAsBytes(fileBytes);
      return 'تم حفظ شيت الإكسيل في التنزيلات:\n$filePath';
    } else {
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(fileBytes);
      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'Joker Cafe - تقرير تقفيل الشيفت وحسابات اليوم',
      );
      return 'تم تجهيز شيت الإكسيل للمشاركة';
    }
  }
}

// =============================================================================
// 5. MAIN ENTRY POINT & UI
// =============================================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  bool firebaseReady = false;
  try {
    await Firebase.initializeApp();
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
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
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
  bool _isOnline = true;
  late StreamSubscription<List<ConnectivityResult>> _connSub;
  late Timer _liveClockTicker;
  final Map<String, int> _posCart = {};

  @override
  void initState() {
    super.initState();
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final connected = !results.contains(ConnectivityResult.none);
      if (mounted && connected != _isOnline) {
        setState(() => _isOnline = connected);
      }
    });

    _liveClockTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _connSub.cancel();
    _liveClockTicker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GamingTable>>(
      stream: widget.db.streamTables(),
      builder: (context, tablesSnap) {
        return StreamBuilder<List<InventoryItem>>(
          stream: widget.db.streamInventory(),
          builder: (context, invSnap) {
            return StreamBuilder<List<SaleRecord>>(
              stream: widget.db.streamTodaySales(),
              builder: (context, salesSnap) {
                return StreamBuilder<List<AuditLog>>(
                  stream: widget.db.streamAuditLogs(),
                  builder: (context, logsSnap) {
                    final tables = tablesSnap.data ?? [];
                    final inventory = invSnap.data ?? [];
                    final sales = salesSnap.data ?? [];
                    final logs = logsSnap.data ?? [];

                    final todayTotal = sales.fold<double>(
                        0.0, (sum, s) => sum + s.totalRevenue);

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final isWideDesktop = constraints.maxWidth >= 900;

                        return Scaffold(
                          appBar: AppBar(
                            backgroundColor: const Color(0xFF181E2C),
                            elevation: 2,
                            title: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.purple.shade900,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: const Color(0xFF00C896)),
                                  ),
                                  child: const Icon(
                                    Icons.theater_comedy,
                                    color: Color(0xFF00C896),
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Joker Cafe - لوحة تحكم الأدمن',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: const Color(0xFF00C896)),
                                  ),
                                  child: Text(
                                    'إجمالي الشيفت: ${todayTotal.toStringAsFixed(1)} ج.م',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF00C896),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            bottom: PreferredSize(
                              preferredSize: const Size.fromHeight(30),
                              child: Container(
                                width: double.infinity,
                                color: _isOnline
                                    ? Colors.green.shade800
                                    : Colors.orange.shade900,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 4, horizontal: 16),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _isOnline ? Icons.wifi : Icons.wifi_off,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _isOnline
                                          ? 'متصل بالنت - متزامن لحظياً بين اللاب والموبايل'
                                          : 'أوفلاين - شغال على التخزين المحلي',
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          body: isWideDesktop
                              ? _buildWindowsDesktopView(
                                  tables, inventory, sales, logs)
                              : _buildAndroidMobileView(
                                  tables, inventory, sales, logs),
                          bottomNavigationBar: isWideDesktop
                              ? null
                              : NavigationBar(
                                  selectedIndex: _selectedIndex,
                                  onDestinationSelected: (idx) =>
                                      setState(() => _selectedIndex = idx),
                                  destinations: const [
                                    NavigationDestination(
                                      icon: Icon(Icons.sports_esports),
                                      label: 'الترابيزات',
                                    ),
                                    NavigationDestination(
                                      icon: Icon(Icons.point_of_sale),
                                      label: 'الكاشير',
                                    ),
                                    NavigationDestination(
                                      icon: Icon(Icons.inventory_2),
                                      label: 'المخزن',
                                    ),
                                    NavigationDestination(
                                      icon: Icon(Icons.bar_chart),
                                      label: 'تقفيل اليوم',
                                    ),
                                    NavigationDestination(
                                      icon: Icon(Icons.notifications_active),
                                      label: 'التعديلات',
                                    ),
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
  }

  Widget _buildWindowsDesktopView(
    List<GamingTable> tables,
    List<InventoryItem> inventory,
    List<SaleRecord> sales,
    List<AuditLog> logs,
  ) {
    final desktopIndex = _selectedIndex > 3 ? 0 : _selectedIndex;

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
              label: Text('الترابيزات والكاشير'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.inventory_2),
              label: Text('إدارة المخزن والأسعار'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.assessment),
              label: Text('التقارير وتقفيل اليوم'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.history),
              label: Text('سجل التعديلات والإشعارات'),
            ),
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
                        child: _buildTablesSection(tables, inventory),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        flex: 5,
                        child: _buildPosSection(inventory, tables),
                      ),
                    ],
                  );
                case 1:
                  return _buildInventorySection(inventory, tables);
                case 2:
                  return _buildReportsSection(sales, logs);
                case 3:
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
    List<AuditLog> logs,
  ) {
    switch (_selectedIndex) {
      case 0:
        return _buildTablesSection(tables, inventory);
      case 1:
        return _buildPosSection(inventory, tables);
      case 2:
        return _buildInventorySection(inventory, tables);
      case 3:
        return _buildReportsSection(sales, logs);
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
        const Text(
          'إدارة الترابيزات - بلياردو وبينج بونج',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...tables.map((table) => _buildTableCard(table, inventory)),
      ],
    );
  }

  Widget _buildTableCard(GamingTable table, List<InventoryItem> inventory) {
    final isRunning = table.status == 'running';
    final isPaused = table.status == 'paused';
    final statusColor = isRunning
        ? const Color(0xFF00C896)
        : (isPaused ? Colors.orangeAccent : Colors.grey);

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
                Row(
                  children: [
                    Icon(
                      table.id == 'billiard'
                          ? Icons.lens_blur
                          : Icons.sports_tennis,
                      color: statusColor,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      table.name,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                ActionChip(
                  avatar: const Icon(Icons.edit, size: 16),
                  label: Text(
                      'سعر الساعة: ${table.hourlyRate.toStringAsFixed(0)} ج.م'),
                  onPressed: () => _showEditHourlyRateDialog(table),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _metricColumn(
                    'الوقت الفعلي', table.formattedDuration, statusColor),
                _metricColumn(
                    'حساب الوقت',
                    '${table.currentTimeCost.toStringAsFixed(1)} ج.م',
                    Colors.white),
                _metricColumn(
                    'حساب المشاريب',
                    '${table.attachedDrinksCost.toStringAsFixed(1)} ج.م',
                    Colors.amber),
                _metricColumn(
                    'إجمالي الترابيزة',
                    '${table.grandTotal.toStringAsFixed(1)} ج.م',
                    const Color(0xFF00C896)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: TextEditingController(text: table.guestNotes)
                ..selection = TextSelection.fromPosition(
                    TextPosition(offset: table.guestNotes.length)),
              onChanged: (val) {
                widget.db.updateTableGuestNotes(table, val);
              },
              decoration: InputDecoration(
                labelText: 'أسماء الأشخاص / ملاحظات الطرابيزة',
                hintText: 'اكتب اسم كل شخص هنا (متزامن لحظياً)...',
                prefixIcon: const Icon(Icons.note_alt, color: Color(0xFF00C896)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: Colors.black26,
              ),
              maxLines: 2,
            ),
            if (table.attachedItems.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Wrap(
                  spacing: 8,
                  children: table.attachedItems
                      .map((item) => Chip(
                            label: Text(
                                '${item.name} × ${item.qty} (${item.total.toStringAsFixed(0)} ج.م)'),
                          ))
                      .toList(),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C896),
                    foregroundColor: Colors.black,
                  ),
                  onPressed:
                      isRunning ? null : () => widget.db.startTableTimer(table),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('ابدأ الوقت',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.shade700,
                    foregroundColor: Colors.black,
                  ),
                  onPressed:
                      isRunning ? () => widget.db.pauseTableTimer(table) : null,
                  icon: const Icon(Icons.pause),
                  label: const Text('إيقاف مؤقت',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showAttachDrinksDialog(table, inventory),
                  icon: const Icon(Icons.local_cafe),
                  label: const Text('إضافة مشاريب للترابيزة'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: (table.currentElapsedSeconds > 0 ||
                          table.attachedItems.isNotEmpty)
                      ? () => _confirmTableCheckout(table)
                      : null,
                  icon: const Icon(Icons.receipt_long),
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
            style: const TextStyle(fontSize: 12, color: Colors.white70)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  Widget _buildPosSection(
      List<InventoryItem> inventory, List<GamingTable> tables) {
    double cartTotal = 0;
    final Map<InventoryItem, int> resolvedCart = {};
    for (final item in inventory) {
      if (_posCart.containsKey(item.id) && _posCart[item.id]! > 0) {
        final q = _posCart[item.id]!;
        resolvedCart[item] = q;
        cartTotal += item.price * q;
      }
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'الكاشير والمشاريب',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 190,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.05,
              ),
              itemCount: inventory.length,
              itemBuilder: (context, index) {
                final item = inventory[index];
                final qtyInCart = _posCart[item.id] ?? 0;

                return InkWell(
                  onTap: item.stock > qtyInCart
                      ? () => setState(() => _posCart[item.id] = qtyInCart + 1)
                      : null,
                  borderRadius: BorderRadius.circular(14),
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: qtyInCart > 0
                            ? const Color(0xFF00C896)
                            : Colors.white12,
                        width: qtyInCart > 0 ? 2 : 1,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'المتاح: ${item.stock}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white60),
                          ),
                          Text(
                            item.name,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            '${item.price.toStringAsFixed(1)} ج.م',
                            style: const TextStyle(
                                color: Color(0xFF00C896),
                                fontWeight: FontWeight.bold),
                          ),
                          if (qtyInCart > 0)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline,
                                      size: 20),
                                  onPressed: () => setState(() {
                                    if (qtyInCart <= 1) {
                                      _posCart.remove(item.id);
                                    } else {
                                      _posCart[item.id] = qtyInCart - 1;
                                    }
                                  }),
                                ),
                                Text('$qtyInCart',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline,
                                      size: 20),
                                  onPressed: item.stock > qtyInCart
                                      ? () => setState(() =>
                                          _posCart[item.id] = qtyInCart + 1)
                                      : null,
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
          ),
          if (resolvedCart.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF181E2C),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF00C896)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'الإجمالي: ${cartTotal.toStringAsFixed(1)} ج.م',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _posCart.clear()),
                        child: const Text('إلغاء',
                            style: TextStyle(color: Colors.redAccent)),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00C896),
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () async {
                          await widget.db.checkoutDirectPos(resolvedCart);
                          setState(() => _posCart.clear());
                        },
                        icon: const Icon(Icons.check_circle),
                        label: const Text('تأكيد الطلب (كاشير)'),
                      ),
                      ...tables.map((t) => OutlinedButton(
                            onPressed: () async {
                              await widget.db
                                  .attachDrinksToTable(t, resolvedCart);
                              setState(() => _posCart.clear());
                            },
                            child: Text('إضافة لـ ${t.name}'),
                          )),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInventorySection(
      List<InventoryItem> inventory, List<GamingTable> tables) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'إدارة المخزن وتعديل الأسعار',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C896),
                foregroundColor: Colors.black,
              ),
              onPressed: _showAddInventoryDialog,
              icon: const Icon(Icons.add),
              label: const Text('إضافة صنف'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...inventory.map((item) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Text(item.name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                    'السعر: ${item.price.toStringAsFixed(1)} ج.م | المخزن: ${item.stock}'),
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

  Widget _buildReportsSection(List<SaleRecord> sales, List<AuditLog> logs) {
    double drinksRev = 0;
    double billiardRev = 0;
    double pingPongRev = 0;
    int billiardSeconds = 0;
    int pingPongSeconds = 0;
    final Map<String, int> itemBreakdown = {};

    for (final s in sales) {
      drinksRev += s.drinksRevenue;
      if (s.type == 'billiard_checkout') {
        billiardRev += s.timeRevenue;
        billiardSeconds += s.playedSeconds;
      } else if (s.type == 'pingpong_checkout') {
        pingPongRev += s.timeRevenue;
        pingPongSeconds += s.playedSeconds;
      }
      for (final item in s.soldItems) {
        itemBreakdown[item.name] = (itemBreakdown[item.name] ?? 0) + item.qty;
      }
    }

    final grandTotal = drinksRev + billiardRev + pingPongRev;

    return StreamBuilder<List<ClosedDaySummary>>(
      stream: widget.db.streamClosedDays(),
      builder: (context, closedSnap) {
        final closedDays = closedSnap.data ?? [];

        ClosedDaySummary? highestDay;
        for (final d in closedDays) {
          if (highestDay == null || d.grandTotal > highestDay.grandTotal) {
            highestDay = d;
          }
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (highestDay != null)
              Card(
                color: const Color(0xFF1D2331),
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Colors.pinkAccent, width: 1),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text('أعلى يوم',
                          style:
                              TextStyle(fontSize: 14, color: Colors.white70)),
                      const SizedBox(height: 6),
                      Text(
                        highestDay.dateLabel,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.pinkAccent,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${highestDay.grandTotal.toStringAsFixed(1)} ج.م',
                        style: const TextStyle(
                            fontSize: 16, color: Color(0xFF00C896)),
                      ),
                    ],
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1D2331),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 10,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00C853),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: const StadiumBorder(),
                    ),
                    onPressed: () => _confirmCloseDayDialog(
                      drinksRev: drinksRev,
                      billiardRev: billiardRev,
                      pingPongRev: pingPongRev,
                      grandTotal: grandTotal,
                    ),
                    icon: const Icon(Icons.lock_clock),
                    label: const Text(
                      'تقفيل اليوم',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => ExportService.exportDailyPdfReport(
                          sales: sales,
                          logs: logs,
                          drinksRev: drinksRev,
                          billiardRev: billiardRev,
                          pingPongRev: pingPongRev,
                          grandTotal: grandTotal,
                          itemBreakdown: itemBreakdown,
                        ),
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text('PDF'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final msg = await ExportService.exportExcelReport(
                            sales: sales,
                            logs: logs,
                            drinksRev: drinksRev,
                            billiardRev: billiardRev,
                            pingPongRev: pingPongRev,
                            grandTotal: grandTotal,
                            itemBreakdown: itemBreakdown,
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text(msg)));
                          }
                        },
                        icon: const Icon(Icons.table_view),
                        label: const Text('إكسيل'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _summaryReportCard(
                    'إيراد المشاريب الحالي', drinksRev, Colors.amber),
                _summaryReportCard(
                    'البلياردو (${(billiardSeconds / 3600).toStringAsFixed(1)} س)',
                    billiardRev,
                    Colors.cyanAccent),
                _summaryReportCard(
                    'البينج بونج (${(pingPongSeconds / 3600).toStringAsFixed(1)} س)',
                    pingPongRev,
                    Colors.purpleAccent),
                _summaryReportCard('إجمالي الشيفت الحالي', grandTotal,
                    const Color(0xFF00C896)),
              ],
            ),
            const SizedBox(height: 24),
            const Text('سجل الأيام المتقفلة السابقة:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if (closedDays.isEmpty)
              const Text('مفيش أيام اتقفلت لسه.')
            else
              ...closedDays.map((day) => Card(
                    color: const Color(0xFF1D2331),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(
                        day.dateLabel,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'مشاريب: ${day.drinksRevenue.toStringAsFixed(0)} | بلياردو: ${day.billiardRevenue.toStringAsFixed(0)} | بينج: ${day.pingPongRevenue.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Text(
                        '${day.grandTotal.toStringAsFixed(1)} ج.م',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00C896),
                        ),
                      ),
                    ),
                  )),
          ],
        );
      },
    );
  }

  Widget _summaryReportCard(String title, double amount, Color accent) {
    return SizedBox(
      width: 220,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: accent.withValues(alpha: 0.6)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(fontSize: 13, color: Colors.white70)),
              const SizedBox(height: 8),
              Text(
                '${amount.toStringAsFixed(2)} ج.م',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: accent),
              ),
            ],
          ),
        ),
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
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const Icon(Icons.notifications_active,
                color: Colors.amberAccent),
            title: Text(log.title,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
                '${log.message}\nقبل: ${log.beforeVal} ⬅ بعد: ${log.afterVal}'),
            trailing: Text(
              intl.DateFormat('hh:mm a').format(log.timestamp),
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ),
        );
      },
    );
  }

  void _confirmCloseDayDialog({
    required double drinksRev,
    required double billiardRev,
    required double pingPongRev,
    required double grandTotal,
  }) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد تقفيل اليوم وتصفير الشيفت'),
        content: Text(
          'هيتم ترحيل حسابات الشيفت الحالي (${grandTotal.toStringAsFixed(1)} ج.م) بالإضافة لأي ترابيزة مفتوحة، وتصفير العدادات بالكامل ليوم جديد.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C853),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);
              await widget.db.closeCurrentDayAndReset(
                drinksRev: drinksRev,
                billiardRev: billiardRev,
                pingPongRev: pingPongRev,
                grandTotal: grandTotal,
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'تم تقفيل اليوم وتصفير جميع الحسابات والترابيزات!'),
                  ),
                );
              }
            },
            child: const Text('نعم، قفّل وصفر الآن'),
          ),
        ],
      ),
    );
  }

  void _showEditHourlyRateDialog(GamingTable table) {
    final ctrl =
        TextEditingController(text: table.hourlyRate.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('تعديل سعر الساعة - ${table.name}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'سعر الساعة (ج.م)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(ctrl.text);
              if (val != null && val > 0) {
                widget.db.updateTableHourlyRate(table, val);
                Navigator.pop(context);
              }
            },
            child: const Text('حفظ'),
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
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('إضافة مشاريب لـ ${table.name}'),
          content: SizedBox(
            width: 400,
            height: 320,
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
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                tempSelection.removeWhere((_, v) => v <= 0);
                if (tempSelection.isNotEmpty) {
                  widget.db.attachDrinksToTable(table, tempSelection);
                }
                Navigator.pop(context);
              },
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmTableCheckout(GamingTable table) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('حساب الترابيزة - ${table.name}'),
        content: Text(
          'الإجمالي المطلوب دفعه: ${table.grandTotal.toStringAsFixed(2)} ج.م',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('رجوع')),
          ElevatedButton(
            onPressed: () async {
              await widget.db.endAndCheckoutTable(table);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('تأكيد التحصيل وتصفير الترابيزة'),
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
      builder: (_) => AlertDialog(
        title: const Text('إضافة صنف جديد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'اسم الصنف'),
            ),
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'السعر (ج.م)'),
            ),
            TextField(
              controller: stockCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'الكمية بالمخزن'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final price = double.tryParse(priceCtrl.text) ?? 0;
              final stock = int.tryParse(stockCtrl.text) ?? 0;
              if (name.isNotEmpty && price > 0) {
                widget.db.addNewInventoryItem(
                  name: name,
                  price: price,
                  stock: stock,
                  threshold: 10,
                );
                Navigator.pop(context, true);
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
      builder: (_) => AlertDialog(
        title: Text('تعديل سعر: ${item.name}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(ctrl.text);
              if (val != null && val > 0) {
                widget.db.updateItemPrice(item, val);
                Navigator.pop(context);
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
      builder: (_) => AlertDialog(
        title: Text('تعديل الكمية: ${item.name}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              val:
              int.tryParse(ctrl.text);
              final val = int.tryParse(ctrl.text);
              if (val != null && val >= 0) {
                widget.db.updateItemStock(item, val);
                Navigator.pop(context);
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}
