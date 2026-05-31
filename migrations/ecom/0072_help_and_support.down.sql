-- 0072_help_and_support.down.sql — reverse 0072_help_and_support.up.sql.
DROP TABLE IF EXISTS support_schema.support_tickets;
DROP TABLE IF EXISTS help_schema.help_articles;
DROP TABLE IF EXISTS help_schema.help_categories;
-- help_schema left in place (owned by bootstrap); dropping it is a cluster op.
