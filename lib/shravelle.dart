/// Shravelle for Flutter.
///
/// ```dart
/// void main() => Shravelle.run(
///   const ShravelleConfig(endpoint: 'https://ingest.example.com', key: 'shv_brw_...', app: 'shop-flutter', release: '1.4.0'),
///   () => runApp(MaterialApp(navigatorObservers: [ShravelleNavigatorObserver()], home: Home())),
/// );
/// final client = ShravelleHttpClient(http.Client());   // network monitoring
/// ```
/// Captures Flutter framework errors, uncaught async errors (crashes), network
/// calls, screen views, sessions and custom events, with a file-backed queue
/// so events survive restarts and offline periods.
library shravelle_flutter;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ShravelleConfig {
  final String endpoint, key, app, release;
  final Duration flushInterval;
  final List<String> tracePropagationHosts;
  const ShravelleConfig({required this.endpoint, required this.key, required this.app, this.release = '',
      this.flushInterval = const Duration(seconds: 15), this.tracePropagationHosts = const []});
}

class Shravelle {
  static ShravelleConfig? _cfg;
  static File? _file;
  static String _session = _rid(16), _user = '';
  static bool _sending = false;
  static final _start = DateTime.now();

  static String _rid(int n) { final r = Random.secure(); return List.generate(n, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join(); }

  /// Starts Shravelle and runs [app] in a guarded zone so every uncaught error is captured.
  static void run(ShravelleConfig cfg, void Function() app) {
    runZonedGuarded(() async {
      WidgetsFlutterBinding.ensureInitialized();
      await start(cfg);
      app();
    }, (e, st) => _crash(e, st));
  }

  static Future<void> start(ShravelleConfig cfg) async {
    if (_cfg != null) return;
    _cfg = cfg;
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/shravelle-queue.jsonl');
    final prevFlutter = FlutterError.onError;
    FlutterError.onError = (d) { _push({'type': 'handled_exception', 'name': d.exception.runtimeType.toString(), 'message': d.exceptionAsString(), 'stack': d.stack.toString()}); prevFlutter?.call(d); };
    PlatformDispatcher.instance.onError = (e, st) { _crash(e, st); return false; };
    _push({'type': 'app_start', 'name': 'cold_start', 'value': DateTime.now().difference(_start).inMilliseconds.toDouble()});
    Timer.periodic(cfg.flushInterval, (_) => flush());
  }

  static void setUser(String id) => _user = id;
  static void screen(String name) => _push({'type': 'page_view', 'name': 'screen', 'route': name, 'page_url': 'app://$name'});
  static void track(String name, {Map<String, String> attributes = const {}, double value = 0}) => _push({'type': 'custom', 'name': name, 'value': value, 'attributes': attributes});
  static void recordError(Object e, [StackTrace? st]) => _push({'type': 'handled_exception', 'name': e.runtimeType.toString(), 'message': e.toString(), 'stack': (st ?? StackTrace.current).toString()});

  static void _crash(Object e, StackTrace st) {
    _push({'type': 'crash', 'name': e.runtimeType.toString(), 'message': e.toString(), 'stack': st.toString()});
    flush();
  }

  static void _push(Map<String, dynamic> e) {
    final cfg = _cfg;
    if (cfg == null || _file == null) return;
    final attrs = <String, String>{'platform': 'flutter', 'os.name': Platform.operatingSystem, 'os.version': Platform.operatingSystemVersion,
      ...((e['attributes'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ?? {})};
    final ev = {...e, 'timestamp': DateTime.now().toUtc().toIso8601String(), 'session_id': _session, 'user_id': _user, 'app': cfg.app, 'release': cfg.release, 'attributes': attrs};
    try { _file!.writeAsStringSync('${jsonEncode(ev)}\n', mode: FileMode.append, flush: true); } catch (_) {}
  }

  static Future<void> flush() async {
    final cfg = _cfg, f = _file;
    if (cfg == null || f == null || _sending || !f.existsSync()) return;
    _sending = true;
    try {
      final lines = f.readAsLinesSync().where((l) => l.isNotEmpty).toList();
      if (lines.isEmpty) return;
      final batch = lines.take(200).toList();
      final body = jsonEncode({'app': cfg.app, 'session_id': _session, 'user_id': _user, 'release': cfg.release, 'events': batch.map(jsonDecode).toList()});
      final r = await http.post(Uri.parse('${cfg.endpoint.replaceAll(RegExp(r'/$'), '')}/v1/rum?key=${Uri.encodeQueryComponent(cfg.key)}'),
          headers: {'Content-Type': 'application/json', 'User-Agent': 'Shravelle-Flutter/1.0 (${Platform.operatingSystem}; Mobile)'}, body: body).timeout(const Duration(seconds: 10));
      if (r.statusCode < 300 || r.statusCode == 400 || r.statusCode == 401) {
        final now = f.readAsLinesSync().where((l) => l.isNotEmpty).toList();
        f.writeAsStringSync(now.skip(batch.length).map((l) => '$l\n').join(), flush: true);
      }
    } catch (_) {
      // offline: keep queued
    } finally {
      _sending = false;
    }
  }

  static bool _propagate(String host) => _cfg?.tracePropagationHosts.any((h) => host == h || host.endsWith('.$h')) ?? false;
  static String _template(Uri u) => '${u.host}${u.path.replaceAll(RegExp(r'/\d+(?=/|$)'), '/:id')}';
}

/// Records every request made through the wrapped client.
class ShravelleHttpClient extends http.BaseClient {
  final http.Client _inner;
  ShravelleHttpClient(this._inner);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest req) async {
    final sw = Stopwatch()..start();
    var traceId = '';
    if (Shravelle._propagate(req.url.host)) {
      traceId = Shravelle._rid(16);
      req.headers['traceparent'] = '00-$traceId-${Shravelle._rid(8)}-01';
    }
    try {
      final r = await _inner.send(req);
      Shravelle._push({'type': 'ajax', 'name': '${req.method} ${Shravelle._template(req.url)}', 'status': r.statusCode, 'duration_ms': sw.elapsedMilliseconds.toDouble(), 'trace_id': traceId});
      return r;
    } catch (e) {
      Shravelle._push({'type': 'ajax', 'name': '${req.method} ${Shravelle._template(req.url)}', 'status': 0, 'duration_ms': sw.elapsedMilliseconds.toDouble(), 'message': '$e', 'trace_id': traceId});
      rethrow;
    }
  }
}

/// MaterialApp(navigatorObservers: [ShravelleNavigatorObserver()])
class ShravelleNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route route, Route? previous) { final n = route.settings.name; if (n != null) Shravelle.screen(n); }
  @override
  void didPop(Route route, Route? previous) { final n = previous?.settings.name; if (n != null) Shravelle.screen(n); }
  @override
  void didReplace({Route? newRoute, Route? oldRoute}) { final n = newRoute?.settings.name; if (n != null) Shravelle.screen(n); }
}
