# Flutter

```yaml
dependencies:
  shravelle: { git: https://github.com/shravelle/shravelle-flutter }
```
```dart
void main() => Shravelle.run(
  const ShravelleConfig(endpoint: 'https://ingest.example.com', key: 'shv_brw_xxx', app: 'shop-flutter', release: '1.4.0'),
  () => runApp(MaterialApp(navigatorObservers: [ShravelleNavigatorObserver()], home: const Home())),
);
final client = ShravelleHttpClient(http.Client());   // network monitoring
```
`Shravelle.run` runs the app in a guarded zone, so uncaught async errors are captured as crashes. Flutter framework
errors (`FlutterError.onError`) are captured too. Events are kept in a file queue across restarts and offline
periods. Status: not compiled in this build environment.


---
Part of [Shravelle](https://shravelle.com). Setup guide for every platform: [shravelle.com/docs](https://shravelle.com/docs.html) · Get your keys: [shravelle.com/get-started](https://shravelle.com/get-started.html)

## Session replay

Turn on with `sessionReplay: true` (and optionally `replaySampleRate: 0.2`, `replayMaskText: false`). About once a
second the screen is recorded as a wireframe (boxes, colours and text; no screenshots) with taps, and sent every
10 seconds. It plays in Shravelle under **Session replay**. Text is masked by default, text fields always; wrap
sensitive widgets in `ShravelleMask(child: ...)` to draw them as a solid box. Needs the Session replay feature.
