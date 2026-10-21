# DesktopTimer

macOS の画面の右上に浮かぶ、小さな作業タイマー。
全画面のアプリや他の窓より上に出続けるので、何をしていても残り時間が目に入る。

## できること

- 残り時間を常に最前面に表示する。全画面アプリの上や、どのデスクトップにも出る
- 「やることを入力」に、この時間でやることを1行メモできる
- 時間は数字を打つか、15分・30分・60分のボタンで決める
- 「時刻」ボタンで、指定の時刻までを数える
- 0になると、すべての画面を赤く覆って知らせる
- 早く終わったら完了ボタンで、かかった時間を添えてお祝いする
- 「−」で小さな丸にたためる。丸の縁に進み具合が出る
- 背景色16色と透明度を選べる
- どこを掴んでも運べる。画面の端に寄せると押し戻される
- ログイン時に自動で起動する

## 動く環境

- macOS 14 Sonoma 以降
- Apple シリコンと Intel のどちらでも動く

## 入れ方

ターミナルに次の1行を貼って実行する。

```sh
curl -fsSL https://raw.githubusercontent.com/totsukash/desktop-timer/main/install.sh | bash
```

次のことを自動でする。

- 最新の配布版をダウンロードし、`~/Applications/DesktopTimer.app` に置く
- ログイン時に起動するよう `~/Library/LaunchAgents/com.totsukash.desktop-timer.plist` を置く
- アプリを起動する

更新するときも同じ1行を実行する。
初回に「バックグラウンド項目が追加されました」と出るのは、ログイン時の起動を登録したため。

### ソースからビルドして入れる

Xcode か Command Line Tools が要る。
入っていなければ `xcode-select --install` で入れる。

```sh
git clone https://github.com/totsukash/desktop-timer.git
cd desktop-timer
./install.sh
```

リポジトリの中で `./install.sh` を実行すると、ダウンロードせず手元でビルドしたものを入れる。

### 配布版を出す

```sh
./release.sh v1.0.0
```

Apple シリコンと Intel の両方で動く版を作り、GitHub のリリースに上げる。

## 使い方

### 時間を決めて始める

- 大きな数字を押して時間を打ち、Enter で始まる
  - `25` で25分
  - `1:30` で1分30秒
  - `1:00:00` で1時間
- 「15分」「30分」「60分」を押すと、その時間がセットされる
- 「時刻」を押して `8:00` や `830` を打つと、その時刻までを数える
- 下の段のボタンは、左からリセット・開始/一時停止・完了

### やることのメモ

- 上の「やることを入力」を押して打ち、Enter で決まる
- 時間切れの画面と、完了のお祝いにも表示される

### 時間切れ

- すべての画面が赤くなる
- 「OK」か Enter で閉じる
- 閉じるまでは、残り時間が赤字で出続ける

### 小さくたたむ

- 右上の「−」で、小さな丸になる
- 丸を押すと元に戻る

### 設定

- 歯車のボタンで開く
- 背景色と透明度を選べる。選んだ値は次に起動したときも使う

### 移動

- 文字やボタンの上も含め、どこを掴んでも運べる
- 入力中の欄と透明度のつまみの上だけは、文字選びとつまみの操作になる
- 置いた位置は覚えていて、次に起動したときもそこに出る

### 終了

- 背景を右クリックして「終了」、または設定の「終了」

## 消し方

```sh
launchctl unload ~/Library/LaunchAgents/com.totsukash.desktop-timer.plist 2>/dev/null
rm ~/Library/LaunchAgents/com.totsukash.desktop-timer.plist
pkill -x DesktopTimer
rm -rf ~/Applications/DesktopTimer.app
```
