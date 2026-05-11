-- 20-schemas.sql — lock down public schema, create one schema per module + ref_schema.

REVOKE ALL ON SCHEMA public FROM PUBLIC;

-- core-svc module schemas
CREATE SCHEMA IF NOT EXISTS identity_schema     AUTHORIZATION identity_user;
CREATE SCHEMA IF NOT EXISTS catalog_schema      AUTHORIZATION catalog_user;
CREATE SCHEMA IF NOT EXISTS cart_schema         AUTHORIZATION cart_user;
CREATE SCHEMA IF NOT EXISTS order_schema        AUTHORIZATION order_user;
CREATE SCHEMA IF NOT EXISTS payment_schema      AUTHORIZATION payment_user;
CREATE SCHEMA IF NOT EXISTS seller_schema       AUTHORIZATION seller_user;
CREATE SCHEMA IF NOT EXISTS search_schema       AUTHORIZATION search_user;

-- jobs-svc module schemas
CREATE SCHEMA IF NOT EXISTS notification_schema AUTHORIZATION notification_user;
CREATE SCHEMA IF NOT EXISTS support_schema      AUTHORIZATION support_user;
CREATE SCHEMA IF NOT EXISTS media_schema        AUTHORIZATION media_user;
CREATE SCHEMA IF NOT EXISTS sizefinder_schema   AUTHORIZATION sizefinder_user;

-- shared read-only reference schema (owned by the superuser / ecom_admin; modules SELECT only)
CREATE SCHEMA IF NOT EXISTS ref_schema;
