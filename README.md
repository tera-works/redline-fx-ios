# REDLINE FX（操作アプリ）

REDLINE FX マルチエフェクターを Bluetooth LE で操作する Flutter アプリです（iOS / Android / Windows）。
RIG / TONE の切替、エフェクト編集、チューナー、ルーパー。本体ファームはプリセット v8 が必要です。

このリポジトリはアプリのソースと iOS 配布用の設定だけを公開しています（本体ファームと基板データは含みません）。

## iPhone へのインストール（AltStore Classic）

1. AltStore Classic を PC の AltServer から iPhone に入れる（[公式手順](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)）。
2. AltStore の Sources に次の URL を追加する。

   ```
   https://tera-works.github.io/redline-fx-ios/source.json
   ```

3. REDLINE FX をインストールする。無料の Apple ID では 7 日ごとに AltStore で Refresh（再署名）が必要です。

新しい版は AltStore の Sources を更新すると Update に出ます。アプリを削除せずに更新すれば設定は残ります。

## 配布のしくみ

`vX.Y.Z` タグを push すると GitHub Actions（macOS）で未署名 IPA をビルドし、Release と AltStore Source（GitHub Pages）を更新します。
タグは `pubspec.yaml` の `version`（例 `2.0.0+1` → `v2.0.0`、build 1）と一致させ、build 番号は毎回増やします。
詳しくは [docs/IOS_DISTRIBUTION.md](docs/IOS_DISTRIBUTION.md)。

## 開発

- Windows: `setup.bat`（pub get → analyze → test → build windows → 起動）。
- iOS: Mac で `flutter build ios`、配布は上記の GitHub Actions。

```
lib/src/
├─ protocol.dart     BLE の UUID・コマンド・状態データの解析
├─ models.dart       音色（プリセット v8）、ライブラリ（設定ファイル v7・ギター/ベース）、パラメータ表
├─ level_log.dart    メーター、演奏レベルログ、チューナーの音名計算
├─ ble_link.dart     universal_ble による通信
├─ controller.dart   アプリの状態とロジック
└─ ui/               テーマ、ノブ等の部品、ペダルボード、エディタ、各パネル、画面レイアウト
assets/defaults.json 工場プリセットとパラメータ表
test/                コーデック・設定移行・ライブラリ・ログ・UI 部品のテスト
```

## ライセンス表記

依存パッケージ: universal_ble（BSD-3）、path_provider（BSD-3）、file_picker（MIT）。
フォントは `assets/fonts/` の各ライセンスファイル（SIL OFL 1.1 ほか）に従います。
