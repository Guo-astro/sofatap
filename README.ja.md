# Sofatap

[English](README.md) · [简体中文](README.zh-CN.md) · **日本語**

**iPhone を、リビングのパソコンのリモコンに。**

![Sofatap の利用シーン：ソファに座り、iPhone でリビングのテレビにつないだパソコンを操作する](docs/images/sofatap-living-room.png)

*AI で生成した利用イメージです。アプリのスクリーンショットではありません。*

Sofatap は [chekusu](https://github.com/chekusu) が開発するオープンソースのリモコンアプリです。iPhone を、Windows・Mac・対応 Linux パソコンのジェスチャーマウスと音声・テキスト入力ツールとして使えます。パソコンの画面はテレビに映し、操作はソファから。

[リリース](https://github.com/chekusu/sofatap/releases) · [Issue](https://github.com/chekusu/sofatap/issues) · [MIT ライセンス](LICENSE)

## 紹介動画

[![Sofatap の紹介動画を見る：ジェスチャー、キーボード入力、音声入力で、テレビにつないだパソコンを iPhone から操作](https://sofatap.app/media/sofatap-demo-poster-ja.jpg)](https://sofatap.app/ja/#video)

ジェスチャーでのポインタ操作、iPhone のキーボード入力、音声入力をソファから試せる 1 分の紹介動画です。[sofatap.app で紹介動画を見る](https://sofatap.app/ja/#video)（日本語ナレーション・字幕）。字幕付き MP4 のダウンロード：[英語版](https://sofatap.app/exports/sofatap-promo-en.mp4) · [簡体字中国語版](https://sofatap.app/exports/sofatap-promo-zh-cn.mp4)。

## できること

- 大きな角丸のタッチ面に、接続先の選択、専用ガイド、マイク、キーボードの操作をまとめています。背景全体にゆっくり動くドットの格子を表示し、触れた場所の近くがゆがみ、タップで波紋が広がります。タッチ面には説明文を置きません。「視差効果を減らす」が有効な場合は、格子を静止させて簡単な反応だけを表示します。
- スワイプして移動、1 回タップで左クリック、2 回連続タップで右クリック、300 ms 長押しでドラッグ、2 本指でスクロールできます。
- 下部のマイクから、対応する端末・言語では端末内の音声認識を利用できます。iPhone キーボード／Typeless も使用可能です。対応する入力欄ではリアルタイム入力が標準で、確定した文字、削除、選択範囲、音声認識の更新を**送信**ボタンなしで同期します。未対応の欄や古い受信アプリでは、下書きを確認して送信します。追加の Enter やフォーム送信操作は行いません。
- **パソコンのネイティブウインドウ**に表示された QR コードでペアリング。Mac は AppKit/SwiftUI、Windows は WinForms、Linux は GTK3 を使用し、ブラウザを開く必要はありません。
- 3 つのデスクトップ受信アプリは、選定済みの **Mint Calm（暮色薄荷）** デザインを使用します。チャコールの背景、淡いミント色の操作ボタン、白地の QR 領域と現在の Sofatap アイコンを、今回のベータパッケージに含めています。[デザイン仕様](docs/RECEIVER-DESIGN.md)をご覧ください。
- 家庭内ネットワークで接続し、WSS/TLS、証明書の固定検証、ローカルのペアリング認証情報を使用します。パソコン側の編集との競合や切断時にはリアルタイム入力を一時停止し、結果が不明な編集を自動再送しません。

TestFlight ビルド 15 はデバイス管理と、公式サイトと同じ 12 言語（英語、簡体字中国語、日本語、韓国語、ドイツ語、フランス語、スペイン語、ブラジルポルトガル語、ロシア語、アラビア語、ヒンディー語、インドネシア語）に対応しています。アラビア語は右から左へ表示し、スクロール領域は画面の物理的な右端に保ちます。[対応言語](docs/APP-LANGUAGES.md)と[検証記録](docs/verification/device-library-2026-10-14.md)をご覧ください。

**現在のベータ版：** iPhone **1.0 (15)** は招待済みの内部 TestFlight テスター向けに公開され、常設テスト用 iPhone へのインストールも確認しました。[受信アプリ 0.7.1 beta.1](https://github.com/chekusu/sofatap/releases/tag/v0.7.1-beta.1) の QR コードにはデバイスの種類と名前が含まれます。**受信アプリの更新前に、iPhone をビルド 15 以降へ更新してください**。[10 月 14 日の配布記録](docs/verification/testflight-1.0-15.md)では、ビルド 12 が外部審査待ちのため Apple はビルド 15 の提出を受け付けず、[公開招待リンク](https://testflight.apple.com/join/e6MuKx9S)からのインストールも未開始でした。実際に確認した範囲は[受信アプリのリリース・デバイステスト記録](docs/verification/receiver-0.7.1.md)をご覧ください。

以前の [0.7.0 (10) の iPhone・Windows 限定実機検証](docs/verification/realtime-input-0.7.0.md)では、ネイティブ RichEdit の既存文章の読み込み、多言語・絵文字・改行の追記、キーボードでの削除、全選択、空欄までの削除を確認しました。最終ビルドでのリアルタイム音声と追加項目は未検証です。[0.6.0 の記録](docs/verification/2026-10-13-iphone-input.md)にはジェスチャー、マイク認識、明示的な文字送信を別途記載しています。パッケージと公証の確認は実入力の検証とは別です。Bluetooth とクラウド中継は未実装です。[操作仕様と今後の独立 CUA 構想](docs/INTERACTION.md)をご覧ください。

2 本指ではコンテンツをドラッグする感覚で、上へスワイプするとページの下側、下へスワイプすると上側を表示します。タッチ面の内側右端にあるスクロール領域はスクロールバーと同じ方向で、下へなぞるとページの下側へ進みます。ミント色の丸い送信ボタンは入力欄の内側右端に置き、文字と重ならない専用の余白を確保しています。小さなクリアとキーボード切り替えアイコンは背景なしで入力欄の左下に並びます。矢印は開閉に合わせて上下に変化し、アニメーションと触覚フィードバックを伴います。状態メッセージは同じ行の右側に表示し、文字数や入力対応状況は常時表示しません。確認後に送信するモードでは、送信済みの下書きに追記した部分だけを次回送信します。[入力欄のプレビュー](docs/images/device-library-20261014/ja-keyboard-open.png)をご覧ください。

左上のデバイス名から管理シートを開き、複数のパソコンやテレビを保存・切り替え、ローカル名の変更、切断、ペアリングの削除ができます。削除はこの iPhone のみが対象で、他のスマートフォンの権限は取り消しません。右上の疑問符から図解付きの専用ガイドを開けます。入力が必要なときだけタッチ面の下に編集欄が開きます。対応する欄はリアルタイム編集となり、その他は下書きを確認して送信できます。[オフラインのシミュレーター画面](docs/images/device-library-20261014/en-touchpad.png)と[ドット格子のプレビュー動画](docs/images/sofatap-touch-effects.mp4)をご覧ください。ローカルの描画を示すもので、実機 iPhone の入力や性能の検証結果ではありません。

**ビルド 15 の更新：**デバイスの追加は共通の**QR コードをスキャン**画面に入り、上部にカメラ、下部に対応プラットフォームの案内を表示します。種類を先に選ばず、パソコンや Android/Google TV のコードを読み取るかリンクを貼り付けます。アプリが接続方式を自動で選び、コードに含まれるプラットフォームと名前を表示し、認証接続の成功後に名前を付けられます。提案された名前を使うか変更して保存し、後から「マイデバイス」でローカル名を変更できます。LG webOS は引き続き IP の手動入力とテレビ上の許可を使います。Android/Google TV は実験的対応で、検証済みのテレビ機種やサードパーティ製テレビアプリはまだありません。

受信アプリ 0.7.1 beta.1 のパソコン用ペアリングコードには `platform` と `name` が含まれ、iPhone が Windows、Mac、Linux を自動識別します。新しいコードには **iPhone 1.0 ビルド 15 以降**が必要で、旧ビルドでは読み取れません。ビルド 15 は[受信アプリ 0.7.0 beta.1](https://github.com/chekusu/sofatap/releases/tag/v0.7.0-beta.1) の従来形式にも対応します。コードの表示情報は接続候補の識別に使い、実際の接続では証明書とペアリング認証情報を検証します。

**ロードマップ：**無料の手動マウス・タッチ操作は現在パソコンに対応し、次にテレビへの直接接続を目指します。テレビ上の実際のポインター操作は個別に検証し、方向キーによるフォーカス移動とは区別します。基本の音声文字起こしは無料の入力機能です。有料の音声目標による自動操作は、まず Windows・macOS・Linux の複数手順のタスク、その後テレビへ広げます。今回のベータ版のテレビ操作は実験的プレビューで、自動操作とサブスクリプションは未提供です。[ロードマップと検証目標](docs/ROADMAP.md)、[自動化の調査](docs/research/natural-language-pro.md)をご覧ください。

**テレビ開発プレビュー：**ソースに LG webOS のプライベート IPv4 アドレスによるネイティブペアリングと、ポインター移動・タップ・スクロール・戻る・ホームを追加しました。ローカルのプロトコルと TLS テストは通過しましたが、実機検証済みのテレビ機種はまだありません。自動検出とテレビへの文字入力・音声入力は今後の実装です。[技術計画](docs/research/tv-implementation-plan.md)と[検証範囲](docs/verification/webos-pointer-preview.md)をご覧ください。

**Android/Google TV プロトタイプ：**共通のネイティブレシーバーと iPhone の QR ペアリングをソースに追加しました。[Android ガイド](android/README.md)から開発用 APK をビルドできます。アクセシビリティのオーバーレイポインター、対応するコントロールのクリック・スクロール、戻る・ホーム・フォーカス移動を提供します。テレビでの文字入力・音声入力・ドラッグ・右クリックには未対応です。[ソフトウェア検証と実機評価](docs/verification/android-tv-probe.md)は別々に記録し、対応を保証するテレビ機種はまだありません。

対応する受信アプリが、アクセシビリティの属性を公開する新しい編集可能な入力欄を検出すると、iPhone のキーボードが自動で開きます。バックグラウンドの検出では欄の内容を読みません。その後リアルタイム編集を開始すると、対応する欄の全文と選択範囲をペアリング済みの iPhone に転送するため、Backspace や「すべて選択 → 削除」で既存の文章も編集できます。検出とリアルタイム編集の対応範囲は異なります。Windows のリアルタイム編集は現在ネイティブの Edit/RichEdit、Mac は選択テキストと選択範囲を書き換えられる Accessibility の欄に対応します。必要な機能を持たないブラウザーや独自描画の欄、Linux、古い受信アプリでは下書き確認後の送信を使います。パスワード欄と読み取り専用の欄ではリアルタイム編集を開始しません。[検出、データ処理、各 OS の制限](docs/TEXT-FOCUS.md)をご確認ください。

**Windows ロック画面の PIN 操作（検証中）：** iPhone のタッチパッドと手動 PIN 入力を基本とし、保存した PIN を Face ID で承認して入力する機能も検討しています。Microsoft アカウントのパスワードは要求しません。従来のアカウントパスワード実験は廃止し、通常の受信側と iPhone UI から無効化しました。ポインター診断、Windows 標準 PIN の受け付け、実機 iPhone の連携は別々に検証します。ペアリングやビルド成功は動作確認を意味しません。[範囲と検証](docs/FACE-ID-UNLOCK.md)をご確認ください。

## プラットフォーム別の状況

| プラットフォーム | 現在の状況 |
| --- | --- |
| iPhone | iOS 17 以降。1.0 (15) は 12 言語に対応し、内部 TestFlight で配布中です。テスト用 iPhone へのインストールを確認しました。外部審査の状態は[配布記録](docs/verification/testflight-1.0-15.md)に記載しています。インストールの確認はカメラ読み取りや受信側入力の実機検証とは別です。[現在の検証記録](docs/verification/receiver-0.7.1.md)をご覧ください。 |
| Windows | 受信アプリ 0.7.1 beta.1 を公開済み。Edit/RichEdit のリアルタイム編集に対応します。以前の RichEdit キーボード操作は限定実機確認済みで、追加項目は未検証です。Windows バイナリに Authenticode 署名はありません。 |
| Mac | macOS 15 以降。0.7.1 beta.1 の Apple Silicon・Intel 両パッケージを署名・公証済み。以前の Apple Silicon 入力を一部確認していますが、現在のリアルタイム編集と Intel の入力は実機検証が必要です。 |
| Linux | 0.7.1 beta.1 の x64・ARM64 GTK3 パッケージを公開済みです。ARM64 版を隔離 Xvfb で実行し、実機 iPhone でカメラ読み取り、Linux の識別、命名・名前変更の保存を確認しました。以前の X11 入力検証は別の結果です。実際の Wayland コンポジターと物理 Linux デスクトップへの入力は未検証です。[現在の記録](docs/verification/receiver-0.7.1.md)をご覧ください。 |

[Mac の検証記録](docs/verification/macos-0.3.0.md)には、2026-10-11 に行った実カメラによるペアリング、TLS 接続、入力文字の完全一致確認、一部のキー・ポインター操作を記載しています。[Linux の検証記録](docs/verification/linux-0.4.0.md)は、ネイティブ GTK の描画、独立した Xvfb デスクトップでの X11 入力、プライベート D-Bus 上の模擬 Wayland portal を対象としています。すべてのアプリとの互換性を保証するものではありません。

ポインター、ショートカット、下書き送信は Windows の Win32 `SendInput`、Mac の明示的なアクセシビリティ許可後の Quartz を使います。リアルタイム編集は Win32 Edit/RichEdit メッセージまたは Mac Accessibility の選択テキスト操作で変更し、読み戻して確認します。変更範囲の外側は書き換えません。Linux X11 は libX11・libXtst・libxdo、Wayland は互換性のある RemoteDesktop portal とシステム画面での許可が必要です。Linux は現在下書き確認後の送信で、1 回につき最大 2,048 Unicode スカラー値を受け付け、クリップボードは読み書きしません。未対応の Wayland では入力を無効にし、XWayland に切り替えません。[Linux の要件と制限](desktop/linux/README.md)をご覧ください。

## 使い始める

### パソコン側の受信アプリをインストール

| パソコン | ダウンロード | 手順 |
| --- | --- | --- |
| Windows x64 | [Windows ZIP](https://github.com/chekusu/sofatap/releases/download/v0.7.1-beta.1/SofaTap-Windows-x64.zip) | 展開して `SofaTap.exe` を実行します。ファイアウォールは信頼できる家庭内のプライベートネットワークのみ許可してください。[Windows ガイド](docs/WINDOWS-START.md) |
| Mac | [Apple Silicon ZIP](https://github.com/chekusu/sofatap/releases/download/v0.7.1-beta.1/SofaTap-macOS-arm64-notarized.zip) · [Intel ZIP](https://github.com/chekusu/sofatap/releases/download/v0.7.1-beta.1/SofaTap-macOS-x64-notarized.zip) | 両方とも公証済みです。[Mac のインストールと権限設定](docs/MAC-START.md)を参照してください。 |
| Linux x64 / ARM64 | [x64 アーカイブ](https://github.com/chekusu/sofatap/releases/download/v0.7.1-beta.1/SofaTap-Linux-x64.tar.gz) · [ARM64 アーカイブ](https://github.com/chekusu/sofatap/releases/download/v0.7.1-beta.1/SofaTap-Linux-arm64.tar.gz) | システムの GTK と入力関連の依存パッケージを入れ、展開後に `./sofatap` を実行します。ネイティブウインドウから Wayland の許可を開始できます。[Linux ガイド](desktop/linux/README.md) |

上記はすべて [0.7.1 beta.1 で、対応する SHA256 ファイルとリリースノート](https://github.com/chekusu/sofatap/releases/tag/v0.7.1-beta.1)を公開しています。.NET ランタイムを同梱し、Linux では記載のシステム依存パッケージが別途必要です。`--dry-run` はデスクトップへの入力なしで接続を試せます。過去の検証記録には、実際に試したバージョンを残しています。

### iPhone アプリをインストールしてペアリング

1. **受信アプリ 0.7.1 beta.1 の前に iPhone 1.0 (15) 以降をインストールしてください**。招待済みの内部テスターは TestFlight を利用できます。外部審査と[公開招待](https://testflight.apple.com/join/e6MuKx9S)の未完了項目は[10 月 14 日の配布記録](docs/verification/testflight-1.0-15.md)をご確認ください。自分でビルドする場合は、Xcode で `ios/SofaTap.xcodeproj` を開き、自分の開発チームと接続した iPhone を選んで実行します。この方法には開発署名、デバイスのペアリング、デベロッパモードが必要です。[iOS ビルドガイド](ios/README.md)を参照してください。
2. iPhone とパソコンを、互いに通信できる家庭内ネットワークにつなぎます。ゲスト Wi-Fi の端末分離設定によっては接続できません。
3. 左上のデバイス選択をタップし、**デバイスを追加**から**QR コードをスキャン**を選びます。パソコンと Android/Google TV は同じスキャナーを使い、認証成功後に名前を設定します。受信アプリのネイティブウインドウの QR コードを読み取るか、完全なペアリングリンクを貼り付けてください。
4. パソコンで入力欄を選び、iPhone のキーボードまたはマイクを開きます。対応する欄では文字、削除、音声認識の結果を自動同期します。未対応の欄では下書きを確認して**送信**します。フォーカスの競合や切断で一時停止した場合は、パソコン側を確認してから明示的に編集を再開してください。不明な編集は自動再送しません。

ペアリングリンクには操作用の認証情報が含まれます。自分のデバイス内で管理してください。最初期の **Tiltro** という名称のバージョンから更新する場合は、[アップグレードガイド](docs/WINDOWS-START.md#从旧名称版本升级)をご確認ください。当時の識別子と保存場所は異なるため、そのペアリングと下書きは自動移行されません。今回の Sofatap の表記統一では、既存の Sofatap のペアリングは維持されます。

## プライバシーと権限

Sofatap はローカルネットワークで直接接続し、このプロジェクトはクラウド中継サービスを提供していません。ペアリングでは TLS 証明書を固定して検証します。認証情報は iPhone の Keychain、Windows の DPAPI、または Mac/Linux 上の現在のユーザーのみ読み取り可能な受信アプリのファイルに保存します。Mac の入力にはアクセシビリティ権限、Wayland の入力には明示的な portal の許可が必要です。

マイクは明示的なタップと必要な権限の許可後にのみ起動します。対応する端末内の音声認識では音声は iPhone 内にとどまり、Sofatap は音声をアップロードせず、自動的にクラウド認識へ切り替えません。リアルタイム編集中は途中の認識結果と訂正をパソコンへ同期します。下書きモードでは**送信**を押すまでローカルに保持します。システムの音声入力やサードパーティ製キーボードには、それぞれ独自のデータ処理方針があります。

リアルタイム編集では、対応する現在の欄の全文と選択範囲を、証明書を固定検証した TLS 接続でペアリング済みの iPhone に直接転送します。取り込んだリアルタイムの文章は iPhone のメモリに保持し、自動で下書きには保存しません。接続先の切り替え後、残った文章の再送信を明示的に許可した場合だけ、確認して送信する端末内の下書きとして保存します。切り替えだけで文章を送信することはありません。受信アプリは重複編集を防ぐため、文章を含む確認応答を接続中の上限付きメモリに保持します。接続終了後にこのキャッシュを保持しません。確認して送信する別の下書きは復元用に端末内へ保存します。欄の文章はログやクラウドサービスへ送らず、バックグラウンドのフォーカス通知は属性情報だけです。

ペアリングの QR コードはローカルのプライベートパイプでネイティブ UI に渡し、Web ページは使いません。ペアリングコード、認証情報、署名用ファイルを公開しないでください。リポジトリには開発アカウント、署名証明書、プロビジョニングプロファイルを含めていません。通信と入力の仕様は [PROTOCOL.md](PROTOCOL.md)、未完了の実機検証は[受け入れチェックリスト](docs/ACCEPTANCE.md)をご覧ください。

## ソースからビルド

受信アプリには **.NET 10 SDK** と Python 3 が必要です。SDK を独自の場所に置いている場合は、`SOFATAP_DOTNET` に `dotnet` 実行ファイルのパスを設定してください。

```sh
# Mac/Unix 上で Windows 配布パッケージを作成
bash scripts/build-windows.sh

# macOS 上で Mac 配布パッケージを作成
bash scripts/build-macos.sh arm64
bash scripts/build-macos.sh x64

# Linux 配布パッケージを作成。クロスビルドにも対応
bash scripts/build-linux.sh x64
bash scripts/build-linux.sh arm64
```

成果物はライセンスと SHA256 ファイルとともに `artifacts/` に出力されます。Windows と Mac は `SofaTap-Windows-x64.zip`、`SofaTap-macOS-<architecture>.zip`、Linux は `SofaTap-Linux-<architecture>.tar.gz` です。Mac は標準で ad-hoc 開発署名を使用します。配布用の署名と Apple の公証手順は [NOTARIZATION.md](docs/NOTARIZATION.md) に記載しています。

Windows 開発者は PowerShell で受信コンポーネント単体をビルドできます。上記の完全な配布パッケージにはネイティブウインドウも含まれます。

```powershell
dotnet publish host/SofaTap.Host.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true
```

再配布する際は `LICENSE`、`THIRD-PARTY-NOTICES.md`、該当する依存関係のライセンスを同梱してください。パッケージ作成スクリプトは、実際に解決されたランタイムと NuGet のバージョンに対応するライセンスを収集します。

iPhone はリポジトリ内の Xcode プロジェクトを開いてください。`ios/project.yml` を変更した場合は `xcodegen generate --spec ios/project.yml` で再生成します。[iOS ガイド](ios/README.md)には直接コンパイルする方法も記載しています。デバイス向けビルドの成功と、署名・インストールの完了は別の確認項目です。

## 開発時の確認

.NET 10、Python 3、Xcode をインストールした Mac で実行します。

```sh
python3 -m pip install websockets==16.0
dotnet run --project tests/host/SofaTap.Host.Tests.csproj -c Release
dotnet run --project desktop/windows-login/Tests/Sofatap.Login.Tests.csproj -c Release
SOFATAP_DOTNET="$(command -v dotnet)" python3 tests/smoke.py
swiftc ios/SofaTap/Core/Pairing.swift tests/PairingTests.swift -o /tmp/sofatap-pairing-tests
/tmp/sofatap-pairing-tests
swiftc ios/SofaTap/Core/ReceiverState.swift tests/ReceiverStateTests.swift -o /tmp/sofatap-receiver-tests
/tmp/sofatap-receiver-tests
swiftc ios/SofaTap/Core/TouchGestureState.swift tests/TouchGestureTests.swift -o /tmp/sofatap-gesture-tests
/tmp/sofatap-gesture-tests
python3 tests/text_focus_linux.py
bash ios/scripts/build-manual.sh device
```

Host runner は模擬入力を使います。TLS/WebSocket の確認は一時的な受信アプリを `--dry-run` で起動し、システムに入力を送りません。最後のコマンドはプロビジョニング未設定の ARM64 iOS アプリをコンパイルするだけで、iPhone にはインストールしません。CI では各プラットフォームのビルドと隔離 Linux デスクトップの確認も行います。関連コマンドは [Linux ガイド](desktop/linux/README.md#lifecycle-and-checks)をご覧ください。

ビルド、プロトコル、仮想デスクトップ、実機の確認は検証範囲が異なります。[0.7.0 の実機記録](docs/verification/realtime-input-0.7.0.md)は RichEdit の読み込み、追記、削除、選択を確認しています。リアルタイム音声、通常の Edit、文章途中の置換、競合、再接続、Mac のリアルタイム編集、Typeless、追加アプリは確認済みの範囲に含みません。

## リポジトリ構成

| パス | 内容 |
| --- | --- |
| `ios/` | ネイティブ iPhone アプリ、Xcode プロジェクト、プロジェクト生成設定 |
| `host/` | 共通受信プロトコル、Windows/Mac 入力バックエンド、Linux worker へのブリッジ |
| `desktop/` | ネイティブのペアリングウインドウと Linux 入力 worker |
| `tests/` | プロトコル、認証、入力境界の確認 |
| `PROTOCOL.md` | 通信プロトコル |
| `docs/` | インストールガイドと検証記録 |
| `scripts/build-*.sh` | パソコン用配布パッケージのビルド |
| `licenses/` | サードパーティのライセンス・通知の原文 |

ローカルのビルド成果物、ペアリング認証情報、署名用ファイルはソースに含めません。名称の背景は [NAME.md](docs/NAME.md) をご覧ください。

## コントリビューションとライセンス

Issue とプルリクエストを歓迎します。参加する前に [CONTRIBUTING.md](CONTRIBUTING.md) をお読みください。

Sofatap は [MIT ライセンス](LICENSE)で公開しています。依存関係の通知は [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) をご覧ください。
