"use client";

import { useEffect, useState } from "react";

// Reads the non-httpOnly mopro_s session indicator cookie client-side.
// httpOnly JWTs are separate; this cookie is a presence flag only.
function hasMoproSession(): boolean {
  if (typeof document === "undefined") return false;
  return document.cookie.split(";").some((c) => c.trim().startsWith("mopro_s="));
}

export function useSession(): { isAuthenticated: boolean } {
  const [isAuthenticated, setIsAuthenticated] = useState(false);

  useEffect(() => {
    setIsAuthenticated(hasMoproSession());
  }, []);

  return { isAuthenticated };
}
