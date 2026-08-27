#!/usr/bin/env bash
# 自动检查 Zed 官方新版本，并更新本仓库的 PKGBUILD / .SRCINFO。
# 供 .github/workflows/update-aur.yml 使用，也可在本地直接运行：
#   bash scripts/update-pkgbuild.sh          # 正常执行（会下载 tarball 刷新校验和）
#   DRY_RUN=1 bash scripts/update-pkgbuild.sh  # 只打印将要做什么，不写任何文件
set -euo pipefail

# 提交身份（AUR 上会显示这个作者信息，可自行修改）
COMMIT_NAME="knight731"
COMMIT_EMAIL="liuxiaopeng731@gmail.com"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

GITHUB_REPO="zed-industries/zed"
AUR_PKG="zed-bin"

# 失败时回滚 PKGBUILD/.SRCINFO，避免留下半更新状态
cleanup() {
    git checkout -- PKGBUILD .SRCINFO 2>/dev/null || true
}
trap cleanup ERR

# --- 1. 从 GitHub API 获取最新 stable release 的 tag（如 v1.17.2）---
api="$(curl -fsSL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest")"
latest_tag="$(printf '%s' "$api" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)"
[ -n "$latest_tag" ] || { echo "ERROR: 无法从 GitHub API 读取 tag_name"; exit 1; }
new_ver="${latest_tag#v}"

# 格式校验：必须是 X.Y.Z 形式的版本号
case "$new_ver" in
    [0-9]*\.[0-9]*\.[0-9]*) ;;
    *) echo "ERROR: 意外的 release tag: '$latest_tag'"; exit 1 ;;
esac

cur_ver="$(sed -n 's/^pkgver=//p' PKGBUILD)"
echo "最新版本: $latest_tag | 当前 pkgver: $cur_ver"

# --- 2. 已是最新则退出 ---
if [ "$new_ver" = "$cur_ver" ]; then
    echo "已经是最新版本，无需更新。"
    exit 0
fi

# 只升级不降级
newer="$(printf '%s\n%s\n' "$new_ver" "$cur_ver" | sort -V | tail -n1)"
if [ "$newer" != "$new_ver" ]; then
    echo "WARNING: 远端 tag ($new_ver) 比当前 pkgver ($cur_ver) 旧，跳过。"
    exit 0
fi

echo "开始更新 ${AUR_PKG}: $cur_ver -> $new_ver"

# --- 3. dry-run：只打印不改动 ---
if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run] 将执行：pkgver=$new_ver, pkgrel=1, updpkgsums, 重新生成 .SRCINFO, 提交"
    exit 0
fi

# --- 4. 应用版本号（上游版本变更时 pkgrel 归 1）---
sed -i "s/^pkgver=.*/pkgver=${new_ver}/" PKGBUILD
sed -i "s/^pkgrel=.*/pkgrel=1/" PKGBUILD

# --- 5. 刷新 sha256sums（会下载 x86_64 + aarch64 两个 tarball，约 300MB）---
updpkgsums

# --- 6. 重新生成 .SRCINFO ---
makepkg --printsrcinfo > .SRCINFO

# --- 7. 提交（仅当确实有改动时）---
if git status --porcelain | grep -qE 'PKGBUILD|\.SRCINFO'; then
    git add PKGBUILD .SRCINFO
    git -c user.name="$COMMIT_NAME" -c user.email="$COMMIT_EMAIL" \
        commit -m "upgpkg: ${AUR_PKG} ${new_ver}-1"
    echo "已提交: upgpkg: ${AUR_PKG} ${new_ver}-1"
else
    echo "没有需要提交的改动。"
fi
