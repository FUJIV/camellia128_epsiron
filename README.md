# camellia128_epsiron

Camellia-128(鍵長・ブロック長ともに128bit)の暗号化・復号コア。8bitバイトシリアルで入出力し、
回路規模の最小化を目的とした実装。Verilog-2001、外部ファイル依存なし(RTLは`` `readmemh``等を使わず自己完結)。

- モジュールの使い方・インタフェース: [`docs/usage.md`](docs/usage.md)

## ディレクトリ構成

```
src/   RTL本体(cam_s1, cam_dp, cam_ctrl, camellia128_epsiron トップ)
sim/   テストベンチ・シミュレーション実行用 Makefile
syn/   Vivado OOC(out-of-context)合成スクリプト(サイズ評価用)
tv/    テストベクタ・テーブル定義(s1表、鍵ROM内容、Pカラムマスク、暗号化ベクタ)
model/ サイクル精度の参照モデル(Python、RTLの期待値・トレースの元)
docs/  設計仕様書・使い方ガイド
```

## 必要なツール

- シミュレータ: AMD Vivado の `xvlog`/`xelab`/`xsim`(本プロジェクトでは Vivado 2025.2 で動作確認済み)
- Lint: [Verilator](https://www.veripool.org/verilator/)(`--lint-only -Wall`)
- 参照モデル・検証データ生成: Python 3(`model/camellia_ref.py`)
- 論理合成(任意): Vivado(`vivado` コマンド、OOC合成)

`xvlog`/`xelab`/`xsim`/`vivado` が `PATH` に無い場合は、`make` 実行時に `VIVADO_BIN=/path/to/Vivado/bin` を渡せばよい(例は後述)。

## シミュレーション方法

すべて `sim/Makefile` から実行する(プロジェクトルートに `cd` してから叩いても、`sim/` から `make -C sim <target>` で叩いてもよい)。

```sh
# PATH に Vivado のツールがあればそのまま:
make -C sim test

# PATH に無い場合は VIVADO_BIN を渡す:
make -C sim test VIVADO_BIN=/path/to/Vivado/bin
```

### 主なターゲット

| ターゲット | 内容 |
|---|---|
| `make -C sim lint` | Verilator による lint(`--lint-only -Wall`、警告ゼロが合格) |
| `make -C sim s1` | `cam_s1`(S-box)単体テスト。全256入力を検証 |
| `make -C sim test` | `s1` に続けて、機能テスト一式(鍵設定・暗号化・復号・鍵変更・busy中のコマンド拒否・リセット・サイクル数・全テストベクタ)をストールなしで実行 |
| `make -C sim stall` | `test` と同内容を `in_valid`/`out_ready` をランダムに落とすストールモード(`+STALL`)で実行 |
| `make -C sim trace` | RTLのサイクルトレースと `model/camellia_ref.py` の参照トレースを diff。既定ではRFC 3713ベクタの暗号化を比較する(下記参照) |
| `make -C sim clean` | シミュレーションのビルド成果物を削除 |
| `make -C sim all` | `lint` → `test` → `stall` → `trace` を通しで実行 |

実行結果は最後に `PASS` または `FAIL <件数>` が出力される。`trace` は `TRACE MATCH` または差分内容を出力する
(KSTOREフェーズの `k` 列のみ、鍵RAMのポート共有による既知の無害な差異が出るが、それ以外が一致していれば問題ない)。

### `trace` の鍵・平文を変える

```sh
make -C sim trace KEY=00000000000000000000000000000000 \
                   PT=00000000000000000000000000000000 \
                   MODE=enc   # または dec
```

### 個別にテストベンチを動かす場合(Makefileを使わない例)

```sh
export PATH=/path/to/Vivado/bin:$PATH
cd camellia128_epsiron   # プロジェクトルート(tv/*.hex への相対パスを解決するため必須)

xvlog src/cam_s1.v src/cam_dp.v src/cam_ctrl.v src/camellia128_epsiron.v sim/tb_camellia128_epsiron.v
xelab -debug typical -s tb_main_snap work.tb_camellia128_epsiron
xsim tb_main_snap -runall                  # ストールなし
xsim tb_main_snap -runall -testplusarg STALL   # ストールあり(+STALL)
xsim tb_main_snap -runall -testplusarg TRACE   # 全コマンドのサイクルトレースを sim_trace.log に出力
```

## 参照モデル(Python)の使い方

```sh
python3 model/camellia_ref.py selftest      # RFC 3713ベクタ + 乱数2000本の自己検証
python3 model/camellia_ref.py gen tv 200    # tv/ 配下のhexファイルを再生成
python3 model/camellia_ref.py trace <KEY> <PT> [enc|dec]   # サイクルトレースを標準出力
```

## 論理合成(サイズ評価)

```sh
make -C syn VIVADO_BIN=/path/to/Vivado/bin
```

`syn/run/`(gitignore対象、再生成可能)にレポートが出力される。現時点の結果: LUT 470 / FF 146 / BRAM 0 / DSP 0
(デバイス `xcsu10p-cmva361-1-e`、OOC合成)。

## ライセンス

[BEERWARE](LICENSE) ;)
