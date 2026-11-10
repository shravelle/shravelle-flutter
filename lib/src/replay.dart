// ignore_for_file: deprecated_member_use
part of shravelle_flutter;

/// Mobile session replay for Flutter (opt in with `sessionReplay: true`).
///
/// About once a second, while the screen changes, the render tree is turned
/// into a lightweight wireframe (positioned boxes with their colours, rounded
/// corners and text) and recorded with taps. Every 10 seconds the recording is
/// sent to `/v1/replay`, where the Session replay player shows it like a web
/// recording. No screenshots are taken. Text is masked (`****`) unless
/// `replayMaskText: false`; text in text fields is always masked; widgets
/// wrapped in [ShravelleMask] are drawn as a solid box.
class ShravelleReplay {
  static final List<Map<String, dynamic>> _buf = [];
  static Timer? _snap, _flush;
  static String _last = '';
  static int _seq = 0, _start = 0, _clicks = 0, _rage = 0;
  static bool _err = false;
  static final List<List<num>> _taps = [];
  static String screen = '';

  static void _startRecording(ShravelleConfig cfg) {
    final r = int.parse(Shravelle._session.substring(0, 8), radix: 16) / 0xffffffff;
    if (r >= cfg.replaySampleRate) return;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    _snap = Timer.periodic(const Duration(seconds: 1), (_) => capture());
    _flush = Timer.periodic(const Duration(seconds: 10), (_) => flush());
  }

  static void _rec(Map<String, dynamic> e) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_start == 0) _start = now;
    _buf.add({...e, 't': now});
    if (_buf.length > 2000) _buf.removeRange(0, _buf.length - 2000);
  }

  static void _onPointer(PointerEvent e) {
    if (e is! PointerDownEvent) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final x = e.position.dx, y = e.position.dy;
    _clicks++;
    _taps.removeWhere((t) => now - t[0] > 1000 || (t[1] - x).abs() > 30 || (t[2] - y).abs() > 30);
    _taps.add([now, x, y]);
    final rage = _taps.length == 3;
    if (rage) _rage++;
    _rec({'k': 'c', 'x': x.round(), 'y': y.round(), 'i': 0, 'r': rage ? 1 : 0});
  }

  /// Stops recording (the buffered part is still sent by [flush]).
  static void stop() {
    _snap?.cancel();
    _flush?.cancel();
    _snap = _flush = null;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
  }

  /// Marks the recording as having an error (shown on the timeline).
  static void markError() { if (_snap != null) { _err = true; _rec({'k': 'e'}); } }

  /// Records the current screen if it changed since the last capture.
  static void capture() {
    final root = _rootRender();
    if (root == null) return;
    final snap = wireframe(root, maskText: Shravelle._cfg?.replayMaskText ?? true);
    final key = jsonEncode(snap);
    if (key == _last) return;
    _last = key;
    _rec({'k': 'full', ...snap, 'url': 'app://${screen.isEmpty ? 'app' : screen}'});
  }

  static RenderObject? _rootRender() {
    try {
      return WidgetsBinding.instance.renderViewElement?.renderObject;
    } catch (_) {
      return null;
    }
  }

  /// Builds the wireframe of a render tree: {n: html tree, w, h}.
  static Map<String, dynamic> wireframe(RenderObject root, {bool maskText = true}) {
    var id = 0;
    final boxes = <Map<String, dynamic>>[];
    Size size = Size.zero;
    if (root is RenderBox && root.hasSize) size = root.size;
    if (root is RenderView) size = root.size;

    void visit(RenderObject o, bool masked) {
      if (boxes.length >= 1500) return;
      if (o is RenderOffstage && o.offstage) return;
      if (o is RenderOpacity && o.opacity < 0.01) return;
      if (o is RenderAnimatedOpacity && o.opacity.value < 0.01) return;
      var mask = masked || o is _RenderShravelleMask;
      if (o is RenderBox && o.hasSize && o.attached) {
        final Rect r;
        try {
          r = o.localToGlobal(Offset.zero) & o.size;
        } catch (_) {
          return;
        }
        if (r.width >= 1 && r.height >= 1 && r.right > 0 && r.bottom > 0 && (size == Size.zero || (r.left < size.width && r.top < size.height))) {
          final b = _box(o, r, maskText, mask);
          if (b != null) {
            id++;
            boxes.add({'i': id + 10, 't': 'div', 'a': {'style': b['style']}, if (b['text'] != null) 'c': [{'i': 100000 + id, 'y': 3, 'x': b['text']}]});
          }
          if (o is _RenderShravelleMask) return; // a masked widget is one solid box
        }
      }
      o.visitChildren((c) => visit(c, mask));
    }

    visit(root, false);
    if (size == Size.zero) {
      for (final b in boxes) {
        final m = RegExp(r'left:([\d.]+)px;top:([\d.]+)px;width:([\d.]+)px;height:([\d.]+)px').firstMatch(b['a']['style'] as String);
        if (m != null) size = Size(max(size.width, double.parse(m[1]!) + double.parse(m[3]!)), max(size.height, double.parse(m[2]!) + double.parse(m[4]!)));
      }
    }
    final w = size.width.round(), h = size.height.round();
    return {
      'n': {'i': 1, 't': 'html', 'c': [
        {'i': 2, 't': 'head', 'c': [{'i': 3, 't': 'style', 'c': [{'i': 4, 'y': 3, 'x': 'body{margin:0;position:relative;overflow:hidden;background:#fff;font-family:-apple-system,Roboto,sans-serif}div{position:absolute;box-sizing:border-box;overflow:hidden;white-space:pre-wrap}'}]}]},
        {'i': 5, 't': 'body', 'a': {'style': 'width:${w}px;height:${h}px'}, 'c': boxes},
      ]},
      'w': w, 'h': h, 'd': 'html',
    };
  }

  static String _css(Color c) => 'rgba(${c.red},${c.green},${c.blue},${c.opacity.toStringAsFixed(2)})';

  static String _mask(String s) => s.replaceAll(RegExp(r'\S'), '*');

  /// What one render box draws, or null when it draws nothing worth showing.
  static Map<String, String?>? _box(RenderBox o, Rect r, bool maskText, bool masked) {
    final pos = 'left:${r.left.toStringAsFixed(1)}px;top:${r.top.toStringAsFixed(1)}px;width:${r.width.toStringAsFixed(1)}px;height:${r.height.toStringAsFixed(1)}px';
    if (o is _RenderShravelleMask) return {'style': '$pos;background:#9CA3AF'};
    if (o is RenderParagraph) {
      final st = o.text.style;
      var text = o.text.toPlainText();
      if (maskText || masked) text = _mask(text);
      final color = st?.color != null ? 'color:${_css(st!.color!)};' : '';
      final fs = st?.fontSize != null ? 'font-size:${st!.fontSize!.toStringAsFixed(0)}px;' : 'font-size:14px;';
      final fw = (st?.fontWeight != null && FontWeight.values.indexOf(st!.fontWeight!) >= FontWeight.values.indexOf(FontWeight.w600)) ? 'font-weight:600;' : '';
      final al = o.textAlign == TextAlign.center ? 'text-align:center;' : o.textAlign == TextAlign.right || o.textAlign == TextAlign.end ? 'text-align:right;' : '';
      return {'style': '$pos;$color$fs$fw$al', 'text': text};
    }
    if (o is RenderEditable) {
      final text = _mask(o.text?.toPlainText() ?? ''); // inputs are always masked
      return {'style': '$pos;font-size:14px;color:#111', 'text': text};
    }
    if (o is RenderImage) return {'style': '$pos;background:#E5E7EB;border-radius:4px'};
    if (o is RenderDecoratedBox && o.decoration is BoxDecoration) {
      final d = o.decoration as BoxDecoration;
      final parts = <String>[];
      if (d.color != null && d.color!.opacity > 0) parts.add('background:${_css(d.color!)}');
      if (d.gradient != null) parts.add('background:${_css(d.gradient!.colors.first)}');
      if (d.image != null) parts.add('background:#E5E7EB');
      final br = d.borderRadius;
      if (br is BorderRadius) parts.add('border-radius:${br.topLeft.x.toStringAsFixed(0)}px');
      if (d.shape == BoxShape.circle) parts.add('border-radius:50%');
      final bd = d.border;
      if (bd is Border && bd.top.width > 0) parts.add('border:${bd.top.width.toStringAsFixed(0)}px solid ${_css(bd.top.color)}');
      if (parts.isEmpty) return null;
      return {'style': '$pos;${parts.join(';')}'};
    }
    if (o is RenderPhysicalModel) {
      if (o.color.opacity == 0) return null;
      final br = o.borderRadius;
      return {'style': '$pos;background:${_css(o.color)}${br != null ? ';border-radius:${br.topLeft.x.toStringAsFixed(0)}px' : ''}${o.shape == BoxShape.circle ? ';border-radius:50%' : ''}${o.elevation > 0 ? ';box-shadow:0 1px 3px rgba(0,0,0,.2)' : ''}'};
    }
    if (o is RenderPhysicalShape) {
      if (o.color.opacity == 0) return null;
      return {'style': '$pos;background:${_css(o.color)};border-radius:6px${o.elevation > 0 ? ';box-shadow:0 1px 3px rgba(0,0,0,.2)' : ''}'};
    }
    return null;
  }

  /// The body sent to /v1/replay for the buffered events.
  static Map<String, dynamic> payload(List<Map<String, dynamic>> events) => {
        'app': Shravelle._cfg?.app ?? '', 'session_id': Shravelle._session, 'user_id': Shravelle._user, 'seq': _seq, 'start': _start,
        'end': DateTime.now().millisecondsSinceEpoch, 'page_url': 'app://${screen.isEmpty ? 'app' : screen}', 'has_error': _err,
        'clicks': _clicks, 'rage_clicks': _rage, 'platform': 'flutter', 'events': events,
      };

  /// Sends the buffered recording (also called when the app goes to the background).
  static Future<void> flush() async {
    final cfg = Shravelle._cfg;
    if (cfg == null || _buf.isEmpty) return;
    final events = List<Map<String, dynamic>>.from(_buf);
    final body = jsonEncode(payload(events));
    _buf.clear();
    _seq++;
    _start = 0; _clicks = 0; _rage = 0; _err = false;
    _last = ''; // the next chunk starts with a full snapshot so it can be played alone
    try {
      await http.post(Uri.parse('${cfg.endpoint.replaceAll(RegExp(r'/$'), '')}/v1/replay?key=${Uri.encodeQueryComponent(cfg.key)}'),
          headers: {'Content-Type': 'text/plain', 'User-Agent': 'Shravelle-Flutter/1.0 (${Platform.operatingSystem}; Mobile)'}, body: body).timeout(const Duration(seconds: 10));
    } catch (_) {
      // a lost chunk only leaves a gap in the recording
    }
  }
}

/// Draws its child as a solid box in session replays (for sensitive content).
class ShravelleMask extends SingleChildRenderObjectWidget {
  const ShravelleMask({super.key, super.child});
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderShravelleMask();
}

class _RenderShravelleMask extends RenderProxyBox {}
