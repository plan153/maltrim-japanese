# Vercel 배포 가이드 — 말트임 일본어

## 1단계: Neon DB 생성

1. https://neon.tech 가입 (무료)
2. 새 프로젝트 생성 → Region: **Asia Pacific (Singapore)**
3. Connection string 복사 → `postgresql://user:pw@ep-xxx.neon.tech/neondb?sslmode=require`
4. Neon SQL 편집기에서 `db/schema.sql` 전체 실행

## 2단계: Vercel 프로젝트 연결

```bash
# Vercel CLI 설치 (한 번만)
npm i -g vercel

# 프로젝트 루트에서
vercel login
vercel link   # plan153/maltrim-japanese 선택
```

## 3단계: 환경변수 등록

Vercel 대시보드 → Settings → Environment Variables

| 변수명 | 값 | 환경 |
|---|---|---|
| `ANTHROPIC_API_KEY` | sk-ant-... | Production, Preview |
| `DATABASE_URL` | postgresql://... | Production, Preview |
| `AZURE_SPEECH_KEY` | (선택) | Production |
| `AZURE_SPEECH_REGION` | japaneast | Production |

또는 CLI:
```bash
vercel env add ANTHROPIC_API_KEY
vercel env add DATABASE_URL
```

## 4단계: 배포

```bash
vercel --prod
```

배포 완료 시 URL: `https://maltrim-japanese.vercel.app`

## 5단계: index.html 도메인 업데이트

현재 `index.html`은 GitHub Pages에서 서빙됩니다.
API 연동 시 `fetch('/api/...')` 경로는 Vercel에서 자동 처리됩니다.
Vercel이 `index.html`도 서빙하도록 `public/` 폴더에 복사하거나
`vercel.json`의 `outputDirectory`를 루트로 변경하면 됩니다.

## API 엔드포인트 요약

| 엔드포인트 | 메서드 | 용도 |
|---|---|---|
| `/api/schedule` | POST | 오늘의 학습 세트 조회 |
| `/api/fluency` | POST | 발음 평가 + AI 피드백 |
| `/api/generate` | POST | 응용 문장 생성 |

### /api/schedule 예시
```json
POST /api/schedule
{ "user_id": "user_123", "new_limit": 3, "review_limit": 5 }
```

### /api/fluency 예시
```json
POST /api/fluency
{
  "user_id": "user_123",
  "expression_id": "uuid-...",
  "azure_result": {
    "reference_text": "みずを のみます",
    "overall": { "accuracy": 68, "fluency": 55, "completeness": 100 },
    "words": [
      { "word": "みずを", "accuracy": 90, "error_type": "None" },
      { "word": "のみます", "accuracy": 42, "error_type": "Mispronunciation" }
    ]
  }
}
```

### /api/generate 예시
```json
POST /api/generate
{ "pattern": "〜て ください", "situation": "식당", "day": 16 }
```
