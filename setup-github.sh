#!/bin/bash
# ╔══════════════════════════════════════════════════════════╗
# ║   말트임 일본어 — GitHub 최초 설정 스크립트              ║
# ║   터미널에서 한 번만 실행하세요                          ║
# ╚══════════════════════════════════════════════════════════╝
set -e

REPO_NAME="maltrim-japanese"
DESCRIPTION="말트임 일본어 - 30일 마스형 선행 소리 학습 앱"
GITHUB_USER=""
GITHUB_TOKEN=""

# ── 인자 파싱 ─────────────────────────────────────────────
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --user)   GITHUB_USER="$2"; shift ;;
    --token)  GITHUB_TOKEN="$2"; shift ;;
    --repo)   REPO_NAME="$2"; shift ;;
    *) echo "알 수 없는 옵션: $1"; exit 1 ;;
  esac
  shift
done

# ── 입력값 확인 ───────────────────────────────────────────
if [ -z "$GITHUB_USER" ]; then
  read -p "GitHub 사용자명: " GITHUB_USER
fi
if [ -z "$GITHUB_TOKEN" ]; then
  read -s -p "GitHub Personal Access Token (repo 권한 필요): " GITHUB_TOKEN
  echo ""
fi

echo ""
echo "🚀 GitHub 레포지토리 생성 중: $GITHUB_USER/$REPO_NAME"

# ── 레포 생성 (GitHub API) ────────────────────────────────
HTTP_STATUS=$(curl -s -o /tmp/gh_create_resp.json -w "%{http_code}" \
  -X POST https://api.github.com/user/repos \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"$REPO_NAME\",
    \"description\": \"$DESCRIPTION\",
    \"private\": false,
    \"auto_init\": false
  }")

if [ "$HTTP_STATUS" = "201" ]; then
  echo "✅ 레포지토리 생성 완료: https://github.com/$GITHUB_USER/$REPO_NAME"
elif [ "$HTTP_STATUS" = "422" ]; then
  echo "ℹ️  레포지토리가 이미 존재합니다. 기존 레포를 사용합니다."
else
  echo "⚠️  레포 생성 응답: $HTTP_STATUS"
  cat /tmp/gh_create_resp.json
fi

# ── git 초기화 및 첫 커밋 ────────────────────────────────
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

if [ ! -d ".git" ]; then
  git init
  git checkout -b main 2>/dev/null || git branch -M main
fi

git config user.name  "$GITHUB_USER"
git config user.email "$(git config --global user.email 2>/dev/null || echo "$GITHUB_USER@users.noreply.github.com")"

# Remote 설정 (토큰 내장)
REMOTE_URL="https://$GITHUB_TOKEN@github.com/$GITHUB_USER/$REPO_NAME.git"
git remote remove origin 2>/dev/null || true
git remote add origin "$REMOTE_URL"

# 초기 커밋
git add -A
git commit -m "feat: 말트임 일본어 앱 초기 구현

- 30일 전체 커리큘럼 (마스형 선행 학습)
- 듣고 따라하기(3회): TTS → STT → 점수
- Levenshtein LCS 발음 교정 시각화
- 일차 서랍 / 진도 트래커 / 키보드 단축키" 2>/dev/null \
|| echo "ℹ️  변경 사항 없음 (이미 커밋됨)"

# Push
git push -u origin main
echo ""
echo "🎉 완료! 브라우저에서 확인하세요:"
echo "   https://github.com/$GITHUB_USER/$REPO_NAME"
echo ""
echo "📌 이제부터 기능 개선 후 push.sh 를 실행하면 자동 업로드됩니다."

# 토큰을 .git/config 에서 제거하고 credential helper 사용
git remote set-url origin "https://github.com/$GITHUB_USER/$REPO_NAME.git"
git config credential.helper store
echo "https://$GITHUB_TOKEN:x-oauth-basic@github.com" >> ~/.git-credentials
echo "✅ 인증 정보 저장 완료 (이후 push.sh 실행 시 토큰 불필요)"
