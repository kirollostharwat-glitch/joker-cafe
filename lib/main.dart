import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const CafePosApp());
}

class CafePosApp extends StatelessWidget {
  const CafePosApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData.dark();
    return MaterialApp(
      title: 'كافيه الجوكر',
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0E14),
        primaryColor: const Color(0xFF7C3AED),
        textTheme: GoogleFonts.cairoTextTheme(baseTheme.textTheme),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7C3AED),
          secondary: Color(0xFF10B981),
          surface: Color(0xFF151A24),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF151A24),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF232A3B)),
          ),
        ),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: DashboardScreen(),
      ),
    );
  }
}

class FirestoreRestService {
  static const String projectId = 'joker-cafe-ddc53';
  static const String baseUrl =
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';

  static dynamic fromFs(Map<String, dynamic> val) {
    if (val.containsKey('stringValue')) return val['stringValue'];
    if (val.containsKey('integerValue')) {
      return int.tryParse(val['integerValue'].toString()) ?? 0;
    }
    if (val.containsKey('doubleValue')) {
      return (val['doubleValue'] as num).toDouble();
    }
    if (val.containsKey('booleanValue')) return val['booleanValue'];
    if (val.containsKey('nullValue')) return null;
    if (val.containsKey('arrayValue')) {
      final values = val['arrayValue']['values'] as List? ?? [];
      return values.map((e) => fromFs(Map<String, dynamic>.from(e))).toList();
    }
    if (val.containsKey('mapValue')) {
      final fields = val['mapValue']['fields'] as Map<String, dynamic>? ?? {};
      return fields.map((k, v) => MapEntry(k, fromFs(Map<String, dynamic>.from(v))));
    }
    return null;
  }

  static Map<String, dynamic> toFs(dynamic val) {
    if (val == null) return {'nullValue': null};
    if (val is String) return {'stringValue': val};
    if (val is int) return {'integerValue': val.toString()};
    if (val is double) return {'doubleValue': val};
    if (val is bool) return {'booleanValue': val};
    if (val is List) {
      return {
        'arrayValue': {'values': val.map((e) => toFs(e)).toList()}
      };
    }
    if (val is Map) {
      return {
        'mapValue': {
          'fields': val.map((k, v) => MapEntry(k.toString(), toFs(v)))
        }
      };
    }
    return {'stringValue': val.toString()};
  }

  static Future<List>> getCollection(String col) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/$col?pageSize=200'));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body);
      final docs = data['documents'] as List? ?? [];
      return docs.map((d) {
        final nameParts = (d['name'] as String).split('/');
        final id = nameParts.last;
        final fields = d['fields'] as Map<String, dynamic>? ?? {};
        final map = fields.map((k, v) => MapEntry(k, fromFs(Map<String, dynamic>.from(v))));
        map['_docId'] = id;
        return map;
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> setDoc(String col, String docId, Map<String, dynamic> data) async {
    final cleanData = Map<String, dynamic>.from(data)..remove('_docId');
    final body = jsonEncode({
      'fields': cleanData.map((k, v) => MapEntry(k, toFs(v))),
    });
    await http.patch(
      Uri.parse('$baseUrl/$col/$docId'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
  }

  static Future<void> deleteDoc(String col, String docId) async {
    await http.delete(Uri.parse('$baseUrl/$col/$docId'));
  }
}

class MenuItem {
  String id;
  String name;
  String category;
  double price;
  int stock;

  MenuItem({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.stock,
  });

  factory MenuItem.fromMap(Map<String, dynamic> m) => MenuItem(
        id: m['_docId'] ?? m['id'] ?? '',
        name: m['name'] ?? '',
        category: m['category'] ?? 'مشروبات',
        price: (m['price'] as num? ?? 0).toDouble(),
        stock: (m['stock'] as num? ?? 0).toInt(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'category': category,
        'price': price,
        'stock': stock,
      };
}

class SaleLine {
  String name;
  double price;
  int qty;

  SaleLine({required this.name, required this.price, required this.qty});

  factory SaleLine.fromMap(Map<String, dynamic> m) => SaleLine(
        name: m['name'] ?? '',
        price: (m['price'] as num? ?? 0).toDouble(),
        qty: (m['qty'] as num? ?? 1).toInt(),
      );

  Map<String, dynamic> toMap() => {'name': name, 'price': price, 'qty': qty};
}

class GameTable {
  String id;
  String name;
  String tableType;
  double hourlyRate;
  String status;
  int? startedAtMs;
  int? limitMinutes;
  List<SaleLine> drinks;

  GameTable({
    required this.id,
    required this.name,
    required this.tableType,
    required this.hourlyRate,
    this.status = 'idle',
    this.startedAtMs,
    this.limitMinutes,
    List<SaleLine>? drinks,
  }) : drinks = drinks ?? [];

  bool get isRunning => status == 'running';

  int get elapsedSeconds {
    if (!isRunning || startedAtMs == null) return 0;
    return ((DateTime.now().millisecondsSinceEpoch - startedAtMs!) / 1000).floor();
  }

  double get timeCost => (elapsedSeconds / 3600.0) * hourlyRate;

  double get drinksCost =>
      drinks.fold(0.0, (sum, item) => sum + (item.price * item.qty));

  double get grandTotal => timeCost + drinksCost;

  bool get isTimeUp =>
      isRunning && limitMinutes != null && elapsedSeconds >= (limitMinutes! * 60);

  factory GameTable.fromMap(
      Map<String, dynamic> m, String fallbackId, String fallbackName, double fallbackRate) {
    final rawDrinks = m['drinks'] as List? ?? [];
    return GameTable(
      id: m['_docId'] ?? fallbackId,
      name: m['name'] ?? fallbackName,
      tableType: m['tableType'] ?? fallbackId,
      hourlyRate: (m['hourlyRate'] as num? ?? fallbackRate).toDouble(),
      status: m['status'] ?? 'idle',
      startedAtMs: (m['startedAtMs'] as num?)?.toInt(),
      limitMinutes: (m['limitMinutes'] as num?)?.toInt(),
      drinks: rawDrinks.map((e) => SaleLine.fromMap(Map<String, dynamic>.from(e))).toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'tableType': tableType,
        'hourlyRate': hourlyRate,
        'status': status,
        'startedAtMs': startedAtMs,
        'limitMinutes': limitMinutes,
        'drinks': drinks.map((e) => e.toMap()).toList(),
      };
}

class SaleRecord {
  String id;
  String source;
  double total;
  double tableHours;
  double drinksRevenue;
  String details;
  int createdAtMs;

  SaleRecord({
    required this.id,
    required this.source,
    required this.total,
    required this.tableHours,
    required this.drinksRevenue,
    required this.details,
    required this.createdAtMs,
  });

  factory SaleRecord.fromMap(Map<String, dynamic> m) => SaleRecord(
        id: m['_docId'] ?? m['id'] ?? '',
        source: m['source'] ?? 'كافيه',
        total: (m['total'] as num? ?? 0).toDouble(),
        tableHours: (m['tableHours'] as num? ?? 0).toDouble(),
        drinksRevenue: (m['drinksRevenue'] as num? ?? 0).toDouble(),
        details: m['details'] ?? '',
        createdAtMs:
            (m['createdAtMs'] as num? ?? DateTime.now().millisecondsSinceEpoch).toInt(),
      );

  Map<String, dynamic> toMap() => {
        'source': source,
        'total': total,
        'tableHours': tableHours,
        'drinksRevenue': drinksRevenue,
        'details': details,
        'createdAtMs': createdAtMs,
      };
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _tabIndex = 0;
  bool _isOnline = true;
  bool _isSyncing = false;
  Timer? _clockTimer;
  Timer? _syncTimer;

  GameTable billiardTable = GameTable(
    id: 'billiard_table',
    name: 'ترابيزة البلياردو',
    tableType: 'billiard',
    hourlyRate: 60,
  );
  GameTable pingPongTable = GameTable(
    id: 'ping_pong_table',
    name: 'ترابيزة البنج بونج',
    tableType: 'ping_pong',
    hourlyRate: 40,
  );

  List<MenuItem> menuItems = [];
  List<SaleLine> posCart = [];
  List<SaleRecord> sales = [];

  @override
  void initState() {
    super.initState();
    _syncFromCloud();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _tabIndex == 0) setState(() {});
    });
    _syncTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_isSyncing) _syncFromCloud();
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _syncFromCloud() async {
    _isSyncing = true;
    try {
      final tablesDocs = await FirestoreRestService.getCollection('game_tables');
      final menuDocs = await FirestoreRestService.getCollection('menu_items');
      final salesDocs = await FirestoreRestService.getCollection('sales');

      if (!mounted) return;

      setState(() {
        _isOnline = true;

        for (final doc in tablesDocs) {
          if (doc['_docId'] == 'billiard_table') {
            billiardTable =
                GameTable.fromMap(doc, 'billiard_table', 'ترابيزة البلياردو', 60);
          } else if (doc['_docId'] == 'ping_pong_table') {
            pingPongTable =
                GameTable.fromMap(doc, 'ping_pong_table', 'ترابيزة البنج بونج', 40);
          }
        }

        if (menuDocs.isNotEmpty) {
          menuItems = menuDocs.map((e) => MenuItem.fromMap(e)).toList();
        } else if (menuItems.isEmpty) {
          _seedDefaultMenu();
        }

        sales = salesDocs.map((e) => SaleRecord.fromMap(e)).toList()
          ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
      });
    } catch (_) {
      if (mounted) setState(() => _isOnline = false);
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _seedDefaultMenu() async {
    final defaults = [
      MenuItem(id: 'tea', name: 'شاي', category: 'مشروبات ساخنة', price: 15, stock: 50),
      MenuItem(id: 'turkey_coffee', name: 'قهوة تركي', category: 'مشروبات ساخنة', price: 25, stock: 40),
      MenuItem(id: 'nescafe', name: 'نسكافيه', category: 'مشروبات ساخنة', price: 30, stock: 35),
      MenuItem(id: 'pepsi', name: 'بيبسي', category: 'مشروبات باردة', price: 25, stock: 48),
      MenuItem(id: 'water', name: 'مياه معدنية', category: 'مشروبات باردة', price: 10, stock: 60),
      MenuItem(id: 'molten_cake', name: 'مولتن كيك', category: 'كيكات', price: 55, stock: 15),
      MenuItem(id: 'cheese_cake', name: 'تشيز كيك', category: 'كيكات', price: 50, stock: 12),
    ];
    for (final item in defaults) {
      await FirestoreRestService.setDoc('menu_items', item.id, item.toMap());
    }
    await FirestoreRestService.setDoc('game_tables', billiardTable.id, billiardTable.toMap());
    await FirestoreRestService.setDoc('game_tables', pingPongTable.id, pingPongTable.toMap());
    _syncFromCloud();
  }

  String _formatTime(int sec) {
    final h = (sec ~/ 3600).toString().padLeft(2, '0');
    final m = ((sec % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  double get _todaySalesTotal {
    final now = DateTime.now();
    return sales.where((s) {
      final dt = DateTime.fromMillisecondsSinceEpoch(s.createdAtMs);
      return dt.year == now.year && dt.month == now.month && dt.day == now.day;
    }).fold(0.0, (sum, s) => sum + s.total);
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      _buildTablesScreen(),
      _buildPosPanel(),
      _buildHistoryScreen(),
      _buildReportsScreen(),
      _buildAdminShell(),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF111520),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.style, color: Color(0xFF7C3AED)),
            ),
            const SizedBox(width: 10),
            const Text('كافيه الجوكر', style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
              ),
              child: Text(
                'اليوم: ${_todaySalesTotal.toStringAsFixed(0)} ج.م',
                style: const TextStyle(
                    color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              _isOnline ? Icons.cloud_done : Icons.cloud_off,
              color: _isOnline ? const Color(0xFF10B981) : Colors.redAccent,
              size: 20,
            ),
          ],
        ),
      ),
      body: screens[_tabIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (i) => setState(() => _tabIndex = i),
        backgroundColor: const Color(0xFF111520),
        selectedItemColor: const Color(0xFF7C3AED),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.sports_esports), label: 'الترابيزات'),
          BottomNavigationBarItem(icon: Icon(Icons.local_cafe), label: 'الكافيه'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'السجل'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'التقارير'),
          BottomNavigationBarItem(icon: Icon(Icons.admin_panel_settings), label: 'الأدمن'),
        ],
      ),
    );
  }

  Widget _buildTablesScreen() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildTableCard(billiardTable, Icons.circle_outlined, const Color(0xFF10B981)),
        const SizedBox(height: 16),
        _buildTableCard(pingPongTable, Icons.sports_tennis, const Color(0xFF7C3AED)),
      ],
    );
  }

  Widget _buildTableCard(GameTable table, IconData icon, Color accent) {
    return Card(
      color: table.isTimeUp ? const Color(0xFF3A121A) : const Color(0xFF151A24),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, color: accent, size: 28),
                const SizedBox(width: 10),
                Text(table.name,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                const Spacer(),
                Chip(label: Text('${table.hourlyRate.toStringAsFixed(0)} ج.م / ساعة')),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              _formatTime(table.elapsedSeconds),
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.bold,
                color: table.isTimeUp ? Colors.redAccent : Colors.white,
              ),
            ),
            if (table.isTimeUp)
              const Text('انتهى الوقت المحدد!',
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text('وقت: ${table.timeCost.ceil()} ج.م'),
                Text('مشروبات: ${table.drinksCost.toStringAsFixed(0)} ج.م'),
                Text('الإجمالي: ${table.grandTotal.ceil()} ج.م',
                    style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            if (table.drinks.isNotEmpty) ...[
              const Divider(height: 20),
              Wrap(
                spacing: 8,
                children:
                    table.drinks.map((d) => Chip(label: Text('${d.name} × ${d.qty}'))).toList(),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                if (!table.isRunning)
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          padding: const EdgeInsets.symmetric(vertical: 12)),
                      onPressed: () => _showStartTableDialog(table),
                      icon: const Icon(Icons.play_arrow, color: Colors.white),
                      label: const Text('تشغيل الترابيزة',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  )
                else ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF263044),
                          padding: const EdgeInsets.symmetric(vertical: 12)),
                      onPressed: () => _showAddDrinksSheet(table),
                      icon: const Icon(Icons.local_drink, color: Colors.white),
                      label: const Text('إضافة مشروب', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(vertical: 12)),
                      onPressed: () => _showTableBillDialog(table),
                      icon: const Icon(Icons.receipt, color: Colors.white),
                      label: const Text('تقفيل وحساب',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ]
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showStartTableDialog(GameTable table) {
    int? mins;
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setDlg) => AlertDialog(
            backgroundColor: const Color(0xFF151A24),
            title: Text('بدء جلسة - ${table.name}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<int?>(
                    title: const Text('وقت مفتوح'),
                    value: null,
                    groupValue: mins,
                    onChanged: (v) => setDlg(() => mins = v)),
                RadioListTile<int?>(
                    title: const Text('30 دقيقة'),
                    value: 30,
                    groupValue: mins,
                    onChanged: (v) => setDlg(() => mins = v)),
                RadioListTile<int?>(
                    title: const Text('60 دقيقة (ساعة)'),
                    value: 60,
                    groupValue: mins,
                    onChanged: (v) => setDlg(() => mins = v)),
                RadioListTile<int?>(
                    title: const Text('120 دقيقة (ساعتين)'),
                    value: 120,
                    groupValue: mins,
                    onChanged: (v) => setDlg(() => mins = v)),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                onPressed: () async {
                  setState(() {
                    table.status = 'running';
                    table.startedAtMs = DateTime.now().millisecondsSinceEpoch;
                    table.limitMinutes = mins;
                  });
                  Navigator.pop(ctx);
                  await FirestoreRestService.setDoc('game_tables', table.id, table.toMap());
                },
                child: const Text('ابدأ الآن', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddDrinksSheet(GameTable table) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151A24),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: menuItems.length,
          itemBuilder: (ctx, i) {
            final item = menuItems[i];
            return ListTile(
              title: Text(item.name),
              subtitle: Text('${item.price} ج.م | المتبقي: ${item.stock}'),
              trailing: ElevatedButton(
                onPressed: item.stock <= 0
                    ? null
                    : () async {
                        setState(() {
                          item.stock--;
                          final found = table.drinks.where((d) => d.name == item.name).toList();
                          if (found.isNotEmpty) {
                            found.first.qty++;
                          } else {
                            table.drinks
                                .add(SaleLine(name: item.name, price: item.price, qty: 1));
                          }
                        });
                        Navigator.pop(ctx);
                        await FirestoreRestService.setDoc('menu_items', item.id, item.toMap());
                        await FirestoreRestService.setDoc(
                            'game_tables', table.id, table.toMap());
                      },
                child: const Text('+ إضافة'),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showTableBillDialog(GameTable table) {
    final total = table.grandTotal.ceilToDouble();
    final tCost = table.timeCost.ceilToDouble();
    final dCost = table.drinksCost;
    final dur = _formatTime(table.elapsedSeconds);
    final hrs = table.elapsedSeconds / 3600.0;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF151A24),
          title: Text('فاتورة ${table.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('المدة: $dur'),
              Text('حساب اللعب: $tCost ج.م'),
              Text('حساب المشروبات: $dCost ج.م'),
              const Divider(),
              Text('الإجمالي: $total ج.م',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C3AED)),
              onPressed: () async {
                final id = DateTime.now().millisecondsSinceEpoch.toString();
                final rec = SaleRecord(
                  id: id,
                  source: table.name,
                  total: total,
                  tableHours: hrs,
                  drinksRevenue: dCost,
                  details: 'لعب ($dur): $tCost ج.م + مشروبات: $dCost ج.م',
                  createdAtMs: DateTime.now().millisecondsSinceEpoch,
                );
                setState(() {
                  sales.insert(0, rec);
                  table.status = 'idle';
                  table.startedAtMs = null;
                  table.limitMinutes = null;
                  table.drinks.clear();
                });
                Navigator.pop(ctx);
                await FirestoreRestService.setDoc('sales', id, rec.toMap());
                await FirestoreRestService.setDoc('game_tables', table.id, table.toMap());
              },
              child: const Text('تحصيل وتصفير', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPosPanel() {
    final cartTotal = posCart.fold(0.0, (sum, e) => sum + (e.price * e.qty));
    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(14),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 190,
              childAspectRatio: 1.15,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: menuItems.length,
            itemBuilder: (ctx, i) {
              final item = menuItems[i];
              return InkWell(
                onTap: item.stock <= 0
                    ? null
                    : () {
                        setState(() {
                          item.stock--;
                          final found = posCart.where((c) => c.name == item.name).toList();
                          if (found.isNotEmpty) {
                            found.first.qty++;
                          } else {
                            posCart.add(SaleLine(name: item.name, price: item.price, qty: 1));
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
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 6),
                        Text('${item.price.toStringAsFixed(0)} ج.م',
                            style: const TextStyle(
                                color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                        Text('المخزون: ${item.stock}',
                            style: TextStyle(
                                fontSize: 12,
                                color: item.stock < 5 ? Colors.redAccent : Colors.grey)),
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
            color: const Color(0xFF151A24),
            child: Column(
              children: [
                Wrap(
                  spacing: 8,
                  children: posCart
                      .map((c) => Chip(
                            label: Text('${c.name} × ${c.qty}'),
                            onDeleted: () {
                              setState(() {
                                final m = menuItems.firstWhere((it) => it.name == c.name);
                                m.stock += c.qty;
                                posCart.remove(c);
                              });
                            },
                          ))
                      .toList(),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('الإجمالي: ${cartTotal.toStringAsFixed(0)} ج.م',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                      onPressed: () async {
                        final id = DateTime.now().millisecondsSinceEpoch.toString();
                        final rec = SaleRecord(
                          id: id,
                          source: 'طلب كافيه',
                          total: cartTotal,
                          tableHours: 0,
                          drinksRevenue: cartTotal,
                          details: posCart.map((e) => '${e.name} (${e.qty})').join('، '),
                          createdAtMs: DateTime.now().millisecondsSinceEpoch,
                        );
                        setState(() {
                          sales.insert(0, rec);
                          posCart.clear();
                        });
                        await FirestoreRestService.setDoc('sales', id, rec.toMap());
                        for (final item in menuItems) {
                          await FirestoreRestService.setDoc(
                              'menu_items', item.id, item.toMap());
                        }
                      },
                      child: const Text('تأكيد البيع',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                )
              ],
            ),
          )
      ],
    );
  }

  Widget _buildHistoryScreen() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sales.length,
      itemBuilder: (ctx, i) {
        final s = sales[i];
        final dt = DateTime.fromMillisecondsSinceEpoch(s.createdAtMs);
        final timeStr =
            '${dt.day}/${dt.month} - ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        return Card(
          child: ListTile(
            leading: Icon(s.tableHours > 0 ? Icons.sports_esports : Icons.local_cafe,
                color: const Color(0xFF7C3AED)),
            title: Text('${s.source} • ${s.total.toStringAsFixed(0)} ج.م',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(s.details),
            trailing: Text(timeStr, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ),
        );
      },
    );
  }

  Widget _buildReportsScreen() {
    final totalAll = sales.fold(0.0, (sum, s) => sum + s.total);
    final drinksAll = sales.fold(0.0, (sum, s) => sum + s.drinksRevenue);
    final gamesAll = totalAll - drinksAll;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text('ملخص الإيرادات المسجلة',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _kpiBox('الإجمالي الكلي', '${totalAll.toStringAsFixed(0)} ج.م',
                        const Color(0xFF10B981)),
                    _kpiBox(
                        'إيراد الألعاب', '${gamesAll.toStringAsFixed(0)} ج.م', const Color(0xFF7C3AED)),
                    _kpiBox('إيراد الكافيه', '${drinksAll.toStringAsFixed(0)} ج.م', Colors.amber),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _kpiBox(String label, String val, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 6),
        Text(val, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildAdminShell() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('إدارة الأسعار والمنيو والمخزن',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C3AED)),
              onPressed: () => _showItemFormDialog(),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('صنف جديد', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            title: const Text('سعر ساعة البلياردو'),
            trailing: Text('${billiardTable.hourlyRate.toStringAsFixed(0)} ج.م',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            onTap: () => _showHourlyRateDialog(billiardTable),
          ),
        ),
        Card(
          child: ListTile(
            title: const Text('سعر ساعة البنج بونج'),
            trailing: Text('${pingPongTable.hourlyRate.toStringAsFixed(0)} ج.م',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            onTap: () => _showHourlyRateDialog(pingPongTable),
          ),
        ),
        const Divider(height: 24),
        ...menuItems.map((item) => Card(
              child: ListTile(
                title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('السعر: ${item.price} ج.م | المخزون: ${item.stock}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: Color(0xFF10B981)),
                      onPressed: () async {
                        setState(() => item.stock += 5);
                        await FirestoreRestService.setDoc('menu_items', item.id, item.toMap());
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.amber),
                      onPressed: () => _showItemFormDialog(existing: item),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () async {
                        setState(() => menuItems.remove(item));
                        await FirestoreRestService.deleteDoc('menu_items', item.id);
                      },
                    ),
                  ],
                ),
              ),
            )),
      ],
    );
  }

  void _showHourlyRateDialog(GameTable table) {
    final ctrl = TextEditingController(text: table.hourlyRate.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF151A24),
          title: Text('تعديل سعر ${table.name}'),
          content: TextField(controller: ctrl, keyboardType: TextInputType.number),
          actions: [
            ElevatedButton(
              onPressed: () async {
                final v = double.tryParse(ctrl.text);
                if (v != null && v > 0) {
                  setState(() => table.hourlyRate = v);
                  Navigator.pop(ctx);
                  await FirestoreRestService.setDoc('game_tables', table.id, table.toMap());
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  void _showItemFormDialog({MenuItem? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final priceCtrl = TextEditingController(text: existing?.price.toStringAsFixed(0) ?? '');
    final stockCtrl = TextEditingController(text: existing?.stock.toString() ?? '20');

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF151A24),
          title: Text(existing == null ? 'إضافة صنف' : 'تعديل صنف'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'اسم الصنف')),
              TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'السعر')),
              TextField(
                  controller: stockCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'الكمية بالمخزن')),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                final price = double.tryParse(priceCtrl.text) ?? 0;
                final stock = int.tryParse(stockCtrl.text) ?? 0;
                if (nameCtrl.text.isNotEmpty && price > 0) {
                  final id = existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
                  final item = MenuItem(
                    id: id,
                    name: nameCtrl.text,
                    category: existing?.category ?? 'مشروبات',
                    price: price,
                    stock: stock,
                  );
                  setState(() {
                    if (existing == null) {
                      menuItems.add(item);
                    } else {
                      existing.name = item.name;
                      existing.price = item.price;
                      existing.stock = item.stock;
                    }
                  });
                  Navigator.pop(ctx);
                  await FirestoreRestService.setDoc('menu_items', id, item.toMap());
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}
