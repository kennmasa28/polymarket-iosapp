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

## 使用 API（いずれも認証不要の公開エンドポイント）

| API | ベース URL | 用途 |
| --- | --- | --- |
| Gamma | `https://gamma-api.polymarket.com` | `/events`, `/markets/{id}`, `/tags`, `/public-search` |
| CLOB | `https://clob.polymarket.com` | `/prices-history`（将来は発注 API） |
| Data | `https://data-api.polymarket.com` | `/trades`（参加者数の推定） |

## 売買機能の拡張について

UI は `TradingService` プロトコルと `TradingState` だけに依存しています。現在は常に未接続の
`DisabledTradingService` を使っているため、売買ボタンは無効表示です。

実装時の手順（`Trading/TradingService.swift` 冒頭コメント参照）:

1. 設定 › ウォレット で秘密鍵を入力し、`KeychainWalletKeyStore`（`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`）に保存
2. `PolymarketTradingService: TradingService` を実装（EIP-712 署名による CLOB の L1/L2 認証と `POST /order`）
3. `AppServices.trading` を差し替える → マーケット詳細の売買パネル・注文チケット・ポートフォリオタブがそのまま有効になる

秘密鍵は Keychain のみに保存し、`settings.json` や UserDefaults には保存しません。

## ディレクトリ構成

```
polymarket-iosapp/
├── polymarket_iosappApp.swift   エントリポイント / 通知デリゲート / BGタスク登録
├── App/AppContainer.swift        サービス・ストアの生成、フォアグラウンド巡回ループ
├── Models/                       API モデル、監視条件・設定、アラート
├── Services/
│   ├── API/                      HTTP クライアント、Gamma / CLOB / Data API
│   ├── Monitoring/               巡回(MarketMonitor)、判定(AnomalyDetector)、通知、BG更新
│   └── Storage/                  JSON 永続化（設定・アラート・スナップショット）
├── Trading/                      売買の拡張ポイント（プロトコル、Keychain）
├── Views/                        Feed / Market / Monitor / Alerts / Settings
└── Utilities/                    寛容なデコード、表示フォーマット
```

## テスト

`polymarket-iosappTests` に API レスポンスのデコード、設定の後方互換、条件マッチング、
急変判定のユニットテストがあります（Xcode で `⌘U`）。
