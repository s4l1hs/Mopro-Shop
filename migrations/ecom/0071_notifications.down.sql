-- 0071_notifications.down.sql — reverse 0071_notifications.up.sql.
DROP TABLE IF EXISTS inbox_schema.push_tokens;
DROP TABLE IF EXISTS inbox_schema.notification_preferences;
DROP TABLE IF EXISTS inbox_schema.notifications;
-- inbox_schema is left in place (owned by bootstrap); dropping it is a cluster op.
