-- 10-roles.sql — create one LOGIN role per module on postgres-ecom.
-- Placeholder password is replaced at runtime by 99-set-passwords.sh from env vars.
-- All roles: NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT LOGIN.

DO $$
DECLARE
  roles TEXT[] := ARRAY[
    'identity_user',
    'catalog_user',
    'cart_user',
    'order_user',
    'payment_user',
    'seller_user',
    'search_user',
    'notification_user',
    'support_user',
    'media_user',
    'sizefinder_user'
  ];
  r TEXT;
BEGIN
  FOREACH r IN ARRAY roles LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
      EXECUTE format(
        'CREATE ROLE %I NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT LOGIN PASSWORD ''REPLACE_BY_INIT''',
        r
      );
    END IF;
  END LOOP;
END;
$$;
