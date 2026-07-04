import 'package:flutter/material.dart';

import '../../theme/messenger_theme.dart';

class MessengerAvatar extends StatelessWidget {
  const MessengerAvatar({
    super.key,
    required this.label,
    this.radius = 26,
    this.isGroup = false,
    this.online,
  });

  final String label;
  final double radius;
  final bool isGroup;
  final bool? online;

  @override
  Widget build(BuildContext context) {
    final ext = messengerExt(context);
    final bg = isGroup ? MessengerPalette.whatsAppGreenDark : MessengerPalette.accent;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: bg,
          child: Text(
            label.isEmpty ? '?' : label,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: radius * 0.55),
          ),
        ),
        if (online == true)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: radius * 0.42,
              height: radius * 0.42,
              decoration: BoxDecoration(
                color: MessengerPalette.whatsAppGreen,
                shape: BoxShape.circle,
                border: Border.all(color: ext.chatBackground, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}
