/**
 * lib/cache.js — Upstash Redis 캐시 래퍼
 *
 * - UPSTASH_REDIS_REST_URL / UPSTASH_REDIS_REST_TOKEN 없으면 graceful fallback
 *   (캐시 없이 그냥 통과 — 개발/테스트 환경에서도 앱이 동작함)
 * - get(): 캐시 히트 시 파싱된 객체 반환, 미스 시 null
 * - set(key, value, ttlSeconds): 직렬화 후 저장
 */

let _redis = null;

function getRedis() {
  if (_redis) return _redis;
  const url   = process.env.UPSTASH_REDIS_REST_URL;
  const token = process.env.UPSTASH_REDIS_REST_TOKEN;
  if (!url || !token) return null;           // env 미설정 → 캐시 비활성
  const { Redis } = require('@upstash/redis');
  _redis = new Redis({ url, token });
  return _redis;
}

async function cacheGet(key) {
  const redis = getRedis();
  if (!redis) return null;
  try {
    const val = await redis.get(key);
    return val ?? null;                       // Upstash는 이미 JSON 파싱 후 반환
  } catch (e) {
    console.warn('[cache] get 실패 (스킵):', e.message);
    return null;
  }
}

async function cacheSet(key, value, ttlSeconds = 3600) {
  const redis = getRedis();
  if (!redis) return;
  try {
    await redis.setex(key, ttlSeconds, value); // Upstash가 직렬화 처리
  } catch (e) {
    console.warn('[cache] set 실패 (스킵):', e.message);
  }
}

async function cacheDel(key) {
  const redis = getRedis();
  if (!redis) return;
  try {
    await redis.del(key);
  } catch (e) {
    console.warn('[cache] del 실패 (스킵):', e.message);
  }
}

module.exports = { cacheGet, cacheSet, cacheDel };
