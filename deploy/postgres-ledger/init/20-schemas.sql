-- 20-schemas.sql — lock down public schema; create one schema per fin-svc module.

REVOKE ALL ON SCHEMA public FROM PUBLIC;

CREATE SCHEMA IF NOT EXISTS wallet_schema        AUTHORIZATION wallet_user;
CREATE SCHEMA IF NOT EXISTS commission_schema    AUTHORIZATION commission_user;
CREATE SCHEMA IF NOT EXISTS sellerpayout_schema  AUTHORIZATION sellerpayout_user;
CREATE SCHEMA IF NOT EXISTS treasury_schema      AUTHORIZATION treasury_user;
CREATE SCHEMA IF NOT EXISTS cashback_schema      AUTHORIZATION cashback_user;
