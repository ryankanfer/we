"use client";

import { create } from "zustand";
import { supabase, supabaseConfigured } from "./supabase";
import type { InsightRecord, InsightState, PersonResponse, Reflection } from "./types";

export type Member = { id: string; name: string; hue: "burgundy" | "sage" };
export type Status = "loading" | "unconfigured" | "signedOut" | "needsCouple" | "ready";

interface DbConsent {
  insight_id: string;
  visibility: "private" | "shared" | "mutual";
  owner_id: string | null;
  readiness: "idle" | "requested" | "accepted" | "declined" | "withdrawn";
  initiator_id: string | null;
  requested_at: string | null;
  accepted_at: string | null;
  resolution_type: "settled" | "released" | "leftOpen" | null;
  resolution_choice: string | null;
}
interface DbResponse {
  insight_id: string;
  profile_id: string;
  status: "none" | "draft" | "submitted" | "revealed";
  choice: string | null;
  note: string | null;
}

interface SessionState {
  status: Status;
  user: { id: string; name: string } | null;
  couple: { id: string; joinCode: string } | null;
  members: Member[];
  viewer: string;
  records: InsightRecord[];
  reflections: Reflection[];
  busy: boolean;
  error: string | null;
  info: string | null;
  announcement: string;

  init: () => Promise<void>;
  signIn: (email: string, password: string) => Promise<void>;
  signUp: (email: string, password: string, name: string) => Promise<void>;
  signOut: () => Promise<void>;
  createCouple: () => Promise<void>;
  joinCouple: (code: string) => Promise<void>;
  load: () => Promise<void>;

  request: (id: string) => Promise<void>;
  accept: (id: string) => Promise<void>;
  decline: (id: string) => Promise<void>;
  withdraw: (id: string) => Promise<void>;
  submit: (id: string, choice: string, note?: string) => Promise<void>;
  settle: (id: string, type: "settled" | "released" | "leftOpen", choice?: string) => Promise<void>;
  dismiss: (id: string) => Promise<void>;

  memberById: (id?: string | null) => Member | undefined;
  partnerId: () => string | undefined;
}

let realtimeBound = false;

export const useSession = create<SessionState>((set, get) => ({
  status: "loading",
  user: null,
  couple: null,
  members: [],
  viewer: "",
  records: [],
  reflections: [],
  busy: false,
  error: null,
  info: null,
  announcement: "",

  memberById: (id) => (id ? get().members.find((m) => m.id === id) : undefined),
  partnerId: () => {
    const { members, viewer } = get();
    return members.find((m) => m.id !== viewer)?.id;
  },

  init: async () => {
    if (!supabaseConfigured) {
      set({ status: "unconfigured" });
      return;
    }
    const { data } = await supabase.auth.getSession();
    if (!data.session) {
      set({ status: "signedOut" });
    } else {
      await get().load();
    }
    supabase.auth.onAuthStateChange((_event, session) => {
      if (!session) {
        set({ status: "signedOut", user: null, couple: null, members: [], records: [], reflections: [] });
      }
    });
  },

  signIn: async (email, password) => {
    set({ busy: true, error: null, info: null });
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    if (error) return set({ busy: false, error: error.message });
    await get().load();
    set({ busy: false });
  },

  signUp: async (email, password, name) => {
    set({ busy: true, error: null, info: null });
    const { data, error } = await supabase.auth.signUp({
      email: email.trim(),
      password,
      options: { data: { name: name.trim() } },
    });
    if (error) return set({ busy: false, error: error.message });
    if (!data.session) {
      // Email confirmation is on for this project — no session yet.
      return set({
        busy: false,
        info: "Check your email to confirm, then sign in.",
      });
    }
    await get().load();
    set({ busy: false });
  },

  signOut: async () => {
    await supabase.auth.signOut();
    set({ status: "signedOut", user: null, couple: null, members: [], records: [], reflections: [] });
  },

  createCouple: async () => {
    set({ busy: true, error: null });
    const { error } = await supabase.rpc("create_couple");
    if (error) return set({ busy: false, error: error.message });
    await get().load();
    set({ busy: false, announcement: "Your shared space is ready." });
  },

  joinCouple: async (code) => {
    set({ busy: true, error: null });
    const { error } = await supabase.rpc("join_couple", { p_code: code.trim() });
    if (error) return set({ busy: false, error: error.message });
    await get().load();
    set({ busy: false, announcement: "You're in. This is yours together now." });
  },

  load: async () => {
    const { data: auth } = await supabase.auth.getUser();
    const u = auth.user;
    if (!u) return set({ status: "signedOut" });

    const { data: profile } = await supabase.from("profiles").select("id,name").eq("id", u.id).maybeSingle();
    const user = { id: u.id, name: profile?.name ?? "You" };

    const { data: myMembership } = await supabase
      .from("couple_members")
      .select("couple_id")
      .eq("profile_id", u.id)
      .maybeSingle();

    if (!myMembership) {
      return set({ status: "needsCouple", user, viewer: u.id, couple: null, members: [], records: [], reflections: [] });
    }

    const coupleId = myMembership.couple_id as string;

    const [coupleRes, membersRes, insightsRes, consentRes, responsesRes, dismissalsRes, reflectionsRes] =
      await Promise.all([
        supabase.from("couples").select("id,join_code").eq("id", coupleId).maybeSingle(),
        supabase.from("couple_members").select("profile_id,hue,profiles(name)").eq("couple_id", coupleId),
        supabase.from("insights").select("*").eq("couple_id", coupleId).order("sort"),
        supabase.from("insight_consent").select("*"),
        supabase.from("responses").select("*"),
        supabase.from("dismissals").select("*"),
        supabase.from("reflections").select("*").eq("owner_id", u.id),
      ]);

    const members: Member[] = (membersRes.data ?? []).map((m) => {
      // profiles may come back as an object or single-element array depending on the join.
      const p = m.profiles as unknown as { name?: string } | { name?: string }[] | null;
      const name = Array.isArray(p) ? p[0]?.name : p?.name;
      return { id: m.profile_id as string, hue: m.hue as Member["hue"], name: name ?? "Partner" };
    });
    const partnerId = members.find((m) => m.id !== u.id)?.id;

    const consentByInsight = new Map<string, DbConsent>();
    (consentRes.data as DbConsent[] | null)?.forEach((c) => consentByInsight.set(c.insight_id, c));

    const responsesByInsight = new Map<string, DbResponse[]>();
    (responsesRes.data as DbResponse[] | null)?.forEach((r) => {
      const arr = responsesByInsight.get(r.insight_id) ?? [];
      arr.push(r);
      responsesByInsight.set(r.insight_id, arr);
    });

    const dismissedSet = new Set<string>();
    (dismissalsRes.data as { insight_id: string }[] | null)?.forEach((d) => dismissedSet.add(d.insight_id));

    const records: InsightRecord[] = (insightsRes.data ?? []).map((i) => {
      const c = consentByInsight.get(i.id);
      const rows = responsesByInsight.get(i.id) ?? [];
      const mkResp = (pid?: string): PersonResponse => {
        const row = rows.find((r) => r.profile_id === pid);
        return row
          ? { status: row.status, choice: row.choice ?? undefined, note: row.note ?? undefined }
          : { status: "none" };
      };
      const responses: Record<string, PersonResponse> = { [u.id]: mkResp(u.id) };
      if (partnerId) responses[partnerId] = mkResp(partnerId);

      const state: InsightState = {
        visibility: c?.visibility ?? "shared",
        owner: c?.owner_id ?? undefined,
        readiness: c?.readiness ?? "idle",
        initiator: c?.initiator_id ?? undefined,
        requestedAt: c?.requested_at ? Date.parse(c.requested_at) : undefined,
        acceptedAt: c?.accepted_at ? Date.parse(c.accepted_at) : undefined,
        responses,
        dismissedBy: dismissedSet.has(i.id) ? [u.id] : [],
        resolution: c?.resolution_type
          ? { type: c.resolution_type, choice: c.resolution_choice ?? undefined, at: 0 }
          : undefined,
      };

      return {
        insight: {
          id: i.id,
          kind: i.kind,
          domain: i.domain,
          present: i.present,
          title: i.title,
          body: i.body,
          evidence: i.evidence,
          source: i.source,
          options: i.options,
        },
        state,
      };
    });

    const reflections: Reflection[] = (reflectionsRes.data ?? []).map((r) => ({
      id: r.id,
      owner: r.owner_id,
      domain: r.domain,
      kind: r.kind,
      text: r.text,
    }));

    set({
      status: "ready",
      user,
      viewer: u.id,
      couple: coupleRes.data ? { id: coupleRes.data.id, joinCode: coupleRes.data.join_code } : null,
      members,
      records,
      reflections,
    });

    // Bind realtime once: any change in the couple's shared tables triggers a reload.
    if (!realtimeBound) {
      realtimeBound = true;
      supabase
        .channel("we-couple")
        .on("postgres_changes", { event: "*", schema: "public", table: "insight_consent" }, () => get().load())
        .on("postgres_changes", { event: "*", schema: "public", table: "responses" }, () => get().load())
        .on("postgres_changes", { event: "*", schema: "public", table: "couple_members" }, () => get().load())
        .subscribe();
    }
  },

  request: async (id) => runRpc(set, get, "request_reveal", { p_insight: id }, "Brought to your partner. Waiting, without pressure."),
  accept: async (id) => runRpc(set, get, "accept_reveal", { p_insight: id }, "Opened together. This now lives between you."),
  decline: async (id) => runRpc(set, get, "decline_reveal", { p_insight: id }, "Held for later. Your partner won't be notified."),
  withdraw: async (id) => runRpc(set, get, "withdraw_reveal", { p_insight: id }, "Withdrawn. No record remains."),
  submit: async (id, choice, note) =>
    runRpc(set, get, "submit_response", { p_insight: id, p_choice: choice, p_note: note ?? null }, "Your answer is in."),
  settle: async (id, type, choice) =>
    runRpc(set, get, "resolve_insight", { p_insight: id, p_type: type, p_choice: choice ?? null },
      type === "leftOpen" ? "Left open. Nothing has been decided." : "Settled together."),
  dismiss: async (id) => runRpc(set, get, "dismiss_suggestion", { p_insight: id }, "Set aside, just for you."),
}));

async function runRpc(
  set: (partial: Partial<SessionState>) => void,
  get: () => SessionState,
  fn: string,
  args: Record<string, unknown>,
  announce: string
) {
  set({ error: null });
  const { error } = await supabase.rpc(fn, args);
  if (error) {
    set({ error: error.message });
    return;
  }
  set({ announcement: announce });
  await get().load();
}
