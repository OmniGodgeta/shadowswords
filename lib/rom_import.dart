import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Extension → EmulatorJS system id. Mirrors `EXT_CORE` in the site's app.js;
/// keep in sync when that changes.
const Map<String, String> kExtCore = {
  'nes': 'nes', 'fds': 'nes', 'unf': 'nes',
  'sfc': 'snes', 'smc': 'snes', 'fig': 'snes', 'bs': 'snes', 'swc': 'snes',
  'gb': 'gb', 'gbc': 'gb', 'gba': 'gba', 'srl': 'gba',
  'n64': 'n64', 'z64': 'n64', 'v64': 'n64',
  'md': 'segaMD', 'gen': 'segaMD', 'smd': 'segaMD',
  'sms': 'segaMS', 'sg': 'segaMS', '32x': 'sega32x', 'gg': 'segaGG',
  'pce': 'pce', 'sgx': 'pce',
  'a26': 'atari2600', 'a52': 'atari5200', 'a78': 'atari7800',
  'lnx': 'lynx', 'j64': 'jaguar', 'jag': 'jaguar',
  'ws': 'ws', 'wsc': 'ws', 'ngp': 'ngp', 'ngc': 'ngp', 'vb': 'vb',
  'col': 'coleco', 'int': 'coleco',
  'd64': 'c64', 't64': 'c64', 'crt': 'c64', 'prg': 'c64',
  'iso': 'psx', 'cue': 'psx', 'chd': 'psx', 'pbp': 'psx', 'bin': 'psx',
  'zip': 'arcade',
};

/// Handles "Open ROM with ShadowSwords" — a shared/opened file is served from a
/// throwaway localhost HTTP server and handed to the web player, which pulls it
/// into a Blob, stashes it in IndexedDB (`ssw-arcade` store `rom`, key `upload`)
/// and navigates to `#/play/upload/<name>`.
class RomImport {
  RomImport({required this.runJs, required this.onStatus});

  /// Runs a snippet of JavaScript in the WebView. Returns false if the page
  /// isn't ready yet (the caller should retry after the next page load).
  final Future<bool> Function(String js) runJs;
  final void Function(String message) onStatus;

  StreamSubscription<List<SharedMediaFile>>? _sub;
  HttpServer? _server;
  String? _pendingJs;

  void start() {
    ReceiveSharingIntent.instance.getInitialMedia().then(_handle).catchError((_) {});
    _sub = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(_handle, onError: (_) {});
  }

  /// Call from the WebView's onPageFinished so a cold-start import can complete.
  void onPageReady() {
    final js = _pendingJs;
    if (js != null) {
      _pendingJs = null;
      runJs(js);
    }
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _server?.close(force: true);
  }

  Future<void> _handle(List<SharedMediaFile> files) async {
    if (files.isEmpty) return;
    final path = files.first.path;
    final name = path.split('/').last;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final core = kExtCore[ext];
    ReceiveSharingIntent.instance.reset();

    if (core == null) {
      onStatus("ShadowSwords can't play a .$ext file");
      return;
    }
    Uint8List bytes;
    try {
      bytes = await File(path).readAsBytes();
    } catch (e) {
      onStatus("Couldn't read that file");
      return;
    }
    await _serve(name, core, bytes);
  }

  Future<void> _serve(String name, String core, Uint8List bytes) async {
    await _server?.close(force: true);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((req) async {
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType('application', 'octet-stream')
        ..headers.set('Access-Control-Allow-Origin', '*')
        ..headers.set('Cache-Control', 'no-store')
        ..add(bytes);
      await req.response.close();
      // one-shot: the player only fetches once.
      Future<void>.delayed(
        const Duration(seconds: 20),
        () => server.close(force: true),
      );
    });

    final n = jsonEncode(name);
    final c = jsonEncode(core);
    final js = '''
      (async function () {
        try {
          var resp = await fetch('http://127.0.0.1:${server.port}/rom');
          var blob = await resp.blob();
          var db = await new Promise(function (res, rej) {
            var r = indexedDB.open('ssw-arcade');
            r.onupgradeneeded = function (e) {
              var d = e.target.result;
              if (!d.objectStoreNames.contains('rom')) d.createObjectStore('rom');
              if (!d.objectStoreNames.contains('romcache')) d.createObjectStore('romcache');
            };
            r.onsuccess = function () { res(r.result); };
            r.onerror = function () { rej(r.error); };
          });
          await new Promise(function (res, rej) {
            var tx = db.transaction('rom', 'readwrite');
            tx.objectStore('rom').put({ name: $n, blob: blob, core: $c }, 'upload');
            tx.oncomplete = res;
            tx.onerror = function () { rej(tx.error); };
          });
          db.close();
          location.hash = '#/play/upload/' + encodeURIComponent($n);
        } catch (e) {
          if (window.SSRom) SSRom.postMessage('error: ' + e);
        }
      })();
    ''';

    onStatus('Loading $name…');
    final ran = await runJs(js);
    if (!ran) _pendingJs = js;
  }
}
