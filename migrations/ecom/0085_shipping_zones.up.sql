-- 0085_shipping_zones.up.sql — P-034 (shipping-ETA infra, enabler for P-007).
-- Static, market-keyed reference data for a CHEAP, table-driven pre-purchase delivery
-- estimate (shipping.EstimateETA) — NO carrier call. Lives in ref_schema (the one schema
-- every module may read, CLAUDE.md §5) alongside currencies / commission_rules /
-- business_calendars. Coarse zones (~7 for TR), NOT 81 provinces: a Z×Z matrix is enough
-- for a "1-3 iş günü" estimate and trivial to seed. Global-ready: a new market is a new
-- seed, zero code. See docs/internal/p034-shipping-eta-architecture.md.

-- city → coarse zone. city is a normalized ASCII key (lower, ascii-folded) to avoid
-- locale-dependent (Turkish İ/ı) casing in joins.
CREATE TABLE IF NOT EXISTS ref_schema.shipping_zones (
    market TEXT NOT NULL,
    city   TEXT NOT NULL,
    zone   TEXT NOT NULL,
    PRIMARY KEY (market, city)
);

-- origin_zone × dest_zone → transit business-day range.
CREATE TABLE IF NOT EXISTS ref_schema.transit_days (
    market      TEXT     NOT NULL,
    origin_zone TEXT     NOT NULL,
    dest_zone   TEXT     NOT NULL,
    min_days    SMALLINT NOT NULL CHECK (min_days >= 0),
    max_days    SMALLINT NOT NULL CHECK (max_days >= min_days),
    PRIMARY KEY (market, origin_zone, dest_zone)
);

-- one conservative national fallback per market: used when origin OR dest zone is unknown
-- (e.g. a guest with no address, or an un-onboarded seller). Data, not a Go literal
-- (CLAUDE.md §2.2: no market constants in business code).
CREATE TABLE IF NOT EXISTS ref_schema.transit_default (
    market   TEXT     PRIMARY KEY,
    min_days SMALLINT NOT NULL CHECK (min_days >= 0),
    max_days SMALLINT NOT NULL CHECK (max_days >= min_days)
);

-- ── TR seed ─────────────────────────────────────────────────────────────────────

-- 7 coarse zones, geographic tiers west→east used to derive transit ranges below.
INSERT INTO ref_schema.shipping_zones (market, city, zone) VALUES
  -- marmara
  ('TR','istanbul','marmara'),('TR','bursa','marmara'),('TR','kocaeli','marmara'),
  ('TR','balikesir','marmara'),('TR','tekirdag','marmara'),('TR','edirne','marmara'),
  ('TR','canakkale','marmara'),('TR','sakarya','marmara'),('TR','yalova','marmara'),('TR','kirklareli','marmara'),
  -- ege
  ('TR','izmir','ege'),('TR','manisa','ege'),('TR','aydin','ege'),('TR','denizli','ege'),
  ('TR','mugla','ege'),('TR','usak','ege'),('TR','afyonkarahisar','ege'),('TR','kutahya','ege'),
  -- ic_anadolu
  ('TR','ankara','ic_anadolu'),('TR','konya','ic_anadolu'),('TR','kayseri','ic_anadolu'),
  ('TR','eskisehir','ic_anadolu'),('TR','sivas','ic_anadolu'),('TR','kirikkale','ic_anadolu'),
  ('TR','aksaray','ic_anadolu'),('TR','nevsehir','ic_anadolu'),('TR','nigde','ic_anadolu'),
  ('TR','karaman','ic_anadolu'),('TR','yozgat','ic_anadolu'),('TR','cankiri','ic_anadolu'),('TR','kirsehir','ic_anadolu'),
  -- akdeniz
  ('TR','antalya','akdeniz'),('TR','adana','akdeniz'),('TR','mersin','akdeniz'),('TR','hatay','akdeniz'),
  ('TR','isparta','akdeniz'),('TR','burdur','akdeniz'),('TR','osmaniye','akdeniz'),('TR','kahramanmaras','akdeniz'),
  -- karadeniz
  ('TR','samsun','karadeniz'),('TR','trabzon','karadeniz'),('TR','ordu','karadeniz'),('TR','giresun','karadeniz'),
  ('TR','rize','karadeniz'),('TR','tokat','karadeniz'),('TR','amasya','karadeniz'),('TR','corum','karadeniz'),
  ('TR','zonguldak','karadeniz'),('TR','kastamonu','karadeniz'),('TR','sinop','karadeniz'),('TR','bartin','karadeniz'),
  ('TR','karabuk','karadeniz'),('TR','duzce','karadeniz'),('TR','bolu','karadeniz'),('TR','gumushane','karadeniz'),
  ('TR','artvin','karadeniz'),('TR','bayburt','karadeniz'),
  -- dogu_anadolu
  ('TR','erzurum','dogu_anadolu'),('TR','erzincan','dogu_anadolu'),('TR','malatya','dogu_anadolu'),
  ('TR','elazig','dogu_anadolu'),('TR','van','dogu_anadolu'),('TR','agri','dogu_anadolu'),('TR','kars','dogu_anadolu'),
  ('TR','mus','dogu_anadolu'),('TR','bitlis','dogu_anadolu'),('TR','hakkari','dogu_anadolu'),('TR','igdir','dogu_anadolu'),
  ('TR','ardahan','dogu_anadolu'),('TR','tunceli','dogu_anadolu'),('TR','bingol','dogu_anadolu'),
  -- guneydogu_anadolu
  ('TR','gaziantep','guneydogu_anadolu'),('TR','sanliurfa','guneydogu_anadolu'),('TR','diyarbakir','guneydogu_anadolu'),
  ('TR','mardin','guneydogu_anadolu'),('TR','batman','guneydogu_anadolu'),('TR','siirt','guneydogu_anadolu'),
  ('TR','sirnak','guneydogu_anadolu'),('TR','adiyaman','guneydogu_anadolu'),('TR','kilis','guneydogu_anadolu')
ON CONFLICT (market, city) DO NOTHING;

-- Transit matrix derived from a geographic tier per zone (west=1 … east=3). intra-zone
-- 1-2 business days; otherwise widens with the tier distance and an extra day reaching
-- the eastern tier. Generated as a Z×Z cross join so the 49 rows stay consistent.
WITH z(zone, tier) AS (
    VALUES ('marmara',1),('ege',1),('ic_anadolu',2),('akdeniz',2),
           ('karadeniz',2),('dogu_anadolu',3),('guneydogu_anadolu',3)
)
INSERT INTO ref_schema.transit_days (market, origin_zone, dest_zone, min_days, max_days)
SELECT 'TR', o.zone, d.zone,
       CASE WHEN o.zone = d.zone THEN 1
            ELSE GREATEST(2, 1 + abs(o.tier - d.tier)) END AS min_days,
       CASE WHEN o.zone = d.zone THEN 2
            ELSE GREATEST(2, 1 + abs(o.tier - d.tier)) + 1 + (CASE WHEN d.tier = 3 THEN 1 ELSE 0 END) END AS max_days
FROM z o CROSS JOIN z d
ON CONFLICT (market, origin_zone, dest_zone) DO NOTHING;

-- Conservative national fallback (unknown origin or dest).
INSERT INTO ref_schema.transit_default (market, min_days, max_days) VALUES ('TR', 2, 5)
ON CONFLICT (market) DO NOTHING;
