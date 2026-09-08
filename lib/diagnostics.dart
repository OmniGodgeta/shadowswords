import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Why the library page can't be reached, from most to least fundamental.
enum ReachFailure {
  /// No network at all.
  offline,

  /// Network is up but even the public internet isn't reachable.
  noInternet,

  /// Internet works, but the home server doesn't answer — usually Tailscale is
  /// off or the PC is asleep.
  serverUnreachable,

  /// The server answered but with an error.
  serverError,
}

extension ReachFailureText on ReachFailure {
  String get title => switch (this) {
        ReachFailure.offline => 'No connection',
        ReachFailure.noInternet => "Can't reach the internet",
        ReachFailure.serverUnreachable => "Can't reach the home server",
        ReachFailure.serverError => 'The home server had a problem',
      };

  String get detail => switch (this) {
        ReachFailure.offline =>
          'Turn on Wi-Fi or mobile data, then retry.',
        ReachFailure.noInternet =>
          "You're connected to a network but nothing's getting through. "
              'Check the connection, then retry.',
        ReachFailure.serverUnreachable =>
          'Connect Tailscale on this phone and make sure the home PC is awake. '
              "It'll retry on its own once it's reachable.",
        ReachFailure.serverError =>
          'The server answered but something went wrong on its side. '
              'Give it a minute and retry.',
      };
}

/// Works out *why* [siteUrl] can't be loaded so the error screen can say
/// something useful. Best-effort, ~10s worst case.
Future<ReachFailure> diagnoseReach(String siteUrl) async {
  final conn = await Connectivity().checkConnectivity();
  if (conn.every((c) => c == ConnectivityResult.none)) {
    return ReachFailure.offline;
  }

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    // A well-known 204 endpoint — fast, tiny, no body.
    final probe = await client
        .getUrl(Uri.parse('https://www.gstatic.com/generate_204'))
        .then((r) => r.close())
        .timeout(const Duration(seconds: 6));
    if (probe.statusCode >= 400) return ReachFailure.noInternet;
  } catch (_) {
    return ReachFailure.noInternet;
  }

  try {
    final res = await client
        .getUrl(Uri.parse(siteUrl))
        .then((r) => r.close())
        .timeout(const Duration(seconds: 8));
    if (res.statusCode >= 500) return ReachFailure.serverError;
    // 2xx/3xx here means it actually *is* reachable now — treat as transient.
    return ReachFailure.serverUnreachable;
  } on TimeoutException {
    return ReachFailure.serverUnreachable;
  } on SocketException {
    return ReachFailure.serverUnreachable;
  } catch (_) {
    return ReachFailure.serverUnreachable;
  } finally {
    client.close(force: true);
  }
}
