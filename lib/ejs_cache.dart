import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'log.dart';

/// A localhost HTTP server that serves EmulatorJS's files (`/emulatorjs/*`) from
/// an on-disk cache, fetching from the home server on a miss. Point the site at
/// it with `window.__ssEjsBase` and games play with no network once their core
/// has been fetched once.
class EjsCache {
  EjsCache({required this.upstreamBase});

  /// e.g. `https://shadow-1.tail51f9d6.ts.net/` — `/emulatorjs/...` is appended.
  String upstreamBase;

  HttpServer? _server;
  Directory? _dir;
  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 12);

  int? get port => _server?.port;
  String? get baseUrl =>
      port == null ? null : 'http://127.0.0.1:$port/emulatorjs/';

  Future<void> start() async {
    if (_server != null) return;
    _dir = Directory('${(await getApplicationSupportDirectory()).path}/ejs');
    await _dir!.create(recursive: true);
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    logEvent('ejs cache server on :${_server!.port}');
    _server!.listen(_handle, onError: (e) => logEvent('ejs server error: $e'));
  }

  Future<void> dispose() async {
    await _server?.close(force: true);
    _server = null;
    _http.close(force: true);
  }

  // --- request handling --------------------------------------------------

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers.set('Access-Control-Allow-Origin', '*');
    if (req.method == 'OPTIONS') {
      res.statusCode = 204;
      await res.close();
      return;
    }

    // /emulatorjs/<rel>
    final rel = req.uri.path.replaceFirst(RegExp(r'^/emulatorjs/'), '');
    if (rel.isEmpty || rel.contains('..')) {
      res.statusCode = 400;
      await res.close();
      return;
    }

    final file = File('${_dir!.path}/$rel');
    try {
      if (await file.exists()) {
        await _serveFile(res, file, rel);
        return;
      }
      // Miss — pull from upstream, tee to disk.
      final upstream = Uri.parse(
        '${upstreamBase.replaceAll(RegExp(r'/$'), '')}/emulatorjs/$rel',
      );
      final upRes = await _http
          .getUrl(upstream)
          .then((r) => r.close())
          .timeout(const Duration(seconds: 20));
      if (upRes.statusCode != 200) {
        res.statusCode = upRes.statusCode;
        await res.close();
        return;
      }
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.part');
      final sink = tmp.openWrite();
      res.headers.contentType = _typeFor(rel);
      await for (final chunk in upRes) {
        sink.add(chunk);
        res.add(chunk);
      }
      await sink.close();
      await tmp.rename(file.path);
      await res.close();
      logEvent('ejs cached $rel');
    } on TimeoutException {
      res.statusCode = 504;
      await res.close();
    } catch (e) {
      // Offline and not cached, or a write error.
      if (!res.headers.persistentConnection || res.connectionInfo != null) {
        try {
          res.statusCode = 502;
          await res.close();
        } catch (_) {}
      }
    }
  }

  Future<void> _serveFile(HttpResponse res, File file, String rel) async {
    res.headers.contentType = _typeFor(rel);
    res.headers.set('Cache-Control', 'public, max-age=31536000, immutable');
    await res.addStream(file.openRead());
    await res.close();
  }

  ContentType _typeFor(String rel) {
    final ext = rel.contains('.') ? rel.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'js' => ContentType('text', 'javascript', charset: 'utf-8'),
      'mjs' => ContentType('text', 'javascript', charset: 'utf-8'),
      'wasm' => ContentType('application', 'wasm'),
      'json' => ContentType('application', 'json', charset: 'utf-8'),
      'css' => ContentType('text', 'css', charset: 'utf-8'),
      'data' => ContentType('application', 'octet-stream'),
      'mem' => ContentType('application', 'octet-stream'),
      'png' => ContentType('image', 'png'),
      _ => ContentType('application', 'octet-stream'),
    };
  }

  // --- management -------------------------------------------------------

  Future<int> cacheBytes() async {
    if (_dir == null || !await _dir!.exists()) return 0;
    var total = 0;
    await for (final e in _dir!.list(recursive: true)) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  Future<void> clear() async {
    if (_dir != null && await _dir!.exists()) {
      await _dir!.delete(recursive: true);
      await _dir!.create(recursive: true);
    }
    logEvent('ejs cache cleared');
  }

  /// Pre-fetch the shell + a set of core `.data` files so they're available
  /// offline without playing each system first. [cores] are EmulatorJS core
  /// ids (e.g. "fceumm", "snes9x").
  Future<void> prewarm(
    List<String> cores, {
    void Function(int done, int total)? onProgress,
  }) async {
    final shell = [
      'loader.js',
      'emulator.min.js',
      'emulator.min.css',
      'compression/extract.js',
      'localization/en-US.json',
    ];
    final wanted = [
      ...shell,
      for (final c in cores) 'cores/$c-wasm.data',
    ];
    var done = 0;
    for (final rel in wanted) {
      final file = File('${_dir!.path}/$rel');
      if (!await file.exists()) {
        try {
          final u = Uri.parse(
            '${upstreamBase.replaceAll(RegExp(r'/$'), '')}/emulatorjs/$rel',
          );
          final r = await _http
              .getUrl(u)
              .then((x) => x.close())
              .timeout(const Duration(seconds: 45));
          if (r.statusCode == 200) {
            await file.parent.create(recursive: true);
            await r.pipe(file.openWrite());
          }
        } catch (_) {/* skip, will fetch on demand later */}
      }
      onProgress?.call(++done, wanted.length);
    }
    logEvent('ejs prewarm done (${cores.length} cores)');
  }
}
