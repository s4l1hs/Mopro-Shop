"use client";

import { motion } from "framer-motion";
import Image from "next/image";
import Link from "next/link";
import { cn } from "@/lib/utils";

export interface CategoryCardProps {
  slug: string;
  name: string;
  imageUrl: string;
  className?: string;
}

export function CategoryCard({ slug, name, imageUrl, className }: CategoryCardProps) {
  return (
    <Link
      href={`/categories/${slug}`}
      className={cn(
        "group block rounded-lg overflow-hidden",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2",
        className,
      )}
    >
      <motion.div
        whileHover={{ scale: 1.04 }}
        transition={{ duration: 0.18, ease: "easeOut" }}
        className="relative aspect-square overflow-hidden rounded-lg shadow-sm group-hover:shadow-lg"
      >
        <Image
          src={imageUrl}
          alt={name}
          fill
          sizes="(max-width: 640px) 25vw, (max-width: 1024px) 12vw, 10vw"
          className="object-cover"
          loading="lazy"
        />
        {/* Bottom gradient + name */}
        <div className="absolute inset-0 bg-gradient-to-t from-black/60 via-transparent to-transparent" />
        <p className="absolute bottom-0 left-0 right-0 px-2 py-1.5 text-xs font-medium text-white line-clamp-2 leading-tight">
          {name}
        </p>
      </motion.div>
    </Link>
  );
}
