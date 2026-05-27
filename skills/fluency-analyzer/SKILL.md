---
name: fluency-analyzer
description: >
  Azure Speech Service가 반환한 음소 단위 발음 평가 JSON을 받아
  한국어 학습자 눈높이의 친절한 피드백 텍스트로 정제합니다.
  Claude(Haiku)를 사용하되 프롬프트를 극소화해 토큰을 최소화합니다.
use_when: >
  사용자가 마이크 녹음을 완료하고 Azure API 분석 결과가 서버에 도착했을 때.
  fluency_score 또는 accuracy_score 가 포함된 JSON이 전달될 때.
token_budget: low   # Haiku 사용, 입력 ~200토큰 / 출력 ~150토큰
model: claude-haiku-4-5
---

# Fluency Analyzer Skill

## 역할
Azure Speech 로우 데이터 → 학습자 친화적 한국어 피드백 변환.
문장 전체 점수 + 틀린 단어 강조 + 1줄 개선 팁 출력.

## 입력 스펙 (Azure JSON → 스킬)

```json
{
  "reference_text": "みずを のみます",
  "overall": { "accuracy": 68, "fluency": 55, "completeness": 100 },
  "words": [
    { "word": "みずを", "accuracy": 90, "error_type": "None" },
    { "word": "のみます", "accuracy": 42, "error_type": "Mispronunciation" }
  ]
}
```

## Claude 호출 프롬프트 (극소화 버전)

```
시스템: 일본어 발음 코치. 한국어로 응답. 50자 이내.
점수:{accuracy}/{fluency} 틀린단어:{bad_words}
→ 칭찬1줄+개선팁1줄만 출력.
```

> 변수 치환 후 실제 토큰: 입력 ~60토큰, 출력 ~80토큰

## 처리 로직 (index.js)

```javascript
const Anthropic = require('@anthropic-ai/sdk');
const client = new Anthropic();

async function analyzeFluency(azureResult) {
  const badWords = azureResult.words
    .filter(w => w.accuracy < 70)
    .map(w => `${w.word}(${w.accuracy}점)`)
    .join(', ');

  const overallScore = Math.round(
    (azureResult.overall.accuracy * 0.5 +
     azureResult.overall.fluency   * 0.3 +
     azureResult.overall.completeness * 0.2)
  );

  const colorMap = azureResult.words.map(w => ({
    word: w.word,
    color: w.accuracy >= 80 ? 'green' : w.accuracy >= 60 ? 'yellow' : 'red'
  }));

  // 90+: 템플릿 즉시 반환 (토큰 0)
  if (overallScore >= 90) {
    return { score: overallScore, feedback: "완벽해요! 원어민에 가까운 발음입니다 🎉",
             bad_words: [], tip: null };
  }

  // 70-89 / 50-69 / 0-49: 점수대별 max_tokens + 프롬프트 차등
  let maxTokens, extraInstruction;
  if (overallScore >= 70) {
    maxTokens = 120;
    extraInstruction = '칭찬1줄+팁1줄';
  } else if (overallScore >= 50) {
    maxTokens = 180;
    extraInstruction = '틀린 음소를 구체적으로 짚고 교정 팁1줄+칭찬1줄';
  } else {
    maxTokens = 250;
    extraInstruction = '발음이 어려운 음소별 가이드 + 재도전 격려 메시지';
  }

  const prompt = `점수:${azureResult.overall.accuracy}/${azureResult.overall.fluency} 틀린단어:${badWords || '없음'}\n${extraInstruction}`;

  const msg = await client.messages.create({
    model: 'claude-haiku-4-5',
    max_tokens: maxTokens,
    system: '일본어 발음 코치. 한국어 응답. 친절하고 간결하게.',
    messages: [{ role: 'user', content: prompt }]
  });

  return {
    score: overallScore,
    feedback: msg.content[0].text,
    bad_words: azureResult.words.filter(w => w.accuracy < 70).map(w => w.word),
    color_map: colorMap
  };
}

module.exports = { analyzeFluency };
```

## 점수대별 처리 전략 (토큰 절감)

| 점수 | 처리 방식 | 토큰 |
|:---:|:---|:---:|
| 90+ | 템플릿 즉시 반환 | 0 |
| 70-89 | Haiku 미니 프롬프트 | ~180 |
| 50-69 | Haiku + 발음 팁 DB 조회 병합 | ~220 |
| 0-49 | Haiku + 해당 음소 가이드 첨부 | ~300 |

## 배치

```
backend/skills/fluency-analyzer/
├── SKILL.md   ← 이 파일
└── index.js   ← 로직 모듈
```
