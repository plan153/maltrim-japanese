#!/bin/bash
# ╔══════════════════════════════════════════════════════════╗
# ║   말트임 일본어 — 기능 개선 후 자동 GitHub 업로드       ║
# ║   사용법: ./push.sh "추가한 기능 설명"                  ║
# ╚══════════════════════════════════════════════════════════╝

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

GITHUB_USER="plan153"
REPO_NAME="maltrim-japanese"

# ── 인증 토큰 로드 (.env 파일에서) ───────────────────────
if [ -f ".env" ]; then
  source .env
fi

if [ -z "$GITHUB_TOKEN" ]; then
  read -s -p "🔑 GitHub Token: " GITHUB_TOKEN
  echo ""
fi

# ── 커밋 메시지 ───────────────────────────────────────────
MSG="${1:-feat: 기능 개선}"

REMOTE_URL="https://${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${REPO_NAME}.git"
TMP_DIR=$(mktemp -d)

# ── 클린 클론 ─────────────────────────────────────────────
echo "📥 클론 중..."
GIT_TERMINAL_PROMPT=0 git clone "$REMOTE_URL" "$TMP_DIR" 2>&1

# ── 변경 파일 복사 (audio/ 포함, .env / *.json 제외) ─────
rsync -a --exclude='.git' --exclude='.env' --exclude='*.json' \
  "$SCRIPT_DIR/" "$TMP_DIR/"

# ── 변경사항 확인 ─────────────────────────────────────────
cd "$TMP_DIR"
if [ -z "$(git status --porcelain)" ]; then
  echo "ℹ️  변경된 파일이 없습니다. 이미 최신 상태예요."
  rm -rf "$TMP_DIR"
  exit 0
fi

echo "📦 변경된 파일:"
git status --short
echo ""

# ── 커밋 + 푸시 ──────────────────────────────────────────
git add -A
git commit -m "$MSG

[자동 업로드] $(date '+%Y-%m-%d %H:%M:%S')"

echo "⬆️  GitHub 업로드 중..."
GIT_TERMINAL_PROMPT=0 git push origin main

rm -rf "$TMP_DIR"

echo ""
echo "✅ 완료! — $MSG"
echo "🔗 https://github.com/${GITHUB_USER}/${REPO_NAME}"
