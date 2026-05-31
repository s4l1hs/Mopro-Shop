-- 30-grants.sql — per-module schema grants + ref_schema read access for all roles.

-- identity
GRANT USAGE ON SCHEMA identity_schema TO identity_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA identity_schema
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO identity_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA identity_schema
  GRANT USAGE, SELECT ON SEQUENCES TO identity_user;

-- catalog
GRANT USAGE ON SCHEMA catalog_schema TO catalog_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA catalog_schema
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO catalog_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA catalog_schema
  GRANT USAGE, SELECT ON SEQUENCES TO catalog_user;

-- cart
GRANT USAGE ON SCHEMA cart_schema TO cart_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA cart_schema
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO cart_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA cart_schema
  GRANT USAGE, SELECT ON SEQUENCES TO cart_user;

-- order
GRANT USAGE ON SCHEMA order_schema TO order_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA order_schema
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO order_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA order_schema
  GRANT USAGE, SELECT ON SEQUENCES TO order_user;

-- payment
GRANT USAGE ON SCHEMA payment_schema TO payment_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA payment_schema
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO payment_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA payment_schema
  GRANT USAGE, SELECT ON SEQUENCES TO payment_user;

-- seller
GRANT USAGE ON SCHEMA seller_schema TO seller_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA seller_schema
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO seller_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA seller_schema
  GRANT USAGE, SELECT ON SEQUENCES TO seller_user;

-- search
GRANT USAGE ON SCHEMA search_schema TO search_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA search_schema
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO search_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA search_schema
  GRANT USAGE, SELECT ON SEQUENCES TO search_user;

-- notification
GRANT USAGE ON SCHEMA notification_schema TO notification_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA notification_schema
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO notification_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA notification_schema
  GRANT USAGE, SELECT ON SEQUENCES TO notification_user;

-- support
GRANT USAGE ON SCHEMA support_schema TO support_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA support_schema
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO support_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA support_schema
  GRANT USAGE, SELECT ON SEQUENCES TO support_user;

-- media
GRANT USAGE ON SCHEMA media_schema TO media_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA media_schema
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO media_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA media_schema
  GRANT USAGE, SELECT ON SEQUENCES TO media_user;

-- sizefinder
GRANT USAGE ON SCHEMA sizefinder_schema TO sizefinder_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA sizefinder_schema
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO sizefinder_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA sizefinder_schema
  GRANT USAGE, SELECT ON SEQUENCES TO sizefinder_user;

-- antifraud (v7 — core-svc)
GRANT USAGE ON SCHEMA antifraud_schema TO antifraud_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA antifraud_schema
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO antifraud_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA antifraud_schema
  GRANT USAGE, SELECT ON SEQUENCES TO antifraud_user;

-- einvoice (v7 — jobs-svc)
GRANT USAGE ON SCHEMA einvoice_schema TO einvoice_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA einvoice_schema
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO einvoice_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA einvoice_schema
  GRANT USAGE, SELECT ON SEQUENCES TO einvoice_user;

-- Cross-module: modules that publish events via order_schema.outbox.
-- cart, payment, seller, identity, catalog all write their domain events to
-- order_schema.outbox (owned by order_user). They need USAGE on the schema
-- plus INSERT + SELECT on the outbox table only.
-- ALTER DEFAULT PRIVILEGES covers tables created in the future (belt-and-suspenders).
GRANT USAGE ON SCHEMA order_schema TO cart_user, payment_user, seller_user, identity_user, catalog_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA order_schema
  GRANT INSERT, SELECT ON TABLES TO cart_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA order_schema
  GRANT INSERT, SELECT ON TABLES TO payment_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA order_schema
  GRANT INSERT, SELECT ON TABLES TO seller_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA order_schema
  GRANT INSERT, SELECT ON TABLES TO identity_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA order_schema
  GRANT INSERT, SELECT ON TABLES TO catalog_user;

-- Retroactive belt-and-suspenders: explicit grant on already-created tables.
DO $$
DECLARE
  tbl RECORD;
BEGIN
  FOR tbl IN SELECT tablename FROM pg_tables WHERE schemaname = 'order_schema' LOOP
    EXECUTE format(
      'GRANT INSERT, SELECT ON order_schema.%I TO cart_user, payment_user, seller_user, identity_user, catalog_user',
      tbl.tablename
    );
  END LOOP;
END;
$$;

-- ref_schema: read-only SELECT for every module role
GRANT USAGE ON SCHEMA ref_schema TO PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA ref_schema
  GRANT SELECT ON TABLES TO PUBLIC;

-- Explicit grants for tables already created before DEFAULT PRIVILEGES applied (belt-and-suspenders)
-- These are no-ops on a clean DB but harmless on re-run.
DO $$
DECLARE
  tbl RECORD;
BEGIN
  FOR tbl IN SELECT tablename FROM pg_tables WHERE schemaname = 'ref_schema' LOOP
    EXECUTE format('GRANT SELECT ON ref_schema.%I TO PUBLIC', tbl.tablename);
  END LOOP;
END;
$$;

-- inbox (user notification inbox — core-svc)
GRANT USAGE ON SCHEMA inbox_schema TO inbox_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA inbox_schema
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO inbox_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA inbox_schema
  GRANT USAGE, SELECT ON SEQUENCES TO inbox_user;
