// Stub file for non-web platforms
// This file is used when dart.library.html is not available (mobile platforms)
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketHelper {
  static dynamic getWindowLocation() => null;
  
  // This will never be called on non-web platforms, but we need it for type compatibility
  static WebSocketChannel connectWebSocket(String uri) {
    throw UnsupportedError('WebSocket web implementation not available on this platform');
  }
}

