import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/html.dart' as html_ws;
import 'dart:html' as html;
import '../../core/constants/app_constants.dart';

class RealtimeService {
  WebSocketChannel? _channel;
  final _events = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get events => _events.stream;

  bool get isConnected => _channel != null;

  void connectApprovals({String? token}) {
    final uri = _computeWsUri(path: AppConfig.wsApprovalsPath, token: token);
    try {
      if (kIsWeb) {
        // Some servers require explicit upgrade; if handshake returns 200,
        // this will throw and we silently disable realtime.
        _channel = html_ws.HtmlWebSocketChannel.connect(uri.toString());
      } else {
        _channel = WebSocketChannel.connect(uri);
      }
    } catch (_) {
      // Silently fail; app will continue using REST
      _channel = null;
      return;
    }
    _channel!.stream.listen((data) {
      try {
        final obj = data is String ? jsonDecode(data) : data as Map<String, dynamic>;
        _events.add(Map<String, dynamic>.from(obj));
      } catch (_) {
        // ignore malformed messages
      }
    }, onError: (_) {
      disconnect();
    }, onDone: () {
      disconnect();
    });
  }

  void send(Map<String, dynamic> message) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(message));
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }

  Uri _computeWsUri({required String path, String? token}) {
    if (kIsWeb) {
      final isHttps = html.window.location.protocol == 'https:';
      final scheme = isHttps ? 'wss' : 'ws';
      final host = html.window.location.hostname ?? '';
      final port = html.window.location.port ?? '';
      return Uri(
        scheme: scheme,
        host: host.isEmpty ? 'localhost' : host,
        port: int.tryParse(port) ?? (isHttps ? 443 : 80),
        path: path,
        queryParameters: {
          if (token != null && token.isNotEmpty) 'token': token,
        },
      );
    }
    // Non-web: use configured base
    final base = Uri.parse(AppConfig.wsBaseUrl);
    return Uri(
      scheme: base.scheme.isEmpty ? 'ws' : base.scheme,
      host: base.host.isEmpty ? 'localhost' : base.host,
      port: base.hasPort ? base.port : (base.scheme == 'wss' ? 443 : 80),
      path: path,
      queryParameters: {
        if (token != null && token.isNotEmpty) 'token': token,
      },
    );
  }
}


