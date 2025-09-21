// api.js – Supabase client + удобни функции

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = "https://tnfefayxaxtailuvdjkg.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRuZmVmYXl4YXh0YWlsdXZkamtnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTgzNjk2MzIsImV4cCI6MjA3Mzk0NTYzMn0.LCuZIIRHKiMCZpRsiUx1YPnkqjYeNJn9tzMRB0R4evo";

export const supa = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// === Auth ===
export async function session() {
  const { data } = await supa.auth.getSession();
  return data.session ?? null;
}
export async function onAuthChanged(cb) {
  supa.auth.onAuthStateChange((_e, s) => cb(s ?? null));
}
export async function signOut() {
  await supa.auth.signOut();
}

export async function signUp({ email, password, username, display_name }) {
  // auth.users ще се създаде; тригерът 0002_profiles_autocreate прави public.profiles
  const { error } = await supa.auth.signUp({
    email, password,
    options: { data: { username, display_name } }
  });
  if (error) throw error;
}

export async function signInUserOrEmail({ userOrEmail, password }) {
  // ако е username – намираме email от profiles
  let email = userOrEmail;
  if (!userOrEmail.includes("@")) {
    const { data, error } = await supa
      .from("profiles")
      .select("email")
      .eq("username", userOrEmail)
      .single();
    if (error || !data) throw new Error("Потребител не е намерен.");
    email = data.email;
  }
  const { error } = await supa.auth.signInWithPassword({ email, password });
  if (error) throw error;
}

// === Profiles ===
export async function myProfile() {
  const { data: { user } } = await supa.auth.getUser();
  if (!user) return null;
  const { data } = await supa.from("profiles").select("*").eq("id", user.id).single();
  return data ?? null;
}

// === Dogs ===
export async function listApprovedDogs() {
  const { data, error } = await supa
    .from("dogs_with_owner") // в 0001 е създаден view; ако не – смени на 'dogs' и направи select нужните полета
    .select("*")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data ?? [];
}

export async function listPendingDogs() {
  const { data, error } = await supa
    .from("dogs")
    .select("*")
    .eq("status", "pending")
    .order("created_at", { ascending: true });
  if (error) throw error;
  return data ?? [];
}

export async function createDog(payload) {
  const { error } = await supa.from("dogs").insert(payload);
  if (error) throw error;
}

export async function approveDog(id) {
  const { error } = await supa.from("dogs").update({ status: "approved" }).eq("id", id);
  if (error) throw error;
}
export async function rejectDog(id) {
  const { error } = await supa.from("dogs").update({ status: "rejected" }).eq("id", id);
  if (error) throw error;
}
