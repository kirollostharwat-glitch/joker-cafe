import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
        'name': name,
        'price': price,
        'stock': stock,
        'lowStockThreshold': lowStockThreshold,
      };

  factory InventoryItem.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return InventoryItem(
      id: doc.id,
      name: data['name'] ?? '',
      price: (data['price'] ?? 0).toDouble(),
      stock: (data['stock'] ?? 0).toInt(),
      lowStockThreshold: (data['lowStockThreshold'] ?? 5).toInt(),
    );
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
  final String status;
  final DateTime? lastStartTime;
  final int accumulatedSeconds;
  final List<AttachedItem> attachedItems;

  GamingTable({
    required this.id,
    required this.name,
    required this.hourlyRate,
    required this.status,
    this.lastStartTime,
    required this.accumulatedSeconds,
    required this.attachedItems,
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

  Map<String, dynamic> toMap() => {
        'name': name,
        'hourlyRate': hourlyRate,
        'status': status,
        'lastStartTime':
            lastStartTime != null ? Timestamp.fromDate(lastStartTime!) : null,
        'accumulatedSeconds': accumulatedSeconds,
        'attachedItems': attachedItems.map((e) => e.toMap()).toList(),
      };

  factory GamingTable.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final rawList = data['attachedItems'] as List<dynamic>? ?? [];
    return GamingTable(
      id: doc.id,
      name: data['name'] ?? '',
      hourlyRate: (data['hourlyRate'] ?? 50.0).toDouble(),
      status: data['status'] ?? 'idle',
      lastStartTime: data['lastStartTime'] != null
          ? (data['lastStartTime'] as Timestamp).toDate()
          : null,
      accumulatedSeconds: (data['accumulatedSeconds'] ?? 0).toInt(),
      attachedItems: rawList
          .map((e) => AttachedItem.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
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

  Map<String, dynamic> toMap() => {
        'type': type,
        'timeRevenue': timeRevenue,
        'drinksRevenue': drinksRevenue,
        'totalRevenue': totalRevenue,
        'playedSeconds': playedSeconds,
        'soldItems': soldItems.map((e) => e.toMap()).toList(),
        'timestamp': Timestamp.fromDate(timestamp),
        'isClosed': isClosed,
      };

  factory SaleRecord.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final rawItems = data['soldItems'] as List<dynamic>? ?? [];
    return SaleRecord(
      id: doc.id,
      type: data['type'] ?? 'drinks_only',
      timeRevenue: (data['timeRevenue'] ?? 0).toDouble(),
      drinksRevenue: (data['drinksRevenue'] ?? 0).toDouble(),
      totalRevenue: (data['totalRevenue'] ?? 0).toDouble(),
      playedSeconds: (data['playedSeconds'] ?? 0).toInt(),
      soldItems: rawItems
          .map((e) => AttachedItem.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      timestamp: data['timestamp'] != null
          ? (data['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
      isClosed: data['isClosed'] ?? false,
    );
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

  Map<String, dynamic> toMap() => {
        'dateLabel': dateLabel,
        'drinksRevenue': drinksRevenue,
        'billiardRevenue': billiardRevenue,
        'pingPongRevenue': pingPongRevenue,
        'grandTotal': grandTotal,
        'closedAt': Timestamp.fromDate(closedAt),
      };

  factory ClosedDaySummary.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ClosedDaySummary(
      id: doc.id,
      dateLabel: data['dateLabel'] ?? '',
      drinksRevenue: (data['drinksRevenue'] ?? 0).toDouble(),
      billiardRevenue: (data['billiardRevenue'] ?? 0).toDouble(),
      pingPongRevenue: (data['pingPongRevenue'] ?? 0).toDouble(),
      grandTotal: (data['grandTotal'] ?? 0).toDouble(),
      closedAt: data['closedAt'] != null
          ? (data['closedAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
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

  Map<String, dynamic> toMap() => {
        'title': title,
        'message': message,
        'beforeVal': beforeVal,
        'afterVal': afterVal,
        'deviceId': deviceId,
        'timestamp': Timestamp.fromDate(timestamp),
      };

  factory AuditLog.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return AuditLog(
      id: doc.id,
      title: data['title'] ?? '',
      message: data['message'] ?? '',
      beforeVal: data['beforeVal'] ?? '',
      afterVal: data['afterVal'] ?? '',
      deviceId: data['deviceId'] ?? '',
      timestamp: data['timestamp'] != null
          ? (data['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }
}

// =============================================================================
// 2. NOTIFICATION SERVICE
// =============================================================================

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const windowsSettings = WindowsInitializationSettings(
      appName: 'Joker Cafe',
      appUserModelId: 'com.jokercafe.pos.admin',
      guid: 'd49b0314-ee7a-4626-bf79-97cdb8a991bb',
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      windows: windowsSettings,
    );

    await _plugin.initialize(initSettings);

    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  Future<void> showEgyptianAlert({
    required int id,
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'joker_cafe_audit_channel',
      'Joker Cafe - تنبيهات التعديلات والمخزن',
      channelDescription: 'إشعارات فورية لتعديلات الأسعار والمخزن والترابيزات',
      importance: Importance.max,
      priority: Priority.high,
    );

    const windowsDetails = WindowsNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      windows: windowsDetails,
    );

    await _plugin.show(id, title, body, details);
  }
}

// =============================================================================
// 3. FIRESTORE SERVICE
// =============================================================================

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  late final String deviceId;
  bool _isInitialAuditLoad = true;

  Future<void> initAndSeed() async {
    _db.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    final prefs = await SharedPreferences.getInstance();
    String? storedId = prefs.getString('device_instance_id');
    if (storedId == null) {
      storedId = const Uuid().v4();
      await prefs.setString('device_instance_id', storedId);
    }
    deviceId = storedId;

    await _seedDefaultDataIfNeeded();
    _listenToAuditLogsForNotifications();
  }

  Future<void> _seedDefaultDataIfNeeded() async {
    try {
      final tablesSnap = await _db.collection('tables').get();
      if (tablesSnap.docs.isEmpty) {
        await _db.collection('tables').doc('billiard').set(GamingTable(
              id: 'billiard',
              name: 'ترابيزة البلياردو',
              hourlyRate: 60.0,
              status: 'idle',
              accumulatedSeconds: 0,
              attachedItems: [],
            ).toMap());

        await _db.collection('tables').doc('pingpong').set(GamingTable(
              id: 'pingpong',
              name: 'ترابيزة البينج بونج',
              hourlyRate: 45.0,
              status: 'idle',
              accumulatedSeconds: 0,
              attachedItems: [],
            ).toMap());
      }

      final invSnap = await _db.collection('inventory').get();
      if (invSnap.docs.isEmpty) {
        final initialDrinks = [
          {'name': 'شاي', 'price': 15.0, 'stock': 100, 'threshold': 15},
          {'name': 'قهوة تركي', 'price': 25.0, 'stock': 60, 'threshold': 10},
          {'name': 'نسكافيه', 'price': 30.0, 'stock': 45, 'threshold': 10},
          {'name': 'بيبسي', 'price': 20.0, 'stock': 50, 'threshold': 12},
          {'name': 'مية معدنية', 'price': 10.0, 'stock': 80, 'threshold': 20},
        ];

        for (final item in initialDrinks) {
          await _db.collection('inventory').add({
            'name': item['name'],
            'price': item['price'],
            'stock': item['stock'],
            'lowStockThreshold': item['threshold'],
          });
        }
      }
    } catch (_) {}
  }

  void _listenToAuditLogsForNotifications() {
    _db
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
    await _db.collection('audit_logs').add(AuditLog(
          id: '',
          title: title,
          message: message,
          beforeVal: beforeVal,
          afterVal: afterVal,
          deviceId: deviceId,
          timestamp: DateTime.now(),
        ).toMap());
  }

  Stream<List<GamingTable>> streamTables() => _db
      .collection('tables')
      .snapshots()
      .map((s) => s.docs.map(GamingTable.fromDoc).toList());

  Stream<List<InventoryItem>> streamInventory() => _db
      .collection('inventory')
      .snapshots()
      .map((s) => s.docs.map(InventoryItem.fromDoc).toList());

  Stream<List<SaleRecord>> streamTodaySales() {
    return _db.collection('sales').snapshots().map((s) => s.docs
        .map(SaleRecord.fromDoc)
        .where((sale) => !sale.isClosed)
        .toList());
  }

  Stream<List<ClosedDaySummary>> streamClosedDays() => _db
      .collection('closed_days')
      .orderBy('closedAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(ClosedDaySummary.fromDoc).toList());

  Stream<List<AuditLog>> streamAuditLogs() => _db
      .collection('audit_logs')
      .orderBy('timestamp', descending: true)
      .limit(100)
      .snapshots()
      .map((s) => s.docs.map(AuditLog.fromDoc).toList());

  Future<void> startTableTimer(GamingTable table) async {
    await _db.collection('tables').doc(table.id).update({
      'status': 'running',
      'lastStartTime': Timestamp.fromDate(DateTime.now()),
    });
    await _recordAudit(
      title: 'تنبيه ترابيزة: ${table.name}',
      message: 'تم تشغيل الوقت على ${table.name}',
      beforeVal: 'متوقفة',
      afterVal: 'شغالة الآن',
    );
  }

  Future<void> pauseTableTimer(GamingTable table) async {
    final totalElapsed = table.currentElapsedSeconds;
    await _db.collection('tables').doc(table.id).update({
      'status': 'paused',
      'lastStartTime': null,
      'accumulatedSeconds': totalElapsed,
    });
    await _recordAudit(
      title: 'تنبيه ترابيزة: ${table.name}',
      message: 'تم إيقاف مؤقت لـ ${table.name}',
      beforeVal: 'شغالة',
      afterVal: 'إيقاف مؤقت (${table.formattedDuration})',
    );
  }

  Future<void> updateTableHourlyRate(GamingTable table, double newRate) async {
    final oldRate = table.hourlyRate;
    await _db.collection('tables').doc(table.id).update({
      'hourlyRate': newRate,
    });
    await _recordAudit(
      title: 'تنبيه تعديل سعر الساعة',
      message:
          'تم تغيير سعر ساعة ${table.name} من ${oldRate.toStringAsFixed(0)} إلى ${newRate.toStringAsFixed(0)} ج.م',
      beforeVal: '${oldRate.toStringAsFixed(0)} ج.م',
      afterVal: '${newRate.toStringAsFixed(0)} ج.م',
    );
  }

  Future<void> attachDrinksToTable(
      GamingTable table, Map<InventoryItem, int> selectedDrinks) async {
    final updatedList = List<AttachedItem>.from(table.attachedItems);

    for (final entry in selectedDrinks.entries) {
      final item = entry.key;
      final qty = entry.value;

      final newStock = (item.stock - qty).clamp(0, 999999);
      await _db
          .collection('inventory')
          .doc(item.id)
          .update({'stock': newStock});

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

    await _db.collection('tables').doc(table.id).update({
      'attachedItems': updatedList.map((e) => e.toMap()).toList(),
    });
  }

  Future<SaleRecord> endAndCheckoutTable(GamingTable table) async {
    final elapsedSecs = table.currentElapsedSeconds;
    final timeCost = table.currentTimeCost;
    final drinksCost = table.attachedDrinksCost;
    final total = timeCost + drinksCost;

    final sale = SaleRecord(
      id: '',
      type: table.id == 'billiard' ? 'billiard_checkout' : 'pingpong_checkout',
      timeRevenue: timeCost,
      drinksRevenue: drinksCost,
      totalRevenue: total,
      playedSeconds: elapsedSecs,
      soldItems: List<AttachedItem>.from(table.attachedItems),
      timestamp: DateTime.now(),
      isClosed: false,
    );

    await _db.collection('sales').add(sale.toMap());

    await _db.collection('tables').doc(table.id).update({
      'status': 'idle',
      'lastStartTime': null,
      'accumulatedSeconds': 0,
      'attachedItems': [],
    });

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
      await _db
          .collection('inventory')
          .doc(item.id)
          .update({'stock': newStock});
    }

    final sale = SaleRecord(
      id: '',
      type: 'drinks_only',
      timeRevenue: 0,
      drinksRevenue: totalDrinks,
      totalRevenue: totalDrinks,
      playedSeconds: 0,
      soldItems: soldItems,
      timestamp: DateTime.now(),
      isClosed: false,
    );

    await _db.collection('sales').add(sale.toMap());
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

    final tablesSnap = await _db.collection('tables').get();
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
        });
      }
    }

    final finalDrinks = drinksRev + extraDrinks;
    final finalBilliard = billiardRev + extraBilliard;
    final finalPingPong = pingPongRev + extraPingPong;
    final finalGrandTotal = finalDrinks + finalBilliard + finalPingPong;

    if (finalGrandTotal > 0) {
      await _db.collection('closed_days').add(ClosedDaySummary(
            id: '',
            dateLabel: dateStr,
            drinksRevenue: finalDrinks,
            billiardRevenue: finalBilliard,
            pingPongRevenue: finalPingPong,
            grandTotal: finalGrandTotal,
            closedAt: now,
          ).toMap());
    }

    final allSalesSnap = await _db.collection('sales').get();
    for (final doc in allSalesSnap.docs) {
      try {
        await doc.reference.delete();
      } catch (_) {
        await doc.reference.update({'isClosed': true});
      }
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
    await _db.collection('inventory').add({
      'name': name,
      'price': price,
      'stock': stock,
      'lowStockThreshold': threshold,
    });
    await _recordAudit(
      title: 'إضافة صنف جديد للمخزن',
      message: 'تم إضافة [$name] بسعر $price ج.م وكمية $stock',
      beforeVal: 'غير موجود',
      afterVal: '$price ج.م ($stock قطعة)',
    );
  }

  Future<void> updateItemPrice(InventoryItem item, double newPrice) async {
    final oldPrice = item.price;
    await _db.collection('inventory').doc(item.id).update({'price': newPrice});
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
    await _db.collection('inventory').doc(item.id).update({'stock': newStock});
    await _recordAudit(
      title: 'تنبيه مخزن',
      message: 'تم تعديل كمية [${item.name}] من $oldStock إلى $newStock',
      beforeVal: '$oldStock',
      afterVal: '$newStock',
    );
  }

  Future<void> deleteInventoryItem(InventoryItem item) async {
    await _db.collection('inventory').doc(item.id).delete();
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

  try {
    await Firebase.initializeApp();
  } catch (_) {}

  await NotificationService().init();
  final firestoreService = FirestoreService();
  await firestoreService.initAndSeed();

  runApp(CafeAdminApp(firestoreService: firestoreService));
}

class CafeAdminApp extends StatelessWidget {
  final FirestoreService firestoreService;
  const CafeAdminApp({super.key, required this.firestoreService});

  @override
  Widget build(BuildContext context) {
    final cairoTheme = GoogleFonts.cairoTextTheme(ThemeData.dark().textTheme);

    return MaterialApp(
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
                                    color: Colors.teal.withOpacity(0.2),
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
                                          ? 'متصل بالنت - متزامن لحظياً'
                                          : 'أوفلاين - هيتم المزامنة أول ما النت يرجع',
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
              icon: Icon(Icons.inventory
