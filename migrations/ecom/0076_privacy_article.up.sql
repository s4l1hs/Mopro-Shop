-- 0076_privacy_article.up.sql — Tranche 4b: seed the "privacy-and-tracking" help
-- article linked from the analytics consent banner ("Daha fazla bilgi").
-- Idempotent: ON CONFLICT (slug) DO NOTHING so re-runs / fresh DBs are safe.
--
-- The body carries a DRAFT notice (first line) — this article and the consent
-- copy require legal review before the production launch flip of
-- kAnalyticsConsentEnabled (see REPORT.md "Pending legal review").

INSERT INTO help_schema.help_articles (category_id, slug, title_translations, body_translations, sort_order)
SELECT id,
       'privacy-and-tracking',
       '{"tr": "Verileriniz ve Gizliliğiniz", "en": "Your Data and Privacy"}'::jsonb,
       jsonb_build_object(
         'tr', E'> ⚠️ Bu makale hukuki inceleme bekliyor. Yayın öncesi nihai metin yayınlanacaktır.\n\n'
               || E'## Hangi verileri topluyoruz?\n\nGörüntülediğin ürünler, aradığın kelimeler (yalnızca normalleştirilmiş haliyle), '
               || E'sepete ekleme/çıkarma, satın alma, kategori ve menü gezintisi gibi alışveriş etkileşimleri.\n\n'
               || E'## Verilerinizi nasıl saklıyoruz?\n\nOlaylar yalnızca-ekleme bir kayıtta tutulur ve **90 gün** sonra silinir. '
               || E'Bu olaylardan türetilen özetler (ör. son baktıkların) önerileri güçlendirmek için saklanır.\n\n'
               || E'## İzni nasıl yönetebilirim?\n\nİzleme **varsayılan olarak kapalıdır**; yalnızca açıkça onay verirsen başlar. '
               || E'Hesabım > Gizlilik''ten istediğin zaman kapatabilir veya **Tüm verilerimi sil** ile tüm analitik verini silebilirsin.\n\n'
               || E'## Üçüncü taraflarla paylaşıyor muyuz?\n\nHayır. Analitik veriler yalnızca Mopro içinde işlenir; üçüncü taraf reklam/analitik sağlayıcılarına aktarılmaz.\n\n'
               || E'## Sorularınız mı var?\n\nYardım > Bize Ulaş üzerinden bize yazabilirsin.',
         'en', E'> ⚠️ This article is pending legal review. Final copy will be published before launch.\n\n'
               || E'## What do we collect?\n\nShopping interactions: products viewed, search terms (normalized only), '
               || E'cart add/remove, purchases, category and menu navigation.\n\n'
               || E'## How do we store it?\n\nEvents live in an append-only log and are deleted after **90 days**. '
               || E'Summaries derived from them (e.g. recently viewed) are kept to power recommendations.\n\n'
               || E'## How do I manage consent?\n\nTracking is **off by default** and starts only if you explicitly opt in. '
               || E'Turn it off anytime under Account > Privacy, or erase everything with **Delete all my data**.\n\n'
               || E'## Do we share with third parties?\n\nNo. Analytics data is processed only within Mopro; it is not sent to third-party ad/analytics providers.\n\n'
               || E'## Questions?\n\nReach us via Help > Contact Us.'
       ),
       99
  FROM help_schema.help_categories WHERE slug = 'account'
ON CONFLICT (slug) DO NOTHING;
