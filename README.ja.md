# Sofatap

[English](README.md) · [简体中文](README.zh-CN.md) · **日本語**

**iPhone を、リビングのパソコンのリモコンに。**

![Sofatap の利用シーン：ソファに座り、iPhone でリビングのテレビにつないだパソコンを操作する](docs/images/sofatap-living-room.png)

*AI で生成した利用イメージです。アプリのスクリーンショットではありません。*

Sofatap は [chekusu](https://github.com/chekusu) が開発するオープンソースのリモコンアプリです。iPhone を、Windows・Mac・対応 Linux パソコンのジェスチャーマウスと音声・テキスト入力ツールとして使えます。パソコンの画面はテレビに映し、操作はソファから。

[リリース](https://github.com/chekusu/sofatap/releases) · [Issue](https://github.com/chekusu/sofatap/issues) · [MIT ライセンス](LICENSE)

## できること

- ひとつのタッチ面で、スワイプして移動、1 回タップで左クリック、2 回連続タップで右クリック、300 ms 長押しでドラッグ、2 本指でスクロールできます。
- 下部のマイクから、対応する端末・言語では端末内の音声認識を利用できます。iPhone キーボード／Typeless も使用可能です。下書きを確認して**送信**すると、パソコンでフォーカスされた欄に入力します。Enter や送信操作は追加せず、文章内の改行は保持します。
- **パソコンのネイティブウインドウ**に表示された QR コードでペアリング。Mac は AppKit/SwiftUI、Windows は WinForms、Linux は GTK3 を使用し、ブラウザを開く必要はありません。
- 家庭内ネットワークで接続し、WSS/TLS、証明書ピンニング、ローカル保存のペアリング認証情報を使用。下書きの保持、送信確認、切断後の自動再送の禁止により、意図しない重複入力を防ぎます。

**現在はアルファプレビュー版です。** 単一画面のジェスチャー、マイク、入力欄の検出は `main` の 0.5.0 開発ソース（iPhone ビルド 6）に含まれます。下記のダウンロードは以前のアルファ版で、これらの変更は含まれません。実機 iPhone の操作・音声、Typeless、アプリごとのフォーカス動作は引き続き検証が必要です。Bluetooth とクラウド中継は未実装です。[操作仕様と今後の独立 CUA 構想](docs/INTERACTION.md)をご覧ください。

対応する受信アプリが、アクセシビリティの属性を公開する新しい編集可能なネイティブ／Web の入力欄を検出すると、iPhone のキーボードが自動で開きます。欄の内容は読みません。未対応・読み取り専用・保護された欄では自動表示しません。Linux の検出には任意の AT-SPI ブリッジが必要です。手動でもキーボードを開けます。[検出方式と各 OS の制限](docs/TEXT-FOCUS.md)をご確認ください。

## プラットフォーム別の状況

| プラットフォーム | 現在の状況 |
| --- | --- |
| iPhone | iOS 17 以降。iPhone 17 Pro Max の 0.3.0 (4) で、Mac との一部の実機連携を確認済み。0.5.0 (6) の単一画面のジェスチャー、マイク、自動キーボードは実機検証が必要です。 |
| Windows | 0.3.0 でネイティブ受信アプリを公開済み。このバージョンのデスクトップ UI と実機 iPhone 連携は検証待ちです。 |
| Mac | macOS 15 以降。Apple Silicon・Intel 両方のパッケージを公証済み。Apple Silicon では一部の実機検証が完了し、Intel の実入力は未検証です。 |
| Linux | 0.4.0 で GTK3 のネイティブ受信アプリを公開済み。X11 入力は隔離デスクトップで検証済み。Wayland portal は実験的対応で、実機 iPhone 連携、実際の Wayland コンポジター、ARM64 での動作は未検証です。 |

[Mac の検証記録](docs/verification/macos-0.3.0.md)には、2026-10-11 に行った実カメラによるペアリング、TLS 接続、入力文字の完全一致確認、一部のキー・ポインター操作を記載しています。[Linux の検証記録](docs/verification/linux-0.4.0.md)は、ネイティブ GTK の描画、独立した Xvfb デスクトップでの X11 入力、プライベート D-Bus 上の模擬 Wayland portal を対象としています。すべてのアプリとの互換性を保証するものではありません。

Windows は Win32 `SendInput`、Mac はユーザーが明示的にアクセシビリティ権限を許可した後に Quartz を使用します。Linux の X11 は libX11・libXtst・libxdo が必要です。Wayland は互換性のある RemoteDesktop portal と、システムのネイティブ画面でのユーザー許可が必要です。Linux では 1 回につき最大 2,048 Unicode スカラー値のテキストを受け付け、クリップボードを読み書きしません。未対応の Wayland セッションでは入力を無効にし、XWayland へのフォールバックは行いません。[Linux の要件と制限](desktop/linux/README.md)をご覧ください。

## 使い始める

### パソコン側の受信アプリをインストール

| パソコン | ダウンロード | 手順 |
| --- | --- | --- |
| Windows x64 | [v0.3.0-alpha](https://github.com/chekusu/sofatap/releases/tag/v0.3.0-alpha)：`SofaTap-Windows-x64.zip` と対応する `.sha256` | 展開して `SofaTap.exe` を実行します。ファイアウォールは信頼できる家庭内のプライベートネットワークのみ許可してください。[Windows ガイド](docs/WINDOWS-START.md) |
| Mac | [v0.3.0-alpha](https://github.com/chekusu/sofatap/releases/tag/v0.3.0-alpha)：`SofaTap-macOS-arm64-notarized.zip` または `SofaTap-macOS-x64-notarized.zip` と対応する `.sha256` | Apple Silicon または Intel 用を選びます。どちらも公証済みです。[Mac のインストールと権限設定](docs/MAC-START.md)を参照してください。 |
| Linux x64 / ARM64 | [v0.4.0-alpha](https://github.com/chekusu/sofatap/releases/tag/v0.4.0-alpha)：`SofaTap-Linux-x64.tar.gz` または `SofaTap-Linux-arm64.tar.gz` と対応する `.sha256` | システムの GTK と入力関連の依存パッケージを入れ、展開後に `./sofatap` を実行します。ネイティブウインドウから Wayland の許可を開始できます。[Linux ガイド](desktop/linux/README.md) |

パソコン側のパッケージには .NET ランタイムを同梱しています。Linux ではガイドに記載したシステム依存パッケージが別途必要です。`--dry-run` ではデスクトップへの入力を発生させずに接続を試せます。

### iPhone アプリをインストールしてペアリング

1. Xcode で `ios/SofaTap.xcodeproj` を開き、自分の開発チームと接続した iPhone を選択して実行します。有効な開発署名、デバイスのペアリング、デベロッパモードが必要です。[iOS ビルドガイド](ios/README.md)を参照してください。
2. iPhone とパソコンを、互いに通信できる家庭内ネットワークにつなぎます。ゲスト Wi-Fi の端末分離設定によっては接続できません。
3. 受信アプリのネイティブウインドウに表示された QR コードを iPhone アプリで読み取るか、完全なペアリングリンクを貼り付けます。
4. パソコンで入力欄を選び、iPhone で文章を入力・確認してから送信します。送信結果が不明な場合は、再送する前にパソコン側の内容を確認してください。

ペアリングリンクには操作用の認証情報が含まれます。自分のデバイス内で管理してください。最初期の **Tiltro** という名称のバージョンから更新する場合は、[アップグレードガイド](docs/WINDOWS-START.md#从旧名称版本升级)をご確認ください。当時の識別子と保存場所は異なるため、そのペアリングと下書きは自動移行されません。今回の Sofatap の表記統一では、既存の Sofatap のペアリングは維持されます。

## プライバシーと権限

Sofatap はローカルネットワークで直接接続し、このプロジェクトはクラウド中継サービスを提供していません。ペアリングでは TLS 証明書を固定して検証します。認証情報は iPhone の Keychain、Windows の DPAPI、または Mac/Linux 上の現在のユーザーのみ読み取り可能な受信アプリのファイルに保存します。Mac の入力にはアクセシビリティ権限、Wayland の入力には明示的な portal の許可が必要です。

マイクは明示的なタップと必要な権限の許可後にのみ起動します。対応する端末内の音声認識では音声は iPhone 内にとどまり、Sofatap は音声をアップロードせず、自動的にクラウド認識へ切り替えません。認識した文章は**送信**を押すまでローカルの下書きとして保持します。システムの音声入力やサードパーティ製キーボードには、それぞれ独自のデータ処理方針があります。

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

ビルド、プロトコル、仮想デスクトップ、実機での確認は、それぞれ検証する範囲が異なります。0.5.0 では実機でのシングル／ダブルタップ、300 ms 長押しドラッグ、スクロール、マイク権限と音声認識、Typeless、アプリごとの入力欄検出、各対応デスクトップとの iPhone 連携を引き続き検証する必要があります。

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
