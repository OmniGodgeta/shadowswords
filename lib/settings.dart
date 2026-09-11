import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The two built-in site locations. A third "custom" value is any other URL the
/// user types in.
const String kTailnetUrl = 'https://shadow-1.tail51f9d6.ts.net/';
const String kPublicUrl = 'https://omnigodgeta.github.io/shadowswords-gamelib/';

/// Build-time override (`--dart-define=SITE_URL=...`), else the tailnet.
const String _defaultSiteUrl =
    String.fromEnvironment('SITE_URL', defaultValue: kTailnetUrl);

class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  final SharedPreferences _prefs;

  static Future<AppSettings> load() async =>
      AppSettings._(await SharedPreferences.getInstance());

  String get siteUrl => _prefs.getString('siteUrl') ?? _defaultSiteUrl;
  set siteUrl(String v) => _set('siteUrl', v.trim());

  bool get keepScreenOnAlways => _prefs.getBool('keepScreenOnAlways') ?? false;
  set keepScreenOnAlways(bool v) => _set('keepScreenOnAlways', v);

  bool get autoLandscapeForGames =>
      _prefs.getBool('autoLandscapeForGames') ?? true;
  set autoLandscapeForGames(bool v) => _set('autoLandscapeForGames', v);

  bool get hapticControls => _prefs.getBool('hapticControls') ?? true;
  set hapticControls(bool v) => _set('hapticControls', v);

  bool get wolEnabled => _prefs.getBool('wolEnabled') ?? false;
  set wolEnabled(bool v) => _set('wolEnabled', v);

  /// Colon/dash-separated MAC of the home server's NIC.
  String get wolMac => _prefs.getString('wolMac') ?? '';
  set wolMac(String v) => _set('wolMac', v.trim());

  String get wolBroadcast =>
      _prefs.getString('wolBroadcast') ?? '255.255.255.255';
  set wolBroadcast(String v) =>
      _set('wolBroadcast', v.trim().isEmpty ? '255.255.255.255' : v.trim());

  bool get seenIntro => _prefs.getBool('seenIntro') ?? false;
  set seenIntro(bool v) => _set('seenIntro', v);

  /// Last in-game hash, used to rejoin after the app is killed.
  String get lastGameHash => _prefs.getString('lastGameHash') ?? '';
  int get lastGameAt => _prefs.getInt('lastGameAt') ?? 0;
  void rememberGame(String hash) {
    _prefs.setString('lastGameHash', hash);
    _prefs.setInt('lastGameAt', DateTime.now().millisecondsSinceEpoch);
  }
  void forgetGame() {
    _prefs.remove('lastGameHash');
    _prefs.remove('lastGameAt');
  }

  /// Route EmulatorJS's files through the app's on-disk cache so games play
  /// offline once fetched.
  bool get offlineEmulator => _prefs.getBool('offlineEmulator') ?? false;
  set offlineEmulator(bool v) => _set('offlineEmulator', v);

  /// libretro core names from the site's `sswCores()`, cached so the offline
  /// "download all" works even when the site can't be reached.
  List<String> get knownCores => _prefs.getStringList('knownCores') ?? const [];
  set knownCores(List<String> v) {
    _prefs.setStringList('knownCores', v);
    notifyListeners();
  }

  void _set(String key, Object value) {
    switch (value) {
      case String v:
        _prefs.setString(key, v);
      case bool v:
        _prefs.setBool(key, v);
      case int v:
        _prefs.setInt(key, v);
    }
    notifyListeners();
  }
}
