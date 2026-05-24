import type { Metadata } from "next";
import { CategoryGrid } from "@/components/home/category-grid";
import { HeroCarousel } from "@/components/home/hero-carousel";
import { HomeProductRail } from "@/components/home/product-rail";
import { TrustBar } from "@/components/home/trust-bar";
import { HERO_SLIDES } from "@/lib/home/hero-slides";

export const revalidate = 60;

export const metadata: Metadata = {
  title: "Mopro — Süresiz Cashback ile Alışveriş",
  description:
    "Mopro'da alışveriş yap, her ay Mopro Coin kazan — süresiz. Türkiye'nin cashback marketplacı.",
  openGraph: {
    title: "Mopro — Süresiz Cashback ile Alışveriş",
    description: "Mopro'da alışveriş yap, her ay Mopro Coin kazan — süresiz.",
    type: "website",
  },
};

export default function HomePage() {
  return (
    <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
      {/* Hero carousel */}
      <section className="py-4 sm:py-6">
        <HeroCarousel slides={HERO_SLIDES} />
      </section>

      {/* Category quick-grid */}
      <section className="py-4 sm:py-6">
        <h2 className="mb-4 text-base font-semibold text-foreground sm:text-lg">Kategoriler</h2>
        <CategoryGrid limit={8} />
      </section>

      {/* Product rails */}
      <div className="space-y-8 py-4 sm:py-6">
        <HomeProductRail
          title="Senin için seçtiklerimiz"
          sort="recommended"
          seeAllHref="/categories?sort=recommended"
        />
        <HomeProductRail
          title="Çok satanlar"
          sort="bestsellers"
          seeAllHref="/categories?sort=bestsellers"
        />
        <HomeProductRail
          title="Yeni gelenler"
          sort="newest"
          seeAllHref="/categories?sort=newest"
        />
      </div>

      {/* Trust bar */}
      <section className="py-6 sm:py-8">
        <TrustBar />
      </section>
    </div>
  );
}
