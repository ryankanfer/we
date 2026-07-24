"use client";

import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

if (!url || !key) {
  // Surfaced at runtime rather than crashing the build, so the app can show a
  // clear "not configured" state if env is missing.
  console.warn("Supabase env not set: NEXT_PUBLIC_SUPABASE_URL / _ANON_KEY");
}

export const supabase = createClient(url ?? "", key ?? "", {
  auth: { persistSession: true, autoRefreshToken: true },
});

export const supabaseConfigured = Boolean(url && key);
