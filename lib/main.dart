import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// The site this app wraps. Points at the self-hosted copy on the user's
/// tailnet (arcade-server), which serves the site and the ROMs from the same
/// origin — so browsing, playing, and the movie library all work once the
/// phone has Tailscale connected. Overridable at build time with
/// --dart-define=SITE_URL=...
const String kSiteUrl = String.fromEnvironment(
  'SITE_URL',
  defaultValue: 'https://shadow-1.tail51f9d6.ts.net/',
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Fullscreen: hide the status and navigation bars; a swipe from the edge
  // brings them back briefly (immersiveSticky).
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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

class _WebShellState extends State<WebShell> {
  late final WebViewController _controller;
  int _progress = 0;
  bool _loading = true;
  bool _hasError = false;
  DateTime? _lastBackPress;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B0B0F))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => setState(() => _progress = p),
          onPageStarted: (_) => setState(() {
            _loading = true;
            _hasError = false;
          }),
          onPageFinished: (_) => setState(() => _loading = false),
          onWebResourceError: (error) {
            // Only treat a failure of the main document as fatal; sub-resource
            // errors (a missing image, etc.) shouldn't blank the whole app.
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

  Future<void> _reload() async {
    setState(() {
      _hasError = false;
      _loading = true;
    });
    await _controller.loadRequest(Uri.parse(kSiteUrl));
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
        // At the site's entry page: require a second back press within 2s to exit.
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
              : Stack(
                  children: [
                    // The WebView owns all scrolling and gestures; no outer
                    // scroll view / pull-to-refresh (it fought the page and a
                    // stray pull reloaded back to the home URL).
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
