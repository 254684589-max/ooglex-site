-- Asset Compass V9: SQLite / Cloudflare D1-compatible research schema.
-- Migration definition only; no live D1 database has been created or modified.
PRAGMA foreign_keys = ON;
CREATE TABLE IF NOT EXISTS macro_series (
  series_id TEXT PRIMARY KEY,
  source TEXT NOT NULL,
  frequency TEXT NOT NULL CHECK(frequency IN ('daily','weekly','monthly','quarterly')),
  units TEXT NOT NULL,
  license_review_status TEXT NOT NULL DEFAULT 'pending',
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS macro_vintages (
  vintage_id INTEGER PRIMARY KEY AUTOINCREMENT,
  series_id TEXT NOT NULL REFERENCES macro_series(series_id),
  observation_date TEXT NOT NULL,
  available_at TEXT NOT NULL,
  value REAL NOT NULL,
  source_release_id TEXT NOT NULL,
  source_url TEXT NOT NULL,
  ingested_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (series_id, observation_date, available_at, source_release_id),
  CHECK(length(observation_date)=10),
  CHECK(length(available_at)>=20)
);
CREATE INDEX IF NOT EXISTS macro_vintages_lookup
  ON macro_vintages(series_id, observation_date, available_at DESC);
CREATE TABLE IF NOT EXISTS asset_factor_vintages (
  factor_id INTEGER PRIMARY KEY AUTOINCREMENT,
  asset_id TEXT NOT NULL,
  factor_group TEXT NOT NULL CHECK(factor_group IN ('rates','inflation','growth','liquidity','risk','asset_specific')),
  observation_date TEXT NOT NULL,
  available_at TEXT NOT NULL,
  factor_signal REAL NOT NULL CHECK(factor_signal BETWEEN -1 AND 1),
  model_version TEXT NOT NULL,
  source_refs_json TEXT NOT NULL,
  UNIQUE(asset_id, factor_group, observation_date, available_at, model_version)
);
CREATE INDEX IF NOT EXISTS factor_vintages_lookup
  ON asset_factor_vintages(asset_id, factor_group, available_at);
CREATE TABLE IF NOT EXISTS model_validation_runs (
  run_id TEXT PRIMARY KEY,
  model_version TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  train_start TEXT,
  test_end TEXT,
  diagnostics_json TEXT NOT NULL,
  approved_for_public_scoring INTEGER NOT NULL DEFAULT 0 CHECK(approved_for_public_scoring = 0)
);
