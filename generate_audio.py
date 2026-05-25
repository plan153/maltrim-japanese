#!/usr/bin/env python3
"""
말트임 일본어 — Google Cloud TTS 오디오 사전 생성 스크립트
─────────────────────────────────────────────────────────
사용법:
  python generate_audio.py --key YOUR_GCP_API_KEY

  또는 .env 파일에 GOOGLE_TTS_KEY=... 를 저장해두면 자동 로드.

생성 결과:  ./audio/d01_p0.mp3 ~ d30_p3.mp3  (총 98개)
모델:       ja-JP-Neural2-B  (남성 Neural2, 원어민 발음)
속도:       0.85 (학습자용 — 자연스럽고 또렷하게)
"""

import os, sys, json, base64, argparse
import urllib.request, urllib.error

# ── .env 자동 로드 ────────────────────────────────────
def load_env(path=".env"):
    if not os.path.exists(path):
        return
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip())

load_env()

# ── 커리큘럼 (index.html CURRICULUM 동기화 유지) ──────
CURRICULUM = {
  1:  [
    "がっこうに　いきます",
    "うちに　かえります",
    "まいにち　いきます",
  ],
  2:  [
    "しごとを　します",
    "べんきょうを　します",
    "しごとに　いきます",
    "たいへんです",
  ],
  3:  [
    "レストランで　たべます",
    "みずを　のみます",
    "おいしいです",
    "なにを　たべますか",
  ],
  4:  [
    "スーパーで　かいます",
    "みせに　いきます",
    "なにを　かいますか",
    "たかいです",
  ],
  5:  [
    "うちに　います",
    "ここに　あります",
    "ともだちが　います",
    "どこに　いますか",
  ],
  6:  [
    "いつ　いきますか",
    "どこに　いきますか",
    "だれと　たべますか",
    "なんじに　きますか",
  ],
  7:  [
    "がっこうで　べんきょうします",
    "まいにち　しごとを　します",
    "ともだちと　みせに　いきます",
  ],
  8:  [
    "がっこうに　いきました",
    "うちに　かえりました",
    "きのう　いきました",
  ],
  9:  [
    "すしを　たべました",
    "コーヒーを　のみました",
    "おいしかったです",
  ],
  10: [
    "べんきょうを　しました",
    "しごとを　しました",
    "たのしかったです",
  ],
  11: [
    "はやく　かえりました",
    "よく　ねました",
    "つかれました",
  ],
  12: [
    "いっしょに　いきましょう",
    "たべましょう",
    "はじめましょう",
    "やすみましょう",
  ],
  13: [
    "にほんに　いきたいです",
    "すしを　たべたいです",
    "にほんごを　はなしたいです",
  ],
  14: [
    "きのう　すしを　たべました",
    "いっしょに　いきましょう",
    "にほんに　いきたいです",
    "たのしかったですね",
  ],
  15: [
    "みて　ください",
    "きいて　ください",
    "まって　ください",
  ],
  16: [
    "たべて　ください",
    "のんで　ください",
    "はなして　ください",
  ],
  17: [
    "して　ください",
    "かいて　ください",
    "おしえて　ください",
  ],
  18: [
    "たべて、のみます",
    "いって、かえります",
    "みて、はなします",
  ],
  19: [
    "たべても　いいですか",
    "いっても　いいですか",
    "みても　いいですか",
  ],
  20: [
    "たべては　いけません",
    "ここに　はいっては　いけません",
    "はなしては　いけません",
  ],
  21: [
    "みて　ください、おいしいです",
    "たべても　いいですか",
    "まって　ください、いきます",
  ],
  22: [
    "いく　→　いきます",
    "たべる　→　たべます",
    "する　→　します",
  ],
  23: [
    "にほんごを　はなす　ことが　できます",
    "すしを　たべる　ことが　できます",
    "およぐ　ことが　できます",
  ],
  24: [
    "たべる　まえに　てを　あらいます",
    "いった　あとで　かえります",
    "べんきょうする　まえに　ねます",
  ],
  25: [
    "にほんに　いくと　おもいます",
    "たべたいと　おもいます",
    "むずかしいと　おもいます",
  ],
  26: [
    "どこに　いくの？",
    "たべようよ！",
    "いいね！",
  ],
  27: [
    "それは　なんだ？",
    "どこに　いたの？",
    "わかった！",
  ],
  28: [
    "いっしょに　たべようよ",
    "もう　かえるの？",
    "また　あそぼう！",
  ],
  29: [
    "きのう　どこに　いったの？",
    "レストランで　たべました",
    "また　いっしょに　いきましょう",
  ],
  30: [
    "にほんごが　はなせるように　なりました",
    "まいにち　べんきょうしました",
    "ありがとうございました！",
    "これからも　がんばります！",
  ],
}

# ── TTS 호출 ──────────────────────────────────────────
def synthesize(text, api_key, speaking_rate=0.85):
    """Google Cloud TTS REST API 호출 → MP3 bytes 반환"""
    clean = text.replace("　", "").replace("　", "")  # 전각 스페이스 제거
    payload = json.dumps({
        "input": {"text": clean},
        "voice": {
            "languageCode": "ja-JP",
            "name": "ja-JP-Neural2-B",
        },
        "audioConfig": {
            "audioEncoding": "MP3",
            "speakingRate": speaking_rate,
            "pitch": 0.0,
        },
    }).encode("utf-8")

    url = f"https://texttospeech.googleapis.com/v1/text:synthesize?key={api_key}"
    req = urllib.request.Request(
        url,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req) as resp:
            body = json.loads(resp.read())
            return base64.b64decode(body["audioContent"])
    except urllib.error.HTTPError as e:
        err = e.read().decode()
        raise RuntimeError(f"API 오류 {e.code}: {err}")

# ── 메인 ─────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="말트임 일본어 TTS 사전 생성")
    parser.add_argument("--key", default=os.environ.get("GOOGLE_TTS_KEY", ""),
                        help="Google Cloud TTS API 키")
    parser.add_argument("--out", default="audio", help="출력 폴더 (기본: ./audio)")
    parser.add_argument("--rate", type=float, default=0.85, help="발음 속도 (기본: 0.85)")
    parser.add_argument("--force", action="store_true", help="이미 존재하는 파일도 재생성")
    args = parser.parse_args()

    if not args.key:
        print("❌  API 키가 없습니다. --key 또는 .env의 GOOGLE_TTS_KEY 설정 필요.")
        sys.exit(1)

    os.makedirs(args.out, exist_ok=True)

    total = sum(len(v) for v in CURRICULUM.values())
    done = 0
    skipped = 0
    failed = []

    print(f"\n🎙  말트임 일본어 — TTS 사전 생성 시작")
    print(f"    모델: ja-JP-Neural2-B  |  속도: {args.rate}  |  총 {total}개\n")

    for day, phrases in CURRICULUM.items():
        for i, text in enumerate(phrases):
            filename = f"d{int(day):02d}_p{i}.mp3"
            out_path = os.path.join(args.out, filename)

            if os.path.exists(out_path) and not args.force:
                skipped += 1
                print(f"  ⏭  {filename}  (skip)")
                continue

            try:
                mp3 = synthesize(text, args.key, args.rate)
                with open(out_path, "wb") as f:
                    f.write(mp3)
                done += 1
                clean = text.replace("　", " ")
                print(f"  ✓  {filename}  {clean}")
            except Exception as e:
                failed.append((filename, str(e)))
                print(f"  ✗  {filename}  오류: {e}")

    print(f"\n{'─'*50}")
    print(f"  완료: {done}개  |  스킵: {skipped}개  |  실패: {len(failed)}개")
    if failed:
        print("\n  실패 목록:")
        for fn, err in failed:
            print(f"    {fn}: {err}")
    else:
        print(f"\n  ✅ 전체 완료! → ./{args.out}/ 폴더 확인 후 GitHub에 커밋하세요.")
        print(f"     git add audio/ && git commit -m 'feat: Neural2 TTS 사전 생성 오디오 추가'")

if __name__ == "__main__":
    main()
