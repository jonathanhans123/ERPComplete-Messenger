import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/messaging/messaging_repository.dart';
import '../../core/models/api_models.dart';

typedef AttachmentSent = void Function(ChatMessage message);

class ChatAttachmentSheet {
  static Future<void> show(
    BuildContext context, {
    required MessagingRepository repo,
    required int conversationId,
    required AttachmentSent onSent,
    required void Function(String error) onError,
  }) async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Camera / photo'), onTap: () async {
              Navigator.pop(ctx);
              await _pickGallery(context, repo: repo, conversationId: conversationId, onSent: onSent, onError: onError, fromCamera: true);
            }),
            ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Gallery'), onTap: () async {
              Navigator.pop(ctx);
              await _pickGallery(context, repo: repo, conversationId: conversationId, onSent: onSent, onError: onError);
            }),
            ListTile(leading: const Icon(Icons.insert_drive_file_outlined), title: const Text('Document'), onTap: () async {
              Navigator.pop(ctx);
              await _pickDocument(context, repo: repo, conversationId: conversationId, onSent: onSent, onError: onError);
            }),
            ListTile(leading: const Icon(Icons.location_on_outlined), title: const Text('Location'), onTap: () async {
              Navigator.pop(ctx);
              await _shareLocation(context, repo: repo, conversationId: conversationId, onSent: onSent, onError: onError);
            }),
            ListTile(leading: const Icon(Icons.person_outline), title: const Text('Contact'), onTap: () async {
              Navigator.pop(ctx);
              await _shareContact(context, repo: repo, conversationId: conversationId, onSent: onSent, onError: onError);
            }),
            ListTile(leading: const Icon(Icons.poll_outlined), title: const Text('Poll'), onTap: () async {
              Navigator.pop(ctx);
              await _createPoll(context, repo: repo, conversationId: conversationId, onSent: onSent, onError: onError);
            }),
          ],
        ),
      ),
    );
  }

  static Future<bool> _ensurePermission(Permission permission) async {
    final status = await permission.request();
    return status.isGranted;
  }

  static Future<void> _pickGallery(
    BuildContext context, {
    required MessagingRepository repo,
    required int conversationId,
    required AttachmentSent onSent,
    required void Function(String) onError,
    bool fromCamera = false,
  }) async {
    if (fromCamera && !await _ensurePermission(Permission.camera)) {
      onError('Camera permission denied');
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.single.path == null) return;
    try {
      final msg = await repo.sendAttachmentMessage(
        conversationId: conversationId,
        type: 'image',
        file: File(result.files.single.path!),
      );
      onSent(msg);
    } catch (e) {
      onError(e.toString());
    }
  }

  static Future<void> _pickDocument(BuildContext context, {required MessagingRepository repo, required int conversationId, required AttachmentSent onSent, required void Function(String) onError}) async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (result == null || result.files.single.path == null) return;
    final path = result.files.single.path!;
    final name = result.files.single.name;
    final lower = name.toLowerCase();
    final type = lower.endsWith('.mp4') || lower.endsWith('.mov') ? 'video' : 'file';
    try {
      final msg = await repo.sendAttachmentMessage(conversationId: conversationId, type: type, file: File(path));
      onSent(msg);
    } catch (e) {
      onError(e.toString());
    }
  }

  static Future<void> _shareLocation(BuildContext context, {required MessagingRepository repo, required int conversationId, required AttachmentSent onSent, required void Function(String) onError}) async {
    if (!await _ensurePermission(Permission.locationWhenInUse)) {
      onError('Location permission denied');
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      final url = 'https://www.google.com/maps?q=${pos.latitude},${pos.longitude}';
      final msg = await repo.sendAttachmentMessage(
        conversationId: conversationId,
        type: 'location',
        body: 'Shared location',
        attachments: [
          {'type': 'location', 'latitude': pos.latitude, 'longitude': pos.longitude, 'url': url},
        ],
      );
      onSent(msg);
    } catch (e) {
      onError(e.toString());
    }
  }

  static Future<void> _shareContact(BuildContext context, {required MessagingRepository repo, required int conversationId, required AttachmentSent onSent, required void Function(String) onError}) async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Share contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone'), keyboardType: TextInputType.phone),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    final phone = phoneCtrl.text.trim();
    if (name.isEmpty || phone.isEmpty) {
      onError('Name and phone are required');
      return;
    }
    try {
      final msg = await repo.sendAttachmentMessage(
        conversationId: conversationId,
        type: 'contact',
        attachments: [{'type': 'contact', 'name': name, 'phone': phone}],
      );
      onSent(msg);
    } catch (e) {
      onError(e.toString());
    }
  }

  static Future<void> _createPoll(BuildContext context, {required MessagingRepository repo, required int conversationId, required AttachmentSent onSent, required void Function(String) onError}) async {
    final qCtrl = TextEditingController();
    final optCtrl = TextEditingController();
    final options = <String>[];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Create poll'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: qCtrl, decoration: const InputDecoration(labelText: 'Question')),
                const SizedBox(height: 8),
                TextField(
                  controller: optCtrl,
                  decoration: InputDecoration(
                    labelText: 'Add option',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        final t = optCtrl.text.trim();
                        if (t.isNotEmpty) {
                          setLocal(() {
                            options.add(t);
                            optCtrl.clear();
                          });
                        }
                      },
                    ),
                  ),
                ),
                ...options.map((o) => ListTile(dense: true, title: Text(o))),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final question = qCtrl.text.trim();
    if (question.isEmpty || options.length < 2) {
      onError('Enter a question and at least two options');
      return;
    }
    try {
      final pollAtt = {
        'type': 'poll',
        'question': question,
        'options': options.asMap().entries.map((e) => {'id': '${e.key + 1}', 'text': e.value, 'votes': 0}).toList(),
        'votes': <String, dynamic>{},
        'multiple': false,
        'closed': false,
      };
      final msg = await repo.sendAttachmentMessage(
        conversationId: conversationId,
        type: 'text',
        body: question,
        attachments: [pollAtt],
      );
      onSent(msg);
    } catch (e) {
      onError(e.toString());
    }
  }
}
