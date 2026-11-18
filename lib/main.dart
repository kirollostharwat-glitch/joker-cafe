import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
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
// 0. APP VERSION & REMOTE OTA UPDATE CONFIG
// =============================================================================
const String kCurrentAppVersion = '1.0.1';
const String kRemoteVersionJsonUrl =
    'https://raw.githubusercontent.com/kirollostharwat-glitch/joker-cafe/main/version.json';

class AppUpdateService {
  static Future?> checkForUpdate() async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      final req = await client.getUrl(Uri.parse(kRemoteVersionJsonUrl));
      final res = await req.close();
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final latestVersion = (data['version'] ?? '').toString().trim();
        if (latestVersion.isNotEmpty && latestVersion != kCurrentAppVersion) {
          return data;
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<void> openDownloadUrl(String url) async {
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url]);
      } else if (Platform.isAndroid) {
        await Process.run(
            'am', ['start', '-a', 'android.intent.action.VIEW', '-d', url]);
      }
    } catch (_) {}
  }
}

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
  final String type; // 'gaming' or 'normal'
  final String status; // 'idle', 'running', 'paused'
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
  final double tablesRevenue;
  final double grandTotal;
  final DateTime closedAt;

  ClosedDaySummary({
    required this.id,
    required this.dateLabel,
    required this.drinksRevenue,
    required this.tablesRevenue,
    required this.grandTotal,
    required this.closedAt,
  });

  Map<String, dynamic> toMap({bool forLocal = false}) => {
        'id': id,
        'dateLabel': dateLabel,
        'drinksRevenue': drinksRevenue,
        'tablesRevenue': tablesRevenue,
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
// 3. FIRESTORE + AUTO LAN P2P REAL-TIME SYNC SERVICE
// =============================================================================

class FirestoreService {
  FirebaseFirestore? _db;
  bool useCloud = false;
  late SharedPreferences _prefs;
  late String deviceId;
  bool _isInitialAuditLoad = true;

  ServerSocket? _tcpServer;
  RawDatagramSocket? _udpSocket;
  Timer? _discoveryTimer;
  final List<Socket> _peerSockets = [];
  final Set<String> _connectedPeerIps = {};
  static const int _syncTcpPort = 45454;
  static const int _syncUdpPort = 45455;
  int _lastStateTimestamp = 0;

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
    _lastStateTimestamp = _prefs.getInt('last_state_ts') ?? 0;

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

    _loadAndSeedLocalData();

    if (useCloud) {
      await _seedCloudDataIfNeeded();
      _listenToCloudRealtimeStreams();
      _listenToAuditLogsForNotifications();
    }

    await _startAutoLanSyncEngine();
  }

  Future<void> _startAutoLanSyncEngine() async {
    try {
      _tcpServer = await ServerSocket.bind(InternetAddress.anyIPv4, _syncTcpPort,
          shared: true);
      _tcpServer!.listen(_handleIncomingPeerSocket);
    } catch (_) {}

    try {
      _udpSocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4, _syncUdpPort,
          reuseAddress: true);
      _udpSocket!.broadcastEnabled = true;
      _udpSocket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final dg = _udpSocket!.receive();
          if (dg == null) return;
          final msg = utf8.decode(dg.data, allowMalformed: true);
          if (msg.startsWith('JOKER_SYNC:')) {
            final senderDeviceId = msg.substring('JOKER_SYNC:'.length).trim();
            if (senderDeviceId != deviceId) {
              final peerIp = dg.address.address;
              if (!_connectedPeerIps.contains(peerIp)) {
                _connectToPeer(peerIp);
              }
            }
          }
        }
      });

      _discoveryTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        try {
          final packet = utf8.encode('JOKER_SYNC:$deviceId');
          _udpSocket?.send(
              packet, InternetAddress('255.255.255.255'), _syncUdpPort);
        } catch (_) {}
      });
    } catch (_) {}
  }

  Future<void> _connectToPeer(String ip) async {
    if (_connectedPeerIps.contains(ip)) return;
    _connectedPeerIps.add(ip);
    try {
      final socket = await Socket.connect(ip, _syncTcpPort,
          timeout: const Duration(seconds: 3));
      _setupPeerSocket(socket);
    } catch (_) {
      _connectedPeerIps.remove(ip);
    }
  }

  void _handleIncomingPeerSocket(Socket socket) {
    final ip = socket.remoteAddress.address;
    _connectedPeerIps.add(ip);
    _setupPeerSocket(socket);
  }

  void _setupPeerSocket(Socket socket) {
    _peerSockets.add(socket);
    _sendSyncPayloadToSocket(socket);

    utf8.decoder
        .bind(socket)
        .transform(const LineSplitter())
        .listen((String line) {
      if (line.trim().isNotEmpty) {
        _handleReceivedSyncLine(line);
      }
    }, onDone: () {
      _peerSockets.remove(socket);
      _connectedPeerIps.remove(socket.remoteAddress.address);
    }, onError: (_) {
      _peerSockets.remove(socket);
      _connectedPeerIps.remove(socket.remoteAddress.address);
    });
  }

  void _sendSyncPayloadToSocket(Socket s) {
    try {
      final payload = jsonEncode({
        'type': 'FULL_SYNC',
        'senderId': deviceId,
        'ts': _lastStateTimestamp,
        'tables': _localTables.map((e) => e.toMap(forLocal: true)).toList(),
        'inv': _localInv.map((e) => e.toMap()).toList(),
        'sales': _localSales.map((e) => e.toMap(forLocal: true)).toList(),
        'closedDays':
            _localClosedDays.map((e) => e.toMap(forLocal: true)).toList(),
        'logs':
            _localLogs.take(100).map((e) => e.toMap(forLocal: true)).toList(),
      });
      s.write('$payload\n');
    } catch (_) {}
  }

  void _broadcastLanSync({AuditLog? latestLog}) {
    if (_peerSockets.isEmpty) return;
    final payload = jsonEncode({
      'type': 'FULL_SYNC',
      'senderId': deviceId,
      'ts': _lastStateTimestamp,
      'tables': _localTables.map((e) => e.toMap(forLocal: true)).toList(),
      'inv': _localInv.map((e) => e.toMap()).toList(),
      'sales': _localSales.map((e) => e.toMap(forLocal: true)).toList(),
      'closedDays':
          _localClosedDays.map((e) => e.toMap(forLocal: true)).toList(),
      'logs':
          _localLogs.take(100).map((e) => e.toMap(forLocal: true)).toList(),
      'alertTitle': latestLog?.title,
      'alertBody': latestLog?.message,
    });

    for (final s in List<Socket>.from(_peerSockets)) {
      try {
        s.write('$payload\n');
      } catch (_) {
        _peerSockets.remove(s);
      }
    }
  }

  void _handleReceivedSyncLine(String line) {
    try {
      final map = jsonDecode(line) as Map<String, dynamic>;
      if (map['type'] != 'FULL_SYNC') return;
      if (map['senderId'] == deviceId) return;

      final incomingTs = (map['ts'] ?? 0) as int;
      if (incomingTs < _lastStateTimestamp) {
        _broadcastLanSync();
        return;
      }

      _lastStateTimestamp = incomingTs;
      _prefs.setInt('last_state_ts', _lastStateTimestamp);

      if (map['tables'] != null) {
        _localTables = (map['tables'] as List)
            .map((e) => GamingTable.fromMap(Map<String, dynamic>.from(e)))
            .toList();
      }
      if (map['inv'] != null) {
        _localInv = (map['inv'] as List)
            .map((e) => InventoryItem.fromMap(Map<String, dynamic>.from(e)))
            .toList();
      }
      if (map['sales'] != null) {
        _localSales = (map['sales'] as List)
            .map((e) => SaleRecord.fromMap(Map<String, dynamic>.from(e)))
            .toList();
      }
      if (map['closedDays'] != null) {
        _localClosedDays = (map['closedDays'] as List)
            .map((e) => ClosedDaySummary.fromMap(Map<String, dynamic>.from(e)))
            .toList();
      }
      if (map['logs'] != null) {
        _localLogs = (map['logs'] as List)
            .map((e) => AuditLog.fromMap(Map<String, dynamic>.from(e)))
            .toList();
      }

      _saveAndEmitLocal(broadcastToPeers: false);

      final alertTitle = map['alertTitle'] as String?;
      final alertBody = map['alertBody'] as String?;
      if (alertTitle != null && alertBody != null) {
        NotificationService().showEgyptianAlert(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title: alertTitle,
          body: alertBody,
        );
      }
    } catch (_) {}
  }

  void _listenToCloudRealtimeStreams() {
    _db!.collection('tables').snapshots().listen((snapshot) {
      final list = snapshot.docs.map(GamingTable.fromDoc).toList();
      if (list.isNotEmpty) {
        _localTables = list;
        _tablesCtrl.add(list);
      }
    });

    _db!.collection('inventory').snapshots().listen((snapshot) {
      final list = snapshot.docs.map(InventoryItem.fromDoc).toList();
      if (list.isNotEmpty) {
        _localInv = list;
        _invCtrl.add(list);
      }
    });

    _db!.collection('sales').snapshots().listen((snapshot) {
      final list = snapshot.docs
          .map(SaleRecord.fromDoc)
          .where((s) => !s.isClosed)
          .toList();
      _localSales = list;
      _salesCtrl.add(list);
    });

    _db!
        .collection('closed_days')
        .orderBy('closedAt', descending: true)
        .snapshots()
        .listen((snapshot) {
      final list = snapshot.docs.map(ClosedDaySummary.fromDoc).toList();
      _localClosedDays = list;
      _closedDaysCtrl.add(list);
    });
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

    _saveAndEmitLocal(broadcastToPeers: false);
  }

  void _saveAndEmitLocal({bool broadcastToPeers = true, AuditLog? latestLog}) {
    if (broadcastToPeers) {
      _lastStateTimestamp = DateTime.now().millisecondsSinceEpoch;
      _prefs.setInt('last_state_ts', _lastStateTimestamp);
    }

    _prefs.setString('local_tables',
        jsonEncode(_localTables.map((e) => e.toMap(forLocal: true)).toList()));
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

    if (broadcastToPeers) {
      _broadcastLanSync(latestLog: latestLog);
    }
  }

  Future<void> _seedCloudDataIfNeeded() async {
    try {
      final tablesSnap = await _db!.collection('tables').get();
      if (tablesSnap.docs.isEmpty) {
        for (final t in _localTables) {
          await _db!.collection('tables').doc(t.id).set(t.toMap());
        }
      }
      final invSnap = await _db!.collection('inventory').get();
      if (invSnap.docs.isEmpty) {
        for (final item in _localInv) {
          await _db!.collection('inventory').doc(item.id).set(item.toMap());
        }
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
              body: log.message);
        }
      }
    });
  }

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
    _saveAndEmitLocal(latestLog: log);

    if (useCloud) {
      try {
        await _db!.collection('audit_logs').add(log.toMap());
      } catch (_) {}
    }
  }

  List<GamingTable> get currentTables => List.from(_localTables);
  List<InventoryItem> get currentInventory => List.from(_localInv);
  List<SaleRecord> get currentSales =>
      _localSales.where((s) => !s.isClosed).toList();
  List<ClosedDaySummary> get currentClosedDays => List.from(_localClosedDays);
  List<AuditLog> get currentLogs => List.from(_localLogs);

  Stream<List<GamingTable>> streamTables() => _tablesCtrl.stream;
  Stream<List<InventoryItem>> streamInventory() => _invCtrl.stream;
  Stream<List<SaleRecord>> streamTodaySales() => _salesCtrl.stream;
  Stream<List<ClosedDaySummary>> streamClosedDays() => _closedDaysCtrl.stream;
  Stream<List<AuditLog>> streamAuditLogs() => _logsCtrl.stream;

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
    _saveAndEmitLocal();

    if (useCloud) {
      try {
        await _db!.collection('tables').doc(newId).set(table.toMap());
      } catch (_) {}
    }
    await _recordAudit(
        title: 'إضافة ترابيزة',
        message: 'تم إضافة ترابيزة [$name]',
        beforeVal: 'غير موجودة',
        afterVal: 'متاحة');
  }

  Future<void> deleteTable(GamingTable table) async {
    _localTables.removeWhere((t) => t.id == table.id);
    _saveAndEmitLocal();

    if (useCloud) {
      try {
        await _db!.collection('tables').doc(table.id).delete();
      } catch (_) {}
    }
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
      _saveAndEmitLocal();
    }
    if (useCloud) {
      try {
        await _db!.collection('tables').doc(table.id).update(
            {'name': newName, 'type': newType, 'hourlyRate': newRate});
      } catch (_) {}
    }
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
      _saveAndEmitLocal();
    }
    if (useCloud) {
      try {
        await _db!.collection('tables').doc(table.id).update(
            {'status': 'running', 'lastStartTime': Timestamp.fromDate(now)});
      } catch (_) {}
    }
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
      _saveAndEmitLocal();
    }
    if (useCloud) {
      try {
        await _db!.collection('tables').doc(table.id).update({
          'status': 'paused',
          'lastStartTime': null,
          'accumulatedSeconds': totalElapsed
        });
      } catch (_) {}
    }
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
      _saveAndEmitLocal();
    }
    if (useCloud) {
      try {
        await _db!
            .collection('tables')
            .doc(tableId)
            .update({'guestNotes': notes});
      } catch (_) {}
    }
  }

  Future<void> updateTableAttachedItems(
      GamingTable table, List<AttachedItem> newItems) async {
    for (final oldItem in table.attachedItems) {
      final iIdx = _localInv.indexWhere((i) => i.id == oldItem.itemId);
      if (iIdx >= 0) {
        _localInv[iIdx] = InventoryItem(
          id: _localInv[iIdx].id,
          name: _localInv[iIdx].name,
          price: _localInv[iIdx].price,
          stock: _localInv[iIdx].stock + oldItem.qty,
          lowStockThreshold: _localInv[iIdx].lowStockThreshold,
        );
      }
    }
    for (final newItem in newItems) {
      final iIdx = _localInv.indexWhere((i) => i.id == newItem.itemId);
      if (iIdx >= 0) {
        _localInv[iIdx] = InventoryItem(
          id: _localInv[iIdx].id,
          name: _localInv[iIdx].name,
          price: _localInv[iIdx].price,
          stock: (_localInv[iIdx].stock - newItem.qty).clamp(0, 999999),
          lowStockThreshold: _localInv[iIdx].lowStockThreshold,
        );
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
      _saveAndEmitLocal();
    }
    if (useCloud) {
      try {
        await _db!.collection('tables').doc(table.id).update(
            {'attachedItems': newItems.map((e) => e.toMap()).toList()});
      } catch (_) {}
    }
  }

  Future<void> attachDrinksToTable(
      GamingTable table, Map<InventoryItem, int> selectedDrinks) async {
    final updatedList = List<AttachedItem>.from(table.attachedItems);
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
      }
      if (useCloud) {
        try {
          await _db!
              .collection('inventory')
              .doc(item.id)
              .update({'stock': newStock});
        } catch (_) {}
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
    _saveAndEmitLocal();

    if (useCloud) {
      try {
        await _db!.collection('tables').doc(table.id).update(
            {'attachedItems': updatedList.map((e) => e.toMap()).toList()});
      } catch (_) {}
    }
  }

  Future<SaleRecord> endAndCheckoutTable(GamingTable table) async {
    final elapsedSecs = table.currentElapsedSeconds;
    final timeCost = table.currentTimeCost;
    final drinksCost = table.attachedDrinksCost;
    final total = timeCost + drinksCost;

    final sale = SaleRecord(
      id: const Uuid().v4(),
      type: table.type == 'normal' ? 'normal_checkout' : 'gaming_checkout',
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
    _saveAndEmitLocal();

    if (useCloud) {
      try {
        await _db!.collection('sales').doc(sale.id).set(sale.toMap());
        await _db!.collection('tables').doc(table.id).update({
          'status': 'idle',
          'lastStartTime': null,
          'accumulatedSeconds': 0,
          'attachedItems': [],
          'guestNotes': ''
        });
      } catch (_) {}
    }
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
      }
      if (useCloud) {
        try {
          await _db!
              .collection('inventory')
              .doc(item.id)
              .update({'stock': newStock});
        } catch (_) {}
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
        isClosed: false);
    _localSales.insert(0, sale);
    _saveAndEmitLocal();

    if (useCloud) {
      try {
        await _db!.collection('sales').doc(sale.id).set(sale.toMap());
      } catch (_) {}
    }
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

    for (final oldItem in oldSale.soldItems) {
      final iIdx = _localInv.indexWhere((i) => i.id == oldItem.itemId);
      if (iIdx >= 0) {
        _localInv[iIdx] = InventoryItem(
          id: _localInv[iIdx].id,
          name: _localInv[iIdx].name,
          price: _localInv[iIdx].price,
          stock: _localInv[iIdx].stock + oldItem.qty,
          lowStockThreshold: _localInv[iIdx].lowStockThreshold,
        );
      }
    }

    for (final newItem in updatedItems) {
      final iIdx = _localInv.indexWhere((i) => i.id == newItem.itemId);
      if (iIdx >= 0) {
        _localInv[iIdx] = InventoryItem(
          id: _localInv[iIdx].id,
          name: _localInv[iIdx].name,
          price: _localInv[iIdx].price,
          stock: (_localInv[iIdx].stock - newItem.qty).clamp(0, 999999),
          lowStockThreshold: _localInv[iIdx].lowStockThreshold,
        );
      }
    }

    final newDrinksRev =
        updatedItems.fold<double>(0.0, (sum, item) => sum + item.total);
    final newTotalRev = oldSale.timeRevenue + newDrinksRev;

    final sIdx = _localSales.indexWhere((s) => s.id == oldSale.id);
    if (sIdx >= 0) {
      if (updatedItems.isEmpty && oldSale.timeRevenue <= 0) {
        _localSales.removeAt(sIdx);
      } else {
        _localSales[sIdx] = SaleRecord(
          id: oldSale.id,
          type: oldSale.type,
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

    _saveAndEmitLocal();

    if (useCloud) {
      try {
        if (updatedItems.isEmpty && oldSale.timeRevenue <= 0) {
          await _db!.collection('sales').doc(oldSale.id).delete();
        } else {
          await _db!.collection('sales').doc(oldSale.id).update({
            'drinksRevenue': newDrinksRev,
            'totalRevenue': newTotalRev,
            'soldItems': updatedItems.map((e) => e.toMap()).toList(),
          });
        }
      } catch (_) {}
    }

    await _recordAudit(
      title: 'تعديل فاتورة مبيعات',
      message:
          'تم تعديل الفاتورة من ${oldTotal.toStringAsFixed(1)} إلى ${newTotalRev.toStringAsFixed(1)} ج.م',
      beforeVal: '${oldTotal.toStringAsFixed(1)} ج.م',
      afterVal: '${newTotalRev.toStringAsFixed(1)} ج.م',
    );
  }

  Future<void> deleteSaleRecord(SaleRecord sale) async {
    for (final item in sale.soldItems) {
      final iIdx = _localInv.indexWhere((i) => i.id == item.itemId);
      if (iIdx >= 0) {
        _localInv[iIdx] = InventoryItem(
          id: _localInv[iIdx].id,
          name: _localInv[iIdx].name,
          price: _localInv[iIdx].price,
          stock: _localInv[iIdx].stock + item.qty,
          lowStockThreshold: _localInv[iIdx].lowStockThreshold,
        );
      }
    }

    _localSales.removeWhere((s) => s.id == sale.id);
    _saveAndEmitLocal();

    if (useCloud) {
      try {
        await _db!.collection('sales').doc(sale.id).delete();
      } catch (_) {}
    }

    await _recordAudit(
      title: 'إلغاء وحذف فاتورة',
      message:
          'تم حذف فاتورة بقيمة ${sale.totalRevenue.toStringAsFixed(1)} ج.م وإرجاع الكميات للمخزن',
      beforeVal: '${sale.totalRevenue.toStringAsFixed(1)} ج.م',
      afterVal: 'محذوفة',
    );
  }

  Future<void> closeCurrentDayAndReset(
      {required double drinksRev,
      required double tableRev,
      required double grandTotal}) async {
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    double extraTableRev = 0;
    double extraDrinks = 0;

    for (int i = 0; i < _localTables.length; i++) {
      final t = _localTables[i];
      if (t.currentElapsedSeconds > 0 || t.attachedItems.isNotEmpty) {
        extraTableRev += t.currentTimeCost;
        extraDrinks += t.attachedDrinksCost;
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
    final finalGrandTotal = finalDrinks + finalTables;

    final summary = ClosedDaySummary(
      id: const Uuid().v4(),
      dateLabel: dateStr,
      drinksRevenue: finalDrinks,
      tablesRevenue: finalTables,
      grandTotal: finalGrandTotal,
      closedAt: now,
    );

    if (finalGrandTotal > 0) {
      _localClosedDays.insert(0, summary);
    }
    _localSales.clear();
    _saveAndEmitLocal();

    if (useCloud) {
      try {
        if (finalGrandTotal > 0) {
          await _db!.collection('closed_days').add(summary.toMap());
        }
        final tablesSnap = await _db!.collection('tables').get();
        for (final doc in tablesSnap.docs) {
          await doc.reference.update({
            'status': 'idle',
            'lastStartTime': null,
            'accumulatedSeconds': 0,
            'attachedItems': [],
            'guestNotes': ''
          });
        }
        final allSalesSnap = await _db!.collection('sales').get();
        for (final doc in allSalesSnap.docs) {
          await doc.reference.delete();
        }
      } catch (_) {}
    }

    await _recordAudit(
        title: 'تقفيل اليوم - Joker Cafe',
        message:
            'تم تقفيل حسابات يوم $dateStr بإجمالي ${finalGrandTotal.toStringAsFixed(1)} ج.م',
        beforeVal: '${finalGrandTotal.toStringAsFixed(1)} ج.م',
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
    _saveAndEmitLocal();

    if (useCloud) {
      try {
        await _db!.collection('inventory').doc(newItem.id).set(newItem.toMap());
      } catch (_) {}
    }
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
      _saveAndEmitLocal();
    }
    if (useCloud) {
      try {
        await _db!
            .collection('inventory')
            .doc(item.id)
            .update({'price': newPrice});
      } catch (_) {}
    }
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
      _saveAndEmitLocal();
    }
    if (useCloud) {
      try {
        await _db!
            .collection('inventory')
            .doc(item.id)
            .update({'stock': newStock});
      } catch (_) {}
    }
  }

  Future<void> deleteInventoryItem(InventoryItem item) async {
    _localInv.removeWhere((i) => i.id == item.id);
    _saveAndEmitLocal();
    if (useCloud) {
      try {
        await _db!.collection('inventory').doc(item.id).delete();
      } catch (_) {}
    }
  }
}

// =============================================================================
// 4. MAIN ENTRY POINT & ANTI-LAG UI
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
  Map<String, dynamic>? _availableUpdate;

  @override
  void initState() {
    super.initState();
    _checkRemoteUpdate();
  }

  Future<void> _checkRemoteUpdate({bool showNoUpdateToast = false}) async {
    final update = await AppUpdateService.checkForUpdate();
    if (!mounted) return;
    if (update != null) {
      setState(() => _availableUpdate = update);
      _showUpdateDialog(update);
    } else if (showNoUpdateToast) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('التطبيق محدث لآخر إصدار ($kCurrentAppVersion)')),
      );
    }
  }

  void _showUpdateDialog(Map<String, dynamic> update) {
    final ver = update['version'] ?? '';
    final notes =
        update['notes'] ?? 'تحديث جديد متاح لتحسين الأداء وإضافة مميزات.';
    final url = Platform.isWindows
        ? (update['windows_url'] ??
            'https://github.com/kirollostharwat-glitch/joker-cafe/releases')
        : (update['android_url'] ??
            'https://github.com/kirollostharwat-glitch/joker-cafe/releases');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.system_update, color: Color(0xFF00C896)),
            const SizedBox(width: 8),
            Text('تحديث جديد متاح ($ver)'),
          ],
        ),
        content: Text(notes),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('لاحقاً'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C896),
                foregroundColor: Colors.black),
            onPressed: () {
              Navigator.pop(ctx);
              AppUpdateService.openDownloadUrl(url);
            },
            icon: const Icon(Icons.download),
            label: const Text('تنزيل التحديث الآن'),
          ),
        ],
      ),
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
                return StreamBuilder<List<AuditLog>>(
                  initialData: widget.db.currentLogs,
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
                                IconButton(
                                  icon: Icon(
                                    Icons.system_update_alt,
                                    color: _availableUpdate != null
                                        ? Colors.amberAccent
                                        : Colors.white70,
                                  ),
                                  tooltip:
                                      'التحقق من التحديثات (v$kCurrentAppVersion)',
                                  onPressed: () => _checkRemoteUpdate(
                                      showNoUpdateToast: true),
                                ),
                                const SizedBox(width: 6),
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
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF00C896)),
                                  ),
                                ),
                              ],
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
  }

  Widget _buildWindowsDesktopView(
      List<GamingTable> tables,
      List<InventoryItem> inventory,
      List<SaleRecord> sales,
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
                label: Text('تقفيل اليوم والتقارير')),
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
                  return _buildReportsSection(sales, logs);
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
      List<AuditLog> logs) {
    switch (_selectedIndex) {
      case 0:
        return _buildTablesSection(tables, inventory);
      case 1:
        return _buildPosSection(inventory, tables, sales);
      case 2:
        return _buildInventorySection(inventory);
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

    final directSales = sales.where((s) => s.type == 'drinks_only').toList();

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
        const Text('فواتير البيع المباشر المسجلة في الشيفت (تعديل / إلغاء):',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        if (directSales.isEmpty)
          const Text('مفيش فواتير بيع مباشر مسجلة في الشيفت الحالي لسه.',
              style: TextStyle(color: Colors.white60))
        else
          ...directSales.map((sale) {
            final itemsSummary = sale.soldItems
                .map((e) => '${e.name} × ${e.qty}')
                .join(' ، ');
            final timeStr = intl.DateFormat('hh:mm a').format(sale.timestamp);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading:
                    const Icon(Icons.receipt_long, color: Color(0xFF00C896)),
                title: Text(
                  '${sale.totalRevenue.toStringAsFixed(1)} ج.م  ($timeStr)',
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

  void _showEditSaleDialog(SaleRecord sale, List<InventoryItem> inventory) {
    final List<AttachedItem> editableItems = List.from(sale.soldItems);

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تعديل فاتورة البيع المباشر'),
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
                              'الفاتورة أصبحت فارغة (سيتم حذفها عند الحفظ)'))
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
        title: const Text('حذف فاتورة البيع المباشر'),
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

  Widget _buildReportsSection(List<SaleRecord> sales, List<AuditLog> logs) {
    double drinksRev = 0;
    double tableRev = 0;
    for (final s in sales) {
      drinksRev += s.drinksRevenue;
      tableRev += s.timeRevenue;
    }
    final grandTotal = drinksRev + tableRev;

    return StreamBuilder<List<ClosedDaySummary>>(
      initialData: widget.db.currentClosedDays,
      stream: widget.db.streamClosedDays(),
      builder: (context, closedSnap) {
        final closedDays = closedSnap.data ?? [];

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
                    const Text('تقفيل الشيفت واليوم الحالي',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00C896))),
                    const SizedBox(height: 10),
                    Text('إيراد المشاريب: ${drinksRev.toStringAsFixed(1)} ج.م'),
                    Text('إيراد الترابيزات: ${tableRev.toStringAsFixed(1)} ج.م'),
                    const Divider(),
                    Text('الإجمالي الكلي: ${grandTotal.toStringAsFixed(1)} ج.م',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber)),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white),
                      onPressed: () => _confirmCloseDayDialog(
                          drinksRev, tableRev, grandTotal),
                      icon: const Icon(Icons.lock_clock),
                      label: const Text('تقفيل اليوم وتصفير الشيفت'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('سجل الأيام السابقة المتقفلة:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                          'مشاريب: ${day.drinksRevenue.toStringAsFixed(0)} | ترابيزات: ${day.tablesRevenue.toStringAsFixed(0)}'),
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

  void _confirmCloseDayDialog(double dRev, double tRev, double gTotal) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('تقفيل اليوم'),
        content: Text(
            'هل تريد تقفيل اليوم بإجمالي ${gTotal.toStringAsFixed(1)} ج.م وتصفير الشيفت؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await widget.db.closeCurrentDayAndReset(
                  drinksRev: dRev, tableRev: tRev, grandTotal: gTotal);
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
