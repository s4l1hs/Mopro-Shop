"use client";

import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import type { ProductDetail } from "@/lib/types/product";

interface ProductTabsProps {
  product: ProductDetail;
}

export function ProductTabs({ product }: ProductTabsProps) {
  const descriptionParagraphs = (product.description ?? "Bu ürün için açıklama bulunmuyor.")
    .split(/\n\n+/)
    .filter(Boolean);

  const specs = product.specs ? Object.entries(product.specs) : [];

  return (
    <Tabs defaultValue="description" className="w-full">
      <TabsList className="w-full justify-start rounded-none border-b border-border bg-transparent h-auto p-0 gap-0">
        {(["description", "specs", "reviews", "qa"] as const).map((tab) => (
          <TabsTrigger
            key={tab}
            value={tab}
            className="rounded-none border-b-2 border-transparent data-[state=active]:border-primary data-[state=active]:bg-transparent px-4 py-3 text-sm"
          >
            {tab === "description" && "Açıklama"}
            {tab === "specs" && "Özellikler"}
            {tab === "reviews" && "Değerlendirmeler"}
            {tab === "qa" && "Soru & Cevap"}
          </TabsTrigger>
        ))}
      </TabsList>

      {/* Description */}
      <TabsContent value="description" className="pt-5 space-y-3">
        {descriptionParagraphs.map((p, i) => (
          <p key={i} className="text-sm text-foreground leading-relaxed">
            {p}
          </p>
        ))}
      </TabsContent>

      {/* Specs */}
      <TabsContent value="specs" className="pt-5">
        {specs.length === 0 ? (
          <p className="text-sm text-muted-foreground">Özellik bilgisi bulunmuyor.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <tbody>
                {specs.map(([key, value]) => (
                  <tr key={key} className="border-b border-border last:border-0">
                    <td className="py-2.5 pr-6 w-1/2 font-medium text-muted-foreground align-top">
                      {key}
                    </td>
                    <td className="py-2.5 text-foreground align-top">{value}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </TabsContent>

      {/* Reviews — stub */}
      <TabsContent value="reviews" className="pt-5">
        <p className="text-sm text-muted-foreground">
          Değerlendirmeler yakında burada görüntülenecek.
        </p>
      </TabsContent>

      {/* Q&A — stub */}
      <TabsContent value="qa" className="pt-5">
        <p className="text-sm text-muted-foreground">
          Soru ve cevaplar yakında burada görüntülenecek.
        </p>
      </TabsContent>
    </Tabs>
  );
}
