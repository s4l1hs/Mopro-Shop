-- 0072_help_and_support.up.sql — help/FAQ content + support tickets.
--
-- Decision (Tranche 2b §2.2): separate modules. Help content (public,
-- guest-readable) lives in help_schema (new, owned by internal/help); support
-- tickets (private) live in support_schema (existing, owned by internal/support).
-- Bootstrap creates help_schema for fresh deploys; CREATE SCHEMA IF NOT EXISTS
-- covers already-initialised clusters. user_id/related_order_id are plain BIGINT
-- (no cross-schema FK to identity/order — codebase convention).

CREATE SCHEMA IF NOT EXISTS help_schema;

CREATE TABLE IF NOT EXISTS help_schema.help_categories (
    id                 BIGSERIAL   PRIMARY KEY,
    slug               TEXT        NOT NULL UNIQUE,
    title_translations JSONB       NOT NULL,  -- {tr,en,de,ar}
    icon_name          TEXT,
    sort_order         INTEGER     NOT NULL DEFAULT 0,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS help_schema.help_articles (
    id                 BIGSERIAL   PRIMARY KEY,
    category_id        BIGINT      NOT NULL REFERENCES help_schema.help_categories(id) ON DELETE CASCADE,
    slug               TEXT        NOT NULL UNIQUE,
    title_translations JSONB       NOT NULL,
    body_translations  JSONB       NOT NULL,  -- markdown per locale
    sort_order         INTEGER     NOT NULL DEFAULT 0,
    is_published       BOOLEAN     NOT NULL DEFAULT true,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_help_articles_category
    ON help_schema.help_articles (category_id, sort_order) WHERE is_published = true;

CREATE TABLE IF NOT EXISTS support_schema.support_tickets (
    id                   BIGSERIAL   PRIMARY KEY,
    user_id              BIGINT,                 -- null for guest submissions
    email                TEXT        NOT NULL,
    subject              TEXT        NOT NULL,
    body                 TEXT        NOT NULL,
    category             TEXT        NOT NULL
                         CHECK (category IN ('order_issue','payment','returns','account','other')),
    related_order_id     BIGINT,
    related_article_slug TEXT,
    status               TEXT        NOT NULL DEFAULT 'open'
                         CHECK (status IN ('open','in_progress','resolved','closed')),
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_support_tickets_user
    ON support_schema.support_tickets (user_id, created_at DESC) WHERE user_id IS NOT NULL;

-- Seed: 4 categories + 6 articles each (Tranche 2b §3.2).
INSERT INTO help_schema.help_categories (slug, title_translations, icon_name, sort_order) VALUES ('account', '{"tr": "Hesabım", "en": "My Account"}'::jsonb, 'person_outline', 1);
INSERT INTO help_schema.help_categories (slug, title_translations, icon_name, sort_order) VALUES ('orders', '{"tr": "Siparişlerim", "en": "My Orders"}'::jsonb, 'shopping_bag_outlined', 2);
INSERT INTO help_schema.help_categories (slug, title_translations, icon_name, sort_order) VALUES ('returns', '{"tr": "İadeler ve İptaller", "en": "Returns & Cancellations"}'::jsonb, 'assignment_return_outlined', 3);
INSERT INTO help_schema.help_categories (slug, title_translations, icon_name, sort_order) VALUES ('payment', '{"tr": "Ödeme ve Güvenlik", "en": "Payment & Security"}'::jsonb, 'shield_outlined', 4);
INSERT INTO help_schema.help_articles (category_id, slug, title_translations, body_translations, sort_order) SELECT id, 'reset-password', '{"tr": "Şifremi nasıl sıfırlarım?", "en": "How do I reset my password?"}'::jsonb, '{"tr": "## Şifre sıfırlama adımları\n\n- Giriş ekranında **Şifremi unuttum**''a dokun.\n- E-posta adresini gir.\n- Gelen bağlantıdan yeni şifreni belirle.", "en": "## Reset steps\n\n- Tap **Forgot password** on the sign-in screen.\n- Enter your email.\n- Set a new password from the emailed link."}'::jsonb, 1 FROM help_schema.help_categories WHERE slug='account';
INSERT INTO help_schema.help_articles (category_id, slug, title_translations, body_translations, sort_order) SELECT id, 'enable-mfa', '{"tr": "İki adımlı doğrulamayı nasıl açarım?", "en": "How do I enable two-factor auth?"}'::jsonb, '{"tr": "## MFA''yı etkinleştir\n\n- Hesabım > Güvenlik''e git.\n- Telefon numaranı doğrula.\n- Her girişte SMS kodu iste.", "en": "## Enable MFA\n\n- Go to Account > Security.\n- Verify your phone number.\n- Require an SMS code on each sign-in."}'::jsonb, 2 FROM help_schema.help_categories WHERE slug='account';
INSERT INTO help_schema.help_articles (category_id, slug, title_translations, body_translations, sort_order) SELECT id, 'change-email', '{"tr": "E-posta adresimi nasıl değiştiririm?", "en": "How do I change my email?"}'::jsonb, '{"tr": "## E-posta güncelleme\n\n- Hesabım > Profil''e git.\n- Yeni e-postanı gir ve doğrula.", "en": "## Update email\n\n- Go to Account > Profile.\n- Enter and verify your new email."}'::jsonb, 3 FROM help_schema.help_categories WHERE slug='account';
INSERT INTO help_schema.help_articles (category_id, slug, title_translations, body_translations, sort_order) SELECT id, 'delete-account', '{"tr": "Hesabımı nasıl silerim?", "en": "How do I delete my account?"}'::jsonb, '{"tr": "## Hesap silme\n\n- Hesabım > Profil > Hesabı sil.\n- İşlem geri alınamaz.", "en": "## Account deletion\n\n- Account > Profile > Delete account.\n- This cannot be undone."}'::jsonb, 4 FROM help_schema.help_categories WHERE slug='account';
INSERT INTO help_schema.help_articles (category_id, slug, title_translations, body_translations, sort_order) SELECT id, 'manage-addresses', '{"tr": "Adreslerimi nasıl yönetirim?", "en": "How do I manage addresses?"}'::jsonb, '{"tr": "## Adres yönetimi\n\n- Profil > Adreslerim''e git.\n- Yeni adres ekle veya düzenle.", "en": "## Address management\n\n- Go to Profile > Addresses.\n- Add or edit an address."}'::jsonb, 5 FROM help_schema.help_categories WHERE slug='account';
INSERT INTO help_schema.help_articles (category_id, slug, title_translations, body_translations, sort_order) SELECT id, 'notification-settings', '{"tr": "Bildirim ayarlarımı nasıl değiştiririm?", "en": "How do I change notification settings?"}'::jsonb, '{"tr": "## Bildirim tercihleri\n\n- Bildirimler > Bildirim ayarları.\n- Kategori ve kanal bazında aç/kapat.", "en": "## Notification preferences\n\n- Notifications > Notification settings.\n- Toggle per category and channel."}'::jsonb, 6 FROM help_schema.help_categories WHERE slug='account';
INSERT INTO help_schema.help_articles (category_id, slug, title_translations, body_translations, sort_order) SELECT id, 'track-order', '{"tr": "Siparişimi nasıl takip ederim?", "en": "How do I track my order?"}'::jsonb, '{"tr": "## Sipariş takibi\n\n- Siparişlerim''e git.\n- Siparişe dokunarak durumu gör.", "en": "## Order tracking\n\n- Go to My Orders.\n- Tap an order to see its status."}'::jsonb, 1 FROM help_schema.help_categories WHERE slug='orders';
INSERT INTO help_schema.help_articles (category_id, slug, title_translations, body_translations, sort_order) SELECT id, 'order-statuses', '{"tr": "Sipariş durumları ne anlama gelir?", "en": "What do order statuses mean?"}'::jsonb, '{"tr": "## Durumlar\n\n- **Ödeme bekleniyor**, **Hazırlanıyor**, **Kargoda**, **Teslim edildi**.", "en": "## Statuses\n\n- **Pending**, **Preparing**, **Shipped**, **Delivered**."}'::jsonb, 2 FROM help_schema.help_categories WHERE slug='orders';
INSERT INTO help_schema.help_articles (category_id, slug, title_translations, body_translations, sort_order) SELECT id, 'cancel-order', '{"tr": "Siparişimi nasıl iptal ederim?", "en": "How do I cancel an order?"}'::jsonb, '{"tr": "## İptal\n\n- Sipariş detayında **Siparişi İptal Et**''e dokun.\n- Kargolanmadan önce iptal edilebilir.", "en": "## Cancel\n\n- Tap **Cancel order** on the order detail.\n- Only before it ships."}'::jsonb, 3 FROM help_schema.help_categories WHERE slug='orders';
INSERT INTO help_schema.help_articles (category_id, slug, title_translations, body_translations, sort_order) SELECT id, 'invoice', '{"tr": "Faturamı nasıl indiririm?", "en": "How do I download my invoice?"}'::jsonb, '{"tr": "## Fatura\n\n- Sipariş detayından faturayı görüntüle.", "en": "## Invoice\n\n- View the invoice from the order detail."}'::jsonb, 4 FROM help_schema.help_categories WHERE slug='orders';
INSERT INTO help_schema.help_articles (category_id, slug, title_translations, body_translations, sort_order) SELECT id, 'missing-item', '{"tr": "Eksik ürün geldiyse ne yapmalıyım?", "en": "What if an item is missing?"}'::jsonb, '{"tr": "## Eksik ürün\n\n- Sipariş detayından **Bize Ulaş** ile talep oluştur.", "en": "## Missing item\n\n- Open a ticket via **Contact Us** from the order detail."}'::jsonb, 5 FROM help_schema.help_categories WHERE slug='orders';
INSERT INTO help_schema.help_articles (category_id, slug, title_translations, body_translations, sort_order) SELECT id, 'change-address', '{"tr": "Sipariş adresimi değiştirebilir miyim?", "en": "Can I change my order address?"}'::jsonb, '{"tr": "## Adres değişikliği\n\n- Kargolanmadan önce destekle iletişime geç.", "en": "## Address change\n\n- Contact support before the order ships."}'::jsonb, 6 FROM help_schema.help_categories WHERE slug='orders';
INSERT INTO help_schema.help_articles (category_id, slug, title_translations, body_translations, sort_order) SELECT id, 'start-return', '{"tr": "İade talebini nasıl başlatırım?", "en": "How do I start a return?"}'::jsonb, '{"tr": "## İade başlatma\n\n- Teslim edilen siparişte **İade Talebi Oluştur**''a dokun.\n- Ürünleri ve nedeni seç.", "en": "## Start a return\n\n- Tap **Request a Return** on a delivered order.\n- Pick items and a reason."}'::jsonb, 1 FROM help_schema.help_categories WHERE slug='returns';
INSERT INTO help_schema.help_articles (category_id, slug, title_translations, body_translations, sort_order) SELECT id, 'return-window', '{"tr": "İade süresi ne kadar?", "en": "What is the return window?"}'::jsonb, '{"tr": "## İade süresi\n\n- Teslimden itibaren **14 gün**.", "en": "## Return window\n\n- **14 days** from delivery."}'::jsonb, 2 FROM help_schema.help_categories WHERE slug='returns';
INSERT INTO help_schema.help_articles (category_id, slug, title_translations, body_translations, sort_order) SELECT id, 'refund-time', '{"tr": "İade param ne zaman yatar?", "en": "When will I get my refund?"}'::jsonb, '{"tr": "## İade süresi\n\n- Onaydan sonra **10 iş günü** içinde.", "en": "## Refund timing\n\n- Within **10 business days** of approval."}'::jsonb, 3 FROM help_schema.help_categories WHERE slug='returns';
INSERT INTO help_schema.help_articles (category_id, slug, title_translations, body_translations, sort_order) SELECT id, 'refund-method', '{"tr": "İade yöntemi nedir?", "en": "What is the refund method?"}'::jsonb, '{"tr": "## İade yöntemi\n\n- Orijinal ödeme yöntemine veya cüzdana.", "en": "## Refund method\n\n- To the original payment method or wallet."}'::jsonb, 4 FROM help_schema.help_categories WHERE slug='returns';
INSERT INTO help_schema.help_articles (category_id, slug, title_translations, body_translations, sort_order) SELECT id, 'return-status', '{"tr": "İade durumumu nasıl görürüm?", "en": "How do I see my return status?"}'::jsonb, '{"tr": "## İade durumu\n\n- **İadelerim**''den durumu takip et.", "en": "## Return status\n\n- Track it from **My Returns**."}'::jsonb, 5 FROM help_schema.help_categories WHERE slug='returns';
INSERT INTO help_schema.help_articles (category_id, slug, title_translations, body_translations, sort_order) SELECT id, 'non-returnable', '{"tr": "Hangi ürünler iade edilemez?", "en": "Which items are non-returnable?"}'::jsonb, '{"tr": "## İade edilemeyenler\n\n- Hijyenik ürünler ve dijital kodlar.", "en": "## Non-returnable\n\n- Hygiene products and digital codes."}'::jsonb, 6 FROM help_schema.help_categories WHERE slug='returns';
INSERT INTO help_schema.help_articles (category_id, slug, title_translations, body_translations, sort_order) SELECT id, 'payment-methods', '{"tr": "Hangi ödeme yöntemleri var?", "en": "What payment methods are accepted?"}'::jsonb, '{"tr": "## Ödeme yöntemleri\n\n- Kredi/banka kartı ve Mopro Coin cüzdanı.", "en": "## Payment methods\n\n- Credit/debit card and Mopro Coin wallet."}'::jsonb, 1 FROM help_schema.help_categories WHERE slug='payment';
INSERT INTO help_schema.help_articles (category_id, slug, title_translations, body_translations, sort_order) SELECT id, 'apply-coupon', '{"tr": "Kuponu nasıl uygularım?", "en": "How do I apply a coupon?"}'::jsonb, '{"tr": "## Kupon\n\n- Ödeme adımında kupon kodunu gir.", "en": "## Coupon\n\n- Enter the code at checkout."}'::jsonb, 2 FROM help_schema.help_categories WHERE slug='payment';
INSERT INTO help_schema.help_articles (category_id, slug, title_translations, body_translations, sort_order) SELECT id, 'coins', '{"tr": "Mopro Coin nedir?", "en": "What is Mopro Coin?"}'::jsonb, '{"tr": "## Mopro Coin\n\n- Her alışverişten kazandığın, her ay cüzdanına yatan puan.", "en": "## Mopro Coin\n\n- Rewards earned on purchases, paid monthly to your wallet."}'::jsonb, 3 FROM help_schema.help_categories WHERE slug='payment';
INSERT INTO help_schema.help_articles (category_id, slug, title_translations, body_translations, sort_order) SELECT id, '3ds', '{"tr": "3D Secure nedir?", "en": "What is 3D Secure?"}'::jsonb, '{"tr": "## 3D Secure\n\n- Kart ödemende bankanın ek doğrulama adımı.", "en": "## 3D Secure\n\n- Your bank''s extra verification step at card payment."}'::jsonb, 4 FROM help_schema.help_categories WHERE slug='payment';
INSERT INTO help_schema.help_articles (category_id, slug, title_translations, body_translations, sort_order) SELECT id, 'card-safety', '{"tr": "Kart bilgilerim güvende mi?", "en": "Are my card details safe?"}'::jsonb, '{"tr": "## Güvenlik\n\n- Kart verileri saklanmaz; ödeme sağlayıcıda işlenir.", "en": "## Safety\n\n- Card data is never stored; processed by the PSP."}'::jsonb, 5 FROM help_schema.help_categories WHERE slug='payment';
INSERT INTO help_schema.help_articles (category_id, slug, title_translations, body_translations, sort_order) SELECT id, 'failed-payment', '{"tr": "Ödemem başarısız olduysa?", "en": "What if my payment fails?"}'::jsonb, '{"tr": "## Başarısız ödeme\n\n- Kartını kontrol et veya farklı bir yöntem dene.", "en": "## Failed payment\n\n- Check your card or try another method."}'::jsonb, 6 FROM help_schema.help_categories WHERE slug='payment';
