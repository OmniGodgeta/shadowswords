import 'dart:io';
import 'dart:typed_data';

/// Sends a Wake-on-LAN "magic packet" for [mac] as a UDP broadcast.
///
/// Works only on the same L2 network as the target (i.e. the phone on the home
/// Wi-Fi) — magic packets don't route over Tailscale. Returns null on success
/// or a short error string.
Future<String?> sendMagicPacket(
  String mac, {
  String broadcast = '255.255.255.255',
  List<int> ports = const [9, 7],
}) async {
  final bytes = _macBytes(mac);
  if (bytes == null) return 'Bad MAC address';

  // 6 × 0xFF, then the MAC repeated 16 times.
  final packet = Uint8List(102);
  for (var i = 0; i < 6; i++) {
    packet[i] = 0xFF;
  }
  for (var i = 0; i < 16; i++) {
    packet.setRange(6 + i * 6, 12 + i * 6, bytes);
  }

  RawDatagramSocket? sock;
  try {
    sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    sock.broadcastEnabled = true;
    final addr = InternetAddress.tryParse(broadcast);
    if (addr == null) return 'Bad broadcast address';
    for (final port in ports) {
      sock.send(packet, addr, port);
    }
    return null;
  } on SocketException catch (e) {
    return e.message;
  } catch (e) {
    return '$e';
  } finally {
    sock?.close();
  }
}

Uint8List? _macBytes(String mac) {
  final parts = mac.trim().split(RegExp(r'[:\-.\s]')).where((s) => s.isNotEmpty);
  final hex = parts.join();
  if (hex.length != 12) return null;
  final out = Uint8List(6);
  for (var i = 0; i < 6; i++) {
    final b = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    if (b == null) return null;
    out[i] = b;
  }
  return out;
}
