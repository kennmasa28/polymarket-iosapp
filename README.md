# polymarket-iosapp

Polymarket の最新トピックスを表示し、興味のある条件に一致するマーケットを監視して
**価格の急変・出来高の急増・参加者の急増** を通知する iOS アプリ（SwiftUI / iOS 26）。

## 機能

| タブ | 内容 |
| --- | --- |
| トピックス | 24h 出来高上位のイベント一覧。監視条件のチップで絞り込み、キーワード検索（`public-search`） |
| モニター | 監視状況（最終チェック・エラー）と、条件ごとの監視対象マーケット（検知ウィンドウ内の変化が大きい順） |
| アラート | 発火したアラートの履歴。タップでマーケット詳細を開く。通知タップでも同じ画面に遷移 |
| 設定 | 監視条件の追加/編集、チェック間隔・再通知間隔、通知、ウォレット（今後対応） |

マーケット詳細では価格チャート（CLOB `prices-history`）、統計、解決ルール、売買パネル（現在は無効）を表示します。

### 監視条件（ローカル保存）

設定は `Application Support/PolymarketMonitor/settings.json` に保存されます。

- **タグ**（Gamma `/tags` から選択、複数可・OR）。未指定なら全カテゴリの出来高上位
- **キーワード**（含む / 除外、カンマ区切り）
- **フィルタ**: 24h 出来高の下限、流動性の下限
- **アラートルール**（条件ごと）
  - 検知ウィンドウ: 5分〜24時間
  - 価格急変: Yes 価格がウィンドウ内で ±N pt 以上動いた
  - 出来高急増: ウィンドウ内出来高が 24h 平均ペースの N 倍以上
  - 参加者急増: Data API の約定履歴から数えたユニーク取引者数が直前ウィンドウの N 倍以上

### 監視の仕組み

1. 有効な条件ごとに Gamma `/events?tag_id=…&active=true&closed=false` をページングして全件取得
2. 条件に一致するマーケットについて、価格・累計出来高のスナップショットを記録（`snapshots.json`、約26時間分）
3. 過去スナップショットと比較して急変を判定（履歴が不足する間は Gamma の `oneHourPriceChange` / `oneDayPriceChange` を代用）
4. 参加者チェックが有効な条件は、出来高上位から上限件数まで Data API `/trades` を呼んで判定
5. 同じマーケット・同じ種類のアラートは再通知間隔の間は抑制し、ローカル通知を送信（1回最大5件＋まとめ1件）

実行タイミング:

- **フォアグラウンド**: 設定したチェック間隔（1〜60分）で実行
- **バックグラウンド**: `BGAppRefreshTask`。iOS が実行タイミングを決めるため **最短でも15分程度・不定期** で、1回あたり約30秒の制限があります

> 常時・確実に監視したい場合は、同じロジックをサーバー（例: Python + APScheduler）で動かし、
> APNs のプッシュ通知で端末に送る構成への拡張が必要です。判定ロジックは
> `Services/Monitoring/AnomalyDetector.swift` に純粋関数として分離してあるので移植しやすくしています。

## 使用 API

| API | ベース URL | 用途 |
| --- | --- | --- |
| Gamma | `https://gamma-api.polymarket.com` | `/events`, `/markets/{id}`, `/tags`, `/public-search` |
| CLOB | `https://clob.polymarket.com` | `/prices-history`、取引（`/auth/*`, `/order`, `/data/orders`, `/balance-allowance` は認証付き） |
| Data | `https://data-api.polymarket.com` | `/trades`（参加者数の推定）、`/positions` |

## 売買機能

設定 › ウォレット で MetaMask の秘密鍵を入力すると、マーケット詳細から Polymarket CLOB に直接発注できます。

- **秘密鍵の保存**: Keychain に「パスコード設定時のみ・この端末のみ」で保存し、読み出すたびに Face ID / パスコードを要求します（`Trading/WalletKeyStore.swift`）。設定ファイルや UserDefaults には保存しません
- **ロック**: ロック解除中だけ鍵をメモリに保持し、アプリがバックグラウンドに入ると自動でロックします
- **署名**: 注文は端末内で EIP-712 署名します（secp256k1 は [swift-secp256k1](https://github.com/21-DOT-DEV/swift-secp256k1) 0.24.0、Keccak-256 と EIP-712 は自前実装）。秘密鍵は外部に送信しません
- **API 認証**: 初回接続時に L1 署名で CLOB の API キーを作成/導出し、以降は HMAC（L2）ヘッダで発注・取消・残高照会を行います
- **アカウント種別**: polymarket.com に MetaMask でログインしている場合は「Polymarket Safe」を選び、Polymarket の入金先アドレス（資金保有アドレス）を入力します。秘密鍵のアドレスで直接 USDC を持つ場合は「EOA」です（EOA の場合は事前にコントラクトへの approve が必要です）
- **注文**: 指値（GTC）と成行（FOK、許容価格を指定）。送信前に確認ダイアログを表示します
- **ポートフォリオタブ**: USDC 残高、保有ポジション（Data API）、未約定注文（スワイプで取消）

注文の金額計算と署名は Polymarket 公式の `py-clob-client` / `py-order-utils` と同じ結果になることを、
同ライブラリで生成した期待値でテストしています（`polymarket-iosappTests/TradingCryptoTests.swift`）。

> 実際の資金が動きます。取引用には少額の専用ウォレットを使い、Polymarket の利用規約とお住まいの地域での利用可否を確認してください。

## Apple Watch（文字盤のコンプリケーション）

1. iPhone アプリのマーケット詳細で ☆ を押してお気に入りに追加（設定 › お気に入り で並べ替え・削除）
2. お気に入りは WatchConnectivity で Watch アプリに送られ、App Group（`group.kengo.shibata.polymarket-iosapp`）に保存されます
3. 文字盤を編集してコンプリケーションに「Polymarket」を追加し、表示するマーケットを選択

表示内容は Yes 価格（確率）と 24 時間の変化です。円形・長方形・インライン・コーナーに対応し、約 15 分ごとに Gamma API から更新します。

| ターゲット | Bundle ID |
| --- | --- |
| PolymarketWatch（Watch アプリ） | `kengo.shibata.polymarket-iosapp.watchkitapp` |
| PolymarketWatchWidgetExtension（コンプリケーション） | `kengo.shibata.polymarket-iosapp.watchkitapp.widget` |

> Watch アプリとウィジェットは App Group を使います。初回は Xcode で一度ビルドして（Automatic Signing）
> Bundle ID と App Group を Apple Developer に登録させてください。iPhone アプリのバージョン番号を上げるときは
> Watch 側 2 ターゲットの `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` も揃えてください。

## ディレクトリ構成

```
polymarket-iosapp/                iPhone アプリ
├── polymarket_iosappApp.swift    エントリポイント / 通知デリゲート / BGタスク登録
├── App/AppContainer.swift        サービス・ストアの生成、フォアグラウンド巡回ループ、自動ロック
├── Models/                       API モデル、監視条件・設定（お気に入り含む）、アラート
├── Services/
│   ├── API/                      HTTP クライアント、Gamma / CLOB / Data API
│   ├── Monitoring/               巡回(MarketMonitor)、判定(AnomalyDetector)、通知、BG更新
│   ├── Storage/                  JSON 永続化（設定・アラート・スナップショット）
│   └── WatchSyncService.swift    お気に入りを Watch へ送信
├── Trading/
│   ├── Crypto/                   Keccak-256、ABI、EIP-712、secp256k1 署名
│   ├── Polymarket/               注文ビルダー、CLOB 認証付きクライアント
│   ├── PolymarketTradingService.swift  ウォレット接続・ロック・発注
│   └── WalletKeyStore.swift      Keychain
├── Views/                        Feed / Market / Monitor / Alerts / Portfolio / Settings
└── Utilities/                    寛容なデコード、表示フォーマット
Shared/                           iPhone・Watch・ウィジェット共通（お気に入り、価格取得、App Group）
PolymarketWatch/                  Watch アプリ
PolymarketWatchWidget/            文字盤のコンプリケーション（WidgetKit）
```

## テスト

`polymarket-iosappTests` に API レスポンスのデコード、設定の後方互換、条件マッチング、
急変判定、Keccak / EIP-712 / 注文署名 / HMAC のユニットテストがあります（Xcode で `⌘U`）。
