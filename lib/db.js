// lib/db.js — Neon PostgreSQL 서버리스 연결
const { neon } = require('@neondatabase/serverless');

let _sql = null;

function getDb() {
  if (!_sql) {
    if (!process.env.DATABASE_URL) {
      throw new Error('DATABASE_URL 환경변수가 설정되지 않았습니다.');
    }
    _sql = neon(process.env.DATABASE_URL);
  }
  return _sql;
}

module.exports = { getDb };
