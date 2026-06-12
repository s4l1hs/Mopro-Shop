-- 50-ref-seed.sql — seed ref_schema with currencies, countries, locales,
-- 42 categories, 42 commission_rules for market='TR', and TR business_calendars 2026-2030.
-- All values verbatim from DATA_DICTIONARY.md § 2.5.

-- ── Currencies ──────────────────────────────────────────────────────────────
INSERT INTO ref_schema.currencies (code, kind, minor_unit_scale, symbol, name_en, active) VALUES
  ('TRY',      'fiat', 2, '₺',    'Turkish Lira',     TRUE),
  ('TRY_COIN', 'coin', 2, '₮',    'Mopro Coin',       TRUE),
  ('USD',      'fiat', 2, '$',    'US Dollar',        FALSE),
  ('EUR',      'fiat', 2, '€',    'Euro',             FALSE),
  ('AED',      'fiat', 2, 'د.إ',  'UAE Dirham',       FALSE),
  ('USD_COIN', 'coin', 2, '₮',    'Mopro Coin (USD)', FALSE),
  ('EUR_COIN', 'coin', 2, '₮',    'Mopro Coin (EUR)', FALSE),
  ('AED_COIN', 'coin', 2, '₮',    'Mopro Coin (AED)', FALSE)
ON CONFLICT DO NOTHING;

-- ── Countries ────────────────────────────────────────────────────────────────
INSERT INTO ref_schema.countries (code, name_en, default_currency, default_locale, default_timezone) VALUES
  ('TR', 'Turkey',        'TRY', 'tr-TR', 'Europe/Istanbul'),
  ('AE', 'UAE',           'AED', 'ar-AE', 'Asia/Dubai'),
  ('DE', 'Germany',       'EUR', 'de-DE', 'Europe/Berlin'),
  ('US', 'United States', 'USD', 'en-US', 'America/New_York')
ON CONFLICT DO NOTHING;

-- ── Locales (BCP 47) ─────────────────────────────────────────────────────────
INSERT INTO ref_schema.locales (tag, name_en, active) VALUES
  ('tr-TR', 'Turkish (Turkey)',   TRUE),
  ('en-US', 'English (US)',       FALSE),
  ('de-DE', 'German (Germany)',   FALSE),
  ('ar-AE', 'Arabic (UAE)',       FALSE)
ON CONFLICT DO NOTHING;

-- ── Categories (42 launch categories) ───────────────────────────────────────
INSERT INTO ref_schema.categories (id, slug, name_tr, name_en, parent_id, active) VALUES
  (1,  'aksesuar-atki-bere',     'Atkı, Bere, Eldiven, Şal ve Fular',                  'Scarves, Hats, Gloves',           NULL, TRUE),
  (2,  'aksesuar-kemer-saat',    'Kemer, Saç Aksesuarı, Kravat, Kol Düğmesi, Şapka',   'Belts, Hair Accessories',         NULL, TRUE),
  (3,  'saat',                   'Saat',                                                'Watches',                         NULL, TRUE),
  (4,  'tablet-aksesuar',        'Tablet Kılıfı, Tablet Standı, Tablet Kalemi',         'Tablet Accessories',              NULL, TRUE),
  (5,  'telefon-yedek-parca',    'Batarya, Ekran, Kamera, Telefon Kasası',              'Phone Spare Parts',               NULL, TRUE),
  (6,  'oyun-konsolu',           'PlayStation 5, PlayStation 4, Xbox, Nintendo',        'Game Consoles',                   NULL, TRUE),
  (7,  'televizyon',             'Televizyon',                                           'Television',                      NULL, TRUE),
  (8,  'bebek-emzirme',          'Emzirme Örtüsü, Emzirme Yastığı, Mama Önlüğü',        'Baby Feeding Accessories',        NULL, TRUE),
  (9,  'bebek-arabasi',          'Bebek Arabası, Puset, Oto Koltuğu, Park Yatak',       'Baby Strollers',                  NULL, TRUE),
  (10, 'bebek-oyuncak',          'Çocuk ve Bebek Oyuncakları',                           'Baby Toys',                       NULL, TRUE),
  (11, 'dijital-hediye',         'Dijital Hediye Kartları (Apple, Google, Netflix)',     'Digital Gift Cards',              NULL, TRUE),
  (12, 'online-egitim',          'Online Eğitim Uygulamaları',                           'Online Education Apps',           NULL, TRUE),
  (13, 'yazilim',                'Yazılım Ürünleri',                                    'Software Products',               NULL, TRUE),
  (14, 'beyaz-esya',             'Bulaşık Makinesi, Buzdolabı, Çamaşır Makinesi',        'Major Appliances',                NULL, TRUE),
  (15, 'klima-kombi',            'Klima – Kombi',                                        'AC and Boilers',                  NULL, TRUE),
  (16, 'akilli-mutfak',          'Akıllı Fritöz, Akıllı Tartı, Akıllı Kettle',          'Smart Kitchen Devices',           NULL, TRUE),
  (17, 'mutfak-makineleri',      'Yiyecek ve İçecek Hazırlama, Dikiş Makinesi',         'Kitchen Machines',                NULL, TRUE),
  (18, 'taki',                   'Bijuteri & Gümüş Takı (Bileklik, Kolye, Küpe)',       'Jewelry',                         NULL, TRUE),
  (19, 'ayakkabi',               'Ayakkabı',                                             'Shoes',                           NULL, TRUE),
  (20, 'canta',                  'Çanta',                                                'Bags',                            NULL, TRUE),
  (21, 'giyim',                  'Üst Giyim, Alt Giyim, İç Giyim, Spor Giyim',          'Clothing',                        NULL, TRUE),
  (22, 'bahce-dekor',            'Bahçe Dekorasyonu',                                    'Garden Decoration',               NULL, TRUE),
  (23, 'havuz',                  'Havuz Ürünleri',                                       'Pool Products',                   NULL, TRUE),
  (24, 'el-aletleri',            'El Aletleri, Elektrikli El Aletleri ve Aksesuarları', 'Hand Tools',                      NULL, TRUE),
  (25, 'bebek-banyo',            'Bebek Banyo Eşyaları, Küvet, Lazımlık',               'Baby Bath Items',                 NULL, TRUE),
  (26, 'kisisel-bakim',          'Epilatör, Saç Düzleştirici, Saç Maşası, Tartı',       'Personal Care',                   NULL, TRUE),
  (27, 'dizustu-bilgisayar',     'Dizüstü Bilgisayar, Oyuncu Dizüstü PC',               'Laptops',                         NULL, TRUE),
  (28, 'pc-yedek-parca',         'Bilgisayar Yedek Parça',                               'PC Components',                   NULL, TRUE),
  (29, 'projeksiyon',            'Projeksiyon Perdesi ve Kumandaları',                   'Projection Equipment',            NULL, TRUE),
  (30, 'akilli-telefon',         'Akıllı Cep Telefonu',                                  'Smartphones',                     NULL, TRUE),
  (31, 'tuslu-telefon',          'Tuşlu Cep Telefonu',                                   'Feature Phones',                  NULL, TRUE),
  (32, 'kopek-mama',             'Köpek Kuru Maması, Köpek Konserve Maması',             'Dog Food',                        NULL, TRUE),
  (33, 'hijyen',                 'Hasta Bezi ve Temizlik Ürünleri',                      'Hygiene Products',                NULL, TRUE),
  (34, 'aydinlatma',             'Avize, Abajur, Aplik, Lambader, Masa Lambası',         'Lighting',                        NULL, TRUE),
  (35, 'ev-tekstili',            'Salon, Mutfak, Yatak Odası, Bebek Tekstili',           'Home Textiles',                   NULL, TRUE),
  (36, 'parti-yilbasi',          'Parti ve Yılbaşı Ürünleri',                            'Party and New Year Products',     NULL, TRUE),
  (37, 'mutfak-gerec',           'Mutfak Gereçleri, Sofra Ürünleri, Pişirme',           'Kitchenware',                     NULL, TRUE),
  (38, 'sanat-malzeme',          'Boya Malzemeleri, Sanatsal Malzemeler',                'Art Supplies',                    NULL, TRUE),
  (39, 'kisisel-bakim-2',        'Ağız Bakım, Diş Macunu, Ağda, Cilt Bakım',            'Personal Hygiene',                NULL, TRUE),
  (40, 'oto-temizlik',           'Oto Bakım / Temizlik Ürünleri',                        'Auto Care Products',              NULL, TRUE),
  (41, 'gida',                   'Atıştırmalık, Kuru Gıda, Süt ve Kahvaltılık',          'Food Products',                   NULL, TRUE),
  (42, 'cicek',                  'Çiçek',                                                 'Flowers',                         NULL, TRUE)
ON CONFLICT DO NOTHING;

-- ── Commission rules for market='TR' (42 rows, verbatim from DATA_DICTIONARY.md §2.5) ──
-- commission_pct_bps: basis points (10000 = 100%)
-- kdv_pct_bps: 2000 = %20 KDV as of May 2026
INSERT INTO ref_schema.commission_rules
  (market, category_id, commission_pct_bps, kdv_pct_bps, effective_from, active) VALUES
  ('TR',  1, 2000, 2000, now(), TRUE),  -- Atkı, Bere, Eldiven, Şal ve Fular       %20.00
  ('TR',  2, 2000, 2000, now(), TRUE),  -- Kemer, Saç Aksesuarı, Kravat             %20.00
  ('TR',  3, 2000, 2000, now(), TRUE),  -- Saat                                     %20.00
  ('TR',  4, 2000, 2000, now(), TRUE),  -- Tablet Aksesuar                          %20.00
  ('TR',  5, 2000, 2000, now(), TRUE),  -- Telefon Yedek Parça                      %20.00
  ('TR',  6,  800, 2000, now(), TRUE),  -- Oyun Konsolu                              %8.00
  ('TR',  7,  800, 2000, now(), TRUE),  -- Televizyon                                %8.00
  ('TR',  8, 1650, 2000, now(), TRUE),  -- Bebek Emzirme Aksesuarları               %16.50
  ('TR',  9, 1650, 2000, now(), TRUE),  -- Bebek Arabası                            %16.50
  ('TR', 10, 1650, 2000, now(), TRUE),  -- Bebek Oyuncak                            %16.50
  ('TR', 11,  500, 2000, now(), TRUE),  -- Dijital Hediye Kartları                   %5.00
  ('TR', 12, 1017, 2000, now(), TRUE),  -- Online Eğitim                            %10.17
  ('TR', 13, 1200, 2000, now(), TRUE),  -- Yazılım                                  %12.00
  ('TR', 14, 1100, 2000, now(), TRUE),  -- Beyaz Eşya                               %11.00
  ('TR', 15, 1100, 2000, now(), TRUE),  -- Klima – Kombi                            %11.00
  ('TR', 16, 1500, 2000, now(), TRUE),  -- Akıllı Mutfak                            %15.00
  ('TR', 17, 1500, 2000, now(), TRUE),  -- Mutfak Makineleri                        %15.00
  ('TR', 18, 2000, 2000, now(), TRUE),  -- Takı                                     %20.00
  ('TR', 19, 2000, 2000, now(), TRUE),  -- Ayakkabı                                 %20.00
  ('TR', 20, 2000, 2000, now(), TRUE),  -- Çanta                                    %20.00
  ('TR', 21, 2000, 2000, now(), TRUE),  -- Giyim                                    %20.00
  ('TR', 22, 1750, 2000, now(), TRUE),  -- Bahçe Dekorasyonu                        %17.50
  ('TR', 23, 1750, 2000, now(), TRUE),  -- Havuz Ürünleri                           %17.50
  ('TR', 24, 1550, 2000, now(), TRUE),  -- El Aletleri                              %15.50
  ('TR', 25, 1650, 2000, now(), TRUE),  -- Bebek Banyo                              %16.50
  ('TR', 26, 1750, 2000, now(), TRUE),  -- Kişisel Bakım                            %17.50
  ('TR', 27,  750, 2000, now(), TRUE),  -- Dizüstü Bilgisayar                        %7.50
  ('TR', 28, 1550, 2000, now(), TRUE),  -- PC Yedek Parça                           %15.50
  ('TR', 29, 1600, 2000, now(), TRUE),  -- Projeksiyon                              %16.00
  ('TR', 30,  700, 2000, now(), TRUE),  -- Akıllı Telefon                            %7.00  ← verification: 700
  ('TR', 31, 1000, 2000, now(), TRUE),  -- Tuşlu Telefon                            %10.00
  ('TR', 32, 1525, 2000, now(), TRUE),  -- Köpek Mama                               %15.25
  ('TR', 33, 1729, 2000, now(), TRUE),  -- Hijyen                                   %17.29
  ('TR', 34, 2000, 2000, now(), TRUE),  -- Aydınlatma                               %20.00
  ('TR', 35, 2000, 2000, now(), TRUE),  -- Ev Tekstili                              %20.00
  ('TR', 36, 2000, 2000, now(), TRUE),  -- Parti ve Yılbaşı                         %20.00
  ('TR', 37, 1932, 2000, now(), TRUE),  -- Mutfak Gereçleri                         %19.32
  ('TR', 38, 1678, 2000, now(), TRUE),  -- Sanat Malzeme                            %16.78
  ('TR', 39, 1678, 2000, now(), TRUE),  -- Kişisel Hijyen                           %16.78
  ('TR', 40, 1650, 2000, now(), TRUE),  -- Oto Temizlik                             %16.50
  ('TR', 41, 1525, 2000, now(), TRUE),  -- Gıda                                     %15.25
  ('TR', 42, 2000, 2000, now(), TRUE)   -- Çiçek                                    %20.00
ON CONFLICT DO NOTHING;

-- ── TR Business Calendars 2026-2030 ─────────────────────────────────────────
-- Used by pkg/timex.AddBusinessDays for seller payout and cashback unlock_at.
-- Sources: Turkish Labour Law (fixed holidays) + Diyanet İşleri Başkanlığı (floating Ramazan/Kurban).

INSERT INTO ref_schema.business_calendars (market, date, reason) VALUES

  -- ── 2026 Fixed holidays ──────────────────────────────────────────────────
  ('TR', '2026-01-01', 'Yılbaşı'),
  ('TR', '2026-04-23', 'Ulusal Egemenlik ve Çocuk Bayramı'),
  ('TR', '2026-05-01', 'Emek ve Dayanışma Günü'),
  ('TR', '2026-05-19', 'Atatürk''ü Anma, Gençlik ve Spor Bayramı'),
  ('TR', '2026-07-15', 'Demokrasi ve Milli Birlik Günü'),
  ('TR', '2026-08-30', 'Zafer Bayramı'),
  ('TR', '2026-10-29', 'Cumhuriyet Bayramı'),

  -- ── 2026 Ramazan Bayramı (Eid al-Fitr) — 3 days ─────────────────────────
  ('TR', '2026-03-20', 'Ramazan Bayramı 1. Günü'),
  ('TR', '2026-03-21', 'Ramazan Bayramı 2. Günü'),
  ('TR', '2026-03-22', 'Ramazan Bayramı 3. Günü'),

  -- ── 2026 Kurban Bayramı (Eid al-Adha) — 4 days ───────────────────────────
  ('TR', '2026-05-27', 'Kurban Bayramı Arefe'),
  ('TR', '2026-05-28', 'Kurban Bayramı 1. Günü'),
  ('TR', '2026-05-29', 'Kurban Bayramı 2. Günü'),
  ('TR', '2026-05-30', 'Kurban Bayramı 3. Günü'),

  -- ── 2027 Fixed holidays ──────────────────────────────────────────────────
  ('TR', '2027-01-01', 'Yılbaşı'),
  ('TR', '2027-04-23', 'Ulusal Egemenlik ve Çocuk Bayramı'),
  ('TR', '2027-05-01', 'Emek ve Dayanışma Günü'),
  ('TR', '2027-05-19', 'Atatürk''ü Anma, Gençlik ve Spor Bayramı'),
  ('TR', '2027-07-15', 'Demokrasi ve Milli Birlik Günü'),
  ('TR', '2027-08-30', 'Zafer Bayramı'),
  ('TR', '2027-10-29', 'Cumhuriyet Bayramı'),

  -- ── 2027 Ramazan Bayramı — 3 days ────────────────────────────────────────
  ('TR', '2027-03-09', 'Ramazan Bayramı 1. Günü'),
  ('TR', '2027-03-10', 'Ramazan Bayramı 2. Günü'),
  ('TR', '2027-03-11', 'Ramazan Bayramı 3. Günü'),

  -- ── 2027 Kurban Bayramı — 4 days ─────────────────────────────────────────
  ('TR', '2027-05-16', 'Kurban Bayramı Arefe'),
  ('TR', '2027-05-17', 'Kurban Bayramı 1. Günü'),
  ('TR', '2027-05-18', 'Kurban Bayramı 2. Günü'),
  ('TR', '2027-05-19', 'Kurban Bayramı 3. Günü'),

  -- ── 2028 Fixed holidays ──────────────────────────────────────────────────
  ('TR', '2028-01-01', 'Yılbaşı'),
  ('TR', '2028-04-23', 'Ulusal Egemenlik ve Çocuk Bayramı'),
  ('TR', '2028-05-01', 'Emek ve Dayanışma Günü'),
  ('TR', '2028-05-19', 'Atatürk''ü Anma, Gençlik ve Spor Bayramı'),
  ('TR', '2028-07-15', 'Demokrasi ve Milli Birlik Günü'),
  ('TR', '2028-08-30', 'Zafer Bayramı'),
  ('TR', '2028-10-29', 'Cumhuriyet Bayramı'),

  -- ── 2028 Ramazan Bayramı — 3 days ────────────────────────────────────────
  ('TR', '2028-02-26', 'Ramazan Bayramı 1. Günü'),
  ('TR', '2028-02-27', 'Ramazan Bayramı 2. Günü'),
  ('TR', '2028-02-28', 'Ramazan Bayramı 3. Günü'),

  -- ── 2028 Kurban Bayramı — 4 days ─────────────────────────────────────────
  ('TR', '2028-05-05', 'Kurban Bayramı Arefe'),
  ('TR', '2028-05-06', 'Kurban Bayramı 1. Günü'),
  ('TR', '2028-05-07', 'Kurban Bayramı 2. Günü'),
  ('TR', '2028-05-08', 'Kurban Bayramı 3. Günü'),

  -- ── 2029 Fixed holidays ──────────────────────────────────────────────────
  ('TR', '2029-01-01', 'Yılbaşı'),
  ('TR', '2029-04-23', 'Ulusal Egemenlik ve Çocuk Bayramı'),
  ('TR', '2029-05-01', 'Emek ve Dayanışma Günü'),
  ('TR', '2029-05-19', 'Atatürk''ü Anma, Gençlik ve Spor Bayramı'),
  ('TR', '2029-07-15', 'Demokrasi ve Milli Birlik Günü'),
  ('TR', '2029-08-30', 'Zafer Bayramı'),
  ('TR', '2029-10-29', 'Cumhuriyet Bayramı'),

  -- ── 2029 Ramazan Bayramı — 3 days ────────────────────────────────────────
  ('TR', '2029-02-14', 'Ramazan Bayramı 1. Günü'),
  ('TR', '2029-02-15', 'Ramazan Bayramı 2. Günü'),
  ('TR', '2029-02-16', 'Ramazan Bayramı 3. Günü'),

  -- ── 2029 Kurban Bayramı — 4 days ─────────────────────────────────────────
  ('TR', '2029-04-24', 'Kurban Bayramı Arefe'),
  ('TR', '2029-04-25', 'Kurban Bayramı 1. Günü'),
  ('TR', '2029-04-26', 'Kurban Bayramı 2. Günü'),
  ('TR', '2029-04-27', 'Kurban Bayramı 3. Günü'),

  -- ── 2030 Fixed holidays ──────────────────────────────────────────────────
  ('TR', '2030-01-01', 'Yılbaşı'),
  ('TR', '2030-04-23', 'Ulusal Egemenlik ve Çocuk Bayramı'),
  ('TR', '2030-05-01', 'Emek ve Dayanışma Günü'),
  ('TR', '2030-05-19', 'Atatürk''ü Anma, Gençlik ve Spor Bayramı'),
  ('TR', '2030-07-15', 'Demokrasi ve Milli Birlik Günü'),
  ('TR', '2030-08-30', 'Zafer Bayramı'),
  ('TR', '2030-10-29', 'Cumhuriyet Bayramı'),

  -- ── 2030 Ramazan Bayramı — 3 days ────────────────────────────────────────
  ('TR', '2030-02-03', 'Ramazan Bayramı 1. Günü'),
  ('TR', '2030-02-04', 'Ramazan Bayramı 2. Günü'),
  ('TR', '2030-02-05', 'Ramazan Bayramı 3. Günü'),

  -- ── 2030 Kurban Bayramı — 4 days ─────────────────────────────────────────
  ('TR', '2030-04-13', 'Kurban Bayramı Arefe'),
  ('TR', '2030-04-14', 'Kurban Bayramı 1. Günü'),
  ('TR', '2030-04-15', 'Kurban Bayramı 2. Günü'),
  ('TR', '2030-04-16', 'Kurban Bayramı 3. Günü')

ON CONFLICT DO NOTHING;


-- ── Membership tiers (AC-05; lockstep with migration 0094) ──────────────────
INSERT INTO ref_schema.membership_tiers
  (code, market, rank, currency, min_spend_minor, min_orders, active)
VALUES
  ('classic', 'TR', 1, 'TRY',       0,  0, TRUE),
  ('gold',    'TR', 2, 'TRY',  250000,  5, TRUE),
  ('elite',   'TR', 3, 'TRY', 1000000, 15, TRUE)
ON CONFLICT (market, code) DO NOTHING;

-- ── Size-fit charts (lockstep with 0096; APPROXIMATE — curate) ─────────────
-- ── Representative standard charts (APPROXIMATE — see header) ───────────────
INSERT INTO ref_schema.size_charts
  (garment_type, size_label, sort_rank, measurement, min_mm, max_mm)
VALUES
  -- top: chest
  ('top','XS',1,'chest', 820, 880),('top','S',2,'chest', 880, 940),
  ('top','M',3,'chest', 940,1000),('top','L',4,'chest',1000,1080),
  ('top','XL',5,'chest',1080,1160),('top','XXL',6,'chest',1160,1260),
  -- bottom: waist + hip
  ('bottom','XS',1,'waist', 660, 720),('bottom','S',2,'waist', 720, 780),
  ('bottom','M',3,'waist', 780, 840),('bottom','L',4,'waist', 840, 920),
  ('bottom','XL',5,'waist', 920,1000),('bottom','XXL',6,'waist',1000,1100),
  ('bottom','XS',1,'hip', 860, 920),('bottom','S',2,'hip', 920, 980),
  ('bottom','M',3,'hip', 980,1040),('bottom','L',4,'hip',1040,1120),
  ('bottom','XL',5,'hip',1120,1200),('bottom','XXL',6,'hip',1200,1300),
  -- dress: chest + waist + hip
  ('dress','XS',1,'chest', 820, 880),('dress','S',2,'chest', 880, 940),
  ('dress','M',3,'chest', 940,1000),('dress','L',4,'chest',1000,1080),
  ('dress','XL',5,'chest',1080,1160),('dress','XXL',6,'chest',1160,1260),
  ('dress','XS',1,'waist', 660, 720),('dress','S',2,'waist', 720, 780),
  ('dress','M',3,'waist', 780, 840),('dress','L',4,'waist', 840, 920),
  ('dress','XL',5,'waist', 920,1000),('dress','XXL',6,'waist',1000,1100),
  ('dress','XS',1,'hip', 860, 920),('dress','S',2,'hip', 920, 980),
  ('dress','M',3,'hip', 980,1040),('dress','L',4,'hip',1040,1120),
  ('dress','XL',5,'hip',1120,1200),('dress','XXL',6,'hip',1200,1300),
  -- skirt: waist + hip
  ('skirt','XS',1,'waist', 660, 720),('skirt','S',2,'waist', 720, 780),
  ('skirt','M',3,'waist', 780, 840),('skirt','L',4,'waist', 840, 920),
  ('skirt','XL',5,'waist', 920,1000),('skirt','XXL',6,'waist',1000,1100),
  ('skirt','XS',1,'hip', 860, 920),('skirt','S',2,'hip', 920, 980),
  ('skirt','M',3,'hip', 980,1040),('skirt','L',4,'hip',1040,1120),
  ('skirt','XL',5,'hip',1120,1200),('skirt','XXL',6,'hip',1200,1300),
  -- outerwear: chest (cut roomier)
  ('outerwear','XS',1,'chest', 860, 920),('outerwear','S',2,'chest', 920, 980),
  ('outerwear','M',3,'chest', 980,1040),('outerwear','L',4,'chest',1040,1120),
  ('outerwear','XL',5,'chest',1120,1200),('outerwear','XXL',6,'chest',1200,1300)
ON CONFLICT (garment_type, size_label, measurement) DO NOTHING;
