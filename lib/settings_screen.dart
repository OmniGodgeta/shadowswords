import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'ejs_cache.dart';
import 'report_screen.dart';
import 'settings.dart';
import 'wol.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.ejs,
    required this.onClearCache,
    required this.onCheckUpdate,
    required this.onInstallUpdate,
  });

  final AppSettings settings;
  final EjsCache ejs;
  final Future<void> Function() onClearCache;
  final Future<String?> Function() onCheckUpdate; // returns newer version or null
  final Future<void> Function() onInstallUpdate;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _urlCtl;
  late final TextEditingController _macCtl;
  late final TextEditingController _bcastCtl;
  String _version = '';
  int _ejsBytes = 0;
  String? _prewarm; // progress text while downloading

  AppSettings get s => widget.settings;

  @override
  void initState() {
    super.initState();
    _urlCtl = TextEditingController(text: s.siteUrl);
    _macCtl = TextEditingController(text: s.wolMac);
    _bcastCtl = TextEditingController(text: s.wolBroadcast);
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _version = '${p.version} (${p.buildNumber})');
    });
    _refreshEjsSize();
  }

  Future<void> _refreshEjsSize() async {
    final b = await widget.ejs.cacheBytes();
    if (mounted) setState(() => _ejsBytes = b);
  }

  String _mb(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';

  // Fallback if the site hasn't handed us `sswCores()` yet (never been online).
  static const _fallbackCores = [
    'a5200', 'beetle_vb', 'fbneo', 'fceumm', 'gambatte', 'gearcoleco',
    'genesis_plus_gx', 'handy', 'mame2003_plus', 'mednafen_ngp', 'mednafen_pce',
    'mednafen_pcfx', 'mednafen_wswan', 'melonds', 'mgba', 'mupen64plus_next',
    'opera', 'pcsx_rearmed', 'picodrive', 'prosystem', 'puae', 'snes9x',
    'stella2014', 'vice_x64sc', 'vice_xplus4', 'vice_xvic', 'virtualjaguar',
  ];

  Future<void> _downloadAllCores() async {
    final cores =
        s.knownCores.isNotEmpty ? s.knownCores : _fallbackCores;
    setState(() => _prewarm = 'Starting…');
    await widget.ejs.prewarm(
      cores,
      onProgress: (done, total) {
        if (mounted) setState(() => _prewarm = 'Downloading $done / $total…');
      },
    );
    await _refreshEjsSize();
    if (mounted) setState(() => _prewarm = null);
  }

  @override
  void dispose() {
    _urlCtl.dispose();
    _macCtl.dispose();
    _bcastCtl.dispose();
    super.dispose();
  }

  String _knownLabel(String url) {
    if (url == kTailnetUrl) return 'Tailnet (self-hosted)';
    if (url == kPublicUrl) return 'Public (GitHub Pages)';
    return 'Custom';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _section('Library address'),
          _urlChoice(
            'Tailnet (self-hosted)',
            'Everything works; needs Tailscale + home server',
            kTailnetUrl,
          ),
          _urlChoice(
            'Public (GitHub Pages)',
            'Browsing works anywhere; ROMs need Funnel',
            kPublicUrl,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _urlCtl,
              decoration: const InputDecoration(
                labelText: 'Custom URL',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              onSubmitted: _setUrl,
            ),
          ),

          _section('Playing'),
          SwitchListTile(
            title: const Text('Keep the screen on'),
            subtitle: const Text('Always, not just during games'),
            value: s.keepScreenOnAlways,
            onChanged: (v) => setState(() => s.keepScreenOnAlways = v),
          ),
          SwitchListTile(
            title: const Text('Rotate freely during games'),
            subtitle: const Text('Browsing stays portrait'),
            value: s.autoLandscapeForGames,
            onChanged: (v) => setState(() => s.autoLandscapeForGames = v),
          ),
          SwitchListTile(
            title: const Text('Haptic feedback on touch controls'),
            value: s.hapticControls,
            onChanged: (v) => setState(() => s.hapticControls = v),
          ),

          _section('Wake the home server'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Sends a Wake-on-LAN packet before connecting. Only works on your '
              'home Wi-Fi (not over cellular / Tailscale).',
              style: TextStyle(fontSize: 12),
            ),
          ),
          SwitchListTile(
            title: const Text('Wake on launch & on Retry'),
            value: s.wolEnabled,
            onChanged: (v) => setState(() => s.wolEnabled = v),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: TextField(
              controller: _macCtl,
              decoration: const InputDecoration(
                labelText: 'Server MAC address',
                hintText: 'e8:fb:1c:3e:c8:89',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => s.wolMac = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: TextField(
              controller: _bcastCtl,
              decoration: const InputDecoration(
                labelText: 'Broadcast address',
                hintText: '10.0.0.255',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => s.wolBroadcast = v,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: OutlinedButton.icon(
              onPressed: _macCtl.text.trim().isEmpty
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final err = await sendMagicPacket(
                        _macCtl.text,
                        broadcast: _bcastCtl.text.trim().isEmpty
                            ? '255.255.255.255'
                            : _bcastCtl.text.trim(),
                      );
                      messenger.showSnackBar(SnackBar(
                        content: Text(err == null
                            ? 'Wake packet sent'
                            : "Couldn't send: $err"),
                      ));
                    },
              icon: const Icon(Icons.power_settings_new_rounded),
              label: const Text('Send a test wake packet'),
            ),
          ),

          _section('Offline'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Keep the emulator files on this device so games you have already '
              'downloaded (Save for offline, on the site) still play with no '
              'connection.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          SwitchListTile(
            title: const Text('Emulator available offline'),
            subtitle: Text(_ejsBytes > 0
                ? 'Cached: ${_mb(_ejsBytes)}'
                : 'Files download the first time you play each system'),
            value: s.offlineEmulator,
            onChanged: (v) async {
              setState(() => s.offlineEmulator = v);
              if (v) {
                await widget.ejs.start();
              } else {
                await widget.ejs.clear();
                await _refreshEjsSize();
              }
            },
          ),
          if (s.offlineEmulator) ...[
            ListTile(
              title: const Text('Download all cores now'),
              subtitle: Text(_prewarm ?? 'Fetch every emulator up front (~100 MB)'),
              trailing: _prewarm != null
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download_rounded),
              onTap: _prewarm != null ? null : _downloadAllCores,
            ),
            ListTile(
              title: const Text('Clear emulator cache'),
              subtitle: Text(_mb(_ejsBytes)),
              trailing: const Icon(Icons.delete_outline_rounded),
              onTap: () async {
                await widget.ejs.clear();
                await _refreshEjsSize();
              },
            ),
          ],

          _section('Maintenance'),
          ListTile(
            title: const Text('Check for app updates'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              final nav = Navigator.of(context);
              final v = await widget.onCheckUpdate();
              if (!mounted) return;
              if (v == null) {
                messenger.showSnackBar(
                  const SnackBar(content: Text("You're on the latest version")),
                );
              } else {
                nav.pop();
                widget.onInstallUpdate();
              }
            },
          ),
          ListTile(
            title: const Text('Clear web cache'),
            subtitle: const Text("Fixes a stuck or stale page (keeps you signed in)"),
            trailing: const Icon(Icons.delete_sweep_rounded),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              final nav = Navigator.of(context);
              await widget.onClearCache();
              messenger.showSnackBar(
                const SnackBar(content: Text('Cache cleared — reloading')),
              );
              nav.pop(true); // signal a reload
            },
          ),
          ListTile(
            title: const Text('Report a problem'),
            subtitle: const Text('View recent activity / open an issue'),
            trailing: const Icon(Icons.bug_report_outlined),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReportScreen()),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'RetroVerse $_version',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _urlChoice(String title, String subtitle, String url) {
    final selected = s.siteUrl == url;
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: selected
          ? Icon(Icons.check_circle_rounded,
              color: Theme.of(context).colorScheme.primary)
          : const Icon(Icons.circle_outlined),
      onTap: () => _setUrl(url),
    );
  }

  void _setUrl(String v) {
    final url = v.trim();
    if (url.isEmpty) return;
    setState(() {
      s.siteUrl = url;
      _urlCtl.text = url;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Library set to ${_knownLabel(url)} — reload to apply')),
    );
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 1,
              ),
        ),
      );
}
