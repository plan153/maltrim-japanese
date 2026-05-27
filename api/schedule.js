// api/schedule.js — curriculum-scheduler 스킬 기반 서버리스 함수
// POST /api/schedule
// Body: { user_id: string, new_limit?: number, review_limit?: number }

const { getDb } = require('../lib/db');

// KST 기준 오늘 날짜 'YYYY-MM-DD'
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

  return {
    session_type: dueReviews.length > 0 ? 'mixed' : 'new_only',
    review_items: dueReviews,
    new_items: newItems,
    total_count: dueReviews.length + newItems.length,
    today: todayStr
  };
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { user_id, new_limit = 3, review_limit = 5 } = req.body || {};
  if (!user_id) {
    return res.status(400).json({ error: 'user_id가 필요합니다.' });
  }

  try {
    const sql = getDb();

    // 사용자 진도 조회
    const user_progress = await sql`
      SELECT up.expression_id, up.review_stage, up.next_review_at,
             up.accuracy_avg, up.fluency_avg, up.attempt_count,
             e.jp_text, e.reading, e.kr_meaning, e.audio_url,
             c.day_number, c.topic, c.grammar_point
      FROM user_progress up
      JOIN expressions e ON up.expression_id = e.expression_id
      JOIN curriculum  c ON e.curriculum_id  = c.curriculum_id
      WHERE up.user_id = ${user_id} AND up.is_mastered = FALSE
    `;

    // 전체 커리큘럼 풀 조회
    const curriculum_pool = await sql`
      SELECT e.expression_id, e.jp_text, e.reading, e.kr_meaning,
             e.audio_url, e.grammar_tags,
             c.day_number, c.topic, c.grammar_point
      FROM expressions e
      JOIN curriculum c ON e.curriculum_id = c.curriculum_id
      WHERE e.is_active = TRUE
      ORDER BY c.day_number, e.seq
    `;

    const session = buildTodaySession({
      user_progress, curriculum_pool, new_limit, review_limit
    });

    return res.status(200).json(session);
  } catch (err) {
    console.error('schedule error:', err.message);
    return res.status(500).json({ error: 'DB 조회 실패', detail: err.message });
  }
};
