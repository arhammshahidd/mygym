// Web-specific implementation
import 'dart:html' as html;
import 'package:web_socket_channel/html.dart' as html_ws;
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketHelper {
  static dynamic getWindowLocation() => html.window.location;
  
  static WebSocketChannel connectWebSocket(String uri) {
    return html_ws.HtmlWebSocketChannel.connect(uri);
  }
}

