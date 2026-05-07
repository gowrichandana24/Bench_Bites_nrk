import 'package:flutter/material.dart';
import '../model/notification_model.dart';
import '../services/session.dart';
import 'cafeteria_page.dart'; // Import to use CustomFloatingNavBar

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userId = AppSession.userId;
      if (userId.isNotEmpty) {
        await NotificationModel.fetchNotifications(userId);
      } else {
        // User not logged in, show empty state
        NotificationModel.notifications = [];
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _markAsRead(String notificationId) async {
    try {
      await NotificationModel.markAsRead(notificationId);
      setState(() {}); // Refresh UI
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to mark as read: $e')),
      );
    }
  }

  Future<void> _deleteNotification(String notificationId) async {
    try {
      await NotificationModel.deleteNotification(notificationId);
      setState(() {}); // Refresh UI
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete notification: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? const Color(0xFF020617) : const Color(0xFFF4F6F9);

    return Scaffold(
      backgroundColor: background,
      extendBody: true, // Allows content to scroll behind the floating nav bar
      body: SafeArea(
        bottom: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180), // Matched width constraints
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTopBar(context, isDark, "Notifications"),
                  const SizedBox(height: 24),
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _error != null
                            ? _buildErrorState(isDark, _error!)
                            : RefreshIndicator(
                                onRefresh: _loadNotifications,
                                child: NotificationModel.notifications.isEmpty
                                    ? _buildEmptyState(isDark)
                                    : ListView.builder(
                                        padding: const EdgeInsets.only(bottom: 120), // Avoid clipping with NavBar
                                        itemCount: NotificationModel.notifications.length,
                                        itemBuilder: (context, index) {
                                          var notif = NotificationModel.notifications[index];
                                          return _buildNotificationCard(context, notif, isDark);
                                        },
                                      ),
                              ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: CustomFloatingNavBar(
        currentIndex: 0, 
        isDark: isDark,
        toggleTheme: () {}, 
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, bool isDark, String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.18 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.12) : const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded, color: isDark ? Colors.white : const Color(0xFF0F4CFF), size: 20),
            ),
          ),
          const SizedBox(width: 16), // Ensures left-alignment right next to the button
          Text(
            title,
            style: TextStyle(
              fontSize: 18, 
              fontFamily: 'Nunito', 
              fontWeight: FontWeight.w900, 
              color: isDark ? Colors.white : const Color(0xFF0F4CFF), 
              letterSpacing: 0.5
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(BuildContext context, Map<String, dynamic> notif, bool isDark) {
    final cardColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF10254E);
    final subTextColor = isDark ? Colors.white70 : const Color(0xFF6B7280);
    final isRead = notif['isRead'] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
            blurRadius: 20, 
            offset: const Offset(0, 10)
          )
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () {
          // Mark as read if not already read
          if (!isRead && notif['_id'] != null) {
            _markAsRead(notif['_id']);
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NotificationDetailPage(
                title: notif["title"] ?? "",
                items: List<String>.from(notif["items"] ?? []),
              ),
            ),
          );
        },
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFE8F0FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                _getNotificationIcon(notif['type']),
                color: isDark ? Colors.white : const Color(0xFF0F4CFF), 
                size: 24
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notif["title"] ?? "",
                          style: TextStyle(
                            fontFamily: 'Nunito', 
                            fontWeight: FontWeight.w900, 
                            fontSize: 16, 
                            color: textColor
                          ),
                        ),
                      ),
                      if (!isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF0F4CFF),
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notif["message"] ?? "",
                    style: TextStyle(
                      fontFamily: 'Inter', 
                      fontWeight: FontWeight.w500,
                      fontSize: 13, 
                      color: subTextColor
                    ),
                  ),
                  if (notif['createdAt'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _formatDate(notif['createdAt']),
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          color: subTextColor.withOpacity(0.7),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'delete' && notif['_id'] != null) {
                  _deleteNotification(notif['_id']);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete'),
                ),
              ],
              icon: Icon(Icons.more_vert, color: subTextColor.withOpacity(0.5), size: 20),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getNotificationIcon(String? type) {
    switch (type) {
      case 'order':
        return Icons.shopping_bag_rounded;
      case 'promotion':
        return Icons.local_offer_rounded;
      default:
        return Icons.notifications_active_rounded;
    }
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return '';
    }
  }

  Widget _buildEmptyState(bool isDark) {
    final subTextColor = isDark ? Colors.white70 : const Color(0xFF6B7280);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none_rounded, size: 80, color: subTextColor.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(
            "No notifications yet", 
            style: TextStyle(
              fontFamily: 'Nunito', 
              fontSize: 18, 
              fontWeight: FontWeight.w900, 
              color: subTextColor
            )
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(bool isDark, String error) {
    final subTextColor = isDark ? Colors.white70 : const Color(0xFF6B7280);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline_rounded, size: 80, color: subTextColor.withOpacity(0.2)),
        const SizedBox(height: 16),
        Text(
          "Failed to load notifications",
          style: TextStyle(
            fontFamily: 'Nunito', 
            fontSize: 18, 
            fontWeight: FontWeight.w900, 
            color: subTextColor
          )
        ),
        const SizedBox(height: 8),
        Text(
          error,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Inter', 
            fontSize: 14, 
            color: subTextColor.withOpacity(0.7)
          )
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _loadNotifications,
          child: const Text('Retry'),
        ),
      ],
    );
  }
}

class NotificationDetailPage extends StatelessWidget {
  final String title;
  final List<String> items;

  const NotificationDetailPage({super.key, required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? const Color(0xFF020617) : const Color(0xFFF4F6F9);
    final cardColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF10254E);

    return Scaffold(
      backgroundColor: background,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTopBar(context, isDark, "Order Details"),
                  const SizedBox(height: 24),
                  Expanded(
                    child: items.isEmpty
                        ? Center(child: Text("No items found", style: TextStyle(fontFamily: 'Inter', color: textColor)))
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 120),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: cardColor,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(isDark ? 0.3 : 0.05), 
                                      blurRadius: 10,
                                      offset: const Offset(0, 4)
                                    )
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFE8F0FF),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(Icons.fastfood_rounded, color: isDark ? Colors.white : const Color(0xFF0F4CFF), size: 20),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        items[index],
                                        style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: textColor, fontSize: 15),
                                      ),
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
          ),
        ),
      ),
      bottomNavigationBar: CustomFloatingNavBar(
        currentIndex: 0, 
        isDark: isDark,
        toggleTheme: () {}, 
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, bool isDark, String barTitle) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.18 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.12) : const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded, color: isDark ? Colors.white : const Color(0xFF0F4CFF), size: 20),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            barTitle,
            style: TextStyle(
              fontSize: 18, 
              fontFamily: 'Nunito', 
              fontWeight: FontWeight.w900, 
              color: isDark ? Colors.white : const Color(0xFF0F4CFF), 
              letterSpacing: 0.5
            ),
          ),
        ],
      ),
    );
  }
}