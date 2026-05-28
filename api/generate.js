/**
 * POST /api/generate
 * 문법 패턴 기반 일본어 예문 생성
 * Body: { pattern, category, level, count }
 *
 * 캐시 전략:
 *   키  = gen:{pattern}:{category}:{level}:{count}
 *   TTL = 24시간 (동일 패턴 요청은 Claude 호출 없이 재사용)
 *   userId 제외 → 공유 캐시 (사용자 무관 동일 결과)
 */
const Anthropic = require('@anthropic-ai/sdk');
const { cacheGet, cacheSet } = require('../lib/cache');

const SYSTEM_PROMPT = `당신은 일본어 초급 학습자를 위한 예문 생성 전문가입니다.
규칙:
1. 요청된 문법 패턴을 사용한 자연스러운 일본어 예문을 생성하세요.
2. 여행·일상 생활 관련 주제를 우선으로 합니다.
3. 반드시 아래 JSON 배열 형식만 반환하세요. 설명이나 마크다운 없이 JSON만.
형식: [{"jp":"일본어","reading":"히라가나","ko":"한국어 의미"}]`;

function parseJsonSafe(text) {
  // ```json ... ``` 또는 ``` ... ``` 펜스 제거
  const stripped = text.replace(/^```(?:json)?\s*/i, '').replace(/\s*```\s*$/, '').trim();
  return JSON.parse(stripped);
}

module.exports = async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  const { pattern = '', category = 'travel', level = 'beginner', count = 5 } = req.body || {};
  if (!pattern) return res.status(400).json({ error: 'pattern 필요' });

  // ── 캐시 확인 ──────────────────────────────────────
  const cacheKey = `gen:${pattern}:${category}:${level}:${count}`;
  const cached = await cacheGet(cacheKey);
  if (cached) {
    return res.json({ phrases: cached, cached: true });
  }

  // ── Claude Sonnet 호출 ──────────────────────────────
  try {
    const client = new Anthropic();
    const msg = await client.messages.create({
      model: 'claude-sonnet-4-6',
      max_tokens: 1024,
      system: [
        {
          type: 'text',
          text: SYSTEM_PROMPT,
          cache_control: { type: 'ephemeral' },  // prompt_caching
        },
      ],
      messages: [
        {
          role: 'user',
          content: `패턴: ${pattern}\n카테고리: ${category}\n난이도: ${level}\n개수: ${count}개`,
        },
      ],
    });

    const raw = msg.content[0].text;
    let phrases;
    try {
      phrases = parseJsonSafe(raw);
    } catch (e) {
      console.error('[generate] JSON 파싱 실패:', raw);
      return res.status(500).json({ error: 'JSON 파싱 실패', raw });
    }

    // ── 캐시 저장 (24시간) ──────────────────────────────
    await cacheSet(cacheKey, phrases, 86400);

    res.json({ phrases, cached: false });
  } catch (err) {
    console.error('[generate] Claude 오류:', err.message);
    res.status(500).json({ error: 'Claude API 오류', detail: err.message });
  }
};
