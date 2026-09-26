import 'dart:async';
import 'dart:convert';

import 'package:dart_pusher_channels/dart_pusher_channels.dart';
import 'package:flutter/foundation.dart';

import '../../config/api_config.dart';
import '../api/api_client.dart';
import '../auth/auth_repository.dart';
import '../models/api_models.dart';

/// Real-time messaging event from a subscribed conversation channel.
class MessagingBroadcastEvent {
  MessagingBroadcastEvent({
    required this.conversationId,
    required this.eventName,
    required this.data,
  });

  final int conversationId;
  final String eventName;
  final Map<String, dynamic> data;
}

/// Maintains a Reverb/Pusher WebSocket and private conversation subscriptions.
class MessagingBroadcastService extends ChangeNotifier {
  static const _conversationEvents = [
    'message.sent',
    'message.updated',
    'messaging.call',
    'user.typing',
    'conversation.read',
  ];

  final _events = StreamController<MessagingBroadcastEvent>.broadcast();
  Stream<MessagingBroadcastEvent> get events => _events.stream;

  PusherChannelsClient? _client;
  StreamSubscription<void>? _connectionSub;
  final Map<int, PrivateChannel> _channels = {};
  final Map<int, List<StreamSubscription<ChannelReadEvent>>> _bindings = {};
  final Map<int, String> _conversationTitles = {};
  final Set<int> _desiredConversationIds = {};

  bool _connecting = false;
  bool _connected = false;
  String? _lastError;

  bool get isConnected => _connected;
  String? get lastError => _lastError;

  String? _token;
  int? _businessUnitId;
  int? _teamId;

  Future<void> connect(AuthRepository auth) async {
    if (!auth.isAuthenticated || auth.token == null) {
      await disconnect();
      return;
    }

    final newToken = auth.token;
    final tokenChanged = _token != null && _token != newToken;
    _token = newToken;
    _businessUnitId = auth.businessUnitId;
    _teamId = auth.teamId;

    if (!tokenChanged && (_connected || _connecting)) return;
    if (tokenChanged && _client != null) {
      await disconnect(notify: false);
    }

    if (_connecting) return;
    _connecting = true;
    _lastError = null;
    notifyListeners();

    try {
      final client = auth.client();
      final config = await _fetchConfig(client);
      if (config == null || config.enabled != true) {
        _lastError = 'Broadcasting disabled on server';
        debugPrint('[MessagingBroadcast] $_lastError');
        await disconnect();
        return;
      }

      await disconnect(notify: false);

      final wsScheme = config.scheme == 'https' ? 'wss' : 'ws';
      final options = PusherChannelsOptions.fromHost(
        scheme: wsScheme,
        host: config.host!,
        key: config.key!,
        port: config.port ?? (wsScheme == 'wss' ? 443 : 80),
      );

      final pusherClient = PusherChannelsClient.websocket(
        options: options,
        connectionErrorHandler: (exception, trace, refresh) {
          _lastError = exception.toString();
          debugPrint('[MessagingBroadcast] connection error: $exception');
          _connected = false;
          notifyListeners();
          refresh();
        },
        minimumReconnectDelayDuration: const Duration(seconds: 2),
      );

      _client = pusherClient;
      _connectionSub = pusherClient.onConnectionEstablished.listen((_) {
        debugPrint('[MessagingBroadcast] WebSocket connected');
        _connected = true;
        _lastError = null;
        notifyListeners();
        _applyDesiredSubscriptions();
      });

      await pusherClient.connect();
      _applyDesiredSubscriptions();
    } catch (e, st) {
      _lastError = e.toString();
      debugPrint('[MessagingBroadcast] connect failed: $e\n$st');
      _connected = false;
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnect({bool notify = true}) async {
    _connecting = false;
    _connected = false;
    await _connectionSub?.cancel();
    _connectionSub = null;

    for (final subs in _bindings.values) {
      for (final sub in subs) {
        await sub.cancel();
      }
    }
    _bindings.clear();
    _channels.clear();

    final client = _client;
    _client = null;
    if (client != null) {
      try {
        client.dispose();
      } catch (_) {}
    }

    if (notify) notifyListeners();
  }

  /// Subscribe to conversation channels (idempotent). Pass titles for incoming-call UI.
  void syncConversations(Iterable<ConversationSummary> conversations) {
    for (final conv in conversations) {
      if (conv.isArchived) continue;
      _conversationTitles[conv.id] = conv.title;
      _desiredConversationIds.add(conv.id);
    }
    _applyDesiredSubscriptions();
  }

  void subscribeConversation(int conversationId, {String? title}) {
    if (title != null && title.isNotEmpty) {
      _conversationTitles[conversationId] = title;
    }
    _desiredConversationIds.add(conversationId);
    _applyDesiredSubscriptions();
  }

  void unsubscribeConversation(int conversationId) {
    if (!_desiredConversationIds.remove(conversationId)) return;
    _teardownChannel(conversationId);
  }

  String? conversationTitle(int conversationId) => _conversationTitles[conversationId];

  void _applyDesiredSubscriptions() {
    final client = _client;
    if (client == null) return;

    final toRemove = _channels.keys.where((id) => !_desiredConversationIds.contains(id)).toList();
    for (final id in toRemove) {
      _teardownChannel(id);
    }

    for (final id in _desiredConversationIds) {
      if (_channels.containsKey(id)) continue;
      _setupChannel(id);
    }

    if (_connected) {
      _resubscribeAll();
    }
  }

  void _resubscribeAll() {
    for (final entry in _channels.entries) {
      final channel = entry.value;
      channel.subscribeIfNotUnsubscribed();
      debugPrint('[MessagingBroadcast] subscribed conversation.${entry.key}');
    }
  }

  void _setupChannel(int conversationId) {
    final client = _client;
    if (client == null) return;

    final channelName = 'private-conversation.$conversationId';
    final channel = client.privateChannel(
      channelName,
      authorizationDelegate: _authDelegate(),
    );
    _channels[conversationId] = channel;

    final subs = <StreamSubscription<ChannelReadEvent>>[];
    subs.add(
      channel.onAuthenticationSubscriptionFailed().listen((event) {
        _lastError = 'Auth failed for conversation.$conversationId';
        debugPrint('[MessagingBroadcast] $_lastError: ${event.data}');
        notifyListeners();
      }),
    );
    for (final eventName in _conversationEvents) {
      subs.add(channel.bind(eventName).listen((event) {
        final data = _parseEventData(event.data);
        _events.add(MessagingBroadcastEvent(
          conversationId: conversationId,
          eventName: eventName,
          data: data,
        ));
      }));
    }
    _bindings[conversationId] = subs;

    if (_connected) {
      channel.subscribeIfNotUnsubscribed();
    }
  }

  void _teardownChannel(int conversationId) {
    final subs = _bindings.remove(conversationId);
    if (subs != null) {
      for (final sub in subs) {
        unawaited(sub.cancel());
      }
    }
    final channel = _channels.remove(conversationId);
    channel?.unsubscribe();
  }

  EndpointAuthorizableChannelTokenAuthorizationDelegate<PrivateChannelAuthorizationData>
      _authDelegate() {
    final token = _token ?? '';
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
    if (_businessUnitId != null) {
      headers['X-Business-Unit-Id'] = _businessUnitId.toString();
    }
    if (_teamId != null) {
      headers['X-Team-Id'] = _teamId.toString();
    }

    return EndpointAuthorizableChannelTokenAuthorizationDelegate.forPrivateChannel(
      authorizationEndpoint: Uri.parse('${ApiConfig.defaultBaseUrl}/broadcasting/auth'),
      headers: headers,
    );
  }

  Future<_BroadcastConfig?> _fetchConfig(ApiClient client) async {
    final json = await client.getJson('messaging/broadcast-config');
    final data = json['data'];
    if (data is! Map<String, dynamic>) return null;
    return _BroadcastConfig.fromJson(data);
  }

  static Map<String, dynamic> _parseEventData(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return {};
  }

  @override
  void dispose() {
    unawaited(disconnect(notify: false));
    _events.close();
    super.dispose();
  }
}

class _BroadcastConfig {
  _BroadcastConfig({
    required this.enabled,
    this.key,
    this.host,
    this.port,
    this.scheme,
  });

  factory _BroadcastConfig.fromJson(Map<String, dynamic> json) {
    return _BroadcastConfig(
      enabled: json['enabled'] == true,
      key: json['key'] as String?,
      host: json['host'] as String?,
      port: json['port'] as int?,
      scheme: json['scheme'] as String?,
    );
  }

  final bool enabled;
  final String? key;
  final String? host;
  final int? port;
  final String? scheme;
}
