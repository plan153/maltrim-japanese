# 말트임 일본어 — 버전 변경 이력 (CHANGELOG)

> 모든 주요 변경사항은 이 문서에 기록됩니다.  
> 형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.0.0/) 규약을 따릅니다.

---

## [v1.5] — 2026-05-29

### ⚡ Added — Vercel 백엔드 + Upstash Redis 캐싱

#### 신규 파일
- **`package.json`**: Node 20.x, `@anthropic-ai/sdk` · `@neondatabase/serverless` · `@upstash/redis` 의존성
- **`vercel.json`**: Serverless Functions 라우팅, `maxDuration: 15`
- **`lib/db.js`**: Neon PostgreSQL 싱글턴 커넥션 (`DATABASE_URL` 환경변수)
- **`lib/cache.js`**: Upstash Redis 래퍼 — `cacheGet` / `cacheSet` / `cacheDel` + graceful fallback (env 미설정 시 캐시 없이 동작)
- **`api/schedule.js`**: `POST /api/schedule` — 에빙하우스 스케줄 기반 오늘 학습 문장 반환 (복습 10개 + 신규 3개)
- **`api/fluency.js`**: `POST /api/fluency` — Claude Haiku 발음 피드백 + Redis 1h 캐시 + Neon 진도 저장
- **`api/generate.js`**: `POST /api/generate` — Claude Sonnet 예문 생성 + Redis 24h 공유 캐시 + prompt_caching

#### Redis 캐싱 전략
| 엔드포인트 | 캐시 키 | TTL | 절감 효과 |
|---|---|---|---|
| `/api/generate` | `gen:{pattern}:{category}:{level}:{count}` | 24시간 | Claude Sonnet 호출 40~60% 절감 |
| `/api/fluency` | `flu:{reference_text}:{score_bucket}` | 1시간 | Claude Haiku 호출 30~40% 절감 |
| `/api/schedule` | 캐시 없음 | — | 사용자별 실시간 데이터 |

#### 환경변수 (Vercel Dashboard에 설정 필요)
```
DATABASE_URL           Neon PostgreSQL 연결 문자열
ANTHROPIC_API_KEY      Claude API 키
UPSTASH_REDIS_REST_URL     Upstash Redis REST URL
UPSTASH_REDIS_REST_TOKEN   Upstash Redis REST Token
```

---

## [v1.4] — 2026-05-25

### 🔊 Changed — Google Neural2 TTS 사전 생성 방식 전환

- **`generate_audio.py` 추가**: Google Cloud TTS `ja-JP-Neural2-B` 모델로 30일 커리큘럼 전 문장(98개) MP3 사전 생성. REST API 직접 호출, SDK 의존성 없음.
- **`speak()` 함수 교체**: `window.speechSynthesis` 대신 GitHub Pages 호스팅 MP3 파일을 `<Audio>` 엘리먼트로 재생. 속도 0.85(학습자용), 원어민 Neural2 발음.
- **Fallback 유지**: `speakFallback()` 분리 — 네트워크 오류 또는 AUDIO_MAP 미등록 텍스트 시 기존 Web Speech API 자동 전환.
- **AUDIO_MAP 사전 계산**: 앱 로드 시 `CURRICULUM` 전체 순회하여 `jp텍스트 → GitHub Pages URL` 매핑 테이블 구성. 런타임 조회 O(1).
- **월 비용**: 월 1만 MAU 기준 TTS 비용 $0 (사전 생성 + GitHub Pages 무료 호스팅).
- **FFD 호환**: `audio.onended` 콜백에서 `S.t0 = Date.now()` 스탬핑으로 기존 반응속도 계측 로직 완전 호환.

---

## [v1.3] — 2026-05-24

### 📊 Added — 학습 통계 대시보드

- **통계 데이터 로깅**: 수동 마이크(`showFeedback`) 및 듣고 따라하기(`runLRRound`) 완료 시 `maltrim_stats_v1` localStorage 키에 `{ts, day, score, ffd, vad}` 기록 (최대 500개 보관)
- **📊 헤더 버튼**: 상단 헤더에 통계 버튼 추가 (항상 접근 가능)
- **요약 카드**: 총 연습 횟수 / 평균 정확도 / 평균 반응속도 3-카드 요약
- **일별 정확도 바 차트**: 최근 7일 일별 평균 정확도 SVG 바 차트 (85점↑ 초록 / 60~84점 노랑 / ~59점 빨강)
- **일별 FFD 라인 차트**: 최근 7일 평균 반응속도(초) SVG 라인 차트

---

## [v1.2] — 2026-05-24

### 🧠 Added — 인지 유창성 계측 엔진 (FFD & VAD)

- **FFD (First Formant Delay)**: TTS `onend` 콜백 완료 시점을 `S.t0`으로 스탬핑하고, `onspeechstart` 이벤트로 최초 발화 지연 시간을 자동 계측. 1.0초 이하 = 최상위 유창성 등급 판정
- **VAD (Voice Activity Detection)**: `interimResults` 스트림에서 발화 간 500ms 이상 무음 구간을 감지·카운트하여 머뭇거림 횟수 추적
- **FFD 칩 UI**: `⚡ 반응속도: 0.7초 ✅` / `🐢 반응속도: 3.1초` — 속도 구간별 색상 분기 (fast / warn / slow)
- **VAD 칩 UI**: `🔊 막힘없음 ✅` / `🔇 머뭇거림: 2회` — 회차별 표시

### ⚖️ Changed — 음절 가중치 기반 LCS 스코어링

- `score()` 함수 전면 개선: 문장 끝 3~4음절(종결 어미 구간)에 **가중치 W_end = 1.5** 적용
- `ます` `ました` `ましょう` `ください` 등 종결 형태소 완벽 일치 시 가산점 부여
- 히라가나 → 가타카나 정규화로 STT 인식 노이즈 보정

### 🔒 Added — 동적 오답 제어 락 루프

- `nextPhrase()` 진도 이동 전 `S.lastScore < 85` 조건 체크
- 85점 미만 시 Lock Layer 표시 → `setTimeout` 1.5초 후 `startRec()` 자동 재기동
- `S.lockActive` 플래그로 이중 실행 방지
- 클리어 조건: **정확도 85점 이상** (반응속도 1초 이하 시 보너스)

### 💬 Added — 실시간 오답 교정 말풍선 레이어

- `buildDiff()` LCS 백트래킹에 `data-hint` 어트리뷰트 주입
- CSS `::after` 말풍선 팝업 — hover 시 문법 힌트 표시
- **HINT_MAP** 31개 항목: 조사(に を が で は も の へ から まで) + 어미(ます ました ましょう たいです ください 등)
- `.diff-miss` (빠뜨린 글자) → 주황 힌트 / `.diff-ng` (잘못 말한 글자) → 빨간 취소선

### 🎮 Added — 속도계(Speedometer)형 게이미피케이션 UX

- 기존 점수 칩 → **SVG 링 게이지** 교체 (`stroke-dasharray` 1.1s 애니메이션)
- FFD + 정확도 결합 타이틀 피드백:
  - `⚡ 조건반사 마스터!` — 95점 이상 + 반응 1초 이내
  - `🎯 유창성 우수!` — 85점 이상 + 반응 1.5초 이내
  - `✅ 통과!` — 85점 이상
  - `👍 조금 더!` — 60~84점
  - `💪 다시 도전!` — 59점 이하
- L&R 모달 내부 3회 평균 요약 속도계 추가

### 🔧 Added — 플랫폼 분기 준비 & STT 오류 처리

- `S.isPremium` / `S.isNativePlatform` 전역 상태 확장 (Flutter/RN 하이브리드 대비)
- STT `onerror` 전체 케이스 토스트 연동:
  - `no-speech` → `"🎙 소음이 없는 곳에서 다시 말씀해 주세요"`
  - `not-allowed` → `"🔒 마이크 권한을 허용해 주세요"`
  - `audio-capture` → `"🎤 마이크를 확인해 주세요"`
  - `network` → `"🌐 네트워크 연결을 확인해 주세요"`
- 헤더 `v1.2` 뱃지 추가

---

## [v1.1] — 2026-05-24

### ✨ Added — 초기 프로토타입 구현

- **30일 전체 커리큘럼** 스켈레톤 (총 98개 문장, 마스형 선행 학습 방식)
  - 1주차 (Day 1~7): 핵심 뼈대 — 이동·일과·음식·쇼핑·존재·의문사·복합 표현
  - 2주차 (Day 8~14): 과거형 + 권유형 + 희망 표현
  - 3주차 (Day 15~21): テ형 연결·요청·허가·금지
  - 4주차 (Day 22~30): 기본형(사전형) 비밀 해제 + 반말 보통체 전환
- **발음 카드** UI: 블라인드(blur) 처리 → 보기/가리기 토글
  - 일본어 표기 (28~32pt 대형) + 한글 독음 + 한국어 의미 3단 계층
- **🔊 듣기**: Web Speech API TTS (일본어 음성 자동 선택)
- **🔁 듣고 따라하기 (3회)**: TTS 재생 → 4초 STT 자동 녹음 → 점수 → 3라운드 반복 모달
- **🎤 수동 마이크**: 누르는 동안 녹음, 파형 애니메이션
- **발음 교정 피드백**: Levenshtein LCS 글자별 색상 diff
- **진도 트래커**: 상단 진행 바 + Day 서랍(30일 그리드)
- **localStorage 진도 저장**: 앱 재시작 시 이어서 학습
- **키보드 단축키**: `←→` 이동, `Space` 공개/가리기, `Enter` 재생, `Esc` 닫기
- **토스트 알림** 컴포넌트

### 🏗 Infrastructure

- 단일 HTML 파일 아키텍처 (외부 의존성 없음)
- GitHub 레포지토리 연동: `plan153/maltrim-japanese`
- `push.sh` 자동 업로드 스크립트
- `.env` 기반 토큰 관리 (gitignore 처리)

---

## [v1.0] — 기획 단계

### 📋 Planned — 계획서 확정 (`japanese_learning_app_plan.md`)

- 마스형(ます형) 선행 학습 교육론 정립
- 크로스플랫폼(iOS / Android / Web) 아키텍처 설계
- UI/UX 와이어프레임: 진도 트래커 · 발음 카드 · 마이크 오버레이
- 기술 스택 결정: Flutter / React Native + Web Speech API
- 30일 커리큘럼 분류 체계 확정
- 이원화 오디오 인프라 전략: 무료 OS TTS + 프리미엄 뉴럴 TTS

---

## 로드맵 (예정)

| 버전 | 예정 기능 |
|------|-----------|
| ~~v1.3~~ | ~~학습 통계 대시보드~~ ✅ 완료 |
| v1.4 | 프리미엄 뉴럴 TTS 연동 (`S.isPremium` 분기 활성화) |
| v1.5 | Flutter/React Native 하이브리드 패키징 (`S.isNativePlatform`) |
| v2.0 | 네이티브 앱 출시 (App Store / Google Play) |
