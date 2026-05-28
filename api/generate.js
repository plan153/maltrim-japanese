// api/generate.js — contextual-generator 스킬 기반 서버리스 함수
const Anthropic = require('@anthropic-ai/sdk');
const client = new Anthropic();

const SYSTEM_PROMPT = `당신은 일본어 학습 문장 생성기입니다.
규칙:
1. Core-50 어휘 + 지정된 문법 패턴만 사용
2. 문법 설명 금지 — 문장과 한국어 의미만 출력
3. 출력 형식: 반드시 순수 JSON 배열만 출력 (마크다운 코드블록 금지)
4. 상황 문맥에 맞게 생성

출력 예시 (이 형식 그대로):
[{"jp":"みずを ください","reading":"미즈오 쿠다사이","kr":"물 주세요."},{"jp":"これを ください","reading":"코레오 쿠다사이","kr":"이거 주세요."},{"jp":"すこし まって ください","reading":"스코시 맛테 쿠다사이","kr":"잠깐 기다려 주세요."}]`;

// 마크다운 코드 fence 제거 후 JSON 파싱
function parseJsonSafe(raw) {
  let text = raw.trim();
  // ```json ... ``` 또는 ``` ... ``` 제거
  text = text.replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '').trim();
  return JSON.parse(text);
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { pattern, situation, day } = req.body || {};
  if (!pattern || !situation) {
    return res.status(400).json({ error: 'pattern, situation이 필요합니다.' });
  }

  try {
    const msg = await client.messages.create({
      model: 'claude-sonnet-4-6',
      max_tokens: 300,
      system: [{ type: 'text', text: SYSTEM_PROMPT, cache_control: { type: 'ephemeral' } }],
      messages: [{ role: 'user', content: `패턴: ${pattern}\n상황: ${situation}\nDay: ${day || 1}` }]
    });

    const firstBlock = msg.content[0];
    if (!firstBlock || firstBlock.type !== 'text') {
      console.error('generate: unexpected content type', firstBlock?.type);
      return res.status(500).json({ error: '응답 형식 오류' });
    }

    let sentences;
    try {
      sentences = parseJsonSafe(firstBlock.text);
    } catch (err) {
      console.error('generate: JSON parse failed', err.message, firstBlock.text);
      return res.status(500).json({ error: 'JSON 파싱 실패', raw: firstBlock.text });
    }

    return res.status(200).json({ sentences });
  } catch (err) {
    console.error('generate error:', err.message);
    return res.status(500).json({ error: '생성 실패', detail: err.message });
  }
};
