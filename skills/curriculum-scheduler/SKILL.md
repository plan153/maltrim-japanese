---
name: curriculum-scheduler
description: >
  사용자의 학습 이력·망각곡선 데이터를 기반으로 오늘 학습할 커리큘럼(신규+복습)을
  동적으로 계산·정렬합니다. Claude 호출 없이 서버 로직만으로 처리해 토큰 비용 0.
use_when: >
  앱 세션 시작 시, 또는 "오늘 뭐 공부해?" 요청이 들어올 때.
  user_progress 테이블에서 next_review_at <= NOW() 인 항목이 존재할 때.
token_budget: zero   # 순수 서버 로직, LLM 호출 없음
---

# Curriculum Scheduler Skill

## 역할
에빙하우스 망각곡선 주기로 **오늘의 세트 = 신규 + 복습** JSON 반환.

## 망각곡선 복습 주기

| stage | 다음 복습 |
|:---:|:---:|
| 0 | 당일 신규 |
| 1 | 1일 후 |
| 2 | 3일 후 |
| 3 | 7일 후 |
| 4 | 14일 후 |
| 5 | 30일 후 |
| 6 | 60일 후 |

accuracy_avg < 70 이면 stage 유지, same-day 재출제.

## 처리 로직 (index.js)

```javascript
// KST 기준 오늘 날짜를 'YYYY-MM-DD' 문자열로 반환
function getTodayKST() {
  return new Date(Date.now() + 9 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

function buildTodaySession({ user_progress, curriculum_pool, new_limit = 3, review_limit = 5, today }) {
  const todayStr = today ? String(today).slice(0, 10) : getTodayKST();
  const dueReviews = user_progress
    .filter(p => String(p.next_review_at).slice(0, 10) <= todayStr)
    .sort((a, b) => a.accuracy_avg - b.accuracy_avg)
    .slice(0, review_limit);

  const learnedIds = new Set(user_progress.map(p => p.expression_id));
  const newItems = curriculum_pool
    .filter(e => !learnedIds.has(e.expression_id))
    .sort((a, b) => a.day_number - b.day_number)
    .slice(0, new_limit);

  return { session_type: dueReviews.length > 0 ? 'mixed' : 'new_only',
           review_items: dueReviews, new_items: newItems,
           total_count: dueReviews.length + newItems.length };
}

function calcNextReview(stage, accuracyScore) {
  const INTERVALS = [0, 1, 3, 7, 14, 30, 60];
  const passed = accuracyScore >= 70;
  const nextStage = passed ? Math.min(stage + 1, 6) : stage;
  const d = new Date(Date.now() + 9 * 60 * 60 * 1000);  // KST
  d.setUTCDate(d.getUTCDate() + INTERVALS[nextStage]);
  return { next_stage: nextStage, next_review_at: d.toISOString().slice(0, 10) };
}

module.exports = { buildTodaySession, calcNextReview };
```

## 배치

```
backend/skills/curriculum-scheduler/
├── SKILL.md   ← 이 파일
└── index.js   ← 로직 모듈
```
