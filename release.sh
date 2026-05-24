#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║   말트임 일본어 — 자동 버전관리 & GitHub 릴리즈 스크립트       ║
# ║                                                                  ║
# ║   사용법:                                                        ║
# ║     ./release.sh                      # 대화형 모드             ║
# ║     ./release.sh v1.3 "기능 설명"    # 직접 입력 모드          ║
# ╚══════════════════════════════════════════════════════════════════╝
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

GITHUB_USER="plan153"
REPO_NAME="maltrim-japanese"
CHANGELOG="CHANGELOG.md"

# ── 토큰 로드 ─────────────────────────────────────────────────────
[ -f ".env" ] && source .env
if [ -z "$GITHUB_TOKEN" ]; then
  read -s -p "🔑 GitHub Token: " GITHUB_TOKEN; echo ""
fi

# ── 현재 버전 자동 감지 ───────────────────────────────────────────
CURRENT_VER=$(grep -m1 '## \[v' "$CHANGELOG" | grep -oE 'v[0-9]+\.[0-9]+')
echo "📌 현재 버전: $CURRENT_VER"

# ── 버전 입력 ─────────────────────────────────────────────────────
if [ -n "$1" ]; then
  NEW_VER="$1"
else
  # 마이너 버전 자동 증가 제안
  MINOR=$(echo "$CURRENT_VER" | grep -oE '[0-9]+$')
  MAJOR=$(echo "$CURRENT_VER" | grep -oE '^v[0-9]+')
  SUGGESTED="${MAJOR}.$((MINOR + 1))"
  read -p "🔖 새 버전 번호 [$SUGGESTED]: " NEW_VER
  NEW_VER="${NEW_VER:-$SUGGESTED}"
fi

# ── 변경 내용 입력 ────────────────────────────────────────────────
if [ -n "$2" ]; then
  SUMMARY="$2"
else
  echo ""
  echo "📝 이번 버전에서 변경된 내용을 입력하세요."
  echo "   (여러 줄 가능 — 빈 줄 입력 시 완료)"
  SUMMARY=""
  while IFS= read -r line; do
    [ -z "$line" ] && break
    SUMMARY="${SUMMARY}- ${line}\n"
  done
fi

TODAY=$(date '+%Y-%m-%d')
echo ""
echo "────────────────────────────────────────────"
echo "  버전  : $NEW_VER"
echo "  날짜  : $TODAY"
echo "  내용  : $(echo -e "$SUMMARY" | head -3)"
echo "────────────────────────────────────────────"
read -p "이대로 릴리즈 진행할까요? [Y/n] " CONFIRM
[ "${CONFIRM:-Y}" = "n" ] && echo "취소됨." && exit 0

# ── CHANGELOG.md 자동 업데이트 ───────────────────────────────────
echo ""
echo "📋 CHANGELOG.md 업데이트 중..."

ENTRY="## [$NEW_VER] — $TODAY\n\n$(echo -e "$SUMMARY")\n---\n\n"

# "## [v" 첫 번째 등장 바로 앞에 새 항목 삽입
TEMP=$(mktemp)
awk -v entry="$ENTRY" '
  /^## \[v/ && !done {
    printf "%s", entry
    done = 1
  }
  { print }
' "$CHANGELOG" > "$TEMP" && mv "$TEMP" "$CHANGELOG"

echo "✅ CHANGELOG.md 업데이트 완료"

# ── git add & commit ──────────────────────────────────────────────
echo "📦 변경사항 스테이징..."
git add -A

if [ -z "$(git status --porcelain)" ]; then
  echo "ℹ️  변경 파일 없음 — 커밋 건너뜀"
else
  COMMIT_MSG="release: $NEW_VER

$(echo -e "$SUMMARY")
[릴리즈] $(date '+%Y-%m-%d %H:%M:%S')"

  git commit -m "$COMMIT_MSG"
  echo "✅ 커밋 완료"
fi

# ── git tag ───────────────────────────────────────────────────────
if git rev-parse "$NEW_VER" >/dev/null 2>&1; then
  echo "ℹ️  태그 $NEW_VER 이미 존재 — 태그 건너뜀"
else
  git tag -a "$NEW_VER" -m "릴리즈 $NEW_VER — $TODAY"
  echo "🏷️  태그 $NEW_VER 생성 완료"
fi

# ── GitHub push (커밋 + 태그) ─────────────────────────────────────
REMOTE="https://${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${REPO_NAME}.git"
git remote set-url origin "$REMOTE" 2>/dev/null || git remote add origin "$REMOTE"

echo "⬆️  GitHub 업로드 중..."
GIT_TERMINAL_PROMPT=0 git push origin main
GIT_TERMINAL_PROMPT=0 git push origin "$NEW_VER" 2>/dev/null || true

echo ""
echo "🎉 릴리즈 완료!"
echo "   버전  : $NEW_VER"
echo "   커밋  : $(git rev-parse --short HEAD)"
echo "🔗 https://github.com/${GITHUB_USER}/${REPO_NAME}"
echo "🔗 https://github.com/${GITHUB_USER}/${REPO_NAME}/blob/main/CHANGELOG.md"
