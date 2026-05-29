-- 0066_home_mood_stories.up.sql
-- Adds a "mood stories" strip to the home screen — a horizontally-scrolled row
-- of circular thumbnails (mood tiles) that each deep-link into a filtered
-- catalog view. Modeled on the Trendyol-style "mood stories" strip but with
-- generic placeholder copy/imagery so nothing brand-specific is copied.

CREATE TABLE IF NOT EXISTS catalog_schema.home_mood_stories (
  id         BIGSERIAL   PRIMARY KEY,
  -- Localized labels rendered under each circle.
  title_tr   TEXT        NOT NULL,
  title_en   TEXT        NOT NULL,
  image_url  TEXT        NOT NULL,
  deep_link  TEXT        NOT NULL,
  sort_order INT         NOT NULL DEFAULT 0,
  active     BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS home_mood_stories_sort_idx
  ON catalog_schema.home_mood_stories(sort_order)
  WHERE active = TRUE;

-- Seed 6 mood stories with generic placeholder imagery. Replace via admin in prod.
INSERT INTO catalog_schema.home_mood_stories (title_tr, title_en, image_url, deep_link, sort_order) VALUES
  ('Yeni Sezon',   'New Season',     'https://placehold.co/200x200/CA4E00/FFFFFF/png?text=New',     '/categories?mood=new_season',   1),
  ('İndirimler',   'Deals',          'https://placehold.co/200x200/E36925/FFFFFF/png?text=Deals',   '/categories?mood=deals',        2),
  ('Ev & Yaşam',   'Home & Living',  'https://placehold.co/200x200/333333/FFFFFF/png?text=Home',    '/categories?mood=home_living',  3),
  ('Spor',         'Sport',          'https://placehold.co/200x200/666666/FFFFFF/png?text=Sport',   '/categories?mood=sport',        4),
  ('Çocuk',        'Kids',           'https://placehold.co/200x200/999999/FFFFFF/png?text=Kids',    '/categories?mood=kids',         5),
  ('Elektronik',   'Electronics',    'https://placehold.co/200x200/444444/FFFFFF/png?text=Tech',    '/categories?mood=electronics',  6)
ON CONFLICT DO NOTHING;

GRANT SELECT ON catalog_schema.home_mood_stories TO catalog_user;
