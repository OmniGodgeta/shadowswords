import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'log.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  String _header = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) {
        setState(() => _header =
            'RetroVerse ${p.version} (${p.buildNumber}) · Android');
      }
    });
  }

  String get _fullText => '$_header\n\n${AppLog.instance.dump()}';

  @override
  Widget build(BuildContext context) {
    final lines = AppLog.instance.lines;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report a problem'),
        actions: [
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _fullText));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied')),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Recent activity from this session. Copy it, then open an issue on '
              'GitHub and paste it in. Nothing is sent automatically.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  lines.isEmpty ? 'Nothing logged yet.' : '$_header\n\n${lines.join('\n')}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      AppLog.instance.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Clear'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(
                          'https://github.com/OmniGodgeta/shadowswords/issues/new'),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.bug_report_outlined),
                    label: const Text('Open issues'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
