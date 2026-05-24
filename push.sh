#!/bin/bash
# ╔══════════════════════════════════════════════════════════╗
# ║   말트임 일본어 — 기능 개선 후 자동 GitHub 업로드       ║
# ║   사용법: ./push.sh "추가한 기능 설명"                  ║
# ╚══════════════════════════════════════════════════════════╝

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# ── 커밋 메시지 ───────────────────────────────────────────
MSG="${1:-feat: 기능 개선}"

# git 변경사항 확인
if [ -z "$(git status --porcelain)" ]; then
  echo "ℹ️  변경된 파일이 없습니다."
  exit 0
fi

# 변경 파일 출력
echo "📦 변경된 파일:"
git status --short
echo ""

# 스테이징 + 커밋
git add -A
git commit -m "$MSG

[자동 업로드] $(date '+%Y-%m-%d %H:%M:%S')"

# Push
echo "⬆️  GitHub에 업로드 중..."
git push origin main

echo ""
echo "✅ 업로드 완료! — $MSG"
REMOTE=$(git remote get-url origin | sed 's/https:\/\/[^@]*@/https:\/\//')
echo "🔗 $REMOTE"
