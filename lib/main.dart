import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const CafePosApp());
}

class CafePosApp extends StatelessWidget {
  const CafePosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'كافيه الجوكر - Joker Cafe POS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0F17),
        primaryColor: const Color(0xFF7C3AED),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7C3AED),
          secondary: Color(0xFF10B981),
          surface: Color(0xFF151C28),
          error: Color(0xFFEF4444),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF151C28),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF263147)),
          ),
        ),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: AdminShell(),
      ),
    );
  }
}

class FirestoreService {
  static const String projectId = 'joker-cafe-ddc53';
  static const String baseUrl =
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';

  static dynamic _fromFs(Map val) {
    if (val.containsKey('stringValue')) {
      return val['stringValue'];
    }
    if (val.containsKey('integerValue')) {
      return int.tryParse(val['integerValue'].toString()) ?? 0;
    }
    if (val.containsKey('doubleValue')) {
      return (val['doubleValue'] as num).toDouble();
    }
    if (val.containsKey('booleanValue')) {
      return val['booleanValue'];
    }
    if (val.containsKey('timestampValue')) {
      final dt = DateTime.tryParse(val['timestampValue'].toString());
      return dt?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;
    }
    if (val.containsKey('nullValue')) {
      return null;
    }
    if (val.containsKey('arrayValue')) {
      final list = val['arrayValue']['values'] as List? ?? [];
      return list.map((e) {
        return _fromFs(Map.from(e));
      }).toList();
    }
    if (val.containsKey('mapValue')) {
      final fields = val['mapValue']['fields'] as Map? ?? {};
      final Map out = {};
      fields.forEach((k, v) {
        out[k.toString()] = _fromFs(Map.from(v));
      });
      return out;
    }
    return null;
  }

  static Map _toFs(dynamic val) {
    if (val == null) {
      return {'nullValue': null};
    }
    if (val is String) {
      return {'stringValue': val};
    }
    if (val is int) {
      return {'integerValue': val.toString()};
    }
    if (val is double) {
      return {'doubleValue': val};
    }
    if (val is bool) {
      return {'booleanValue': val};
    }
    if (val is List) {
      return {
        'arrayValue': {
          'values': val.map((e) {
            return _toFs(e);
          }).toList()
        }
      };
    }
    if (val is Map) {
      final Map f = {};
      val.forEach((k, v) {
        f[k.toString()] = _toFs(v);
      });
      return {
        'mapValue': {'fields': f}
      };
    }
    return {'stringValue': val.toString()};
  }

  static Future fetchCollection(String col) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse('$baseUrl/$col?pageSize=300'));
      final res = await req.close();
      if (res.statusCode != 200) {
        return null;
      }
      final body = await res.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      final docs = data['documents'] as List? ?? [];
      return docs.map((d) {
        final parts = (d['name'] as String).split('/');
        final fields = d['fields'] as Map? ?? {};
        final Map m = {'_docId': parts.last};
        fields.forEach((k, v) {
          m[k.toString()] = _fromFs(Map.from(v));
        });
        return m;
      }).toList();
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static Future saveDoc(String col, String docId, Map data) async {
    final client = HttpClient();
    try {
      final clean = Map.from(data)..remove('_docId');
      final Map fields = {};
      clean.forEach((k, v) {
        fields[k.toString()] = _toFs(v);
      });
      final req = await client.patchUrl(Uri.parse('$baseUrl/$col/$docId'));
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode({'fields': fields})));
      await req.close();
    } catch (_) {
    } finally {
      client.close();
    }
  }

  static Future removeDoc(String col, String docId) async {
    final client = HttpClient();
    try {
      final req = await client.deleteUrl(Uri.parse('$baseUrl/$col/$docId'));
      await req.close();
    } catch (_) {
    } finally {
      client.close();
    }
  }
}

class MenuItem {
  String id;
  String name;
  String category;
  double price;
  int stock;
  int lowStockThreshold;

  MenuItem({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.stock,
    this.lowStockThreshold = 5,
  });

  bool get isLowStock {
    return (stock - lowStockThreshold).isNegative || stock == lowStockThreshold;
  }

  Map toMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'price': price,
      'stock': stock,
      'lowStockThreshold': lowStockThreshold,
    };
  }

  factory MenuItem.fromDoc(Map m) {
    return MenuItem(
      id: (m['_docId'] ?? m['id'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      category: (m['category'] ?? 'مشروبات ساخنة').toString(),
      price: (m['price'] as num? ?? 0).toDouble(),
      stock: (m['stock'] as num? ?? 0).toInt(),
      lowStockThreshold: (m['lowStockThreshold'] as num? ?? 5).toInt(),
    );
  }
}

class SaleLine {
  String itemId;
  String name;
  double price;
  int qty;

  SaleLine({
    required this.itemId,
    required this.name,
    required this.price,
    required this.qty,
  });

  double get lineTotal {
    return price * qty;
  }

  Map toMap() {
    return {
      'itemId': itemId,
      'name': name,
      'price': price,
      'qty': qty,
      'count': qty,
    };
  }

  factory SaleLine.fromMap(Map m) {
    return SaleLine(
      itemId: (m['itemId'] ?? m['id'] ?? m['name'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      price: (m['price'] as num? ?? 0).toDouble(),
      qty: ((m['qty'] ?? m['count']) as num? ?? 1).toInt(),
    );
  }
}

class GameTable {
  String id;
  String name;
  String tableType;
  double hourlyRate;
  String status;
  int? startedAtMs;
  int accumulatedSeconds;
  int? limitMinutes;
  List drinks;

  GameTable({
    required this.id,
    required this.name,
    required this.tableType,
    required this.hourlyRate,
    this.status = 'idle',
    this.startedAtMs,
    this.accumulatedSeconds = 0,
    this.limitMinutes,
    List? drinks,
  }) : drinks = drinks ?? [];

  bool get isRunning {
    return status == 'running';
  }

  bool get isPaused {
    return status == 'paused';
  }

  bool get isIdle {
    return status == 'idle';
  }

  int get elapsedSeconds {
    if (isIdle) {
      return 0;
    }
    if (isPaused || startedAtMs == null) {
      return accumulatedSeconds;
    }
    final currentRun =
        ((DateTime.now().millisecondsSinceEpoch - startedAtMs!) / 1000).floor();
    if (currentRun.isNegative) {
      return accumulatedSeconds;
    }
    return accumulatedSeconds + currentRun;
  }

  double get timeCost {
    return (elapsedSeconds / 3600.0) * hourlyRate;
  }

  double get drinksCost {
    double sum = 0.0;
    for (final raw in drinks) {
      final d = raw as SaleLine;
      sum += d.lineTotal;
    }
    return sum;
  }

  int get drinksCount {
    int count = 0;
    for (final raw in drinks) {
      count += (raw as SaleLine).qty;
    }
    return count;
  }

  double get grandTotal {
    return timeCost + drinksCost;
  }

  bool get isTimeUp {
    if (isIdle || limitMinutes == null) {
      return false;
    }
    return !(elapsedSeconds - (limitMinutes! * 60)).isNegative;
  }

  Map toMap() {
    return {
      'id': id,
      'name': name,
      'tableType': tableType,
      'hourlyRate': hourlyRate,
      'status': status,
      'isRunning': isRunning,
      'startedAtMs': startedAtMs,
      'startTimeMs': startedAtMs,
      'accumulatedSeconds': accumulatedSeconds,
      'limitMinutes': limitMinutes,
      'drinks': drinks.map((e) {
        return (e as SaleLine).toMap();
      }).toList(),
      'orders': drinks.map((e) {
        return (e as SaleLine).toMap();
      }).toList(),
    };
  }

  factory GameTable.fromDoc(
      Map m, String defId, String defName, String defType, double defRate) {
    final rawDrinks = (m['drinks'] ?? m['orders']) as List? ?? [];
    String st = (m['status'] ?? '').toString();
    if (st.isEmpty) {
      st = (m['isRunning'] == true) ? 'running' : 'idle';
    }
    final startRaw = m['startedAtMs'] ?? m['startTimeMs'] ?? m['startedAt'];
    int? parsedStart;
    if (startRaw is num) {
      parsedStart = startRaw.toInt();
    }
    return GameTable(
      id: (m['_docId'] ?? m['id'] ?? defId).toString(),
      name: (m['name'] ?? defName).toString(),
      tableType: (m['tableType'] ?? defType).toString(),
      hourlyRate: (m['hourlyRate'] as num? ?? defRate).toDouble(),
      status: st,
      startedAtMs: parsedStart,
      accumulatedSeconds: (m['accumulatedSeconds'] as num? ?? 0).toInt(),
      limitMinutes: (m['limitMinutes'] as num?)?.toInt(),
      drinks: rawDrinks.map((e) {
        return SaleLine.fromMap(Map.from(e));
      }).toList(),
    );
  }
}

class Sale {
  String id;
  String source;
  String tableType;
  double tableHours;
  double timeCost;
  double drinksRevenue;
  double grandTotal;
  String details;
  String dayKey;
  String monthKey;
  int createdAtMs;
  List items;

  Sale({
    required this.id,
    required this.source,
    required this.tableType,
    required this.tableHours,
    required this.timeCost,
    required this.drinksRevenue,
    required this.grandTotal,
    required this.details,
    required this.dayKey,
    required this.monthKey,
    required this.createdAtMs,
    List? items,
  }) : items = items ?? [];

  Map toMap() {
    return {
      'id': id,
      'source': source,
      'tableType': tableType,
      'tableHours': tableHours,
      'timeCost': timeCost,
      'drinksRevenue': drinksRevenue,
      'drinksCost': drinksRevenue,
      'grandTotal': grandTotal,
      'total': grandTotal,
      'amount': grandTotal,
      'details': details,
      'dayKey': dayKey,
      'monthKey': monthKey,
      'createdAtMs': createdAtMs,
      'items': items.map((e) {
        return (e as SaleLine).toMap();
      }).toList(),
    };
  }

  factory Sale.fromDoc(Map m) {
    final ms = (m['createdAtMs'] ?? m['createdAt'] ?? DateTime.now().millisecondsSinceEpoch);
    final int ts = (ms is num) ? ms.toInt() : DateTime.now().millisecondsSinceEpoch;
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    final dKey =
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    final mKey = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
    final tot = ((m['grandTotal'] ?? m['total'] ?? m['amount']) as num? ?? 0).toDouble();
    final dRev = ((m['drinksRevenue'] ?? m['drinksCost']) as num? ?? 0).toDouble();
    final tCost = (m['timeCost'] as num? ?? (tot - dRev)).toDouble();
    final rawItems = m['items'] as List? ?? [];
    return Sale(
      id: (m['_docId'] ?? m['id'] ?? ts.toString()).toString(),
      source: (m['source'] ?? m['tableName'] ?? 'طلب كافيه').toString(),
      tableType: (m['tableType'] ?? 'cafe').toString(),
      tableHours: (m['tableHours'] as num? ?? 0).toDouble(),
      timeCost: tCost.isNegative ? 0 : tCost,
      drinksRevenue: dRev,
      grandTotal: tot,
      details: (m['details'] ?? '').toString(),
      dayKey: (m['dayKey'] ?? dKey).toString(),
      monthKey: (m['monthKey'] ?? mKey).toString(),
      createdAtMs: ts,
      items: rawItems.map((e) {
        return SaleLine.fromMap(Map.from(e));
      }).toList(),
    );
  }
}

class AuditLog {
  String id;
  String category;
  String title;
  String details;
  int createdAtMs;

  AuditLog({
    required this.id,
    required this.category,
    required this.title,
    required this.details,
    required this.createdAtMs,
  });

  Map toMap() {
    return {
      'id': id,
      'category': category,
      'title': title,
      'details': details,
      'createdAtMs': createdAtMs,
    };
  }

  factory AuditLog.fromDoc(Map m) {
    final ts =
        (m['createdAtMs'] as num? ?? DateTime.now().millisecondsSinceEpoch).toInt();
    return AuditLog(
      id: (m['_docId'] ?? m['id'] ?? ts.toString()).toString(),
      category: (m['category'] ?? 'system').toString(),
      title: (m['title'] ?? '').toString(),
      details: (m['details'] ?? '').toString(),
      createdAtMs: ts,
    );
  }
}

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State createState() {
    return _AdminShellState();
  }
}

class _AdminShellState extends State {
  int _selectedIndex = 0;
  bool _isOnline = true;
  bool _syncing = false;
  Timer? _clockTimer;
  Timer? _cloudTimer;

  String _selectedMenuCategory = 'الكل';
  String _stockFilter = 'all';
  String _historyFilter = 'all';
  DateTime _reportMonth = DateTime(DateTime.now().year, DateTime.now().month);

  List tables = [];
  List menuItems = [];
  List posCart = [];
  List sales = [];
  List auditLogs = [];
  Map closedDays = {};

  @override
  void initState() {
    super.initState();
    tables = [
      GameTable(
        id: 'billiard_table',
        name: 'ترابيزة البلياردو',
        tableType: 'billiard',
        hourlyRate: 60,
      ),
      GameTable(
        id: 'ping_pong_table',
        name: 'ترابيزة البنج بونج',
        tableType: 'ping_pong',
        hourlyRate: 40,
      ),
    ];
    _loadLocalCache();
    _syncWithCloud();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (_selectedIndex == 0 || _selectedIndex == 1)) {
        setState(() {});
      }
    });
    _cloudTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_syncing) {
        _syncWithCloud();
      }
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _cloudTimer?.cancel();
    super.dispose();
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _monthKey(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
  }

  String _formatClock(int totalSec) {
    final h = (totalSec ~/ 3600).toString().padLeft(2, '0');
    final m = ((totalSec % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (totalSec % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatDateTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} - ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future _loadLocalCache() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      final tStr = prefs.getString('cafe_pos_tables');
      if (tStr != null) {
        final rawList = jsonDecode(tStr) as List;
        tables = rawList.map((e) {
          final m = Map.from(e);
          return GameTable.fromDoc(
              m, m['id'] ?? 'table', m['name'] ?? 'ترابيزة', m['tableType'] ?? 'billiard', 60);
        }).toList();
      }

      final mStr = prefs.getString('cafe_pos_menu');
      if (mStr != null) {
        menuItems = (jsonDecode(mStr) as List).map((e) {
          return MenuItem.fromDoc(Map.from(e));
        }).toList();
      } else {
        menuItems = _defaultMenuItems();
      }

      final sStr = prefs.getString('cafe_pos_sales');
      if (sStr != null) {
        sales = (jsonDecode(sStr) as List).map((e) {
          return Sale.fromDoc(Map.from(e));
        }).toList();
      }

      final aStr = prefs.getString('cafe_pos_audits');
      if (aStr != null) {
        auditLogs = (jsonDecode(aStr) as List).map((e) {
          return AuditLog.fromDoc(Map.from(e));
        }).toList();
      }
    });
  }

  List _defaultMenuItems() {
    return [
      MenuItem(id: 'tea', name: 'شاي', category: 'مشروبات ساخنة', price: 15, stock: 50),
      MenuItem(id: 'turkey_coffee', name: 'قهوة تركي', category: 'مشروبات ساخنة', price: 25, stock: 40),
      MenuItem(id: 'nescafe', name: 'نسكافيه', category: 'مشروبات ساخنة', price: 30, stock: 35),
      MenuItem(id: 'espresso', name: 'إسبريسو', category: 'مشروبات ساخنة', price: 35, stock: 30),
      MenuItem(id: 'pepsi', name: 'بيبسي كانز', category: 'مشروبات باردة', price: 25, stock: 48),
      MenuItem(id: 'water', name: 'مياه معدنية', category: 'مشروبات باردة', price: 10, stock: 60),
      MenuItem(id: 'mango', name: 'عصير مانجو فريش', category: 'مشروبات باردة', price: 40, stock: 25),
      MenuItem(id: 'molten_cake', name: 'مولتن كيك', category: 'كيكات وحلويات', price: 55, stock: 15),
      MenuItem(id: 'cheese_cake', name: 'تشيز كيك', category: 'كيكات وحلويات', price: 50, stock: 12),
      MenuItem(id: 'brownies', name: 'براونيز', category: 'كيكات وحلويات', price: 45, stock: 18),
    ];
  }

  Future _saveLocalCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'cafe_pos_tables',
        jsonEncode(tables.map((e) {
          return (e as GameTable).toMap();
        }).toList()));
    await prefs.setString(
        'cafe_pos_menu',
        jsonEncode(menuItems.map((e) {
          return (e as MenuItem).toMap();
        }).toList()));
    await prefs.setString(
        'cafe_pos_sales',
        jsonEncode(sales.map((e) {
          return (e as Sale).toMap();
        }).toList()));
    await prefs.setString(
        'cafe_pos_audits',
        jsonEncode(auditLogs.map((e) {
          return (e as AuditLog).toMap();
        }).toList()));
  }

  Future _logAudit(String category, String title, String details) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final entry = AuditLog(
      id: nowMs.toString(),
      category: category,
      title: title,
      details: details,
      createdAtMs: nowMs,
    );
    setState(() {
      auditLogs.insert(0, entry);
    });
    _saveLocalCache();
    await FirestoreService.saveDoc('audit_logs', entry.id, entry.toMap());
  }

  Future _syncWithCloud() async {
    _syncing = true;
    try {
      final tDocs = await FirestoreService.fetchCollection('game_tables');
      final mDocs = await FirestoreService.fetchCollection('menu_items');
      final sDocs = await FirestoreService.fetchCollection('sales');
      final aDocs = await FirestoreService.fetchCollection('audit_logs');
      final cDocs = await FirestoreService.fetchCollection('daily_closures');

      if (!mounted) {
        return;
      }

      if (tDocs == null && mDocs == null && sDocs == null) {
        setState(() {
          _isOnline = false;
        });
        return;
      }

      setState(() {
        _isOnline = true;

        if (tDocs != null && (tDocs as List).isNotEmpty) {
          final List loadedTables = [];
          for (final raw in tDocs) {
            final d = raw as Map;
            final docId = (d['_docId'] ?? '').toString();
            final isPing = docId.contains('ping');
            loadedTables.add(GameTable.fromDoc(
              d,
              docId,
              isPing ? 'ترابيزة البنج بونج' : 'ترابيزة البلياردو',
              isPing ? 'ping_pong' : 'billiard',
              isPing ? 40 : 60,
            ));
          }
          tables = loadedTables;
        }

        if (mDocs != null && (mDocs as List).isNotEmpty) {
          menuItems = mDocs.map((e) {
            return MenuItem.fromDoc(e as Map);
          }).toList();
        }

        if (sDocs != null && (sDocs as List).isNotEmpty) {
          sales = sDocs.map((e) {
            return Sale.fromDoc(e as Map);
          }).toList()
            ..sort((a, b) {
              return (b as Sale).createdAtMs.compareTo((a as Sale).createdAtMs);
            });
        }

        if (aDocs != null && (aDocs as List).isNotEmpty) {
          auditLogs = aDocs.map((e) {
            return AuditLog.fromDoc(e as Map);
          }).toList()
            ..sort((a, b) {
              return (b as AuditLog).createdAtMs.compareTo((a as AuditLog).createdAtMs);
            });
        }

        if (cDocs != null) {
          for (final raw in (cDocs as List)) {
            final d = raw as Map;
            closedDays[(d['_docId'] ?? '').toString()] = d;
          }
        }
      });
      _saveLocalCache();
    } catch (_) {
      if (mounted) {
        setState(() {
          _isOnline = false;
        });
      }
    } finally {
      _syncing = false;
    }
  }

  double get _todaySales {
    final tKey = _todayKey();
    double sum = 0.0;
    for (final raw in sales) {
      final s = raw as Sale;
      if (s.dayKey == tKey) {
        sum += s.grandTotal;
      }
    }
    return sum;
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF7C3AED),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = !(width - 900).isNegative;

    final pages = [
      _buildDashboardCombinedScreen(isWide),
      _buildPosOnlyScreen(),
      _buildInventoryAdminScreen(),
      _buildReportsScreen(),
      _buildHistoryAndAuditScreen(),
    ];

    return Scaffold(
      appBar: _buildTopBar(),
      body: Row(
        children: [
          if (isWide)
            NavigationRail(
              backgroundColor: const Color(0xFF111622),
              selectedIndex: _selectedIndex,
              onDestinationSelected: (i) {
                setState(() {
                  _selectedIndex = i;
                });
              },
              extended: !(width - 1150).isNegative,
              selectedIconTheme: const IconThemeData(color: Color(0xFF7C3AED)),
              selectedLabelTextStyle: const TextStyle(
                  color: Color(0xFF7C3AED), fontWeight: FontWeight.bold),
              unselectedLabelTextStyle: const TextStyle(color: Colors.grey),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.dashboard),
                  label: Text('لوحة التشغيل والترابيزات'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.local_cafe),
                  label: Text('نقطة بيع الكافيه (POS)'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.inventory_2),
                  label: Text('إدارة الأصناف والمخزن'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.bar_chart),
                  label: Text('التقارير وتقفيل اليومية'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.history),
                  label: Text('سجل الفواتير والتعديلات'),
                ),
              ],
            ),
          if (isWide) const VerticalDivider(width: 1, color: Color(0xFF263147)),
          Expanded(child: pages[_selectedIndex]),
        ],
      ),
      bottomNavigationBar: isWide
          ? null
          : BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: (i) {
                setState(() {
                  _selectedIndex = i;
                });
              },
              backgroundColor: const Color(0xFF111622),
              selectedItemColor: const Color(0xFF7C3AED),
              unselectedItemColor: Colors.grey,
              type: BottomNavigationBarType.fixed,
              items: const [
                BottomNavigationBarItem(
                    icon: Icon(Icons.sports_esports), label: 'الترابيزات'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.local_cafe), label: 'الكافيه'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.inventory_2), label: 'المخزن'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.bar_chart), label: 'التقارير'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.history), label: 'السجل'),
              ],
            ),
    );
  }

  PreferredSizeWidget _buildTopBar() {
    return AppBar(
      backgroundColor: const Color(0xFF111622),
      elevation: 0,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.style, color: Color(0xFF7C3AED), size: 24),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('كافيه الجوكر | JOKER CAFE',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              Text('نظام الإدارة المتكامل والمزامنة السحابية',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.payments_outlined,
                    color: Color(0xFF10B981), size: 16),
                const SizedBox(width: 6),
                Text(
                  'إيراد اليوم: ${_todaySales.toStringAsFixed(0)} ج.م',
                  style: const TextStyle(
                      color: Color(0xFF10B981),
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: () {
              _syncWithCloud();
              _showSnack('جاري مزامنة البيانات مع الموبايل...');
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: (_isOnline ? const Color(0xFF10B981) : Colors.redAccent)
                    .withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Icon(
                    _isOnline ? Icons.cloud_done : Icons.cloud_off,
                    color: _isOnline ? const Color(0xFF10B981) : Colors.redAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isOnline ? 'متصل' : 'محلي',
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          _isOnline ? const Color(0xFF10B981) : Colors.redAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardCombinedScreen(bool isWide) {
    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 6,
            child: _buildTablesListSection(),
          ),
          const VerticalDivider(width: 1, color: Color(0xFF263147)),
          Expanded(
            flex: 5,
            child: _buildPosPanelWidget(),
          ),
        ],
      );
    }
    return _buildTablesListSection();
  }

  Widget _buildTablesListSection() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('صالة الألعاب والترابيزات',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED)),
              onPressed: () {
                _showEditOrAddTableDialog();
              },
              icon: const Icon(Icons.add, color: Colors.white, size: 18),
              label: const Text('إضافة ترابيزة',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...tables.map((raw) {
          final t = raw as GameTable;
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _buildTableCard(t),
          );
        }),
      ],
    );
  }

  Widget _buildTableCard(GameTable table) {
    final isBilliard = table.tableType == 'billiard';
    final accent =
        isBilliard ? const Color(0xFF10B981) : const Color(0xFF7C3AED);
    final statusLabel = table.isRunning
        ? 'شغالة الآن'
        : (table.isPaused ? 'متوقفة مؤقتاً' : 'متاحة');
    final statusColor = table.isRunning
        ? const Color(0xFF10B981)
        : (table.isPaused ? Colors.amber : Colors.grey);

    return Card(
      color: table.isTimeUp ? const Color(0xFF3B1219) : const Color(0xFF151C28),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isBilliard ? Icons.circle_outlined : Icons.sports_tennis,
                    color: accent,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(table.name,
                          style: const TextStyle(
                              fontSize: 19, fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: statusColor, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Text(statusLabel,
                              style:
                                  TextStyle(color: statusColor, fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                ),
                ActionChip(
                  backgroundColor: accent.withOpacity(0.15),
                  avatar: Icon(Icons.edit, size: 15, color: accent),
                  label: Text('${table.hourlyRate.toStringAsFixed(0)} ج.م/س'),
                  onPressed: () {
                    _showEditOrAddTableDialog(existing: table);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF0B0F17),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF263147)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _formatClock(table.elapsedSeconds),
                        style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color:
                              table.isTimeUp ? Colors.redAccent : Colors.white,
                        ),
                      ),
                      if (!table.isIdle) ...[
                        const SizedBox(width: 10),
                        IconButton(
                          tooltip: 'تعديل الوقت يدوياً',
                          icon: const Icon(Icons.edit_calendar,
                              color: Colors.amber, size: 22),
                          onPressed: () {
                            _showEditElapsedTimeDialog(table);
                          },
                        ),
                      ],
                    ],
                  ),
                  if (table.isTimeUp)
                    const Text('تنبيه: انتهى الوقت المحدد للترابيزة!',
                        style: TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Text('حساب اللعب: ${table.timeCost.ceil()} ج.م',
                          style: const TextStyle(color: Colors.white70)),
                      Text(
                          'المشروبات (${table.drinksCount}): ${table.drinksCost.toStringAsFixed(0)} ج.م',
                          style: const TextStyle(color: Colors.white70)),
                      Text('الإجمالي: ${table.grandTotal.ceil()} ج.م',
                          style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                    ],
                  ),
                ],
              ),
            ),
            if (table.drinks.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('طلبات الترابيزة (اضغط لتعديل الكمية أو الحذف):',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: table.drinks.map((raw) {
                  final d = raw as SaleLine;
                  return InputChip(
                    label: Text(
                        '${d.name} × ${d.qty} (${d.lineTotal.toStringAsFixed(0)} ج)'),
                    onPressed: () {
                      _showEditTableDrinkDialog(table, d);
                    },
                    onDeleted: () async {
                      setState(() {
                        final mList = menuItems.where((m) {
                          return (m as MenuItem).name == d.name;
                        }).toList();
                        if (mList.isNotEmpty) {
                          (mList.first as MenuItem).stock += d.qty;
                        }
                        table.drinks.remove(d);
                      });
                      _saveLocalCache();
                      await FirestoreService.saveDoc(
                          'game_tables', table.id, table.toMap());
                    },
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (table.isIdle)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                    onPressed: () {
                      _showStartTableSessionDialog(table);
                    },
                    icon: const Icon(Icons.play_arrow, color: Colors.white),
                    label: const Text('بدء وقت اللعب',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                if (table.isRunning)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade700,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                    onPressed: () async {
                      setState(() {
                        table.accumulatedSeconds = table.elapsedSeconds;
                        table.startedAtMs = null;
                        table.status = 'paused';
                      });
                      _saveLocalCache();
                      await FirestoreService.saveDoc(
                          'game_tables', table.id, table.toMap());
                      _logAudit('table', 'إيقاف مؤقت', table.name);
                    },
                    icon: const Icon(Icons.pause, color: Colors.white),
                    label: const Text('إيقاف مؤقت',
                        style: TextStyle(color: Colors.white)),
                  ),
                if (table.isPaused)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                    onPressed: () async {
                      setState(() {
                        table.startedAtMs =
                            DateTime.now().millisecondsSinceEpoch;
                        table.status = 'running';
                      });
                      _saveLocalCache();
                      await FirestoreService.saveDoc(
                          'game_tables', table.id, table.toMap());
                      _logAudit('table', 'استئناف الوقت', table.name);
                    },
                    icon: const Icon(Icons.play_arrow, color: Colors.white),
                    label: const Text('استئناف',
                        style: TextStyle(color: Colors.white)),
                  ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF263147),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                  onPressed: () {
                    _showAddDrinksSheet(table);
                  },
                  icon: const Icon(Icons.local_cafe, color: Colors.white),
                  label: const Text('+ مشروب',
                      style: TextStyle(color: Colors.white)),
                ),
                if (!table.isIdle || table.drinks.isNotEmpty)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    onPressed: () {
                      _showTableBillDialog(table);
                    },
                    icon: const Icon(Icons.receipt_long, color: Colors.white),
                    label: const Text('إنهاء وحساب',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showStartTableSessionDialog(GameTable table) {
    int? mins;
    showDialog(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (ctx, setDlg) {
              return AlertDialog(
                backgroundColor: const Color(0xFF151C28),
                title: Text('تشغيل ${table.name}'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile(
                      title: const Text('وقت مفتوح'),
                      value: null,
                      groupValue: mins,
                      onChanged: (v) {
                        setDlg(() {
                          mins = v;
                        });
                      },
                    ),
                    RadioListTile(
                      title: const Text('نصف ساعة (30 دقيقة)'),
                      value: 30,
                      groupValue: mins,
                      onChanged: (v) {
                        setDlg(() {
                          mins = v;
                        });
                      },
                    ),
                    RadioListTile(
                      title: const Text('ساعة كاملة (60 دقيقة)'),
                      value: 60,
                      groupValue: mins,
                      onChanged: (v) {
                        setDlg(() {
                          mins = v;
                        });
                      },
                    ),
                    RadioListTile(
                      title: const Text('ساعة ونصف (90 دقيقة)'),
                      value: 90,
                      groupValue: mins,
                      onChanged: (v) {
                        setDlg(() {
                          mins = v;
                        });
                      },
                    ),
                    RadioListTile(
                      title: const Text('ساعتين (120 دقيقة)'),
                      value: 120,
                      groupValue: mins,
                      onChanged: (v) {
                        setDlg(() {
                          mins = v;
                        });
                      },
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                    },
                    child: const Text('إلغاء'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981)),
                    onPressed: () async {
                      setState(() {
                        table.status = 'running';
                        table.startedAtMs =
                            DateTime.now().millisecondsSinceEpoch;
                        table.accumulatedSeconds = 0;
                        table.limitMinutes = mins;
                      });
                      _saveLocalCache();
                      Navigator.pop(ctx);
                      await FirestoreService.saveDoc(
                          'game_tables', table.id, table.toMap());
                      _logAudit('table', 'بدء تشغيل ترابيزة', table.name);
                    },
                    child: const Text('ابدأ الآن',
                        style: TextStyle(color: Colors.white)),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _showEditElapsedTimeDialog(GameTable table) {
    final currentMinutes = (table.elapsedSeconds / 60).floor();
    final ctrl = TextEditingController(text: currentMinutes.toString());
    showDialog(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: const Color(0xFF151C28),
            title: Text('تعديل وقت ${table.name} (بالدقائق)'),
            content: TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'عدد الدقائق المنقضية',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                },
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final newMins = int.tryParse(ctrl.text);
                  if (newMins != null && !newMins.isNegative) {
                    setState(() {
                      table.accumulatedSeconds = newMins * 60;
                      if (table.isRunning) {
                        table.startedAtMs =
                            DateTime.now().millisecondsSinceEpoch;
                      }
                    });
                    _saveLocalCache();
                    Navigator.pop(ctx);
                    await FirestoreService.saveDoc(
                        'game_tables', table.id, table.toMap());
                    _logAudit('table', 'تعديل وقت يدوي',
                        '${table.name}: $newMins دقيقة');
                  }
                },
                child: const Text('حفظ الوقت'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditTableDrinkDialog(GameTable table, SaleLine drink) {
    final qtyCtrl = TextEditingController(text: drink.qty.toString());
    final priceCtrl =
        TextEditingController(text: drink.price.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: const Color(0xFF151C28),
            title: Text('تعديل ${drink.name} على ${table.name}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'الكمية'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'سعر الوحدة'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                },
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final q = int.tryParse(qtyCtrl.text) ?? drink.qty;
                  final p = double.tryParse(priceCtrl.text) ?? drink.price;
                  setState(() {
                    if (q.isNegative || q == 0) {
                      table.drinks.remove(drink);
                    } else {
                      drink.qty = q;
                      drink.price = p;
                    }
                  });
                  _saveLocalCache();
                  Navigator.pop(ctx);
                  await FirestoreService.saveDoc(
                      'game_tables', table.id, table.toMap());
                },
                child: const Text('حفظ التعديل'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditOrAddTableDialog({GameTable? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final rateCtrl = TextEditingController(
        text: existing?.hourlyRate.toStringAsFixed(0) ?? '50');
    String selectedType = existing?.tableType ?? 'billiard';

    showDialog(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (ctx, setDlg) {
              return AlertDialog(
                backgroundColor: const Color(0xFF151C28),
                title: Text(existing == null
                    ? 'إضافة ترابيزة جديدة'
                    : 'تعديل إعدادات ${existing.name}'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration:
                          const InputDecoration(labelText: 'اسم الترابيزة'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: rateCtrl,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'سعر الساعة (ج.م)'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField(
                      value: selectedType,
                      decoration:
                          const InputDecoration(labelText: 'نوع الترابيزة'),
                      items: const [
                        DropdownMenuItem(
                            value: 'billiard', child: Text('بلياردو')),
                        DropdownMenuItem(
                            value: 'ping_pong', child: Text('بنج بونج')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setDlg(() {
                            selectedType = v.toString();
                          });
                        }
                      },
                    ),
                  ],
                ),
                actions: [
                  if (existing != null)
                    TextButton(
                      onPressed: () async {
                        setState(() {
                          tables.remove(existing);
                        });
                        _saveLocalCache();
                        Navigator.pop(ctx);
                        await FirestoreService.removeDoc(
                            'game_tables', existing.id);
                      },
                      child: const Text('حذف الترابيزة',
                          style: TextStyle(color: Colors.redAccent)),
                    ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                    },
                    child: const Text('إلغاء'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final rate = double.tryParse(rateCtrl.text) ?? 50;
                      if (nameCtrl.text.trim().isEmpty) {
                        return;
                      }
                      if (existing == null) {
                        final newTable = GameTable(
                          id: 'table_${DateTime.now().millisecondsSinceEpoch}',
                          name: nameCtrl.text.trim(),
                          tableType: selectedType,
                          hourlyRate: rate,
                        );
                        setState(() {
                          tables.add(newTable);
                        });
                        _saveLocalCache();
                        Navigator.pop(ctx);
                        await FirestoreService.saveDoc(
                            'game_tables', newTable.id, newTable.toMap());
                      } else {
                        setState(() {
                          existing.name = nameCtrl.text.trim();
                          existing.hourlyRate = rate;
                          existing.tableType = selectedType;
                        });
                        _saveLocalCache();
                        Navigator.pop(ctx);
                        await FirestoreService.saveDoc(
                            'game_tables', existing.id, existing.toMap());
                      }
                    },
                    child: const Text('حفظ'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _showAddDrinksSheet(GameTable table) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151C28),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (ctx, setSheet) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('إضافة مشروبات لـ ${table.name}',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const Divider(),
                    Expanded(
                      child: ListView.builder(
                        itemCount: menuItems.length,
                        itemBuilder: (ctx, i) {
                          final item = menuItems[i] as MenuItem;
                          final empty =
                              item.stock.isNegative || item.stock == 0;
                          return ListTile(
                            title: Text(item.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(
                                '${item.price.toStringAsFixed(0)} ج.م | المتاح بالمخزن: ${item.stock}'),
                            trailing: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981)),
                              onPressed: empty
                                  ? null
                                  : () async {
                                      setState(() {
                                        item.stock--;
                                        final found = table.drinks.where((d) {
                                          return (d as SaleLine).name ==
                                              item.name;
                                        }).toList();
                                        if (found.isNotEmpty) {
                                          (found.first as SaleLine).qty++;
                                        } else {
                                          table.drinks.add(SaleLine(
                                            itemId: item.id,
                                            name: item.name,
                                            price: item.price,
                                            qty: 1,
                                          ));
                                        }
                                      });
                                      setSheet(() {});
                                      _saveLocalCache();
                                      await FirestoreService.saveDoc(
                                          'menu_items', item.id, item.toMap());
                                      await FirestoreService.saveDoc(
                                          'game_tables',
                                          table.id,
                                          table.toMap());
                                    },
                              icon: const Icon(Icons.add,
                                  color: Colors.white, size: 16),
                              label: const Text('إضافة',
                                  style: TextStyle(color: Colors.white)),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _showTableBillDialog(GameTable table) {
    final durStr = _formatClock(table.elapsedSeconds);
    final hrs = table.elapsedSeconds / 3600.0;
    final tCost = table.timeCost.ceilToDouble();
    final dCost = table.drinksCost;
    final initialTotal = (tCost + dCost).ceilToDouble();
    final totalCtrl =
        TextEditingController(text: initialTotal.toStringAsFixed(0));

    showDialog(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: const Color(0xFF151C28),
            title: Text('تقفيل حساب ${table.name}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المدة: $durStr'),
                Text('حساب الوقت: ${tCost.toStringAsFixed(0)} ج.م'),
                Text('حساب المشروبات: ${dCost.toStringAsFixed(0)} ج.م'),
                const Divider(height: 20),
                TextField(
                  controller: totalCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'الإجمالي النهائي للتحصيل (قابل للتعديل/الخصم)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                },
                child: const Text('رجوع'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981)),
                onPressed: () async {
                  final finalAmount =
                      double.tryParse(totalCtrl.text) ?? initialTotal;
                  final nowMs = DateTime.now().millisecondsSinceEpoch;
                  final nowDt = DateTime.fromMillisecondsSinceEpoch(nowMs);
                  final sale = Sale(
                    id: nowMs.toString(),
                    source: table.name,
                    tableType: table.tableType,
                    tableHours: hrs,
                    timeCost: tCost,
                    drinksRevenue: dCost,
                    grandTotal: finalAmount,
                    details:
                        'لعب ($durStr): ${tCost.toStringAsFixed(0)} ج + مشروبات: ${dCost.toStringAsFixed(0)} ج',
                    dayKey: _todayKey(),
                    monthKey: _monthKey(nowDt),
                    createdAtMs: nowMs,
                    items: List.from(table.drinks),
                  );
                  setState(() {
                    sales.insert(0, sale);
                    table.status = 'idle';
                    table.startedAtMs = null;
                    table.accumulatedSeconds = 0;
                    table.limitMinutes = null;
                    table.drinks.clear();
                  });
                  _saveLocalCache();
                  Navigator.pop(ctx);
                  await FirestoreService.saveDoc(
                      'sales', sale.id, sale.toMap());
                  await FirestoreService.saveDoc(
                      'game_tables', table.id, table.toMap());
                  _logAudit('sale', 'تحصيل ${table.name}',
                      '${finalAmount.toStringAsFixed(0)} ج.م');
                },
                child: const Text('تأكيد التحصيل وتصفير الترابيزة',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPosOnlyScreen() {
    return _buildPosPanelWidget();
  }

  Widget _buildPosPanelWidget() {
    final categories = ['الكل', 'مشروبات ساخنة', 'مشروبات باردة', 'كيكات وحلويات', 'عام'];
    final filteredMenu = menuItems.where((raw) {
      final m = raw as MenuItem;
      if (_selectedMenuCategory == 'الكل') {
        return true;
      }
      return m.category == _selectedMenuCategory;
    }).toList();

    double cartTotal = 0.0;
    for (final raw in posCart) {
      cartTotal += (raw as SaleLine).lineTotal;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('نقطة بيع الكافيه المباشر (POS)',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: () {
                  _showItemFormDialog();
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('صنف سريع'),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: categories.map((cat) {
              final selected = _selectedMenuCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(left: 8),
                child: ChoiceChip(
                  label: Text(cat),
                  selected: selected,
                  selectedColor: const Color(0xFF7C3AED),
                  onSelected: (_) {
                    setState(() {
                      _selectedMenuCategory = cat;
                    });
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(14),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 175,
              childAspectRatio: 1.1,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: filteredMenu.length,
            itemBuilder: (ctx, i) {
              final item = filteredMenu[i] as MenuItem;
              final outOfStock = item.stock.isNegative || item.stock == 0;
              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onLongPress: () {
                  _showItemFormDialog(existing: item);
                },
                onTap: outOfStock
                    ? null
                    : () {
                        setState(() {
                          item.stock--;
                          final existing = posCart.where((c) {
                            return (c as SaleLine).name == item.name;
                          }).toList();
                          if (existing.isNotEmpty) {
                            (existing.first as SaleLine).qty++;
                          } else {
                            posCart.add(SaleLine(
                              itemId: item.id,
                              name: item.name,
                              price: item.price,
                              qty: 1,
                            ));
                          }
                        });
                      },
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(item.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 6),
                        Text('${item.price.toStringAsFixed(0)} ج.م',
                            style: const TextStyle(
                                color: Color(0xFF10B981),
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                        const SizedBox(height: 4),
                        Text('المخزون: ${item.stock}',
                            style: TextStyle(
                                fontSize: 11,
                                color: item.isLowStock
                                    ? Colors.redAccent
                                    : Colors.grey)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (posCart.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF151C28),
              border: Border(top: BorderSide(color: Color(0xFF263147))),
            ),
            child: Column(
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: posCart.map((raw) {
                    final line = raw as SaleLine;
                    return InputChip(
                      label: Text('${line.name} × ${line.qty}'),
                      onDeleted: () {
                        setState(() {
                          final found = menuItems.where((m) {
                            return (m as MenuItem).name == line.name;
                          }).toList();
                          if (found.isNotEmpty) {
                            (found.first as MenuItem).stock += line.qty;
                          }
                          posCart.remove(line);
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('الإجمالي: ${cartTotal.toStringAsFixed(0)} ج.م',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981)),
                      onPressed: () {
                        _checkoutPosCart(cartTotal);
                      },
                      icon: const Icon(Icons.check_circle, color: Colors.white),
                      label: const Text('تحصيل الفاتورة',
                          style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future _checkoutPosCart(double cartTotal) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final nowDt = DateTime.fromMillisecondsSinceEpoch(nowMs);
    final detailsStr = posCart.map((raw) {
      final e = raw as SaleLine;
      return '${e.name} (${e.qty})';
    }).join('، ');

    final sale = Sale(
      id: nowMs.toString(),
      source: 'طلب كافيه مباشر',
      tableType: 'cafe',
      tableHours: 0,
      timeCost: 0,
      drinksRevenue: cartTotal,
      grandTotal: cartTotal,
      details: detailsStr,
      dayKey: _todayKey(),
      monthKey: _monthKey(nowDt),
      createdAtMs: nowMs,
      items: List.from(posCart),
    );

    setState(() {
      sales.insert(0, sale);
      posCart.clear();
    });
    _saveLocalCache();
    await FirestoreService.saveDoc('sales', sale.id, sale.toMap());
    for (final raw in menuItems) {
      final m = raw as MenuItem;
      await FirestoreService.saveDoc('menu_items', m.id, m.toMap());
    }
    _logAudit('pos', 'بيع مباشر بالكافيه',
        '${cartTotal.toStringAsFixed(0)} ج.م ($detailsStr)');
    _showSnack('تم تسجيل الفاتورة ومزامنتها!');
  }

  Widget _buildInventoryAdminScreen() {
    final filtered = menuItems.where((raw) {
      final m = raw as MenuItem;
      if (_stockFilter == 'low') {
        return m.isLowStock;
      }
      if (_stockFilter == 'out') {
        return m.stock.isNegative || m.stock == 0;
      }
      return true;
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('إدارة الأصناف والأسعار والمخزن',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED)),
              onPressed: () {
                _showItemFormDialog();
              },
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('إضافة صنف جديد',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: Text('كل الأصناف (${menuItems.length})'),
              selected: _stockFilter == 'all',
              onSelected: (_) {
                setState(() {
                  _stockFilter = 'all';
                });
              },
            ),
            ChoiceChip(
              label: const Text('نواقص المخزن'),
              selected: _stockFilter == 'low',
              onSelected: (_) {
                setState(() {
                  _stockFilter = 'low';
                });
              },
            ),
            ChoiceChip(
              label: const Text('نفد من المخزن'),
              selected: _stockFilter == 'out',
              onSelected: (_) {
                setState(() {
                  _stockFilter = 'out';
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...filtered.map((raw) {
          final item = raw as MenuItem;
          return Card(
            child: ListTile(
              title: Text(item.name,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                  'التصنيف: ${item.category} | السعر: ${item.price.toStringAsFixed(0)} ج.م | المخزون: ${item.stock}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'تزويد المخزون +5',
                    icon: const Icon(Icons.add_circle, color: Color(0xFF10B981)),
                    onPressed: () async {
                      setState(() {
                        item.stock += 5;
                      });
                      _saveLocalCache();
                      await FirestoreService.saveDoc(
                          'menu_items', item.id, item.toMap());
                    },
                  ),
                  IconButton(
                    tooltip: 'تعديل الكمية مباشرة',
                    icon: const Icon(Icons.inventory, color: Colors.blueAccent),
                    onPressed: () {
                      _showStockDialog(item);
                    },
                  ),
                  IconButton(
                    tooltip: 'تعديل الصنف والسعر',
                    icon: const Icon(Icons.edit, color: Colors.amber),
                    onPressed: () {
                      _showItemFormDialog(existing: item);
                    },
                  ),
                  IconButton(
                    tooltip: 'حذف الصنف',
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    onPressed: () async {
                      setState(() {
                        menuItems.remove(item);
                      });
                      _saveLocalCache();
                      await FirestoreService.removeDoc('menu_items', item.id);
                    },
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  void _showStockDialog(MenuItem item) {
    final ctrl = TextEditingController(text: item.stock.toString());
    showDialog(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: const Color(0xFF151C28),
            title: Text('تعديل مخزون: ${item.name}'),
            content: TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'الكمية الجديدة بالمخزن'),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                },
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final st = int.tryParse(ctrl.text);
                  if (st != null && !st.isNegative) {
                    setState(() {
                      item.stock = st;
                    });
                    _saveLocalCache();
                    Navigator.pop(ctx);
                    await FirestoreService.saveDoc(
                        'menu_items', item.id, item.toMap());
                    _logAudit(
                        'stock', 'تعديل مخزون', '${item.name}: $st قطعة');
                  }
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showItemFormDialog({MenuItem? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final priceCtrl = TextEditingController(
        text: existing?.price.toStringAsFixed(0) ?? '');
    final stockCtrl =
        TextEditingController(text: existing?.stock.toString() ?? '30');
    final lowCtrl = TextEditingController(
        text: existing?.lowStockThreshold.toString() ?? '5');
    String cat = existing?.category ?? 'مشروبات ساخنة';

    showDialog(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (ctx, setDlg) {
              return AlertDialog(
                backgroundColor: const Color(0xFF151C28),
                title:
                    Text(existing == null ? 'إضافة صنف جديد' : 'تعديل الصنف'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration:
                            const InputDecoration(labelText: 'اسم الصنف'),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField(
                        value: cat,
                        decoration: const InputDecoration(labelText: 'التصنيف'),
                        items: const [
                          DropdownMenuItem(
                              value: 'مشروبات ساخنة',
                              child: Text('مشروبات ساخنة')),
                          DropdownMenuItem(
                              value: 'مشروبات باردة',
                              child: Text('مشروبات باردة')),
                          DropdownMenuItem(
                              value: 'كيكات وحلويات',
                              child: Text('كيكات وحلويات')),
                          DropdownMenuItem(value: 'عام', child: Text('عام')),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setDlg(() {
                              cat = v.toString();
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: priceCtrl,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'السعر (ج.م)'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: stockCtrl,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'الكمية بالمخزن'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: lowCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'حد التنبيه للنواقص'),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                    },
                    child: const Text('إلغاء'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final price = double.tryParse(priceCtrl.text) ?? 0;
                      final stock = int.tryParse(stockCtrl.text) ?? 0;
                      final low = int.tryParse(lowCtrl.text) ?? 5;
                      if (nameCtrl.text.trim().isEmpty ||
                          price.isNegative ||
                          price == 0) {
                        return;
                      }
                      final id = existing?.id ??
                          DateTime.now().millisecondsSinceEpoch.toString();
                      final item = MenuItem(
                        id: id,
                        name: nameCtrl.text.trim(),
                        category: cat,
                        price: price,
                        stock: stock,
                        lowStockThreshold: low,
                      );
                      setState(() {
                        if (existing == null) {
                          menuItems.add(item);
                        } else {
                          existing.name = item.name;
                          existing.category = item.category;
                          existing.price = item.price;
                          existing.stock = item.stock;
                          existing.lowStockThreshold = item.lowStockThreshold;
                        }
                      });
                      _saveLocalCache();
                      Navigator.pop(ctx);
                      await FirestoreService.saveDoc(
                          'menu_items', id, item.toMap());
                      _logAudit('menu', 'حفظ صنف',
                          '${item.name} (${item.price} ج.م)');
                    },
                    child: const Text('حفظ'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildReportsScreen() {
    final mKey = _monthKey(_reportMonth);
    final monthSales = sales.where((raw) {
      return (raw as Sale).monthKey == mKey;
    }).toList();

    double totalRev = 0;
    double drinksRev = 0;
    double tablesRev = 0;
    double totalHours = 0;
    final Map dayTotals = {};

    for (final raw in monthSales) {
      final s = raw as Sale;
      totalRev += s.grandTotal;
      drinksRev += s.drinksRevenue;
      tablesRev += s.timeCost;
      totalHours += s.tableHours;
      dayTotals[s.dayKey] = (dayTotals[s.dayKey] as double? ?? 0) + s.grandTotal;
    }

    String bestDay = '-';
    double bestDayVal = 0;
    dayTotals.forEach((k, v) {
      final val = v as double;
      if (!(val - bestDayVal).isNegative && val != 0) {
        bestDayVal = val;
        bestDay = k.toString();
      }
    });

    final dayKeysList = dayTotals.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('التقارير الشهرية وتقفيل اليومية',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    setState(() {
                      _reportMonth =
                          DateTime(_reportMonth.year, _reportMonth.month - 1);
                    });
                  },
                ),
                Text(mKey,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    setState(() {
                      _reportMonth =
                          DateTime(_reportMonth.year, _reportMonth.month + 1);
                    });
                  },
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 24,
              runSpacing: 16,
              alignment: WrapAlignment.spaceAround,
              children: [
                _kpiTile('إجمالي الشهر', '${totalRev.toStringAsFixed(0)} ج.م',
                    const Color(0xFF10B981)),
                _kpiTile('عدد الفواتير', '${monthSales.length}',
                    const Color(0xFF7C3AED)),
                _kpiTile('إيراد الترابيزات',
                    '${tablesRev.toStringAsFixed(0)} ج.م', Colors.blueAccent),
                _kpiTile('ساعات اللعب', '${totalHours.toStringAsFixed(1)} س',
                    Colors.cyan),
                _kpiTile('إيراد المشروبات',
                    '${drinksRev.toStringAsFixed(0)} ج.م', Colors.amber),
                _kpiTile('أعلى يوم', bestDay, Colors.pinkAccent),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: const Color(0xFF1A2234),
          child: ListTile(
            leading: const Icon(Icons.lock_clock, color: Color(0xFF10B981)),
            title: Text(
                'تقفيل يومية اليوم (${_todayKey()}) - الإجمالي: ${_todaySales.toStringAsFixed(0)} ج.م'),
            subtitle: Text(closedDays.containsKey(_todayKey())
                ? 'تم تقفيل هذا اليوم وحفظه بالسحابة'
                : 'اضغط لحفظ تقفيل شيفت اليوم في السحابة'),
            trailing: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981)),
              onPressed: () async {
                final tKey = _todayKey();
                final data = {
                  'dayKey': tKey,
                  'total': _todaySales,
                  'closedAtMs': DateTime.now().millisecondsSinceEpoch,
                };
                setState(() {
                  closedDays[tKey] = data;
                });
                await FirestoreService.saveDoc('daily_closures', tKey, data);
                _logAudit('closure', 'تقفيل يومية',
                    '$tKey: ${_todaySales.toStringAsFixed(0)} ج.م');
                _showSnack('تم تقفيل اليومية وحفظها بنجاح');
              },
              child: const Text('تقفيل اليوم',
                  style: TextStyle(color: Colors.white)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('تفصيل أيام الشهر:',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...dayKeysList.reversed.map((dKey) {
          final val = dayTotals[dKey] as double;
          return Card(
            child: ListTile(
              title: Text('يوم $dKey'),
              trailing: Text('${val.toStringAsFixed(0)} ج.م',
                  style: const TextStyle(
                      color: Color(0xFF10B981),
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
          );
        }),
      ],
    );
  }

  Widget _kpiTile(String label, String val, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Text(val,
            style: TextStyle(
                color: color, fontSize: 19, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildHistoryAndAuditScreen() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('سجل الفواتير وحركات النظام (قابل للتعديل)',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('الفواتير'),
                  selected: _historyFilter == 'all',
                  onSelected: (_) {
                    setState(() {
                      _historyFilter = 'all';
                    });
                  },
                ),
                ChoiceChip(
                  label: const Text('سجل المراقبة (Audit)'),
                  selected: _historyFilter == 'audit',
                  onSelected: (_) {
                    setState(() {
                      _historyFilter = 'audit';
                    });
                  },
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_historyFilter == 'all')
          ...sales.map((raw) {
            final s = raw as Sale;
            return Card(
              child: ListTile(
                leading: Icon(
                  s.tableType == 'cafe'
                      ? Icons.local_cafe
                      : Icons.sports_esports,
                  color: const Color(0xFF7C3AED),
                ),
                title: Text(
                    '${s.source} • ${s.grandTotal.toStringAsFixed(0)} ج.م',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle:
                    Text('${s.details}\n${_formatDateTime(s.createdAtMs)}'),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'تعديل الفاتورة',
                      icon: const Icon(Icons.edit, color: Colors.amber),
                      onPressed: () {
                        _showEditSaleDialog(s);
                      },
                    ),
                    IconButton(
                      tooltip: 'حذف الفاتورة',
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () async {
                        setState(() {
                          sales.remove(s);
                        });
                        _saveLocalCache();
                        await FirestoreService.removeDoc('sales', s.id);
                      },
                    ),
                  ],
                ),
              ),
            );
          })
        else
          ...auditLogs.map((raw) {
            final a = raw as AuditLog;
            return Card(
              child: ListTile(
                leading:
                    const Icon(Icons.verified_user, color: Color(0xFF10B981)),
                title: Text(a.title,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(a.details),
                trailing: Text(_formatDateTime(a.createdAtMs),
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ),
            );
          }),
      ],
    );
  }

  void _showEditSaleDialog(Sale sale) {
    final sourceCtrl = TextEditingController(text: sale.source);
    final totalCtrl =
        TextEditingController(text: sale.grandTotal.toStringAsFixed(0));
    final detailsCtrl = TextEditingController(text: sale.details);

    showDialog(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: const Color(0xFF151C28),
            title: const Text('تعديل بيانات الفاتورة'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: sourceCtrl,
                  decoration:
                      const InputDecoration(labelText: 'المصدر / اسم الترابيزة'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: totalCtrl,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'المبلغ الإجمالي (ج.م)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: detailsCtrl,
                  decoration:
                      const InputDecoration(labelText: 'تفاصيل الفاتورة'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                },
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final newTotal =
                      double.tryParse(totalCtrl.text) ?? sale.grandTotal;
                  setState(() {
                    sale.source = sourceCtrl.text.trim();
                    sale.grandTotal = newTotal;
                    sale.details = detailsCtrl.text.trim();
                  });
                  _saveLocalCache();
                  Navigator.pop(ctx);
                  await FirestoreService.saveDoc(
                      'sales', sale.id, sale.toMap());
                  _logAudit('edit_sale', 'تعديل فاتورة',
                      '${sale.source}: ${newTotal.toStringAsFixed(0)} ج.م');
                },
                child: const Text('حفظ التعديلات'),
              ),
            ],
          ),
        );
      },
    );
  }
}
