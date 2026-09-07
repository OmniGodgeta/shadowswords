import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'rom_import.dart';
import 'settings.dart';
import 'settings_screen.dart';
import 'wol.dart';

/// Default library location; the live value comes from [AppSettings.siteUrl].
/// Overridable at build time with --dart-define=SITE_URL=...
const String kSiteUrl = String.fromEnvironment(
  'SITE_URL',
  defaultValue: kTailnetUrl,
);

const String kGithubRepo = 'OmniGodgeta/shadowswords';
const MethodChannel _native = MethodChannel('shadowswords/native');

/// Lets background helpers surface a snackbar.
final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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

late final AppSettings settings;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  settings = await AppSettings.load();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ShadowSwordsApp());
}

class ShadowSwordsApp extends StatelessWidget {
  const ShadowSwordsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShadowSwords',
      scaffoldMessengerKey: messengerKey,
      navigatorKey: navigatorKey,
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
  late final RomImport _romImport;
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  String _siteHost = Uri.parse(kSiteUrl).host;
  int _progress = 0;
  bool _loading = true;
  bool _hasError = false;
  bool _playing = false;
  DateTime? _lastBackPress;
  String? _updateVersion;
  bool _updateDismissed = false;
  String? _pendingHash; // from a shortcut / deep link, applied once ready
  bool _firstLoadDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _siteHost = Uri.parse(settings.siteUrl).host;
    _initWebView();
    _initShortcuts();
    _initDeepLinks();
    _initConnectivity();
    _initHomeWidget();
    _checkForUpdate();
    _romImport = RomImport(
      runJs: (js) async {
        if (!_firstLoadDone) return false;
        await _controller.runJavaScript(js);
        return true;
      },
      onStatus: (m) => messengerKey.currentState
        ?..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(m))),
    )..start();
    if (settings.keepScreenOnAlways) WakelockPlus.enable();
    if (settings.wolEnabled) _wake();
  }

  Future<void> _wake() async {
    if (settings.wolMac.trim().isEmpty) return;
    await sendMagicPacket(settings.wolMac, broadcast: settings.wolBroadcast);
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
      ..addJavaScriptChannel(
        'SSRom',
        onMessageReceived: (msg) {
          if (msg.message.startsWith('error:')) {
            messengerKey.currentState
              ?..clearSnackBars()
              ..showSnackBar(
                const SnackBar(content: Text("Couldn't load that ROM")),
              );
          }
        },
      )
      ..addJavaScriptChannel(
        'SSMedia',
        onMessageReceived: (msg) => _onMusicState(msg.message == 'playing'),
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
            _injectMediaWatch();
            if (settings.hapticControls) _injectHaptics();
            if (!_firstLoadDone) {
              _firstLoadDone = true;
              _applyPendingHash();
            }
            _romImport.onPageReady();
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
      ..loadRequest(Uri.parse(settings.siteUrl));
  }

  // --- external links -------------------------------------------------------

  void _patchExternalLinks() {
    _controller.runJavaScript('''
      (function () {
        if (window.__ssPatched) return;
        window.__ssPatched = true;
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

  // --- keep the web music player alive in the background ------------------

  bool _musicPlaying = false;

  void _injectMediaWatch() {
    _controller.runJavaScript('''
      (function () {
        if (window.__ssMedia) return;
        window.__ssMedia = true;
        function report() {
          var on = Array.prototype.some.call(
            document.querySelectorAll('audio'),
            function (m) { return !m.paused && !m.ended; });
          try { SSMedia.postMessage(on ? 'playing' : 'stopped'); } catch (e) {}
        }
        document.addEventListener('play', report, true);
        document.addEventListener('pause', function () { setTimeout(report, 200); }, true);
        document.addEventListener('ended', function () { setTimeout(report, 200); }, true);
      })();
    ''');
  }

  Future<void> _onMusicState(bool playing) async {
    if (playing == _musicPlaying) return;
    _musicPlaying = playing;
    try {
      await _native.invokeMethod(playing ? 'startMusic' : 'stopMusic');
    } catch (_) {}
  }

  // --- haptics on the emulator's touch controls ----------------------------

  void _injectHaptics() {
    _controller.runJavaScript('''
      (function () {
        if (window.__ssHaptics || !navigator.vibrate) return;
        window.__ssHaptics = true;
        document.addEventListener('touchstart', function (e) {
          var t = e.target;
          if (t && t.closest && t.closest(
              '.ejs_button, .ejs_dpad, [class*="ejs_"] button, .ejs_context_menu_button')) {
            navigator.vibrate(8);
          }
        }, { passive: true, capture: true });
      })();
    ''');
  }

  // --- game-running detection: wake lock + rotation -----------------------

  static final RegExp _playingRe = RegExp(r'#/play/[^/]+/.+');

  void _onUrlChange(String url) {
    final playing = _playingRe.hasMatch(url);
    if (playing == _playing) return;
    setState(() => _playing = playing);
    if (playing) {
      WakelockPlus.enable();
      if (settings.autoLandscapeForGames) {
        SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      }
    } else {
      if (!settings.keepScreenOnAlways) WakelockPlus.disable();
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_playing || settings.keepScreenOnAlways) WakelockPlus.enable();
    } else if (state == AppLifecycleState.paused) {
      if (!settings.keepScreenOnAlways) WakelockPlus.disable();
    }
  }

  // --- shortcuts / deep links / widget -----------------------------------

  void _initShortcuts() {
    const actions = QuickActions();
    actions.initialize((type) {
      const map = {
        'play': '#/play',
        'random': '#/play/random',
        'movies': '#/movies',
      };
      if (type == 'settings') {
        _openSettings();
        return;
      }
      final hash = map[type];
      if (hash != null) _goHashOrPend(hash);
    });
    actions.setShortcutItems(const [
      ShortcutItem(type: 'play', localizedTitle: 'Play'),
      ShortcutItem(type: 'random', localizedTitle: 'Surprise me'),
      ShortcutItem(type: 'movies', localizedTitle: 'Movies'),
      ShortcutItem(type: 'settings', localizedTitle: 'Settings'),
    ]);
  }

  Future<void> _initDeepLinks() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handleLink(initial);
    } catch (_) {}
    _linkSub = _appLinks.uriLinkStream.listen(_handleLink, onError: (_) {});
  }

  void _handleLink(Uri uri) {
    String? hash;
    if (uri.scheme == 'shadowswords') {
      // shadowswords://play/nes/game.nes  ->  #/play/nes/game.nes
      final path = [uri.host, uri.path].join('').replaceAll(RegExp(r'^/+'), '');
      if (path.isNotEmpty) hash = '#/$path';
    } else if (uri.fragment.startsWith('/')) {
      hash = '#${uri.fragment}';
    }
    if (hash != null) _goHashOrPend(hash);
  }

  Future<void> _initHomeWidget() async {
    HomeWidget.widgetClicked.listen((uri) {
      if (uri != null) _handleLink(uri);
    });
    final launch = await HomeWidget.initiallyLaunchedFromHomeWidget();
    if (launch != null) _handleLink(launch);
  }

  void _goHashOrPend(String hash) {
    if (_firstLoadDone) {
      _navigateHash(hash);
    } else {
      _pendingHash = hash;
    }
  }

  void _applyPendingHash() {
    final h = _pendingHash;
    if (h != null) {
      _pendingHash = null;
      _navigateHash(h);
    }
  }

  void _navigateHash(String hash) {
    _controller.runJavaScript("location.hash = ${jsonEncode(hash)};");
  }

  // --- connectivity: auto-retry when the network returns ------------------

  void _initConnectivity() {
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online && _hasError) {
        if (settings.wolEnabled) _wake();
        _reload();
      }
    });
  }

  // --- update check -----------------------------------------------------

  Future<String?> _fetchLatestNewer() async {
    try {
      final resp = await http.get(
        Uri.parse('https://api.github.com/repos/$kGithubRepo/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final tag = (jsonDecode(resp.body)['tag_name'] as String?)
          ?.replaceFirst(RegExp('^v'), '');
      if (tag == null) return null;
      final current = (await PackageInfo.fromPlatform()).version;
      return isVersionNewer(tag, current) ? tag : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _checkForUpdate() async {
    final newer = await _fetchLatestNewer();
    if (newer != null && mounted) setState(() => _updateVersion = newer);
  }

  // --- settings / actions ---------------------------------------------

  Future<void> _openSettings() async {
    final urlBefore = settings.siteUrl;
    final reload = await navigatorKey.currentState?.push<bool>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          settings: settings,
          onCheckUpdate: _fetchLatestNewer,
          onClearCache: () async {
            await _controller.clearCache();
            await WebViewCookieManager().clearCookies();
          },
        ),
        fullscreenDialog: true,
      ),
    );
    if (!mounted) return;
    setState(() => _siteHost = Uri.parse(settings.siteUrl).host);
    if (settings.keepScreenOnAlways) {
      WakelockPlus.enable();
    } else if (!_playing) {
      WakelockPlus.disable();
    }
    if (reload == true || settings.siteUrl != urlBefore) _reload();
  }

  Future<void> _screenshot() async {
    try {
      final path = await _native.invokeMethod<String>('screenshot');
      messengerKey.currentState
        ?..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(path != null ? 'Saved to Pictures/ShadowSwords' : 'Screenshot failed'),
        ));
    } catch (_) {
      messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Screenshot failed')),
      );
    }
  }

  Future<void> _reload() async {
    setState(() {
      _hasError = false;
      _loading = true;
    });
    await _controller.loadRequest(Uri.parse(settings.siteUrl));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSub?.cancel();
    _connSub?.cancel();
    WakelockPlus.disable();
    _romImport.dispose();
    if (_musicPlaying) _native.invokeMethod('stopMusic').catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final messenger = ScaffoldMessenger.of(context);
        if (_playing) {
          await _controller.runJavaScript(
            "(window.exitPlayer||function(){location.hash='#/play';location.reload();})();",
          );
          return;
        }
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
          child: Column(
            children: [
              if (_updateVersion != null && !_updateDismissed)
                _UpdateBanner(
                  version: _updateVersion!,
                  onOpen: () => _openExternal(
                    'https://github.com/$kGithubRepo/releases/latest',
                  ),
                  onDismiss: () => setState(() => _updateDismissed = true),
                ),
              Expanded(
                child: _hasError
                    ? _ErrorView(
                        onRetry: () async {
                          if (settings.wolEnabled) await _wake();
                          await _reload();
                        },
                        onSettings: _openSettings,
                        onOpenTailscale: () =>
                            _openExternal('com.tailscale.ipn://'),
                      )
                    : Listener(
                        onPointerDown: _onPointerDown,
                        onPointerUp: _onPointerUp,
                        behavior: HitTestBehavior.translucent,
                        child: Stack(
                          children: [
                            WebViewWidget(controller: _controller),
                            if (_loading)
                              LinearProgressIndicator(
                                value: _progress == 0 ? null : _progress / 100,
                                minHeight: 2,
                                backgroundColor: Colors.transparent,
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- power-user gestures ------------------------------------------------
  // Two-finger long-press -> Settings. Three-finger tap -> screenshot.
  final Set<int> _pointers = {};
  Timer? _twoFingerTimer;
  DateTime? _threeFingerAt;

  void _onPointerDown(PointerDownEvent e) {
    _pointers.add(e.pointer);
    if (_pointers.length == 2) {
      _twoFingerTimer?.cancel();
      _twoFingerTimer = Timer(const Duration(milliseconds: 650), () {
        if (_pointers.length == 2) {
          HapticFeedback.mediumImpact();
          _openSettings();
        }
      });
    }
    if (_pointers.length == 3) {
      _threeFingerAt = DateTime.now();
      _twoFingerTimer?.cancel();
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    _pointers.remove(e.pointer);
    _twoFingerTimer?.cancel();
    if (_threeFingerAt != null &&
        DateTime.now().difference(_threeFingerAt!) <
            const Duration(milliseconds: 500) &&
        _pointers.isEmpty) {
      _threeFingerAt = null;
      HapticFeedback.selectionClick();
      _screenshot();
    }
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
  const _ErrorView({
    required this.onRetry,
    required this.onSettings,
    required this.onOpenTailscale,
  });

  final Future<void> Function() onRetry;
  final VoidCallback onSettings;
  final VoidCallback onOpenTailscale;

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
              'Connect Tailscale and make sure the home server is on. '
              "It'll retry on its own when you're back online.",
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenTailscale,
                  icon: const Icon(Icons.vpn_key_rounded),
                  label: const Text('Tailscale'),
                ),
                OutlinedButton.icon(
                  onPressed: onSettings,
                  icon: const Icon(Icons.settings_rounded),
                  label: const Text('Settings'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
