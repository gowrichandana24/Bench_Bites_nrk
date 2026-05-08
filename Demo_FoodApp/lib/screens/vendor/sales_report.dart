import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/api_service.dart';
import '../../services/session.dart';
import 'vendor_data.dart';
import 'vendor_page_wrapper.dart';

class SalesReportPage extends StatefulWidget {
  const SalesReportPage({super.key});

  @override
  State<SalesReportPage> createState() => _SalesReportPageState();
}

class _SalesReportPageState extends State<SalesReportPage> {
  final Color primaryBlue = const Color(0xFF0F4CFF);
  bool isLoading = true;
  int totalOrders = 0;
  int revenue = 0;
  int averageOrderValue = 0;
  List<Map<String, dynamic>> recentOrders = [];
  List<Map<String, dynamic>> topItems = [];
  List<int> weeklyOrders = [];
  List<double> weeklyRevenue = [];
  Map<String, double> categoryShares = {};

  @override
  void initState() {
    super.initState();
    loadSalesReport();
  }

  Future<void> loadSalesReport() async {
    try {
      final data = await ApiService.getVendorDashboard(AppSession.vendorId);
      if (!mounted) return;

      final orders = ((data['recentOrders'] as List<dynamic>?) ?? []).map((order) => Map<String, dynamic>.from(order as Map)).toList();
      final itemCounts = <String, Map<String, dynamic>>{};
      final revenuePerDay = <String, double>{};
      final ordersPerDay = <String, int>{};
      final categoryRevenue = <String, double>{};

      for (final order in orders) {
        final createdAt = order['createdAt'];
        DateTime date;
        try {
          date = DateTime.parse(createdAt?.toString() ?? '');
        } catch (_) {
          date = DateTime.now();
        }
        final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        revenuePerDay[key] = (revenuePerDay[key] ?? 0) + (order['total'] is num ? (order['total'] as num).toDouble() : double.tryParse(order['total']?.toString() ?? '0') ?? 0);
        ordersPerDay[key] = (ordersPerDay[key] ?? 0) + 1;

        final items = (order['items'] as List<dynamic>?) ?? [];
        for (final rawItem in items) {
          final item = Map<String, dynamic>.from(rawItem as Map);
          final name = item['name']?.toString() ?? 'Unknown';
          final qty = item['qty'] is num ? (item['qty'] as num).toInt() : int.tryParse(item['qty']?.toString() ?? '1') ?? 1;
          final price = item['price'] is num ? (item['price'] as num).toDouble() : double.tryParse(item['price']?.toString() ?? '0') ?? 0;
          final category = item['category']?.toString().trim() ?? 'Others';
          itemCounts[name] ??= {'name': name, 'qty': 0, 'revenue': 0.0};
          itemCounts[name]!['qty'] = (itemCounts[name]!['qty'] as int) + qty;
          itemCounts[name]!['revenue'] = (itemCounts[name]!['revenue'] as double) + price * qty;
          categoryRevenue[category] = (categoryRevenue[category] ?? 0) + price * qty;
        }
      }

      final sortedTopItems = itemCounts.values.toList()..sort((a, b) => (b['qty'] as int).compareTo(a['qty'] as int));
      final last7Days = List.generate(7, (index) {
        final day = DateTime.now().subtract(Duration(days: 6 - index));
        return '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      });

      setState(() {
        totalOrders = (data['totalOrders'] as num?)?.toInt() ?? 0;
        revenue = (data['revenue'] as num?)?.toInt() ?? 0;
        averageOrderValue = totalOrders > 0 ? (revenue / totalOrders).round() : 0;
        recentOrders = orders;
        topItems = sortedTopItems.take(5).map((item) => {
              'name': item['name'],
              'qty': item['qty'],
              'revenue': item['revenue'],
            }).toList();
        weeklyRevenue = last7Days.map((key) => revenuePerDay[key] ?? 0).toList();
        weeklyOrders = last7Days.map((key) => ordersPerDay[key] ?? 0).toList();
        final totalCategory = categoryRevenue.values.fold<double>(0.0, (prev, next) => prev + next);
        categoryShares = categoryRevenue.map((key, value) => MapEntry(key, totalCategory > 0 ? (value / totalCategory) * 100 : 0));
        isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
    }
  }

  String formatRupees(int amount) {
    return '₹${amount.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => ',')}';
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF020617) : const Color(0xFFF4F6F9);
    Color cardColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    Color textColor = isDark ? Colors.white : const Color(0xFF081F47);
    Color subText = isDark ? Colors.white54 : const Color(0xFF6B7280);

    return VendorPageWrapper(
      pageTitle: 'Sales Reports',
      selectedMenuIndex: 4,
      toggleTheme: () {},
      child: Scaffold(
        backgroundColor: bgColor,
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              double availableWidth = constraints.maxWidth;
              bool isMobile = MediaQuery.of(context).size.width < 850;
              double cardWidth = isMobile ? (availableWidth - 16) / 2 : (availableWidth - 32) / 3;
              double halfWidth = isMobile ? availableWidth : (availableWidth - 16) / 2;

              return SingleChildScrollView(
                child: Column(
                  children: [
                    isMobile
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Track ${VendorData.displayName}'s performance",
                                style: TextStyle(fontFamily: 'Inter', color: subText, fontSize: 14),
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  InteractiveScale(
                                    onTap: () {},
                                    child: TextButton.icon(
                                      onPressed: () {},
                                      icon: Icon(Icons.calendar_today_rounded, size: 16, color: primaryBlue),
                                      label: Text(
                                        "Last 30 Days",
                                        style: TextStyle(fontFamily: 'Inter', color: primaryBlue, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                  InteractiveScale(
                                    onTap: () {},
                                    child: ElevatedButton.icon(
                                      onPressed: () {},
                                      icon: const Icon(Icons.download_rounded, size: 16),
                                      label: const Text(
                                        "Download CSV",
                                        style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.bold),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: primaryBlue,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                        elevation: 0,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Track ${VendorData.displayName}'s performance",
                                style: TextStyle(fontFamily: 'Inter', color: subText, fontSize: 14),
                              ),
                              Row(
                                children: [
                                  InteractiveScale(
                                    onTap: () {},
                                    child: TextButton.icon(
                                      onPressed: () {},
                                      icon: Icon(Icons.calendar_today_rounded, size: 16, color: primaryBlue),
                                      label: Text(
                                        "Last 30 Days",
                                        style: TextStyle(fontFamily: 'Inter', color: primaryBlue, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  InteractiveScale(
                                    onTap: () {},
                                    child: ElevatedButton.icon(
                                      onPressed: () {},
                                      icon: const Icon(Icons.download_rounded, size: 16),
                                      label: const Text(
                                        "Download CSV",
                                        style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.bold),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: primaryBlue,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                        elevation: 0,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                    const SizedBox(height: 20),
                    if (isLoading)
                      const Center(child: CircularProgressIndicator())
                    else
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          InteractiveScale(onTap: () {}, child: _topCard(formatRupees(revenue), "Total Revenue", "+0%", cardColor, textColor, subText, isDark, cardWidth)),
                          InteractiveScale(onTap: () {}, child: _topCard(totalOrders.toString(), "Total Orders", "+0%", cardColor, textColor, subText, isDark, cardWidth)),
                          InteractiveScale(onTap: () {}, child: _topCard(formatRupees(averageOrderValue), "Avg Order Value", "+0%", cardColor, textColor, subText, isDark, cardWidth)),
                        ],
                      ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        SizedBox(width: halfWidth, child: InteractiveScale(onTap: () {}, child: _lineChart(cardColor, textColor, isDark))),
                        SizedBox(width: halfWidth, child: InteractiveScale(onTap: () {}, child: _pieChart(cardColor, textColor, isDark))),
                      ],
                    ).animate().fade(delay: 200.ms).slideY(begin: 0.1, curve: Curves.easeOutCubic),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        SizedBox(width: halfWidth, child: InteractiveScale(onTap: () {}, child: _barChart(cardColor, textColor, isDark))),
                        SizedBox(width: halfWidth, child: InteractiveScale(onTap: () {}, child: _topItems(cardColor, textColor, subText, isDark))),
                      ],
                    ).animate().fade(delay: 300.ms).slideY(begin: 0.1, curve: Curves.easeOutCubic),
                    const SizedBox(height: 20),
                    InteractiveScale(onTap: () {}, child: _transactionsTable(cardColor, textColor, subText, isDark)).animate().fade(delay: 400.ms).slideY(begin: 0.1, curve: Curves.easeOutCubic),
                    const SizedBox(height: 50),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _topCard(String value, String title, String growth, Color card, Color text, Color sub, bool isDark, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Color.fromRGBO(0, 0, 0, isDark ? 0.3 : 0.05), blurRadius: 20, offset: const Offset(0, 10))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: TextStyle(fontFamily: 'Nunito', fontSize: 22, fontWeight: FontWeight.w900, color: text), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(fontFamily: 'Inter', color: sub, fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.green.withAlpha(26), borderRadius: BorderRadius.circular(8)), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.trending_up_rounded, color: Colors.green, size: 14), const SizedBox(width: 4), Text(growth, style: const TextStyle(fontFamily: 'Inter', color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12))])),
        ],
      ),
    );
  }

  Widget _lineChart(Color card, Color text, bool isDark) {
    final maxOrders = weeklyRevenue.isNotEmpty ? weeklyRevenue.reduce((a, b) => a > b ? a : b) : 1;
    return _box(
      "Revenue & Orders Trend",
      card,
      text,
      isDark,
      Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: weeklyRevenue.map((value) {
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: maxOrders > 0 ? (value / maxOrders) * 170 : 0,
                    decoration: BoxDecoration(color: primaryBlue, borderRadius: BorderRadius.circular(6)),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: List.generate(7, (index) => Text('D${index + 1}', style: TextStyle(fontSize: 10, color: text)))),
        ],
      ),
    );
  }

  Widget _pieChart(Color card, Color text, bool isDark) {
    final sections = categoryShares.entries.where((entry) => entry.value > 0).take(4).map((entry) => PieChartSectionData(value: entry.value, color: _colorForCategory(entry.key), radius: 40, showTitle: false)).toList();
    return _box(
      "Sales by Category",
      card,
      text,
      isDark,
      sections.isEmpty
          ? Center(child: Text('No category data', style: TextStyle(color: text)))
          : PieChart(PieChartData(centerSpaceRadius: 40, borderData: FlBorderData(show: false), sectionsSpace: 4, sections: sections)),
    );
  }

  Color _colorForCategory(String category) {
    final colors = [Colors.blue, Colors.green, Colors.orange, Colors.purple, Colors.red];
    return colors[category.hashCode.remainder(colors.length)];
  }

  Widget _barChart(Color card, Color text, bool isDark) {
    final maxOrders = weeklyOrders.isNotEmpty ? weeklyOrders.reduce((a, b) => a > b ? a : b) : 1;
    return _box(
      "Peak Hours",
      card,
      text,
      isDark,
      Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: weeklyOrders.map((value) {
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: maxOrders > 0 ? (value / maxOrders) * 170 : 0,
                    decoration: BoxDecoration(color: primaryBlue, borderRadius: BorderRadius.circular(6)),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: List.generate(7, (index) => Text('D${index + 1}', style: TextStyle(fontSize: 10, color: text)))),
        ],
      ),
    );
  }

  Widget _topItems(Color card, Color text, Color subText, bool isDark) {
    return _box(
      "Top Selling Items",
      card,
      text,
      isDark,
      topItems.isEmpty
          ? Center(child: Text('No sales data yet', style: TextStyle(color: text)))
          : ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: topItems.map((item) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item['name'].toString(), style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.bold, fontSize: 16, color: text)),
                  subtitle: Text('${item['qty']} items sold', style: TextStyle(fontFamily: 'Inter', color: subText)),
                  trailing: Text(formatRupees((item['revenue'] as double).round()), style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 16, color: text)),
                );
              }).toList(),
            ),
    );
  }

  Widget _transactionsTable(Color card, Color text, Color subText, bool isDark) {
    return _box(
      "Recent Transactions",
      card,
      text,
      isDark,
      recentOrders.isEmpty
          ? Center(child: Text('No recent transactions yet', style: TextStyle(color: text)))
          : ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: recentOrders.length,
              separatorBuilder: (_, __) => Divider(color: isDark ? Colors.white12 : Colors.grey.shade200),
              itemBuilder: (context, index) {
                final order = recentOrders[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(order['orderId']?.toString() ?? 'Unknown', style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.bold, fontSize: 16, color: text)),
                  subtitle: Text(order['customerName']?.toString() ?? 'Customer', style: TextStyle(fontFamily: 'Inter', color: subText)),
                  trailing: Text(formatRupees((order['total'] is num ? (order['total'] as num).toInt() : int.tryParse(order['total']?.toString() ?? '0') ?? 0)), style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 16, color: text)),
                );
              },
            ),
    );
  }

  Widget _box(String title, Color card, Color text, bool isDark, Widget child) {
    return Container(
      height: 350,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Color.fromRGBO(0, 0, 0, isDark ? 0.3 : 0.05), blurRadius: 20, offset: const Offset(0, 10))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 18, color: text)), const SizedBox(height: 24), Expanded(child: child)]),
    );
  }
}

class InteractiveScale extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const InteractiveScale({super.key, required this.child, required this.onTap});
  @override State<InteractiveScale> createState() => _InteractiveScaleState();
}

class _InteractiveScaleState extends State<InteractiveScale> {
  bool isHovered = false, isPressed = false;
  @override Widget build(BuildContext context) {
    return AnimatedScale(scale: isPressed ? 0.95 : (isHovered ? 1.02 : 1.0), duration: const Duration(milliseconds: 150), curve: Curves.easeOutCubic, child: Material(color: Colors.transparent, child: InkWell(focusColor: Colors.transparent, hoverColor: Colors.transparent, highlightColor: Colors.transparent, splashColor: Colors.transparent, onHover: (h) => setState(() => isHovered = h), onHighlightChanged: (h) => setState(() => isPressed = h), onTap: widget.onTap, child: widget.child)));
  }
}
