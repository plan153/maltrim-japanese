// api/fluency.js — fluency-analyzer 스킬 기반 서버리스 함수
// POST /api/fluency
// Body: { user_id, azure_result, expression_id? }
// expression_id 없으면 DB 저장 스킵, AI 피드백만 반환

const Anthropic = require('@anthropic-ai/sdk');
const { getDb } = require('../lib/db');

const client = new Anthropic();

async function analyzeFluency(azureResult) {
  const badWords = azureResult.words
    .filter(w => w.accuracy < 70)
    .map(w => `${w.word}(${w.accuracy}점)`)
    .join(', ');

  const overallScore = Math.round(
    azureResult.overall.accuracy     * 0.5 +
    azureResult.overall.fluency      * 0.3 +
    azureResult.overall.completeness * 0.2
  );

  const colorMap = azureResult.words.map(w => ({
    word:  w.word,
    color: w.accuracy >= 80 ? 'green' : w.accuracy >= 60 ? 'yellow' : 'red'
  }));

  if (overallScore >= 90) {
    return { score: overallScore, feedback: '완벽해요! 원어민에 가까운 발음입니다 🎉',
             bad_words: [], color_map: colorMap, tip: null };
  }

  let maxTokens, extraInstruction;
  if (overallScore >= 70) {
    maxTokens = 120; extraInstruction = '칭찬1줄+팁1줄';
  } else if (overallScore >= 50) {
    maxTokens = 180; extraInstruction = '틀린 음소를 구체적으로 짚고 교정 팁1줄+칭찬1줄';
  } else {
    maxTokens = 250; extraInstruction = '발음이 어려운 음소별 가이드 + 재도전 격려 메시지';
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

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  const { user_id, expression_id, azure_result } = req.body || {};
  if (!user_id || !azure_result) {
    return res.status(400).json({ error: 'user_id, azure_result가 필요합니다.' });
  }

  try {
    const result = await analyzeFluency(azure_result);

    // expression_id 있을 때만 DB 저장
    if (expression_id) {
      try {
        const sql = getDb();
        await sql`
          INSERT INTO speaking_log
            (user_id, expression_id, accuracy_score, fluency_score, completeness, word_detail, asr_provider)
          VALUES
            (${user_id}, ${expression_id},
             ${azure_result.overall.accuracy}, ${azure_result.overall.fluency},
             ${azure_result.overall.completeness}, ${JSON.stringify(azure_result.words)}, 'web_speech')
        `;
        await sql`
          INSERT INTO user_progress (user_id, expression_id, accuracy_avg, fluency_avg, attempt_count)
          VALUES (${user_id}, ${expression_id}, ${result.score}, ${azure_result.overall.fluency}, 1)
          ON CONFLICT (user_id, expression_id) DO UPDATE SET
            accuracy_avg  = (user_progress.accuracy_avg * user_progress.attempt_count + ${result.score})
                            / (user_progress.attempt_count + 1),
            fluency_avg   = (user_progress.fluency_avg  * user_progress.attempt_count + ${azure_result.overall.fluency})
                            / (user_progress.attempt_count + 1),
            attempt_count = user_progress.attempt_count + 1,
            updated_at    = NOW()
        `;
      } catch (dbErr) {
        console.error('fluency DB save failed (non-fatal):', dbErr.message);
        // DB 오류는 무시하고 AI 피드백은 반환
      }
    }

    return res.status(200).json(result);
  } catch (err) {
    console.error('fluency error:', err.message);
    return res.status(500).json({ error: '분석 실패', detail: err.message });
  }
};
