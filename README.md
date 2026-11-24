# AimAssist.dylib — Fortnite iOS

## 仕組み
`UIApplication sendEvent:` をswizzleして右半分スクリーンのタッチ移動に
EMAスムージングを掛ける。高速フリック時に減速 = エイムアシスト感。

## ビルド
1. このリポジトリをGitHubにpush
2. Actions → Build AimAssist.dylib → Run workflow
3. 完了後 Artifacts から `AimAssist-dylib.zip` をダウンロード
4. 解凍して `AimAssist.dylib` を取り出す

## Esign注入手順
1. EsignでFortnite IPA (復号済み) を開く
2. 「Inject」→ dylib追加 → `AimAssist.dylib` を選択
3. 署名 → インストール

## 強度調整 (`Sources/AimAssist.m` 内)
| 定数 | 意味 | 推奨範囲 |
|---|---|---|
| `kSmoothing` | スムージング強度 | 0.50〜0.70 |
| `kAimZoneStart` | エイムゾーン開始位置 | 0.45〜0.55 |
| `kVelocityThreshold` | アシスト発動最小速度px | 5.0〜12.0 |

## 注意
- Fortnite (EAC搭載) はBANリスクあり。自己責任で使用すること
- decrypted IPAは自分で用意する (AppDB / Scarlet 等)
