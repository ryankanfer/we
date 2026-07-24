"use client";

import { useEffect } from "react";

/** Registers the service worker so WE is installable as a PWA. */
export default function ServiceWorker() {
  useEffect(() => {
    if ("serviceWorker" in navigator) {
      navigator.serviceWorker.register("/sw.js").catch(() => {});
    }
  }, []);
  return null;
}
