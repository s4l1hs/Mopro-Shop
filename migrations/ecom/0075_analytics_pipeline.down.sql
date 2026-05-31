-- 0075_analytics_pipeline.down.sql — reverse 0075_analytics_pipeline.up.sql.
DROP TABLE IF EXISTS analytics_schema.user_recently_viewed;
DROP TABLE IF EXISTS analytics_schema.user_consent;
DROP TABLE IF EXISTS analytics_schema.session_identity;
DROP TABLE IF EXISTS analytics_schema.analytics_events;
-- analytics_schema is left in place (owned by bootstrap); dropping it is a cluster op.
