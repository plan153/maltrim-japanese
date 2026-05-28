/**
 * POST /api/fluency
 * 발음 평가 결과를 받아 Claude Haiku로 한국어 피드백 생성
 * Body: { user_id, azure_result: { reference_text, overall, words[] }, expression_id? }
 *
 * 캐시 전략:
 *   키  = flu:{reference_text}:{score_bucket}
 *   TTL = 1시간
 *   score_bucket: 점수를 10단위로 버킷화 (71→70, 85→80)
 *   → 같은 문장 + 비슷한 점수대의 피드백 재사용
 */
const Anthropic = require('@anthropic-ai/sdk');
const { getDb } = require('../lib/db');
const { cacheGet, cacheSet } = require('../lib/cache');

const FEEDBACK_SYSTEM = `당신은 친절한 일본어 발음 코치입니다.
발음 평가 데이터를 받아 한국어로 짧고 격려적인 피드백을 제공하세요.
- 2~3문장 이내로 간결하게
- 잘한 점 먼저, 개선점은 구체적으로
- 이모지 1~2개 포함해 친근하게`;

function scoreBucket(score) {
  return Math.floor((score || 0) / 10) * 10;  // 71 → 70, 85 → 80
}

function buildFeedbackPrompt(azureResult) {
  const { reference_text, overall, words = [] } = azureResult;
  const wrongWords = words
    .filter(w => w.error_type && w.error_type !== 'None')
    .map(w => w.word)
    .slice(0, 5);

  return `문장: ${reference_text}
정확도: ${overall.accuracy}점 / 유창성: ${overall.fluency}점 / 완성도: ${overall.completeness}점
${wrongWords.length > 0 ? `틀린 부분: ${wrongWords.join(', ')}` : '발음 오류 없음'}`;
}

module.exports = async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  const { user_id, azure_result, expression_id } = req.body || {};
  if (!user_id || !azure_result) {
    return res.status(400).json({ error: 'user_id, azure_result 필요' });
  }

  const score = azure_result.overall?.accuracy || 0;

  // ── 캐시 확인 ──────────────────────────────────────
  const refText   = azure_result.reference_text || '';
  const bucket    = scoreBucket(score);
  const cacheKey  = `flu:${refText}:${bucket}`;
  const cached    = await cacheGet(cacheKey);
  if (cached) {
    // DB 저장은 캐시 히트 시에도 수행 (학습 기록은 항상 남김)
    if (expression_id) {
      await saveProgress(user_id, expression_id, score).catch(() => {});
    }
    return res.json({ feedback: cached, cached: true });
  }

  // ── Claude Haiku 피드백 생성 ────────────────────────
  let feedback = '';
  try {
    const client = new Anthropic();
    const msg = await client.messages.create({
      model: 'claude-haiku-4-5',
      max_tokens: 256,
      system: [
        {
          type: 'text',
          text: FEEDBACK_SYSTEM,
          cache_control: { type: 'ephemeral' },
        },
      ],
      messages: [{ role: 'user', content: buildFeedbackPrompt(azure_result) }],
    });
    feedback = msg.content[0].text;
  } catch (err) {
    console.error('[fluency] Claude 오류:', err.message);
    return res.status(500).json({ error: 'Claude API 오류', detail: err.message });
  }

  // ── 캐시 저장 (1시간) ────────────────────────────────
  await cacheSet(cacheKey, feedback, 3600);

  // ── DB 저장 (expression_id 있을 때만) ───────────────
  if (expression_id) {
    await saveProgress(user_id, expression_id, score).catch(e =>
      console.warn('[fluency] DB 저장 스킵:', e.message)
    );
  }

  res.json({ feedback, cached: false });
};

// 에빙하우스 다음 복습일 계산
const INTERVALS = [0, 1, 3, 7, 14, 30, 60];
function nextReviewDate(stage) {
  const days = INTERVALS[Math.min(stage, INTERVALS.length - 1)];
  const d = new Date(Date.now() + 9 * 60 * 60 * 1000);
  d.setDate(d.getDate() + days);
  return String(d).slice(0, 10);
}

async function saveProgress(userId, expressionId, score) {
  const sql = getDb();
  const passed = score >= 80;
  const rows = await sql`
    SELECT stage FROM user_progress
    WHERE user_id = ${userId} AND expression_id = ${expressionId}
  `;
  if (rows.length === 0) {
    const newStage = passed ? 1 : 0;
    await sql`
      INSERT INTO user_progress (user_id, expression_id, stage, next_review_date, last_score)
      VALUES (${userId}, ${expressionId}, ${newStage},
              ${nextReviewDate(newStage)}, ${score})
    `;
  } else {
    const oldStage = rows[0].stage;
    const newStage = passed ? Math.min(oldStage + 1, 6) : Math.max(oldStage - 1, 0);
    await sql`
      UPDATE user_progress
      SET stage = ${newStage}, next_review_date = ${nextReviewDate(newStage)},
          last_score = ${score}, updated_at = NOW()
      WHERE user_id = ${userId} AND expression_id = ${expressionId}
    `;
  }
}
