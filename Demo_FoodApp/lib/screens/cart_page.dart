import 'package:flutter/material.dart';
import 'checkout_page.dart';
import 'cafeteria_page.dart'; 
import '../model/cart_model.dart'; 
import 'package:lottie/lottie.dart';// ✅ Imported to keep cart and home page synced

// ✅ GLOBAL CART STATE: Single source of truth for the entire app
List<Map<String, dynamic>> globalCartItems = [];

class CartPage extends StatefulWidget {
  final List<Map<String, dynamic>>? cartItems;
  final VoidCallback? toggleTheme;

  const CartPage({super.key, this.cartItems, this.toggleTheme});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  final Color primaryBlue = const Color(0xFF0F4CFF);
  TextEditingController couponController = TextEditingController();
  bool couponApplied = false;
  int discount = 50;

  @override
  void initState() {
    super.initState();
    if (widget.cartItems != null && widget.cartItems!.isNotEmpty) {
      globalCartItems = widget.cartItems!;
    }
  }

  int getTotal() {
    return globalCartItems.fold(0, (sum, item) => sum + ((item["price"] as int) * (item["qty"] as int)));
  }

  int getFinalTotal() {
    int total = getTotal() + 3; // Platform fee
    return couponApplied ? total - discount : total;
  }

  // ✅ SYNC LOGIC: Updates global list AND the CartModel!
  void updateQty(Map<String, dynamic> item, int delta) {
    setState(() {
      item["qty"] += delta;
      
      // Keep original model synced so Home Page numbers don't reset
      if (delta > 0) {
        CartModel.add(item["id"]);
      } else {
        CartModel.remove(item["id"]);
      }

      if (item["qty"] <= 0) {
        globalCartItems.remove(item);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? const Color(0xFF020617) : const Color(0xFFF4F6F9);
    final cardColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF10254E);
    final subTextColor = isDark ? Colors.white70 : const Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: background,
      extendBody: true, 
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180), // Matched width
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTopBar(isDark, cardColor, textColor),
                    const SizedBox(height: 24),

                    if (globalCartItems.isEmpty)
                      _buildEmptyCart(subTextColor)
                    else ...[
                      ...globalCartItems.map((item) => _buildCartItemCard(item, isDark, cardColor, textColor, subTextColor)).toList(),
                      const SizedBox(height: 16),
                      _buildCouponSection(isDark, cardColor, textColor, subTextColor),
                      const SizedBox(height: 24),
                      _buildBillDetails(isDark, cardColor, textColor, subTextColor),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryBlue,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 58),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CheckoutPage(
                              cafeteriaName: globalCartItems.first["cafeteriaName"]?.toString(),
                              cafeId: globalCartItems.first["cafeId"]?.toString(),
                              pickupLocation: globalCartItems.first["location"]?.toString(),
                            ),
                          ),
                        ),
                        child: const Text("Continue to Checkout", style: TextStyle(fontFamily: 'Nunito', fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      ),
                      const SizedBox(height: 120),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: CustomFloatingNavBar(
        currentIndex: 1, 
        isDark: isDark,
        toggleTheme: widget.toggleTheme ?? () {},
      ),
    );
  }

  Widget _buildTopBar(bool isDark, Color cardColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.18 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
  if (Navigator.canPop(context)) {
    Navigator.pop(context);
  } else {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => CafeteriaPage(toggleTheme: widget.toggleTheme ?? () {})),
      (route) => false,
    );
  }
},
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.12) : const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.arrow_back_ios_new_rounded, color: isDark ? Colors.white : primaryBlue, size: 20),
                ),
              ),
              const SizedBox(width: 44), // Placeholder to keep title centered
            ],
          ),
          Text(
            "My Cart",
            style: TextStyle(fontSize: 18, fontFamily: 'Nunito', fontWeight: FontWeight.w900, color: textColor, letterSpacing: 0.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCartItemCard(Map<String, dynamic> item, bool isDark, Color cardColor, Color textColor, Color subTextColor) {
    final imageValue = item["image"]?.toString() ?? '';
    Widget imageWidget;
    if (imageValue.isEmpty) {
      imageWidget = Container(
        color: Colors.grey.shade200,
        height: 80,
        width: 80,
        child: const Icon(Icons.fastfood, color: Colors.grey, size: 32),
      );
    } else if (imageValue.startsWith('http') || imageValue.startsWith('data:')) {
      imageWidget = Image.network(imageValue, height: 80, width: 80, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(
        color: Colors.grey.shade200,
        height: 80,
        width: 80,
        child: const Icon(Icons.fastfood, color: Colors.grey, size: 32),
      ));
    } else {
      imageWidget = Image.asset(imageValue, height: 80, width: 80, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(
        color: Colors.grey.shade200,
        height: 80,
        width: 80,
        child: const Icon(Icons.fastfood, color: Colors.grey, size: 32),
      ));
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(14), child: imageWidget),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item["name"],
                  style: TextStyle(fontFamily: 'Nunito', color: textColor, fontWeight: FontWeight.w900, fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text("₹${item["price"]}", style: TextStyle(fontFamily: 'Inter', color: subTextColor, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Container(
                  height: 32,
                  width: 100,
                  decoration: BoxDecoration(
                    color: primaryBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: primaryBlue.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      InkWell(onTap: () => updateQty(item, -1), child: Icon(Icons.remove, size: 16, color: primaryBlue)),
                      Text("${item["qty"]}", style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, color: primaryBlue)),
                      InkWell(onTap: () => updateQty(item, 1), child: Icon(Icons.add, size: 16, color: primaryBlue)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
            ),
            onPressed: () => setState(() {
               for(int i = 0; i < item["qty"]; i++) CartModel.remove(item["id"]); 
               globalCartItems.remove(item);
            }),
          )
        ],
      ),
    );
  }

  Widget _buildCouponSection(bool isDark, Color cardColor, Color textColor, Color subTextColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: primaryBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.local_offer_outlined, color: primaryBlue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: couponController,
              style: TextStyle(color: textColor, fontFamily: 'Inter', fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: "Enter coupon code",
                hintStyle: TextStyle(color: subTextColor, fontFamily: 'Inter', fontWeight: FontWeight.w400),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: couponApplied ? Colors.green : primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: () {
              if (couponController.text.isNotEmpty) setState(() => couponApplied = true);
            },
            child: Text(couponApplied ? "Applied" : "Apply", style: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  Widget _buildBillDetails(bool isDark, Color cardColor, Color textColor, Color subTextColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Bill Details", style: TextStyle(fontFamily: 'Nunito', color: textColor, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          _billRow("Item Total", getTotal(), subTextColor, textColor),
          _billRow("Platform Fee", 3, subTextColor, textColor),
          if (couponApplied) _billRow("Discount", -discount, Colors.green, Colors.green),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Divider(color: isDark ? Colors.white12 : Colors.grey.shade200, thickness: 1.5),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Total Pay", style: TextStyle(fontFamily: 'Nunito', color: textColor, fontSize: 16, fontWeight: FontWeight.w900)),
              Text("₹${getFinalTotal()}", style: TextStyle(fontFamily: 'Inter', color: textColor, fontSize: 18, fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _billRow(String title, int amount, Color titleColor, Color amountColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(fontFamily: 'Inter', color: titleColor, fontWeight: FontWeight.w500, fontSize: 14)),
          Text("₹$amount", style: TextStyle(fontFamily: 'Inter', color: amountColor, fontWeight: FontWeight.w700, fontSize: 14)),
        ],
      ),
    );
  }


Widget _buildEmptyCart(Color subTextColor) {
  return Padding(
    padding: const EdgeInsets.only(top: 100),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 🔥 Lottie with bottom crop
        Stack(
  alignment: Alignment.bottomCenter,
  children: [
    SizedBox(
      height: 180,
      child: Lottie.asset(
        'assets/Cart icon.json',
        fit: BoxFit.contain,
      ),
    ),

    // 👇 Mask overlay to hide watermark
    Container(
      height: 30, // adjust based on watermark height
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
      ),
    ),
  ],
),
        const SizedBox(height: 20),

        Text(
          "Your cart is empty",
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: subTextColor,
          ),
        ),

        const SizedBox(height: 8),

        Text(
          "Add items from cafeterias to see them here.",
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            color: subTextColor.withOpacity(0.7),
          ),
        ),
      ],
    ),
  );
}
}
