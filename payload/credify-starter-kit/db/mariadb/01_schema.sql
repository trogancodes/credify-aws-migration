-- CREDIFY LMS ledger (MariaDB) - LEGACY SCHEMA, no secondary indexes
CREATE DATABASE IF NOT EXISTS credify_lms;
USE credify_lms;
CREATE TABLE ledger_entries (
  id            BIGINT AUTO_INCREMENT PRIMARY KEY,
  loan_id       BIGINT NOT NULL,
  entry_type    VARCHAR(20) NOT NULL,
  amount        DECIMAL(14,2) NOT NULL,
  balance_after DECIMAL(14,2) NOT NULL,
  created_at    DATETIME NOT NULL
) ENGINE=InnoDB;
