import { describe, expect, it } from "vitest";
import { cn } from "./utils";

describe("cn()", () => {
  it("passes through a single class", () => {
    expect(cn("bg-primary")).toBe("bg-primary");
  });

  it("merges multiple classes", () => {
    expect(cn("flex", "items-center", "gap-2")).toBe("flex items-center gap-2");
  });

  it("deduplicates conflicting Tailwind classes (last wins)", () => {
    expect(cn("bg-red-500", "bg-blue-500")).toBe("bg-blue-500");
  });

  it("deduplicates conflicting padding classes", () => {
    expect(cn("p-4", "p-2")).toBe("p-2");
  });

  it("ignores falsy values", () => {
    expect(cn("base", false && "skipped", "end")).toBe("base end");
  });

  it("ignores undefined and null", () => {
    expect(cn("base", undefined, null, "end")).toBe("base end");
  });

  it("handles conditional object syntax from clsx", () => {
    expect(cn({ "font-bold": true, "font-normal": false })).toBe("font-bold");
  });

  it("merges array inputs", () => {
    expect(cn(["flex", "gap-2"], "text-sm")).toBe("flex gap-2 text-sm");
  });
});
