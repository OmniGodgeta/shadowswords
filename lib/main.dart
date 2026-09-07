import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// The site this app wraps. Points at the self-hosted copy on the user's
/// tailnet (arcade-server), which serves the site and the ROMs from the same
/// origin. Overridable at build time with --dart-define=SITE_URL=...
const String kSiteUrl = String.fromEnvironment(
  'SITE_URL',
  defaultValue: 'https://shadow-1.tail51f9d6.ts.net/',
);

const String kGithubRepo = 'OmniGodgeta/shadowswords';

/// True when semver [a] is strictly newer than [b] (compares major.minor.patch).
bool isVersionNewer(String a, String b) {
  final pa = a.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
  final pb = b.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  // Browsing is a portrait, mobile-first layout; games unlock rotation.
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ShadowSwordsApp());
}

class ShadowSwordsApp extends StatelessWidget {
  const ShadowSwordsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShadowSwords',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6D28D9),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const WebShell(),
    );
  }
}

class WebShell extends StatefulWidget {
  const WebShell({super.key});

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> with WidgetsBindingObserver {
  late final WebViewController _controller;
  final String _siteHost = Uri.parse(kSiteUrl).host;

  int _progress = 0;
  bool _loading = true;
  bool _hasError = false;
  bool _playing = false;
  DateTime? _lastBackPress;
  String? _updateVersion; // set when a newer GitHub release exists
  bool _updateDismissed = false;
  String? _pendingHash; // from an app shortcut, applied once the page is ready
  bool _firstLoadDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initWebView();
    _initShortcuts();
    _checkForUpdate();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B0B0F))
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36 '
        'ShadowSwordsApp',
      )
      ..addJavaScriptChannel(
        'SSExternal',
        onMessageReceived: (msg) => _openExternal(msg.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => setState(() => _progress = p),
          onPageStarted: (_) => setState(() {
            _loading = true;
            _hasError = false;
          }),
          onPageFinished: (_) {
            setState(() => _loading = false);
            _patchExternalLinks();
            if (!_firstLoadDone) {
              _firstLoadDone = true;
              _applyPendingHash();
            }
          },
          onUrlChange: (change) => _onUrlChange(change.url ?? ''),
          onNavigationRequest: (req) {
            final host = Uri.tryParse(req.url)?.host ?? '';
            if (host.isNotEmpty && host != _siteHost) {
              _openExternal(req.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) {
              setState(() {
                _hasError = true;
                _loading = false;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(kSiteUrl));
  }

  // --- external links (target=_blank / window.open) --------------------------

  void _patchExternalLinks() {
    _controller.runJavaScript('''
      (function () {
        if (window.__ssPatched) return;
        window.__ssPatched = true;
        var nativeOpen = window.open;
        window.open = function (u) {
          try { if (u) SSExternal.postMessage('' + u); } catch (e) {}
          return null;
        };
        document.addEventListener('click', function (e) {
          var a = e.target && e.target.closest
              ? e.target.closest('a[target="_blank"], a[rel~="external"]') : null;
          if (a && a.href) {
            e.preventDefault();
            e.stopPropagation();
            SSExternal.postMessage(a.href);
          }
        }, true);
      })();
    ''');
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // --- game-running detection: wake lock + rotation --------------------------

  static final RegExp _playingRe = RegExp(r'#/play/[^/]+/.+');

  void _onUrlChange(String url) {
    final playing = _playingRe.hasMatch(url);
    if (playing == _playing) return;
    setState(() => _playing = playing);
    if (playing) {
      WakelockPlus.enable();
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    } else {
      WakelockPlus.disable();
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Don't hold the wake lock while backgrounded.
    if (state == AppLifecycleState.resumed && _playing) {
      WakelockPlus.enable();
    } else if (state == AppLifecycleState.paused) {
      WakelockPlus.disable();
    }
  }

  // --- app shortcuts (long-press launcher icon) -----------------------------

  void _initShortcuts() {
    const actions = QuickActions();
    actions.initialize((type) {
      const map = {
        'play': '#/play',
        'random': '#/play/random',
        'movies': '#/movies',
        'search': '#/q/',
      };
      final hash = map[type];
      if (hash == null) return;
      if (_firstLoadDone) {
        _navigateHash(hash);
      } else {
        _pendingHash = hash;
      }
    });
    actions.setShortcutItems(const [
      ShortcutItem(type: 'play', localizedTitle: 'Play'),
      ShortcutItem(type: 'random', localizedTitle: 'Surprise me'),
      ShortcutItem(type: 'movies', localizedTitle: 'Movies'),
      ShortcutItem(type: 'search', localizedTitle: 'Search'),
    ]);
  }

  void _applyPendingHash() {
    final h = _pendingHash;
    if (h != null) {
      _pendingHash = null;
      _navigateHash(h);
    }
  }

  void _navigateHash(String hash) {
    _controller.runJavaScript(
      "location.hash = ${jsonEncode(hash)};",
    );
  }

  // --- update check --------------------------------------------------------

  Future<void> _checkForUpdate() async {
    try {
      final resp = await http.get(
        Uri.parse('https://api.github.com/repos/$kGithubRepo/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return;
      final tag = (jsonDecode(resp.body)['tag_name'] as String?)
          ?.replaceFirst(RegExp('^v'), '');
      if (tag == null) return;
      final current = (await PackageInfo.fromPlatform()).version;
      if (isVersionNewer(tag, current) && mounted) {
        setState(() => _updateVersion = tag);
      }
    } catch (_) {
      // offline / rate-limited — no update prompt, no harm.
    }
  }

  Future<void> _reload() async {
    setState(() {
      _hasError = false;
      _loading = true;
    });
    await _controller.loadRequest(Uri.parse(kSiteUrl));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final messenger = ScaffoldMessenger.of(context);
        if (await _controller.canGoBack()) {
          await _controller.goBack();
          return;
        }
        final now = DateTime.now();
        if (_lastBackPress != null &&
            now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
          await SystemNavigator.pop();
          return;
        }
        _lastBackPress = now;
        messenger.clearSnackBars();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Press back again to exit'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0B0F),
        body: SafeArea(
          child: _hasError
              ? _ErrorView(onRetry: _reload)
              : Column(
                  children: [
                    if (_updateVersion != null && !_updateDismissed)
                      _UpdateBanner(
                        version: _updateVersion!,
                        onOpen: () => _openExternal(
                          'https://github.com/$kGithubRepo/releases/latest',
                        ),
                        onDismiss: () =>
                            setState(() => _updateDismissed = true),
                      ),
                    Expanded(
                      child: Stack(
                        children: [
                          // The WebView owns all scrolling and gestures.
                          WebViewWidget(controller: _controller),
                          if (_loading)
                            LinearProgressIndicator(
                              value:
                                  _progress == 0 ? null : _progress / 100,
                              minHeight: 2,
                              backgroundColor: Colors.transparent,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({
    required this.version,
    required this.onOpen,
    required this.onDismiss,
  });

  final String version;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
          child: Row(
            children: [
              const Icon(Icons.system_update_rounded, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'ShadowSwords $version is available — tap to download',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 56),
            const SizedBox(height: 16),
            Text(
              "Couldn't reach ShadowSwords",
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Make sure Tailscale is connected and the home server is on, '
              'then retry.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
