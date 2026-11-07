# AI向け導入・保守説明書

## 目的

この文書は、AIコーディングエージェントがiOS配布モジュールを既存のSwift/Xcodeプロジェクトへ導入・更新するための作業仕様です。
利用者向け操作は同じディレクトリの `IOS_DISTRIBUTION.md` を参照してください。
この文書は公開やアカウント操作の権限を新たに与えるものではありません。ユーザーの依頼範囲と導入先の指示に従って作業します。

目標は「Windowsでコードとアプリのバージョンを変更し、Gitタグをpushすると、GitHubで未署名IPAを生成・公開し、AltStore Classicから更新できる」ことです。

## 最初に判断すること

- **モジュール本体のリポジトリ**: `ios-distribution/install.py` と `ios-distribution/templates/ios.yml` が存在します。ここにはアプリを要求しません。Workflowはテンプレートであり、このリポジトリでビルドする設定ではありません。
- **導入先のアプリリポジトリ**: `.xcodeproj` / `.xcworkspace` が存在し、導入後は `distribution.json` と `.github/workflows/ios.yml` を持ちます。実際のビルド検証はこちらで行います。
- 実アプリがない状態で、Scheme・Bundle ID・iOS要求・ビルド成功を推測して報告しないでください。

## ファイルと責務

|ファイル|責務|
|---|---|
|`ios-distribution/install.py`|導入先へファイルをコピー。既存の対象ファイルが1つでもあれば上書き前に停止|
|`ios-distribution/config.example.json`|空の設定ひな形。導入先では `distribution.json` になる|
|`ios-distribution/templates/ios.yml`|Workflowひな形。導入先では `.github/workflows/ios.yml` になる|
|`ios-distribution/scripts/distribute.py`|ビルド、IPA検証、Release公開、Source生成|
|`ios-distribution/tests/test_distribute.py`|履歴・重複・IPA構造の共通テスト|
|`docs/IOS_DISTRIBUTION.md`|利用者向け導入・運用・復旧手順|
|`docs/AI_INSTRUCTIONS.md`|AI向けの調査・実装・検証手順（本書）|

モジュール更新は自動追従しません。導入先では差分を確認して反映します。
各アプリリポジトリは独立したSourceを公開します。集約関数はBundle ID別の複数アプリに対応しますが、別リポジトリからの自動収集は未実装です。

## 導入前の調査

1. 導入先の指示ファイルと `git status` を確認し、既存の変更を把握します。
2. Xcode project/workspace、共有Scheme、アプリとExtensionのターゲットを列挙します。
3. `project.pbxproj`、xcconfig、Info.plist、Asset Catalog、Entitlements、Package.resolved、既存CIを読みます。
4. Bundle ID、Deployment Target、Swift/Xcode要求、version/build、SPM等の依存、アイコン候補を記録します。
5. 署名を必要とする機能や独自生成工程があれば、無料署名への影響を確認します。機能を削除して通過させないでください。
6. 候補が複数なら設定で明示します。既存のCI、Pages、Release公開処理と競合させないでください。

Windowsから読んだ静的設定と、macOSの `xcodebuild -showBuildSettings` で評価された設定を区別してください。
静的調査だけではSchemeの利用可否やビルド成功を確定できません。

## 導入手順

導入先ディレクトリを確認してから、モジュール本体のインストーラーを実行します。

```powershell
python C:\WorkSpace\iOS\ios-distribution\install.py C:\WorkSpace\MyApp
```

既に導入済みならインストーラーによる強制上書きはせず、対象ファイルを比較して必要な変更だけ反映します。
導入先の `.gitignore` に `dist/`、`site/`、`.ios-build/`、`__pycache__/` を追加します。
以降のコマンドはアプリリポジトリのルートから実行します。

### 設定

`distribution.json` だけにアプリ固有の配布設定をまとめます。

- `sourceName`、`developerName`、`description`: 必須。既存資料やユーザーの指定から設定します。不明なら確認事項として残し、公開用の架空情報を埋めないでください。
- `project`: リポジトリ相対のproject/workspace。空の場合はworkspace優先で1候補のときだけ自動選択します。
- `scheme`、`target`: 一意なら自動選択。複数の場合は調査したアプリの値を指定します。
- `xcodePath`: Xcode.appのパス。空ならランナーの既定値です。利用可能なXcodeとプロジェクト要求を照合し、必要ならWorkflowのmacOSラベルも調整します。
- `icon`: 既存PNGへの相対パス。空なら1024x1024のAppIcon候補を探します。複数や不在なら既存ファイルを明示します。
- `reviewedEntitlements`: 互換性を確認済みのキーだけを列挙します。検査エラーを消す目的で全キーを機械的に追加しないでください。値や利用機能の確認も必要です。

Bundle ID・version/build・最低iOSは設定ファイルへ重複定義せず、生成IPAから取得します。
既存のBundle IDやユーザーデータを破壊する変更は避けてください。

## 実装上の契約

- Python 3.10以降と標準ライブラリを使用します。公開・Source取得にはGitHub CLI `gh` も必要です。
- `validate` は必須3文字列の確認だけです。JSON Schema検証、パス・Scheme検証、ビルド検証は行いません。
- `build` はmacOS専用です。`xcodebuild` のRelease / iphoneos / generic iOS deviceビルドで署名を無効化します。
- SPM解決後に全ターゲットの静的Entitlementsを確認します。CocoaPods等の準備工程は自動追加しません。
- 生成.app全体をdittoで `Payload/` に格納し、`dist/app.ipa`、`dist/icon.png`、`dist/manifest.json` を生成します。
- `publish` / `source` は `GITHUB_REPOSITORY` とGitHub認証を使用します。`publish` はさらに `GITHUB_REF_NAME` を使います。ローカルで実行する前に外部公開操作であることを認識してください。
- タグは `vMAJOR.MINOR.PATCH`、IPA内versionと完全一致が必要です。build番号は過去の同じBundle IDの全公開版より増やします。
- 同じタグの上書きはせず、Assetsを揃えたDraft Releaseを公開します。
- `source` は公開済みの非prereleaseからmanifestを取得し、実在AssetのURL・サイズを利用します。manifestなしのReleaseは対象外です。
- Sourceはversion/buildの数値順で最新を先頭にし、履歴を保持します。公開済みReleaseとAssetsを履歴の保存元として扱います。
- Release公開とPagesデプロイは別操作です。Pages失敗時に公開Releaseまで未公開だったと報告しないでください。

### Workflowの動作

main push・PR・通常の手動実行でビルドし、versionタグでは成功後に公開します。
現行の公開条件はタグrefを判定するため、タグを選んだ手動実行も公開対象になり得ます。
`rebuild_source=true` はmainから実行し、ビルドを省略して公開履歴からPagesを復旧するための入力です。
concurrencyは同じリポジトリの実行を直列化しますが、処理順を保証しません。複数タグの同時pushは避けます。

PRには書き込み権限やApple認証情報を渡さず、`pull_request_target` に変更しないでください。
通常ジョブはcontents:read、公開ジョブだけcontents:write / pages:write / id-token:writeを使用します。
Apple ID、証明書、パスワード、PATの追加を通常の導入条件にしないでください。

## 検証と報告

導入先ルートで実行します。

```powershell
python -m unittest discover -s ios-distribution/tests -v
python -m py_compile ios-distribution/scripts/distribute.py
python ios-distribution/scripts/distribute.py validate
```

テストは疑似IPAを使った構造検査であり、実機インストールやコード署名の互換性を保証しません。
YAMLパーサーが使える場合は構文解析し、可能ならactionlint等でWorkflowの式や依存関係も検証します。
YAMLを読めたこととGitHub Actions上で正常に動くことを区別してください。

認証と依頼範囲が許せば、GitHubで以下を確認します。操作できなければ未実施として具体的な手順を残します。

1. 初回ビルドでXcode、Scheme、依存解決、Entitlements検査とIPA生成を確認する。
2. ArtifactのInfo.plistと配布メタデータを照合する。
3. リリース時にタグ・version/build、Assets、Sourceの履歴・順序・URLを確認する。
4. Pages復旧入力で、buildジョブがskipされても公開ジョブが実行されることを確認する。
5. iPhoneでSource登録、初回インストール、更新、Refreshを個別に確認する。

モジュール作成時点ではPython構文・3テスト・コピー導入確認だけが済んでいます。
YAML解析、macOS実ビルド、GitHub公開、Pages疎通、iPhone動作は未検証です。後続の検証結果でこの記録を更新してください。

## エラー対応と保守

- Schemeやアイコンの候補が曖昧なら設定を明示します。自動検出を無条件に最初の候補へ変更しないでください。
- 失敗ログと `.ios-build/schemes.json` / `settings.json` を確認します。現行Workflowではこれらの診断ファイルはArtifactに含まれません。
- `dist/` やパッケージ用ディレクトリが既存ならビルドは停止します。再試行時は生成物であると確認した範囲だけを整理します。
- Draft公開失敗はAssetsを確認し、不完全Draftを削除して再試行します。既に公開されたReleaseを自動削除しないでください。
- Release成功後のPages失敗はmainで `rebuild_source=true` を実行します。履歴Assetsを削除して回避しないでください。
- Sourceのpermissionsは静的設定と生成Info.plistから収集します。独自工程が生成するEntitlements、Mach-O署名、全権限の互換性は別途検査が必要です。
- バックエンド用秘密鍵やAPIキーがアプリに含まれないか、依頼範囲で履歴・Resourcesも確認します。秘密の値をログや最終報告に載せないでください。
- 運用仕様を変更したらWorkflowひな形・スクリプト・設定・両説明書の整合を保ちます。既存導入先への移行手順も記載します。

最終報告には、変更ファイル、設定根拠、実施した検証と未実施の検証、GitHubで必要な設定、初回導入と次回更新の操作を含めます。
無料運用・無料署名・Remote AltServerの最新仕様を説明する際は公式資料を確認してください。
アプリ更新と7日間の再署名は別処理として説明し、PCとの初期ペアリング、利用時のWi-FiとLocalDevVPNの要件も明記します。
