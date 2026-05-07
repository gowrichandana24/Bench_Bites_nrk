import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../../services/session.dart';
import 'vendor_page_wrapper.dart';

class MenuItemModel {
  final String id;
  String name;
  int price;
  String category;
  bool available;
  String image;

  MenuItemModel({
    required this.id,
    required this.name,
    required this.price,
    required this.category,
    this.available = true,
    this.image = '',
  });

  factory MenuItemModel.fromJson(Map<String, dynamic> json) {
    return MenuItemModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      price: (json['price'] is num) ? (json['price'] as num).toInt() : int.tryParse(json['price']?.toString() ?? '0') ?? 0,
      category: json['category']?.toString() ?? 'Others',
      available: json['available'] != null ? json['available'] as bool : true,
      image: json['image']?.toString() ?? '',
    );
  }
}

class MenuPage extends StatefulWidget {
  final VoidCallback toggleTheme;
  const MenuPage({super.key, required this.toggleTheme});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  final Color primaryBlue = const Color(0xFF0F4CFF);
  bool isLoading = true;
  List<MenuItemModel> menu = [];

  Map<String, List<MenuItemModel>> groupByCategory() {
    final grouped = <String, List<MenuItemModel>>{};
    for (var item in menu) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }
    return grouped;
  }

  List<String> getCategoryOptions() {
    final normalized = <String, String>{};
    for (var item in menu) {
      final category = item.category.trim();
      if (category.isEmpty) continue;
      final lower = category.toLowerCase();
      if (!normalized.containsKey(lower)) {
        normalized[lower] = normalizeCategory(category);
      }
    }
    return normalized.values.toList();
  }

  String normalizeCategory(String category) {
    final trimmed = category.trim();
    if (trimmed.isEmpty) return 'Others';
    return trimmed
        .split(RegExp(r'\s+'))
        .map((part) => part.isEmpty ? '' : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
        .join(' ');
  }

  String canonicalCategory(String category) {
    final normalized = normalizeCategory(category);
    for (var existing in getCategoryOptions()) {
      if (existing.toLowerCase() == normalized.toLowerCase()) {
        return existing;
      }
    }
    return normalized;
  }

  @override
  void initState() {
    super.initState();
    loadMenu();
  }

  Future<void> loadMenu() async {
    setState(() {
      isLoading = true;
    });

    try {
      final cafe = AppSession.cafe;
      if (cafe == null) {
        if (!mounted) return;
        setState(() {
          menu = [];
        });
        return;
      }

      final cafeId = cafe['_id']?.toString() ?? cafe['id']?.toString();
      if (cafeId == null || cafeId.isEmpty) {
        if (!mounted) return;
        setState(() {
          menu = [];
        });
        return;
      }

      final items = await ApiService.getMenu(cafeId: cafeId);
      if (!mounted) return;
      setState(() {
        menu = items.map((item) => MenuItemModel.fromJson(item)).toList();
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> addItem(Color cardColor, Color textColor) async {
    String name = '';
    String selectedCategory = '';
    String customCategory = '';
    bool useCustomCategory = false;
    int price = 0;
    Uint8List? selectedImageBytes;
    String selectedImageDataUrl = '';
    final categories = getCategoryOptions();
    const customOption = 'Create new category';
    if (categories.isNotEmpty) {
      selectedCategory = categories.first;
    } else {
      selectedCategory = customOption;
      useCustomCategory = true;
    }

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          final categoryItems = [
            ...categories,
            customOption,
          ];
          return AlertDialog(
            backgroundColor: cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text('Add New Item', style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, color: textColor)),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _inputField('Item Name', (v) => setDialogState(() => name = v), textColor),
                  if (categories.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Category',
                          labelStyle: TextStyle(color: Colors.grey.shade500, fontFamily: 'Inter'),
                          filled: true,
                          fillColor: Colors.grey.withOpacity(0.05),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: useCustomCategory ? customOption : selectedCategory,
                            isExpanded: true,
                            items: categoryItems.map((categoryValue) {
                              return DropdownMenuItem<String>(
                                value: categoryValue,
                                child: Text(categoryValue, style: TextStyle(color: textColor, fontFamily: 'Inter', fontWeight: FontWeight.w500)),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              setDialogState(() {
                                if (value == customOption) {
                                  useCustomCategory = true;
                                  customCategory = '';
                                } else {
                                  useCustomCategory = false;
                                  selectedCategory = value;
                                }
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                  if (useCustomCategory)
                    _inputField('New Category', (v) => setDialogState(() => customCategory = v), textColor),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.grey.withOpacity(0.08),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (selectedImageBytes != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.memory(selectedImageBytes!, height: 140, fit: BoxFit.cover),
                          ),
                          const SizedBox(height: 10),
                        ],
                        ElevatedButton.icon(
                          icon: const Icon(Icons.image),
                          label: Text(selectedImageBytes != null ? 'Replace photo' : 'Upload photo', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryBlue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () async {
                            final pickedImage = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
                            if (pickedImage == null) return;
                            final bytes = await pickedImage.readAsBytes();
                            final mimeType = pickedImage.mimeType ?? 'image/png';
                            setDialogState(() {
                              selectedImageBytes = bytes;
                              selectedImageDataUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _inputField('Price (₹)', (v) => setDialogState(() => price = int.tryParse(v) ?? 0), textColor, isNumber: true),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: Colors.grey, fontFamily: 'Inter', fontWeight: FontWeight.bold))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: primaryBlue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                onPressed: () async {
                  if (name.isEmpty || price <= 0) return;
                  Navigator.pop(context);
                  final cafeId = AppSession.cafe?['_id']?.toString() ?? AppSession.cafe?['id']?.toString();
                  final vendorId = AppSession.vendorId;
                  if (cafeId == null || cafeId.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Vendor cafe id missing'), backgroundColor: Colors.redAccent),
                    );
                    return;
                  }

                  final rawCategory = useCustomCategory ? customCategory : selectedCategory;
                  final savedCategory = canonicalCategory(rawCategory.isEmpty ? 'Others' : rawCategory);

                  try {
                    final newItem = await ApiService.createMenuItem(
                      name: name,
                      price: price,
                      category: savedCategory,
                      cafeId: cafeId,
                      vendorId: vendorId,
                      image: selectedImageDataUrl,
                      imageType: selectedImageDataUrl.isNotEmpty ? 'base64' : 'none',
                    );
                    if (!mounted) return;
                    setState(() {
                      menu.add(MenuItemModel.fromJson(newItem));
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Menu item added successfully'), backgroundColor: Colors.green),
                    );
                  } catch (error) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(error.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.redAccent),
                    );
                  }
                },
                child: const Text('Save Item', style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _inputField(String label, Function(String) onChanged, Color textColor, {bool isNumber = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        onChanged: onChanged,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        style: TextStyle(color: textColor, fontFamily: 'Inter', fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.grey.shade500, fontFamily: 'Inter'),
          filled: true,
          fillColor: Colors.grey.withOpacity(0.05),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Future<void> toggleAvailability(MenuItemModel item) async {
    try {
      final updated = await ApiService.updateMenuItem(item.id, {'available': !item.available});
      if (!mounted) return;
      setState(() {
        item.available = updated['available'] as bool? ?? !item.available;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> deleteItem(MenuItemModel item) async {
    try {
      await ApiService.deleteMenuItem(item.id);
      if (!mounted) return;
      setState(() {
        menu.removeWhere((m) => m.id == item.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Menu item deleted'), backgroundColor: Colors.green),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupedMenu = groupByCategory();
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark ? const Color(0xFF020617) : const Color(0xFFF4F6F9);
    final Color cardColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    final Color textColor = isDark ? Colors.white : const Color(0xFF081F47);

    return VendorPageWrapper(
      pageTitle: 'Menu Management',
      selectedMenuIndex: 3,
      toggleTheme: widget.toggleTheme,
      child: Scaffold(
        backgroundColor: bgColor,
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : AppSession.cafe == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.storefront_outlined, size: 80, color: Colors.grey.withOpacity(0.5)),
                        const SizedBox(height: 16),
                        Text('No cafeteria assigned yet', style: TextStyle(fontFamily: 'Nunito', fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 8),
                        Text('Please wait for an admin to assign your cafeteria.', style: TextStyle(fontFamily: 'Inter', color: Colors.grey.shade500), textAlign: TextAlign.center),
                      ],
                    ),
                  )
                : menu.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.restaurant_menu_rounded, size: 80, color: Colors.grey.withOpacity(0.5)),
                            const SizedBox(height: 16),
                            Text('Your menu is empty', style: TextStyle(fontFamily: 'Nunito', fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey)),
                            const SizedBox(height: 8),
                            Text('Click + Add Item to get started', style: TextStyle(fontFamily: 'Inter', color: Colors.grey.shade500)),
                          ],
                        ),
                      )
                    : ListView(
                    padding: const EdgeInsets.all(16),
                    children: groupedMenu.entries.map((entry) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.key, style: TextStyle(fontFamily: 'Nunito', fontSize: 20, fontWeight: FontWeight.w900, color: textColor)).animate().fade().slideX(),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: entry.value.map((item) => buildCard(item, cardColor, textColor, isDark)).toList(),
                          ).animate().fade(delay: 100.ms),
                          const SizedBox(height: 32),
                        ],
                      );
                    }).toList(),
                  ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: primaryBlue,
          onPressed: AppSession.cafe == null ? null : () => addItem(cardColor, textColor),
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  Widget buildCard(MenuItemModel item, Color cardColor, Color textColor, bool isDark) {
    return Container(
      width: MediaQuery.of(context).size.width > 600 ? 240 : (MediaQuery.of(context).size.width / 2) - 24,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.05), blurRadius: 20, offset: const Offset(0, 10))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 100,
            width: double.infinity,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: Colors.grey.withOpacity(0.1)),
            clipBehavior: Clip.antiAlias,
            child: item.image.isEmpty
                ? Icon(Icons.fastfood_rounded, color: primaryBlue.withOpacity(0.5), size: 40)
                : Image.network(item.image, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.fastfood_rounded, color: primaryBlue.withOpacity(0.5), size: 40)),
          ),
          const SizedBox(height: 16),
          Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 16, color: textColor)),
          const SizedBox(height: 4),
          Text('₹${item.price}', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: primaryBlue, fontSize: 14)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => toggleAvailability(item),
                  style: ElevatedButton.styleFrom(backgroundColor: item.available ? primaryBlue.withOpacity(0.1) : Colors.grey.withOpacity(0.2), foregroundColor: item.available ? primaryBlue : Colors.grey, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 10)),
                  child: Text(item.available ? 'Enabled' : 'Disabled', style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20), onPressed: () => deleteItem(item)),
              ),
            ],
          )
        ],
      ),
    );
  }
}
