ALTER TABLE payments 
  ADD COLUMN method ENUM('nowpayments','card2card','telegram_stars') NOT NULL DEFAULT 'telegram_stars',
  ADD COLUMN currency VARCHAR(8) DEFAULT 'XTR',
  ADD COLUMN stars_total BIGINT DEFAULT NULL,
  ADD COLUMN tg_payload VARCHAR(128) DEFAULT NULL,
  ADD COLUMN tg_charge_id VARCHAR(128) DEFAULT NULL,
  ADD COLUMN paid_at DATETIME NULL;
