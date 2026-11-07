# iOS無料ビルド・AltStore Classic配布

## 方式と適用範囲

各アプリのリポジトリに共通スクリプトとWorkflowをコピーして使用します。WindowsにXcodeは不要です。
GitHub ActionsのmacOS上で既存のXcodeプロジェクトを実機向けReleaseビルドし、署名を無効にした.appを
dittoでPayloadに格納します。Frameworks、Resources、Extensionは.appを丸ごと保持します。
Apple ID・証明書・パスワード・個人アクセストークンをActionsに登録する必要はありません。

現時点でこのモジュールに実アプリは含まれません。個別プロジェクトのBundle ID、Deployment Target、
Swift/Xcode要求、SPM依存関係、アイコン、Entitlementsの調査・ビルド結果はまだありません。

## 1. Windowsで準備・導入

Git、Python 3.10以降、任意のSwiftコード編集環境を用意します。
アプリには.xcodeprojまたは.xcworkspaceと共有されたアプリSchemeが必要です。
Schemeが共有されていなければxcshareddata/xcschemesに共有Schemeを追加してcommitしてください。

```powershell
git clone https://github.com/OWNER/APP.git C:\WorkSpace\APP
python C:\WorkSpace\iOS\ios-distribution\install.py C:\WorkSpace\APP
cd C:\WorkSpace\APP
```

インストーラーは既存ファイルを上書きしません。更新時は元モジュールとの差分をレビューして反映します。
導入先の.gitignoreに `dist/`、`site/`、`.ios-build/`、`__pycache__/` を追加してください。

## 2. 設定の一元管理

`distribution.json` の次の3項目は必須です。情報を推測して埋めることはしません。

|項目|値|
|---|---|
|sourceName|Sourceの表示名|
|developerName|公開する開発者名|
|description|公開するアプリ説明|
|project|リポジトリ相対の.xcodeproj/.xcworkspace。候補が1つなら空で自動検出|
|scheme|共有アプリScheme。候補が1つなら自動検出|
|target|アプリターゲット。候補が1つなら自動検出|
|xcodePath|例 `/Applications/Xcode_26.3.app`。空ならランナーの標準Xcode|
|icon|既存PNGへの相対パス。1024x1024 AppIconが1候補なら自動検出|
|reviewedEntitlements|無料署名との互換性を人が確認済みのEntitlementキーの配列|

アプリ名・Bundle ID・バージョン・ビルド番号・最低iOSは生成されたIPAのInfo.plistから取得します。
開発者名や説明はXcodeから確実に取得できないため設定します。
Xcodeは `xcodePath` で固定を推奨します。インストール済みバージョンと要求Swiftは
[ランナー一覧](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md) で照合してください。
macOS世代が合わなければWorkflowのruns-onも変更します。

```powershell
python ios-distribution/scripts/distribute.py validate
git add .github ios-distribution distribution.json docs .gitignore
git commit -m "Add unsigned iOS distribution pipeline"
git push origin main
```

SPMはxcodebuildで解決します。Package.resolvedをcommitして依存更新をレビューしてください。
CocoaPods、Carthage、プライベート依存の認証・独自生成工程は共通モジュールでは導入しません。
必要な場合は対象プロジェクトの準備ステップをWorkflowに明示的に追加します。

## 3. GitHubの初期設定

1. 無料運用と公開ダウンロードには公開リポジトリを推奨します。
2. Settings → Actions → GeneralでGitHub Actionsと公式Actionを許可します。
3. Settings → Pages → Build and deployment → Sourceを **GitHub Actions** にします。
4. Environments → github-pagesの保護ルールでバージョンタグ `v*` とmainからのデプロイを許可します。
5. タグ保護・Rulesetsでリリースタグの書き換えと削除を制限します。

通常はApple関連SecretsもPATも不要です。公開ジョブのみGITHUB_TOKENにcontents:write、pages:write、id-token:writeを付与します。
PRではpull_requestイベントを使い、公開ジョブには進みません。pull_request_targetは使用しません。

## 4. 初回ビルドと公開

mainへのpush、PR、Actions → iOS distribution → Run workflowでビルドできます。
通常mainや手動ビルドは公開Releaseを作りません。成功したRunのArtifactsからios-packageを取得してください。
ArtifactのZIPを展開するとapp.ipa、icon.png、manifest.jsonがあります。

IPAを検証後、プロジェクトのMARKETING_VERSIONとCURRENT_PROJECT_VERSIONを更新してcommitします。
これらの値は共通モジュールから上書きしません。

```powershell
git add .
git commit -m "Release 1.0.0 build 1"
git push origin main
git tag v1.0.0
git push origin v1.0.0
```

タグはvMAJOR.MINOR.PATCH形式で、IPAのCFBundleShortVersionStringと一致させます。
ビルド番号は過去の全リリースより増やしてください。同一versionでもbuild番号だけのリリースはこのタグ方式では行いません。
公開履歴より古いバージョン、同じbuild番号、同じタグの上書きは拒否します。
同じリポジトリの実行はconcurrencyで直列化し、自動キャンセルしません。到着順は保証されないため、
複数タグを同時pushせず、前の公開完了後に次のタグをpushしてください。

ビルド成功後にDraft ReleaseへIPA・アイコン・メタデータをまとめてアップロードしてから公開します。
アップロードが失敗したDraftは公開されません。Releases画面で原因とAssetsを確認してDraftを削除してから再実行します。
公開Releaseは自動上書きしません。手動で同じタグのReleaseを作成しないでください。

## 5. PagesとSource

各公開Releaseのmanifest.jsonをAPIでページング取得し、過去履歴を含むsite/source.jsonを再構築します。
IPAとアイコンのURLはGitHub APIが返す実際のRelease Asset URLを利用します。
バージョンは数値順に最新が先頭です。アプリはBundle ID別にグループ化されるため、集約処理は複数アプリにも対応します。
各アプリを別リポジトリに導入した場合は各々独立したSourceです。別リポジトリからの中央集約は別途設計が必要です。
履歴を保持するため、公開済みReleaseとそのAssetsを削除・置換しないでください。

Source URLはSettings → Pagesに表示されるURLに `source.json` を追加したものです。
例: `https://OWNER.github.io/APP/source.json`。独自ドメインを使う場合も表示URLを基準にします。

Release公開後にPagesだけ失敗することはあります。ReleaseとPagesには共通トランザクションがないためです。
修復はmainのActions → Run workflowで **rebuild_source** をオンにしてください。
公開済みReleaseから再構築するため、再ビルドやReleaseの作り直しは不要です。
Pages設定・環境保護・履歴内のAssets欠損を確認してから再実行してください。

## 6. Windows AltServerとiPhoneの初期設定

1. [公式Windows手順](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)に従いAltServerを導入します。
   必要なiTunes/iCloud等は公式手順の配布元指定に従ってください。
2. iPhoneをUSBで接続し「このコンピュータを信頼」を承認します。
3. AltServerからAltStore Classicをインストールし、自分のApple IDで認証します。
   認証情報はローカルのAltStore/AltServerだけに入力してください。
4. iPhoneで必要に応じ開発者の信頼とDeveloper Modeを有効にします。
5. AltStore Classic 2.3以降のSettings → Set up Remote AltServer…から、PCとのペアリングを完了します。
6. LocalDevVPNをインストールし、Wi-FiとLocalDevVPNを有効にします。
7. Sources画面の追加操作でSource URLを登録し、アプリをインストールします。

[公式Remote AltServer手順](https://faq.altstore.io/altstore-classic/remote-altservers)に従ってください。
初期設定後はWi-FiとLocalDevVPN経由でPCに接続せずインストール・更新・再署名ができます。
Remote AltServer停止時はサーバー変更・復旧待ち、必要に応じWindowsのAltServerを使います。

## 7. 更新と7日間の再署名

次回以降はWindowsでコードとプロジェクトのversion/buildを更新し、commitと新しいタグをpushします。
Actions → Release → Pages更新後、AltStoreでSourceを更新してアプリのUpdateを実行します。
AltStoreが検出する時期はSource再取得のタイミングに依存します。

新バージョンのインストールと、署名期限を延長するRefreshは別処理です。
無料Apple IDの署名期限は通常7日間のため、期限内にAltStoreのRefresh All等で
AltStore自身とアプリを再署名してください。自動バックグラウンド更新の成功は保証できません。
Bundle IDと同じApple IDを維持し、更新時にアプリを削除しないことでデータ維持を図ります。
アプリ自身のマイグレーション・App Groups・署名の変更によって維持できない場合があるため、重要なデータはバックアップします。

## 8. 制約とエラー

- 無料Apple IDには通常同時3アプリ（AltStore自身を含む）やApp ID登録数等の制約があります。
  Extensionも制約に影響します。各インストール利用者が自分のApple IDで署名します。
- Push通知、iCloud、App Groups等のEntitlementsは無料署名で利用できない場合があります。
  ビルド前に全ターゲットのCODE_SIGN_ENTITLEMENTSを調査し、キーを表示して停止します。
  reviewedEntitlementsへの追加は互換性確認の記録であり、署名権限を付与するものではありません。
  未対応機能があれば設計変更や有料登録を検討し、共通スクリプトから機能は削除しません。
- Entitlementsの静的設定を監査しますが、依存パッケージ・独自ビルド工程で動的生成される設定までは保証しません。
- Schemeなし: 共有Schemeのcommitと設定名を確認します。候補が複数ならproject/scheme/targetを指定します。
- アイコンが複数/PNGなし: 設定のiconに既存PNGを指定します。Asset Catalogからの変換は行いません。
- タグ不一致: IPAのversionとタグを合わせます。ビルド番号を増やして新タグで公開します。
- 非公開リポジトリのAssetsは一般利用者が認証なしで取得できません。公開配布には公開リポジトリを使用します。
- APIキー、秘密鍵、設定ファイルはアプリのBundleに埋め込むと公開されます。モジュールは秘密情報の意味的検査を行いません。
  commit前に差分、Git履歴、IPA内Resourcesを確認し、漏えい済みキーは失効してください。

標準GitHubホストランナーは公開リポジトリで無料ですが、privateの利用枠、Artifactストレージ、帯域、
Pagesのプラン条件は契約に依存します。Artifactは7日保持です。課金設定と使用量を確認してください。
[GitHub料金仕様](https://docs.github.com/en/billing/concepts/product-billing/github-actions)。

## 9. 検証手順と未検証範囲

Windowsで共通ロジックのテスト:

```powershell
python -m unittest discover -s ios-distribution/tests -v
python ios-distribution/scripts/distribute.py validate
```

macOSのビルドではxcodebuild -list / -showBuildSettingsを.ios-buildに保存し、Xcodeバージョンとビルドログを出します。
署名を無効にし、IPAのZIP破損、パス、単一.app、実行ファイル、Info.plist、実機プラットフォーム、
署名ディレクトリ・provisioning profile不在を確認します。公開時もIPAとmanifestのversion/build/Bundle ID・SHA256を照合します。

導入後は必ずActionsで初回ビルドを実行し、実際のScheme、SPM解決、Swift互換性、Extensionを確認してください。
生成したIPAをAltStoreでインストールし、Sourceのpermissions、起動、データ維持、更新とRefreshをそれぞれ確認します。
未署名IPAの構造検証は実機でのインストール成功や全Mach-Oの署名状態を保証しません。
Source形式は[AltStore公式仕様](https://faq.altstore.io/developers/make-a-source)に沿って生成していますが、
実際のアプリとAltStoreによる互換性検証は導入先で必要です。
このWindows環境ではXcodeビルド、GitHub公開、PagesのHTTP疎通、iPhoneインストールは実行していません。

モジュール作成時の検証結果: Python構文検証、上記3テスト、導入先へのファイル配置確認は成功しました。
YAMLはパーサー未導入で、ネットワーク制限により追加取得できず構文解析未実施です。
導入後、GitHub ActionsがWorkflowを正常に認識することも確認してください。
