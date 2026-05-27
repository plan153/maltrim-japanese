---
name: contextual-generator
description: >
  커리큘럼의 문법 패턴을 기반으로, 여행·일상 상황에 맞는 응용 문장을
  동적으로 생성합니다. 최소 어휘 원칙(core-50) + 어미 변형 확장 플랜을
  따르며, 불필요한 문법 설명을 배제해 토큰과 인지 부하를 동시에 줄입니다.
use_when: >
  사용자가 "응용 문장 더 보기" 또는 자유 대화 모드를 요청할 때.
  여행 응용 코너에서 해당 Day의 추가 예문이 필요할 때.
token_budget: medium   # Sonnet 사용, 캐시 활용으로 반복 비용 제거
model: claude-sonnet-4-6
cache: prompt_caching   # system prompt를 캐시하여 반복 호출 비용 90% 절감
---

# Contextual Generator Skill

## 핵심 원칙: 최소 어휘 × 최대 표현

### Core-50 기본 어휘 (확장의 씨앗)

| 카테고리 | 단어 |
|:---|:---|
| 동사 5 | いく／くる／する／たべる／のむ |
| 동사 5 | かう／かえる／みる／きく／はなす |
| 형용사 6 | おいしい／たかい／やすい／おおきい／ちいさい／いい |
| 명사 10 | みず／ごはん／みせ／えき／うち／しごと／がっこう／ともだち／かね／じかん |
| 조사 8 | に／を／で／が／は／と／から／まで |
| 부사 6 | まいにち／よく／はやく／すこし／もう／また |
| 의문사 5 | なに／どこ／だれ／いつ／なんじ |
| 지시어 5 | これ／それ／あれ／ここ／そこ |

### 어미 변형 확장 트리

```
기본형 (いく)
├─ Step 1 현재  : いきます
├─ Step 2 과거  : いきました
├─ Step 3 권유  : いきましょう
├─ Step 4 희망  : いきたいです
├─ Step 5 テ형  : いって + ください／もいいですか／はいけません
├─ Step 6 기본형: いく + ことができます／まえに／とおもいます
└─ Step 7 반말  : いく／いった／いこう
```

> **원칙**: 새 단어 추가보다 기존 단어의 어미 변형을 먼저 완전히 소화.

---

## 시스템 프롬프트 (캐시 대상 — 변경 빈도 낮음)

```
당신은 일본어 학습 문장 생성기입니다.

규칙:
1. Core-50 어휘 + 지정된 문법 패턴만 사용
2. 문법 설명 금지 — 문장과 한국어 의미만 출력
3. 상황은 여행/일상 중 하나로 지정
4. 출력 형식: JSON 배열, 문장당 jp/reading/kr 3필드
5. 항상 3문장 생성

출력 예시:
[
  {"jp":"みずを　ください","reading":"미즈오 쿠다사이","kr":"물 주세요."},
  {"jp":"これを　ください","reading":"코레오 쿠다사이","kr":"이거 주세요."},
  {"jp":"すこし　まって　ください","reading":"스코시 맛테 쿠다사이","kr":"잠깐 기다려 주세요."}
]
```

> 이 시스템 프롬프트는 prompt_caching으로 1회 전송 후 캐시 → 이후 호출 90% 절감.

---

## 사용자 메시지 (호출마다 변하는 부분 — 짧게 유지)

```
패턴: 〜て ください
상황: 식당
Day: 16
```

총 입력 토큰: 시스템(캐시) + 사용자 ~20토큰

---

## 처리 로직 (index.js)

```javascript
const Anthropic = require('@anthropic-ai/sdk');
const client = new Anthropic();

// 시스템 프롬프트 — 한 번 정의, 캐시로 재사용
const SYSTEM_PROMPT = `당신은 일본어 학습 문장 생성기입니다.
규칙:
1. Core-50 어휘 + 지정된 문법 패턴만 사용
2. 문법 설명 금지 — 문장과 한국어 의미만 출력
3. 출력 형식: JSON 배열 [{jp, reading, kr}] 3개
4. 상황 문맥에 맞게 생성`;

async function generateContextual({ pattern, situation, day }) {
  const msg = await client.messages.create({
    model: 'claude-sonnet-4-6',
    max_tokens: 300,
    system: [
      {
        type: 'text',
        text: SYSTEM_PROMPT,
        cache_control: { type: 'ephemeral' }  // 캐시 설정
      }
    ],
    messages: [{
      role: 'user',
      content: `패턴: ${pattern}\n상황: ${situation}\nDay: ${day}`
    }]
  });

  const firstBlock = msg.content[0];
  if (!firstBlock || firstBlock.type !== 'text') {
    console.error('contextual-generator: unexpected content type', firstBlock?.type);
    return [];
  }
  try {
    return JSON.parse(firstBlock.text);
  } catch (err) {
    console.error('contextual-generator: JSON parse failed', err.message, firstBlock.text);
    return [];
  }
}

module.exports = { generateContextual };
```

---

## 캐싱으로 인한 토큰 절감 효과

| 항목 | 캐시 없음 | 캐시 사용 |
|:---|:---:|:---:|
| 시스템 프롬프트 토큰 | ~200 | ~5 (90% 절감) |
| 사용자 메시지 토큰 | ~20 | ~20 |
| 응답 토큰 | ~150 | ~150 |
| **합계** | **~370** | **~175** |

---

## 배치

```
backend/skills/contextual-generator/
├── SKILL.md   ← 이 파일
└── index.js   ← 로직 모듈
```
