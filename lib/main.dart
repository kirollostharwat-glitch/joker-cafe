import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const JokerCafeApp());
}

class JokerCafeApp extends StatelessWidget {
  const JokerCafeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'كافيه الجوكر',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0E0E14),
        primaryColor: const Color(0xFF8B5CF6),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF8B5CF6),
          secondary: Color(0xFF10B981),
          surface: Color(0xFF181822),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF181822),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF2A2A3C)),
          ),
        ),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: MainDashboard(),
      ),
    );
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'price': price,
        'stock': stock,
      };

  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
        id: json['id'],
        name: json['name'],
        category: json['category'],
        price: (json['price'] as num).toDouble(),
        stock: json['stock'],
      );
}

class OrderLine {
  String name;
  double price;
  int qty;

  OrderLine({required this.name, required this.price, required this.qty});

  Map<String, dynamic> toJson() => {'name': name, 'price': price, 'qty': qty};
  factory OrderLine.fromJson(Map<String, dynamic> json) => OrderLine(
        name: json['name'],
        price: (json['price'] as num).toDouble(),
        qty: json['qty'],
      );
}

class GameTable {
  String id;
  String name;
  double hourlyRate;
  bool isRunning;
  int? startTimeMs;
  int? limitMinutes;
  List<OrderLine> orders;

  GameTable({
    required this.id,
    required this.name,
    required this.hourlyRate,
    this.isRunning = false,
    this.startTimeMs,
    this.limitMinutes,
    List<OrderLine>? orders,
  }) : orders = orders ?? [];

  int get elapsedSeconds {
    if (!isRunning || startTimeMs == null) return 0;
    return ((DateTime.now().millisecondsSinceEpoch - startTimeMs!) / 1000)
        .floor();
  }

  double get timeCost => (elapsedSeconds / 3600.0) * hourlyRate;

  double get ordersCost =>
      orders.fold(0.0, (sum, item) => sum + (item.price * item.qty));

  double get totalCost => timeCost + ordersCost;

  bool get isTimeUp =>
      isRunning &&
      limitMinutes != null &&
      elapsedSeconds >= (limitMinutes! * 60);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'hourlyRate': hourlyRate,
        'isRunning': isRunning,
        'startTimeMs': startTimeMs,
        'limitMinutes': limitMinutes,
        'orders': orders.map((e) => e.toJson()).toList(),
      };

  factory GameTable.fromJson(Map<String, dynamic> json) => GameTable(
        id: json['id'],
        name: json['name'],
        hourlyRate: (json['hourlyRate'] as num).toDouble(),
        isRunning: json['isRunning'] ?? false,
        startTimeMs: json['startTimeMs'],
        limitMinutes: json['limitMinutes'],
        orders: (json['orders'] as List? ?? [])
            .map((e) => OrderLine.fromJson(e))
            .toList(),
      );
}

class Invoice {
  String id;
  String source;
  double amount;
  String details;
  String time;

  Invoice({
    required this.id,
    required this.source,
    required this.amount,
    required this.details,
    required this.time,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source,
        'amount': amount,
        'details': details,
        'time': time,
      };

  factory Invoice.fromJson(Map<String, dynamic> json) => Invoice(
        id: json['id'],
        source: json['source'],
        amount: (json['amount'] as num).toDouble(),
        details: json['details'],
        time: json['time'],
      );
}

class MainDashboard extends StatefulWidget {
  const MainDashboard({super.key});

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  int _selectedIndex = 0;
  Timer? _ticker;
  String _adminPin = '1234';
  bool _adminUnlocked = false;

  late GameTable billiardsTable;
  late GameTable pingPongTable;
  List<MenuItem> menu = [];
  List<OrderLine> directCart = [];
  List<Invoice> invoices = [];

  @override
  void initState() {
    super.initState();
    billiardsTable =
        GameTable(id: 'billiards', name: 'ترابيزة البلياردو', hourlyRate: 60);
    pingPongTable =
        GameTable(id: 'pingpong', name: 'ترابيزة البنج بونج', hourlyRate: 40);
    _loadData();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _adminPin = prefs.getString('adminPin') ?? '1234';

      final bJson = prefs.getString('billiards');
      if (bJson != null) billiardsTable = GameTable.fromJson(jsonDecode(bJson));

      final pJson = prefs.getString('pingpong');
      if (pJson != null) pingPongTable = GameTable.fromJson(jsonDecode(pJson));

      final mJson = prefs.getString('menu');
      if (mJson != null) {
        menu = (jsonDecode(mJson) as List)
            .map((e) => MenuItem.fromJson(e))
            .toList();
      } else {
        menu = [
          MenuItem(id: '1', name: 'شاي', category: 'مشروبات ساخنة', price: 15, stock: 50),
          MenuItem(id: '2', name: 'قهوة تركي', category: 'مشروبات ساخنة', price: 25, stock: 40),
          MenuItem(id: '3', name: 'نسكافيه', category: 'مشروبات ساخنة', price: 30, stock: 35),
          MenuItem(id: '4', name: 'بيبسي / كانز', category: 'مشروبات باردة', price: 25, stock: 48),
          MenuItem(id: '5', name: 'مياه معدنية', category: 'مشروبات باردة', price: 10, stock: 60),
          MenuItem(id: '6', name: 'عصير مانجو', category: 'مشروبات باردة', price: 35, stock: 25),
          MenuItem(id: '7', name: 'مولتن كيك', category: 'كيكات وحلويات', price: 55, stock: 15),
          MenuItem(id: '8', name: 'تشيز كيك', category: 'كيكات وحلويات', price: 50, stock: 12),
          MenuItem(id: '9', name: 'براونيز', category: 'كيكات وحلويات', price: 45, stock: 18),
        ];
      }

      final iJson = prefs.getString('invoices');
      if (iJson != null) {
        invoices = (jsonDecode(iJson) as List)
            .map((e) => Invoice.fromJson(e))
            .toList();
      }
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('adminPin', _adminPin);
    await prefs.setString('billiards', jsonEncode(billiardsTable.toJson()));
    await prefs.setString('pingpong', jsonEncode(pingPongTable.toJson()));
    await prefs.setString(
        'menu', jsonEncode(menu.map((e) => e.toJson()).toList()));
    await prefs.setString(
        'invoices', jsonEncode(invoices.map((e) => e.toJson()).toList()));
  }

  String _formatDuration(int totalSeconds) {
    final h = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _nowTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  void _startTable(GameTable table) {
    int? selectedMinutes;
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setDlgState) => AlertDialog(
            backgroundColor: const Color(0xFF181822),
            title: Text('تشغيل ${table.name}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<int?>(
                  title: const Text('وقت مفتوح'),
                  value: null,
                  groupValue: selectedMinutes,
                  onChanged: (v) => setDlgState(() => selectedMinutes = v),
                ),
                RadioListTile<int?>(
                  title: const Text('نصف ساعة (30 دقيقة)'),
                  value: 30,
                  groupValue: selectedMinutes,
                  onChanged: (v) => setDlgState(() => selectedMinutes = v),
                ),
                RadioListTile<int?>(
                  title: const Text('ساعة كاملة (60 دقيقة)'),
                  value: 60,
                  groupValue: selectedMinutes,
                  onChanged: (v) => setDlgState(() => selectedMinutes = v),
                ),
                RadioListTile<int?>(
                  title: const Text('ساعتين (120 دقيقة)'),
                  value: 120,
                  groupValue: selectedMinutes,
                  onChanged: (v) => setDlgState(() => selectedMinutes = v),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981)),
                onPressed: () {
                  setState(() {
                    table.isRunning = true;
                    table.startTimeMs = DateTime.now().millisecondsSinceEpoch;
                    table.limitMinutes = selectedMinutes;
                  });
                  _saveData();
                  Navigator.pop(ctx);
                },
                child: const Text('ابدأ الوقت',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addDrinkToTable(GameTable table) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF181822),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: menu.length,
          itemBuilder: (ctx, i) {
            final item = menu[i];
            return ListTile(
              title: Text(item.name),
              subtitle: Text('${item.price} ج.م | المتاح: ${item.stock}'),
              trailing: ElevatedButton(
                onPressed: item.stock <= 0
                    ? null
                    : () {
                        setState(() {
                          item.stock--;
                          final existing = table.orders
                              .where((o) => o.name == item.name)
                              .toList();
                          if (existing.isNotEmpty) {
                            existing.first.qty++;
                          } else {
                            table.orders.add(OrderLine(
                                name: item.name, price: item.price, qty: 1));
                          }
                        });
                        _saveData();
                        Navigator.pop(ctx);
                      },
                child: const Text('+ إضافة'),
              ),
            );
          },
        ),
      ),
    );
  }

  void _checkoutTable(GameTable table) {
    final total = table.totalCost.ceilToDouble();
    final timeCost = table.timeCost.ceilToDouble();
    final ordersCost = table.ordersCost;
    final durationStr = _formatDuration(table.elapsedSeconds);

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF181822),
          title: Text('حساب ${table.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('المدة: $durationStr'),
              Text('حساب اللعب: $timeCost ج.م'),
              Text('حساب الطلبات: $ordersCost ج.م'),
              const Divider(),
              Text('الإجمالي المطلوب: $total ج.م',
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF10B981))),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('رجوع')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6)),
              onPressed: () {
                setState(() {
                  invoices.insert(
                    0,
                    Invoice(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      source: table.name,
                      amount: total,
                      details:
                          'لعب ($durationStr): $timeCost ج.م + طلبات: $ordersCost ج.م',
                      time: _nowTime(),
                    ),
                  );
                  table.isRunning = false;
                  table.startTimeMs = null;
                  table.limitMinutes = null;
                  table.orders.clear();
                });
                _saveData();
                Navigator.pop(ctx);
              },
              child: const Text('تأكيد التحصيل وتصفير الترابيزة',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildHallPage(),
      _buildCafePosPage(),
      _buildInventoryPage(),
      _buildAdminPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF14141D),
        title: const Row(
          children: [
            Icon(Icons.style, color: Color(0xFF8B5CF6)),
            SizedBox(width: 8),
            Text('كافيه الجوكر | JOKER CAFE',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        backgroundColor: const Color(0xFF14141D),
        selectedItemColor: const Color(0xFF8B5CF6),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.sports_esports), label: 'صالة الألعاب'),
          BottomNavigationBarItem(
              icon: Icon(Icons.local_cafe), label: 'الكافيه (POS)'),
          BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long), label: 'الجرد والتقارير'),
          BottomNavigationBarItem(
              icon: Icon(Icons.admin_panel_settings), label: 'الأدمن والمخزن'),
        ],
      ),
    );
  }

  Widget _buildHallPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildTableCard(billiardsTable, Icons.circle_outlined, const Color(0xFF10B981)),
        const SizedBox(height: 16),
        _buildTableCard(pingPongTable, Icons.sports_tennis, const Color(0xFF8B5CF6)),
      ],
    );
  }

  Widget _buildTableCard(GameTable table, IconData icon, Color accent) {
    final isAlert = table.isTimeUp;
    return Card(
      color: isAlert ? const Color(0xFF3B1219) : const Color(0xFF181822),
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
                    Icon(icon, color: accent, size: 28),
                    const SizedBox(width: 10),
                    Text(table.name,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
                Chip(
                  label: Text('${table.hourlyRate} ج.م / ساعة'),
                  backgroundColor: accent.withOpacity(0.2),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                _formatDuration(table.elapsedSeconds),
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: isAlert ? Colors.redAccent : Colors.white,
                ),
              ),
            ),
            if (isAlert)
              const Center(
                child: Text('تنبيه: انتهى الوقت المحدد!',
                    style: TextStyle(
                        color: Colors.redAccent, fontWeight: FontWeight.bold)),
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text('حساب الوقت: ${table.timeCost.ceil()} ج.م'),
                Text('الطلبات: ${table.ordersCost} ج.م'),
                Text('الإجمالي: ${table.totalCost.ceil()} ج.م',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: accent, fontSize: 16)),
              ],
            ),
            if (table.orders.isNotEmpty) ...[
              const Divider(height: 24),
              Wrap(
                spacing: 8,
                children: table.orders
                    .map((o) => Chip(label: Text('${o.name} × ${o.qty}')))
                    .toList(),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                if (!table.isRunning)
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: accent),
                      onPressed: () => _startTable(table),
                      icon: const Icon(Icons.play_arrow, color: Colors.white),
                      label: const Text('تشغيل الترابيزة',
                          style: TextStyle(color: Colors.white)),
                    ),
                  )
                else ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey),
                      onPressed: () => _addDrinkToTable(table),
                      icon: const Icon(Icons.add_shopping_cart,
                          color: Colors.white),
                      label: const Text('إضافة مشروب',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent),
                      onPressed: () => _checkoutTable(table),
                      icon: const Icon(Icons.check_circle, color: Colors.white),
                      label: const Text('إنهاء وحساب',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ]
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildCafePosPage() {
    final cartTotal =
        directCart.fold(0.0, (sum, item) => sum + (item.price * item.qty));
    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              childAspectRatio: 1.2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: menu.length,
            itemBuilder: (ctx, i) {
              final item = menu[i];
              return InkWell(
                onTap: item.stock <= 0
                    ? null
                    : () {
                        setState(() {
                          item.stock--;
                          final existing = directCart
                              .where((c) => c.name == item.name)
                              .toList();
                          if (existing.isNotEmpty) {
                            existing.first.qty++;
                          } else {
                            directCart.add(OrderLine(
                                name: item.name, price: item.price, qty: 1));
                          }
                        });
                        _saveData();
                      },
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(item.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 6),
                        Text('${item.price} ج.م',
                            style: const TextStyle(color: Color(0xFF10B981))),
                        const SizedBox(height: 4),
                        Text('المخزون: ${item.stock}',
                            style: TextStyle(
                                fontSize: 12,
                                color: item.stock < 5
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
        if (directCart.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF181822),
            child: Column(
              children: [
                Wrap(
                  spacing: 8,
                  children: directCart
                      .map((c) => Chip(
                            label: Text('${c.name} × ${c.qty}'),
                            onDeleted: () {
                              setState(() {
                                final mItem =
                                    menu.firstWhere((m) => m.name == c.name);
                                mItem.stock += c.qty;
                                directCart.remove(c);
                              });
                              _saveData();
                            },
                          ))
                      .toList(),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('الإجمالي: $cartTotal ج.م',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981)),
                      onPressed: () {
                        setState(() {
                          invoices.insert(
                            0,
                            Invoice(
                              id: DateTime.now()
                                  .millisecondsSinceEpoch
                                  .toString(),
                              source: 'طلب كافيه مباشر',
                              amount: cartTotal,
                              details: directCart
                                  .map((e) => '${e.name} (${e.qty})')
                                  .join('، '),
                              time: _nowTime(),
                            ),
                          );
                          directCart.clear();
                        });
                        _saveData();
                      },
                      child: const Text('تحصيل الفاتورة',
                          style: TextStyle(color: Colors.white)),
                    )
                  ],
                )
              ],
            ),
          )
      ],
    );
  }

  Widget _buildInventoryPage() {
    final totalRevenue =
        invoices.fold(0.0, (sum, inv) => sum + inv.amount);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('إجمالي إيراد الوردية',
                        style: TextStyle(color: Colors.grey)),
                    Text('$totalRevenue ج.م',
                        style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF10B981))),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent),
                  onPressed: () {
                    setState(() => invoices.clear());
                    _saveData();
                  },
                  icon: const Icon(Icons.delete_sweep, color: Colors.white),
                  label: const Text('تقفيل وتصفير الوردية',
                      style: TextStyle(color: Colors.white)),
                )
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('سجل الفواتير:',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...invoices.map((inv) => Card(
              child: ListTile(
                title: Text('${inv.source} - ${inv.amount} ج.م'),
                subtitle: Text(inv.details),
                trailing: Text(inv.time),
              ),
            )),
      ],
    );
  }

  Widget _buildAdminPage() {
    if (!_adminUnlocked) {
      final pinCtrl = TextEditingController();
      return Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('لوحة الأدمن (الرمز الافتراضي: 1234)',
                    style: TextStyle(fontSize: 18)),
                const SizedBox(height: 12),
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      border: OutlineInputBorder(), labelText: 'أدخل رمز المرور'),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () {
                    if (pinCtrl.text == _adminPin) {
                      setState(() => _adminUnlocked = true);
                    }
                  },
                  child: const Text('دخول'),
                )
              ],
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('إعدادات الأسعار والمنيو',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              onPressed: _showAddOrEditItemDialog,
              icon: const Icon(Icons.add),
              label: const Text('إضافة صنف جديد'),
            )
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            title: const Text('سعر ساعة البلياردو'),
            trailing: Text('${billiardsTable.hourlyRate} ج.م'),
            onTap: () => _editRateDialog(billiardsTable),
          ),
        ),
        Card(
          child: ListTile(
            title: const Text('سعر ساعة البنج بونج'),
            trailing: Text('${pingPongTable.hourlyRate} ج.م'),
            onTap: () => _editRateDialog(pingPongTable),
          ),
        ),
        const Divider(height: 24),
        ...menu.map((item) => Card(
              child: ListTile(
                title: Text(item.name),
                subtitle: Text('السعر: ${item.price} ج.م | المخزون: ${item.stock}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add_box, color: Colors.green),
                      onPressed: () {
                        setState(() => item.stock += 5);
                        _saveData();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.amber),
                      onPressed: () => _showAddOrEditItemDialog(existing: item),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () {
                        setState(() => menu.remove(item));
                        _saveData();
                      },
                    ),
                  ],
                ),
              ),
            )),
      ],
    );
  }

  void _editRateDialog(GameTable table) {
    final ctrl = TextEditingController(text: table.hourlyRate.toString());
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('تعديل سعر ${table.name}'),
          content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'السعر الجديد للساعة'),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                final val = double.tryParse(ctrl.text);
                if (val != null && val > 0) {
                  setState(() => table.hourlyRate = val);
                  _saveData();
                }
                Navigator.pop(ctx);
              },
              child: const Text('حفظ'),
            )
          ],
        ),
      ),
    );
  }

  void _showAddOrEditItemDialog({MenuItem? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final priceCtrl =
        TextEditingController(text: existing?.price.toString() ?? '');
    final stockCtrl =
        TextEditingController(text: existing?.stock.toString() ?? '20');

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(existing == null ? 'إضافة صنف جديد' : 'تعديل الصنف'),
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
                  decoration: const InputDecoration(labelText: 'الكمية بالمخزن')),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                final price = double.tryParse(priceCtrl.text) ?? 0;
                final stock = int.tryParse(stockCtrl.text) ?? 0;
                if (nameCtrl.text.isNotEmpty && price > 0) {
                  setState(() {
                    if (existing == null) {
                      menu.add(MenuItem(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        name: nameCtrl.text,
                        category: 'عام',
                        price: price,
                        stock: stock,
                      ));
                    } else {
                      existing.name = nameCtrl.text;
                      existing.price = price;
                      existing.stock = stock;
                    }
                  });
                  _saveData();
                }
                Navigator.pop(ctx);
              },
              child: const Text('حفظ'),
            )
          ],
        ),
      ),
    );
  }
}
