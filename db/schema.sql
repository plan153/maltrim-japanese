-- ================================================================
-- 말트임 일본어 앱 — PostgreSQL 스키마 v1.0
-- 설계 원칙: 변경 자유도 최우선 (JSONB 확장 컬럼 + 버전 관리)
-- ================================================================

-- 확장 모듈
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";  -- 일본어 텍스트 검색용

-- ================================================================
-- 1. CURRICULUM — 커리큘럼 단위 (Day별 주제)
-- ================================================================
CREATE TABLE curriculum (
  curriculum_id   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  day_number      SMALLINT NOT NULL UNIQUE CHECK (day_number BETWEEN 1 AND 365),
  level           VARCHAR(10) NOT NULL DEFAULT 'beginner'
                  CHECK (level IN ('beginner','intermediate','advanced')),
  topic           VARCHAR(100) NOT NULL,          -- "핵심 뼈대 · 이동 동사"
  grammar_point   VARCHAR(200),                   -- "〜に いきます"
  week_number     SMALLINT GENERATED ALWAYS AS (CEIL(day_number::numeric / 7)) STORED,
  is_review_day   BOOLEAN NOT NULL DEFAULT FALSE,
  meta            JSONB DEFAULT '{}',             -- 자유 확장 필드 (태그, 카테고리 등)
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_curriculum_day   ON curriculum(day_number);
CREATE INDEX idx_curriculum_level ON curriculum(level);
CREATE INDEX idx_curriculum_meta  ON curriculum USING GIN(meta);

-- ================================================================
-- 2. EXPRESSIONS — 학습 문장 (오디오 포함)
-- ================================================================
CREATE TABLE expressions (
  expression_id   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  curriculum_id   UUID NOT NULL REFERENCES curriculum(curriculum_id) ON DELETE CASCADE,
  seq             SMALLINT NOT NULL DEFAULT 0,    -- Day 내 순서
  jp_text         VARCHAR(200) NOT NULL,          -- "みずを　のみます"
  reading         VARCHAR(200),                   -- "미즈오 노미마스"
  kr_meaning      VARCHAR(300) NOT NULL,          -- "물을 마십니다"
  base_form       VARCHAR(100),                   -- 기본형 "のむ"
  grammar_tags    TEXT[] DEFAULT '{}',            -- ['て형','요청','ください']
  audio_url       VARCHAR(500),                   -- CDN MP3 경로
  audio_duration  REAL,                           -- 초 단위
  tts_version     SMALLINT NOT NULL DEFAULT 1,    -- TTS 재생성 시 버전 올림
  difficulty      SMALLINT DEFAULT 1 CHECK (difficulty BETWEEN 1 AND 5),
  meta            JSONB DEFAULT '{}',             -- 자유 확장
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (curriculum_id, seq)
);

CREATE INDEX idx_expr_curriculum ON expressions(curriculum_id);
CREATE INDEX idx_expr_tags       ON expressions USING GIN(grammar_tags);
CREATE INDEX idx_expr_meta       ON expressions USING GIN(meta);
CREATE INDEX idx_expr_jp_trgm    ON expressions USING GIN(jp_text gin_trgm_ops);

-- ================================================================
-- 3. USER_PROGRESS — 사용자별 진도 + 망각곡선 관리
-- ================================================================
CREATE TABLE user_progress (
  progress_id     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         VARCHAR(100) NOT NULL,          -- 외부 Auth 시스템 ID
  expression_id   UUID NOT NULL REFERENCES expressions(expression_id) ON DELETE CASCADE,
  review_stage    SMALLINT NOT NULL DEFAULT 0 CHECK (review_stage BETWEEN 0 AND 6),
  last_studied_at DATE NOT NULL DEFAULT CURRENT_DATE,
  next_review_at  DATE NOT NULL DEFAULT CURRENT_DATE,
  attempt_count   SMALLINT NOT NULL DEFAULT 0,
  accuracy_avg    REAL DEFAULT 0 CHECK (accuracy_avg BETWEEN 0 AND 100),
  fluency_avg     REAL DEFAULT 0 CHECK (fluency_avg BETWEEN 0 AND 100),
  is_mastered     BOOLEAN NOT NULL DEFAULT FALSE, -- stage 6 도달 시 TRUE
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, expression_id)
);

CREATE INDEX idx_progress_user        ON user_progress(user_id);
CREATE INDEX idx_progress_next_review ON user_progress(user_id, next_review_at);
CREATE INDEX idx_progress_mastered    ON user_progress(user_id, is_mastered);

-- 복습 주기 자동 계산 함수
CREATE OR REPLACE FUNCTION calc_next_review(stage SMALLINT, accuracy REAL)
RETURNS DATE AS $$
DECLARE
  intervals INT[] := ARRAY[0, 1, 3, 7, 14, 30, 60];
  next_stage SMALLINT;
BEGIN
  IF accuracy >= 70 THEN
    next_stage := LEAST(stage + 1, 6);
  ELSE
    next_stage := stage;  -- 낮은 점수면 같은 단계 유지
  END IF;
  RETURN CURRENT_DATE + (intervals[next_stage + 1] || ' days')::INTERVAL;
END;
$$ LANGUAGE plpgsql STABLE;

-- ================================================================
-- 4. SPEAKING_LOG — 발음 평가 전체 이력
-- ================================================================
CREATE TABLE speaking_log (
  log_id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id           VARCHAR(100) NOT NULL,
  expression_id     UUID NOT NULL REFERENCES expressions(expression_id) ON DELETE CASCADE,
  session_id        UUID,                         -- 오늘 세션 묶음 ID
  accuracy_score    REAL CHECK (accuracy_score BETWEEN 0 AND 100),
  fluency_score     REAL CHECK (fluency_score BETWEEN 0 AND 100),
  completeness      REAL CHECK (completeness BETWEEN 0 AND 100),
  composite_score   REAL GENERATED ALWAYS AS (
    COALESCE(accuracy_score, 0) * 0.5 +
    COALESCE(fluency_score, 0)  * 0.3 +
    COALESCE(completeness, 0)   * 0.2
  ) STORED,
  word_detail       JSONB DEFAULT '[]',           -- 단어별 점수 [{"word":"みず","accuracy":88}]
  user_audio_url    VARCHAR(500),                 -- S3 사용자 녹음 파일
  asr_provider      VARCHAR(30) DEFAULT 'azure',  -- 'azure'/'web_speech'/'whisper'
  duration_ms       INTEGER,                      -- 녹음 길이 (ms)
  ffd_ms            INTEGER,                      -- First Formant Delay
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_log_user       ON speaking_log(user_id, created_at DESC);
CREATE INDEX idx_log_expression ON speaking_log(expression_id);
CREATE INDEX idx_log_session    ON speaking_log(session_id);
CREATE INDEX idx_log_word       ON speaking_log USING GIN(word_detail);

-- ================================================================
-- 5. TRAVEL_PHRASES — 여행 응용 코너 (Day별 연계)
-- ================================================================
CREATE TABLE travel_phrases (
  travel_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  curriculum_id   UUID NOT NULL REFERENCES curriculum(curriculum_id) ON DELETE CASCADE,
  situation       VARCHAR(50) NOT NULL,           -- "교통 · 전철"
  q_jp            VARCHAR(200) NOT NULL,
  q_kr            VARCHAR(200) NOT NULL,
  a_jp            VARCHAR(200) NOT NULL,
  a_kr            VARCHAR(200) NOT NULL,
  link_text       VARCHAR(300),                   -- 패턴 연계 설명
  strength        VARCHAR(10) DEFAULT 'strong'
                  CHECK (strength IN ('strong','medium','loose')),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_travel_curriculum ON travel_phrases(curriculum_id);

-- ================================================================
-- 6. 변경 이력 트리거 (updated_at 자동 갱신)
-- ================================================================
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_curriculum_updated  BEFORE UPDATE ON curriculum  FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_expressions_updated BEFORE UPDATE ON expressions FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_progress_updated    BEFORE UPDATE ON user_progress FOR EACH ROW EXECUTE FUNCTION update_timestamp();

-- ================================================================
-- 7. 유용한 뷰
-- ================================================================

-- 오늘 복습 대상 (user_id 파라미터로 필터)
CREATE VIEW v_due_reviews AS
SELECT up.*, e.jp_text, e.reading, e.kr_meaning, e.audio_url,
       c.day_number, c.topic, c.grammar_point
FROM user_progress up
JOIN expressions e ON up.expression_id = e.expression_id
JOIN curriculum  c ON e.curriculum_id  = c.curriculum_id
WHERE up.next_review_at <= CURRENT_DATE
  AND up.is_mastered = FALSE;

-- 사용자별 Day 완료 현황
CREATE VIEW v_day_completion AS
SELECT user_id,
       c.day_number,
       COUNT(e.expression_id)                           AS total_phrases,
       COUNT(up.expression_id)                          AS studied_phrases,
       AVG(up.accuracy_avg)                             AS avg_accuracy,
       BOOL_AND(up.accuracy_avg >= 70)                  AS day_passed
FROM curriculum c
JOIN expressions e ON c.curriculum_id = e.curriculum_id
LEFT JOIN user_progress up ON e.expression_id = up.expression_id
GROUP BY user_id, c.day_number
ORDER BY user_id, c.day_number;

-- ================================================================
-- 8. 시드 데이터 — Day 1 샘플
-- ================================================================
INSERT INTO curriculum (day_number, topic, grammar_point, is_review_day) VALUES
(1,  '핵심 뼈대 · 이동 동사',     '〜に いきます', FALSE),
(2,  '핵심 뼈대 · 일과 공부',     '〜を します', FALSE),
(3,  '핵심 뼈대 · 먹고 마시기',   '〜を たべます / のみます', FALSE),
(4,  '핵심 뼈대 · 쇼핑',         '〜を かいます', FALSE),
(5,  '핵심 뼈대 · 존재 표현',     '〜が います / あります', FALSE),
(6,  '핵심 뼈대 · 의문사',       'どこ / なに / なんじ', FALSE),
(7,  '1주차 복습 · 복합 표현',    '장소(で)+목적어(を)+동사', TRUE)
ON CONFLICT (day_number) DO NOTHING;

-- Day 1 문장 시드
WITH d1 AS (SELECT curriculum_id FROM curriculum WHERE day_number = 1)
INSERT INTO expressions (curriculum_id, seq, jp_text, reading, kr_meaning, grammar_tags,
                          audio_url)
SELECT d1.curriculum_id, s.seq, s.jp, s.rd, s.kr, s.tags, s.url
FROM d1, (VALUES
  (0, 'がっこうに　いきます', '각꼬우니 이키마스', '학교에 갑니다',
   ARRAY['に格','いきます','現在形'], 'https://plan153.github.io/maltrim-japanese/audio/d01_p0.mp3'),
  (1, 'うちに　かえります',   '우치니 카에리마스',  '집에 돌아갑니다',
   ARRAY['に格','かえります','現在形'], 'https://plan153.github.io/maltrim-japanese/audio/d01_p1.mp3'),
  (2, 'まいにち　いきます',   '마이니치 이키마스',  '매일 갑니다',
   ARRAY['副詞','いきます','現在形'], 'https://plan153.github.io/maltrim-japanese/audio/d01_p2.mp3')
) AS s(seq, jp, rd, kr, tags, url)
ON CONFLICT DO NOTHING;
