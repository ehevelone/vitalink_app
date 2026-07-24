import 'package:flutter/material.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';

/// ✅ Reusable AppBar that automatically shows the user's name (if available).
class AppHeader extends StatefulWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Color? backgroundColor;

  const AppHeader({
    super.key,
    required this.title,
    this.actions,
    this.backgroundColor,
  });

  @override
  State<AppHeader> createState() => _AppHeaderState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _AppHeaderState extends State<AppHeader> {
  String _userName = "";

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    final repo = DataRepository(SecureStore());
    final profile = await repo.loadProfile();

    if (!mounted) return;

    setState(() {
      if (profile.fullName.isNotEmpty) {
        _userName = profile.fullName;
      } else {
        _userName = "Guest";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: widget.backgroundColor ??
          Theme.of(context).appBarTheme.backgroundColor,
      title: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title),
                if (_userName.isNotEmpty)
                  Row(
                    children: [
                      Text(
                        _userName,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Image.asset(
                        "assets/images/logo_icon.png", // ✅ use your actual logo
                        height: 16,
                        width: 16,
                        color: Colors.white70, // optional subtle tint
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: widget.actions,
    );
  }
}
