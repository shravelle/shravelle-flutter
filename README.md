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
