#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/.github/prompts/開発用プロンプト.prompt.md"

REPOS=(
  "git@github.com:officeharukaze/ToremaruHome.git"
  "git@github.com:officeharukaze/ToremaruSignage.git"
  "git@github.com:officeharukaze/ToremaruSync.git"
)

CLONE_DIR="$ROOT/.external_repos"
mkdir -p "$(dirname "$OUT")" "$CLONE_DIR"

echo "[generate_dev_prompt] Ensuring reference repos are cloned/updated in $CLONE_DIR"
for repo in "${REPOS[@]}"; do
  name=$(basename "$repo" .git)
  dir="$CLONE_DIR/$name"
  if [ -d "$dir/.git" ]; then
    echo "[generate_dev_prompt] Updating $name"
    git -C "$dir" fetch --depth=1 origin || true
    # try to pull current branch if it exists
    curbranch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [ -n "$curbranch" ]; then
      git -C "$dir" pull --ff-only origin "$curbranch" || true
    fi
  else
    echo "[generate_dev_prompt] Cloning $name"
    git clone --depth 1 "$repo" "$dir" || true
  fi
done

gather_info(){
  local dir="$1"
  if [ ! -d "$dir" ]; then
    echo "(not cloned)"
    return
  fi
  local commit branch gradver kv compileSdk minSdk targetSdk out
  commit=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo "-")
  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "-")
  out="commit=$commit; branch=$branch"

  if [ -f "$dir/gradle/wrapper/gradle-wrapper.properties" ]; then
    gradurl=$(awk -F= '/distributionUrl/ {print $2}' "$dir/gradle/wrapper/gradle-wrapper.properties" 2>/dev/null || echo "")
    gradver=$(echo "$gradurl" | sed -E 's/.*gradle-([0-9.]+).*/\1/' || echo "")
    if [ -n "$gradver" ]; then out+="; gradle=$gradver"; fi
  fi

  if [ -f "$dir/gradle/libs.versions.toml" ]; then
    kv=$(awk -F= '/kotlin/ {gsub(/"/,"",$2); print $2; exit}' "$dir/gradle/libs.versions.toml" 2>/dev/null || echo "")
    kv=$(echo "$kv" | tr -d ' \t\n"')
    if [ -n "$kv" ]; then out+="; kotlin=$kv"; fi
  else
    kv=$(grep -R "kotlin(" "$dir" 2>/dev/null | head -n1 | sed -E 's/.*kotlin\("?([^"\)]+)"?\).*/\1/' || echo "")
    if [ -n "$kv" ]; then out+="; kotlin=$kv"; fi
  fi

  if [ -f "$dir/app/build.gradle.kts" ]; then
    compileSdk=$(grep -E "compileSdk\(" "$dir/app/build.gradle.kts" 2>/dev/null | sed -E 's/.*\(([^\)]+)\).*/\1/' | tr -d ' ' | head -n1 || echo "")
    minSdk=$(grep -E "minSdk\s*=" -n "$dir/app/build.gradle.kts" 2>/dev/null | sed -E 's/.*=\s*([^\s]+).*/\1/' | head -n1 || echo "")
    targetSdk=$(grep -E "targetSdk\s*=" -n "$dir/app/build.gradle.kts" 2>/dev/null | sed -E 's/.*=\s*([^\s]+).*/\1/' | head -n1 || echo "")
    if [ -n "$compileSdk" ]; then out+="; compileSdk=$compileSdk"; fi
    if [ -n "$minSdk" ]; then out+="; minSdk=$minSdk"; fi
    if [ -n "$targetSdk" ]; then out+="; targetSdk=$targetSdk"; fi
  fi

  echo "$out"
}

# collect and write info directly (avoid associative arrays for macOS bash)

cat > "$OUT" <<EOF
# 開発用プロンプト

このリポジトリの開発を行う際に使用するアシスタント向けのプロンプトです。

目的
- このリポジトリを素早く理解し、コード変更のたびにビルドを実行してビルドエラーを解析・修正すること。
- 参考リポジトリ:
  - git@github.com:officeharukaze/ToremaruHome.git
  - git@github.com:officeharukaze/ToremaruSignage.git
  - git@github.com:officeharukaze/ToremaruSync.git

参考リポジトリのバージョン情報（このスクリプトが収集）
EOF

for repo in "${REPOS[@]}"; do
  name=$(basename "$repo" .git)
  dir="$CLONE_DIR/$name"
  info=$(gather_info "$dir")
  echo "- $name: $info" >> "$OUT"
done

cat >> "$OUT" <<'EOF'

ルール
- コードを変更したら必ずビルドを実行する。
- ビルドが失敗した場合、ログを読み取り、根本原因を特定して修正を試みる。
- 修正は最小限に留め、既存のコードスタイルと依存関係に従う。
- ビルドエラーが完全に解消されるまで、ビルドは自動で繰り返し実行する（`scripts/watch_and_build.sh` を利用）。

ローカルでの推奨ワークフロー
1. 参考リポジトリが必要ならローカルにクローンして参照する。
2. ビルドとインストール／実行は `./scripts/install_and_run.sh` を使う。
3. 変更を検知して自動でビルドしたい場合は `./scripts/watch_and_build.sh` を使う。

よく使うコマンド
- ビルド（詳細ログ）:
  - `./gradlew assembleDebug --stacktrace`
- スクリプトでビルド・インストール・起動:
  - `./scripts/install_and_run.sh`
- 変更監視して自動でビルド（ビルドが成功するまでリトライ）:
  - `./scripts/watch_and_build.sh`

修正ポリシー
- まずビルドログを読み、根本原因を見つける。
- 可能なら最小のコード修正で解決する（例: リソース参照の修正、属性名の変更、import 修正、Gradle 設定の微調整）。
- 外部環境（JDK など）の問題であれば、`gradle.properties` に `org.gradle.java.home` を追加するなどして環境を固定する。

自動化ツール
- `scripts/generate_dev_prompt.sh`: このファイルを（必要に応じて）自動生成／更新するスクリプト。
- `scripts/watch_and_build.sh`: 変更を検知して `./scripts/install_and_run.sh` を実行、ビルドが成功するまで再試行するスクリプト。

注意事項
- このプロンプトはアシスタントと人間の協働を前提としています。アシスタントは診断と最小修正を試みますが、設計上の大きな変更は事前に相談してください。

EOF

echo "[generate_dev_prompt] Wrote $OUT"
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/.github/prompts/開発用プロンプト.prompt.md"

REPOS=(
  "git@github.com:officeharukaze/ToremaruHome.git"
  "git@github.com:officeharukaze/ToremaruSignage.git"
  "git@github.com:officeharukaze/ToremaruSync.git"
)

mkdir -p "$(dirname "$OUT")"

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/.github/prompts/開発用プロンプト.prompt.md"

REPOS=(
  "git@github.com:officeharukaze/ToremaruHome.git"
  "git@github.com:officeharukaze/ToremaruSignage.git"
  "git@github.com:officeharukaze/ToremaruSync.git"
)

mkdir -p "$(dirname "$OUT")"

cat > "$OUT" <<'EOF'
# 開発用プロンプト

このリポジトリの開発を行う際に使用するアシスタント向けのプロンプトです。

目的
- このリポジトリを素早く理解し、コード変更のたびにビルドを実行してビルドエラーを解析・修正すること。
- 参考リポジトリ:
  - git@github.com:officeharukaze/ToremaruHome.git
  - git@github.com:officeharukaze/ToremaruSignage.git
  - git@github.com:officeharukaze/ToremaruSync.git

ルール
- コードを変更したら必ずビルドを実行する。
- ビルドが失敗した場合、ログを読み取り、根本原因を特定して修正を試みる。
- 修正は最小限に留め、既存のコードスタイルと依存関係に従う。
- ビルドエラーが完全に解消されるまで、ビルドは自動で繰り返し実行する（ウォッチャーを利用）。

ローカルでの推奨ワークフロー
1. 参考リポジトリが必要ならローカルにクローンして参照する。直接依存しない限り、READMEや実装を参照用に使う。
2. ビルドとインストール／実行は `./scripts/install_and_run.sh` を使う。
3. 変更を検知して自動でビルドしたい場合は `./scripts/watch_and_build.sh` を使う。

デバッグとログ取得
- ビルド失敗時は `./gradlew assembleDebug --stacktrace` を実行して詳細を収集する。
- 取得したスタックトレースは問題切り分けに使う。可能な限りコードで修正して再ビルドする。

修正ポリシー
- コンパイルエラーやリソースリンクエラーなどは優先的に修正する。
- 外部環境（JDK のバージョンなど）が原因であればプロジェクト設定（`gradle.properties` に `org.gradle.java.home` を追加する等）を提案・適用する。
- 依存関係のバージョン衝突や破壊的な変更が必要な場合はまず提案し、合意後に変更を適用する。

自動化ツール
- `scripts/generate_dev_prompt.sh`: このプロンプトを自動生成／更新するスクリプト。
- `scripts/watch_and_build.sh`: 変更を検知して `./scripts/install_and_run.sh` を実行、ビルドが成功するまで再試行する。

注意事項
- このプロンプトは人間のレビューと調整を前提としています。アシスタントが自動で全てのビルドエラーを直せるわけではありませんが、可能な限り診断と最小修正を試みます。

EOF

echo "[generate_dev_prompt] Wrote $OUT"
