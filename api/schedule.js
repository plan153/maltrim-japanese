/**
 * POST /api/schedule
 * 오늘 학습할 문장 목록을 에빙하우스 스케줄 기반으로 반환
 * Body: { user_id }
 */
const { getDb } = require('../lib/db');

function getTodayKST() {
  return String(new Date(Date.now() + 9 * 60 * 60 * 1000)).slice(0, 10);
}

module.exports = async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  const { user_id } = req.body || {};
  if (!user_id) return res.status(400).json({ error: 'user_id 필요' });

  const sql = getDb();
  const today = getTodayKST();

  try {
    // 오늘 복습 대상 (이미 학습 중)
    const review = await sql`
      SELECT e.id, e.expression, e.reading, e.meaning, e.category,
             up.stage, up.next_review_date
      FROM user_progress up
      JOIN expressions e ON e.id = up.expression_id
      WHERE up.user_id = ${user_id}
        AND up.next_review_date <= ${today}
      ORDER BY up.stage ASC, up.next_review_date ASC
      LIMIT 10
    `;

    // 신규 문장 (아직 학습 안 한 것)
    const newPhrases = await sql`
      SELECT e.id, e.expression, e.reading, e.meaning, e.category
      FROM expressions e
      WHERE e.id NOT IN (
        SELECT expression_id FROM user_progress WHERE user_id = ${user_id}
      )
      ORDER BY e.sort_order ASC
      LIMIT 3
    `;

    res.json({
      session_type: review.length > 0 ? 'review_and_new' : 'new_only',
      today,
      review: review.map(r => ({
        id: r.id, expression: r.expression, reading: r.reading,
        meaning: r.meaning, category: r.category, stage: r.stage,
        next_review_date: r.next_review_date,
      })),
      new_phrases: newPhrases.map(e => ({
        id: e.id, expression: e.expression, reading: e.reading,
        meaning: e.meaning, category: e.category, stage: 0,
      })),
    });
  } catch (err) {
    console.error('[schedule] DB 오류:', err.message);
    res.status(500).json({ error: 'DB 오류', detail: err.message });
  }
};
