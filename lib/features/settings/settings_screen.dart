import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/api_config.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/preferences/messenger_preferences.dart';
import '../../core/theme/theme_controller.dart';
import '../../theme/messenger_theme.dart';
import '../../widgets/messenger_avatar.dart';
import '../../core/models/api_models.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthRepository>();
    final themeCtrl = context.watch<ThemeController>();
    final prefs = context.watch<MessengerPreferences>();
    final ext = messengerExt(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: MessengerAvatar(label: ConversationSummary.initialsFrom(auth.userName), radius: 24),
            title: Text(auth.userName ?? 'User', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            subtitle: Text(auth.userEmail ?? ''),
          ),
          const Divider(height: 32),
          _SectionHeader(title: 'Appearance'),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Theme'),
            subtitle: Text(_themeLabel(themeCtrl.mode)),
            onTap: () => _pickTheme(context, themeCtrl),
          ),
          ListTile(
            leading: const Icon(Icons.wallpaper_outlined),
            title: const Text('Chat wallpaper'),
            subtitle: Text(ChatWallpaper.byId(prefs.wallpaperId).name),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WallpaperPickerScreen())),
          ),
          _SectionHeader(title: 'Notifications (mobile)'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Message notifications'),
            subtitle: Text(
              'Alerts when app is in background. Mute individual chats from chat menu.',
              style: TextStyle(color: ext.subtext, fontSize: 13),
            ),
            value: prefs.pushNotificationsEnabled,
            onChanged: (v) => prefs.setPushNotificationsEnabled(v),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_off_outlined),
            title: const Text('Muted chats'),
            subtitle: Text('${prefs.mutedConversationIds.length} conversations (mobile only)'),
          ),
          const Divider(height: 32),
          _SectionHeader(title: 'Chats'),
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: const Text('Archived chats'),
            subtitle: Text('Use Archived filter on Chats tab', style: TextStyle(color: ext.subtext, fontSize: 13)),
          ),
          const Divider(height: 32),
          _SectionHeader(title: 'About'),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Server'),
            subtitle: Text(ApiConfig.defaultBaseUrl, style: TextStyle(color: ext.subtext, fontSize: 12)),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Version'),
            subtitle: const Text('0.1.0'),
          ),
          const Divider(height: 32),
          _SectionHeader(title: 'Account'),
          ListTile(
            leading: const Icon(Icons.logout, color: MessengerPalette.danger),
            title: const Text('Sign out', style: TextStyle(color: MessengerPalette.danger, fontWeight: FontWeight.w600)),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  title: const Text('Sign out?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Sign out')),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                await auth.logout();
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
          const SizedBox(height: 24),
          Center(child: Text('ERPComplete Messenger', style: TextStyle(color: ext.subtext, fontSize: 12))),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _themeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'System default',
      };

  Future<void> _pickTheme(BuildContext context, ThemeController themeCtrl) async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: const Text('Theme'), trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))),
            for (final mode in ThemeMode.values)
              RadioListTile<ThemeMode>(
                value: mode,
                groupValue: themeCtrl.mode,
                title: Text(_themeLabel(mode)),
                onChanged: (v) {
                  if (v != null) themeCtrl.setMode(v);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class WallpaperPickerScreen extends StatelessWidget {
  const WallpaperPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<MessengerPreferences>();
    final brightness = Theme.of(context).brightness;

    return Scaffold(
      appBar: AppBar(title: const Text('Chat wallpaper')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12),
        itemCount: ChatWallpaper.presets.length,
        itemBuilder: (context, index) {
          final wp = ChatWallpaper.presets[index];
          final selected = prefs.wallpaperId == wp.id;
          final color = wp.colorFor(brightness);
          return InkWell(
            onTap: () => prefs.setWallpaper(wp.id),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                color: wp.id == ChatWallpaper.defaultId ? messengerExt(context).chatBackground : color,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? MessengerPalette.whatsAppGreen : Colors.grey.withValues(alpha: 0.3),
                  width: selected ? 3 : 1,
                ),
              ),
              child: Center(
                child: Text(wp.name, style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500, fontSize: 12)),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(title.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: messengerExt(context).subtext, letterSpacing: 0.8)),
    );
  }
}
