// app.js – мини SPA (hash router) + UI логика
import {
  supa, onAuthChanged, session, signOut,
  signUp, signInUserOrEmail, myProfile,
  listApprovedDogs, listPendingDogs, createDog,
  approveDog, rejectDog
} from "./api.js";

// ===== NAV / AUTH STATE =====
const els = {
  views: {
    home: document.getElementById("view-home"),
    catalog: document.getElementById("view-catalog"),
    admin: document.getElementById("view-admin"),
  },
  nav: {
    btnLogin: document.getElementById("btn-login"),
    btnRegister: document.getElementById("btn-register"),
    btnLogout: document.getElementById("btn-logout"),
    meName: document.getElementById("me-name"),
  },
  modals: {
    login: document.getElementById("dlg-login"),
    register: document.getElementById("dlg-register"),
  },
  forms: {
    login: document.getElementById("login-form"),
    register: document.getElementById("register-form"),
    newDog: document.getElementById("form-new-dog"),
  },
  catalogList: document.getElementById("catalog-list"),
  pendingList: document.getElementById("pending-list"),
  newDogMsg: document.getElementById("new-dog-msg"),
};

let currentProfile = null;

// показва/скрива елементи по атрибут
function applyAuthVisibility(signed) {
  document.querySelectorAll("[data-if-logged-in]").forEach(n => n.hidden = !signed);
  document.querySelectorAll("[data-if-logged-out]").forEach(n => n.hidden = !!signed);
}
function applyAdminVisibility(isAdmin) {
  document.querySelectorAll("[data-if-admin]").forEach(n => n.hidden = !isAdmin);
}

async function refreshAuthUI() {
  const s = await session();
  const signed = !!s;
  applyAuthVisibility(signed);
  if (!signed) {
    currentProfile = null;
    els.nav.meName.textContent = "";
    applyAdminVisibility(false);
    return;
  }
  // вземи профила (роль)
  currentProfile = await myProfile();
  els.nav.meName.textContent = currentProfile?.display_name || currentProfile?.email || "Потребител";
  applyAdminVisibility(currentProfile?.role === "admin");
}

// ===== ROUTER =====
const routes = {
  "/": async () => {
    show("home");
  },
  "/catalog": async () => {
    show("catalog");
    await renderCatalog();
  },
  "/admin": async () => {
    // гард
    await refreshAuthUI();
    if (currentProfile?.role !== "admin") {
      location.hash = "/"; return;
    }
    show("admin");
    await renderPending();
  },
};

function show(name) {
  for (const k of Object.keys(els.views)) els.views[k].hidden = (k !== name);
}

function handleRoute() {
  const hash = location.hash.replace(/^#/, "") || "/";
  const route = routes[hash] || routes["/"];
  route().catch(console.error);
}
window.addEventListener("hashchange", handleRoute);

// ===== RENDER =====
async function renderCatalog() {
  els.catalogList.innerHTML = "Зареждане…";
  const rows = await listApprovedDogs();
  if (!rows.length) { els.catalogList.innerHTML = "<p class='muted'>Няма одобрени записи.</p>"; return; }
  els.catalogList.innerHTML = rows.map(r => CardDog(r, false)).join("");
}
async function renderPending() {
  els.pendingList.innerHTML = "Зареждане…";
  const rows = await listPendingDogs();
  if (!rows.length) { els.pendingList.innerHTML = "<p class='muted'>Няма чакащи.</p>"; return; }
  els.pendingList.innerHTML = rows.map(r => CardDog(r, true)).join("");
  // вържи бутони
  els.pendingList.querySelectorAll("[data-approve]").forEach(b=>{
    b.addEventListener("click", async ()=>{
      await approveDog(b.dataset.id); await renderPending();
    });
  });
  els.pendingList.querySelectorAll("[data-reject]").forEach(b=>{
    b.addEventListener("click", async ()=>{
      await rejectDog(b.dataset.id); await renderPending();
    });
  });
}

function CardDog(r, admin=false){
  const meta = [
    r.sex==='male'?'♂ мъжко':'♀ женско',
    r.date_of_birth ? `р. ${r.date_of_birth}` : '',
    r.color || ''
  ].filter(Boolean).join(" • ");
  const owner = r.owner_name || r.owner_full || r.owner_email || "";
  const adminBtns = admin ? `
    <div class="right" style="gap:8px;">
      <button class="btn" data-approve data-id="${r.id}">Одобри</button>
      <button class="btn ghost" data-reject data-id="${r.id}">Откажи</button>
    </div>` : "";
  return `
  <div class="card-item">
    <h3>${escapeHtml(r.name)}</h3>
    <div class="meta">${escapeHtml(meta)}</div>
    ${owner ? `<div class="meta">собственик: ${escapeHtml(owner)}</div>` : ""}
    ${r.microchip_number ? `<div class="meta">микрочип: ${escapeHtml(r.microchip_number)}</div>` : ""}
    ${r.pedigree_number ? `<div class="meta">родословие: ${escapeHtml(r.pedigree_number)}</div>` : ""}
    ${adminBtns}
  </div>`;
}
function escapeHtml(s){ return String(s??"").replace(/[&<>"]/g, m=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;" }[m])) }

// ===== FORMS / MODALS =====
document.getElementById("cta-new")?.addEventListener("click", ()=>{
  els.forms.newDog.hidden = !els.forms.newDog.hidden;
});

els.nav.btnLogin.addEventListener("click", ()=> els.modals.login.showModal());
els.nav.btnRegister.addEventListener("click", ()=> els.modals.register.showModal());
els.nav.btnLogout.addEventListener("click", async ()=> { await signOut(); });

els.forms.login.addEventListener("submit", async (e)=>{
  e.preventDefault();
  const fd = new FormData(els.forms.login);
  const user = fd.get("user")?.trim();
  const password = fd.get("password")?.trim();
  setMsg("login-msg", "", true);
  try{
    await signInUserOrEmail({ userOrEmail:user, password });
    els.modals.login.close();
    await refreshAuthUI();
  }catch(err){ setMsg("login-msg", err.message||"Грешка при вход.", false); }
});

els.forms.register.addEventListener("submit", async (e)=>{
  e.preventDefault();
  const fd = new FormData(els.forms.register);
  const payload = {
    display_name: fd.get("display_name")?.trim(),
    username: fd.get("username")?.trim(),
    email: fd.get("email")?.trim(),
    password: fd.get("password")?.trim(),
  };
  setMsg("register-msg", "", true);
  try{
    await signUp(payload);
    setMsg("register-msg", "Създаден е акаунт. Влез с потребителско име или email.", true, true);
  }catch(err){ setMsg("register-msg", err.message||"Грешка при регистрация.", false); }
});

els.forms.newDog.addEventListener("submit", async (e)=>{
  e.preventDefault();
  const fd = new FormData(els.forms.newDog);
  const payload = {
    name: fd.get("name")?.trim(),
    sex: fd.get("sex"),
    date_of_birth: fd.get("date_of_birth"),
    color: fd.get("color")?.trim() || null,
    microchip_number: fd.get("microchip_number")?.trim() || null,
    pedigree_number: fd.get("pedigree_number")?.trim() || null,
    notes: fd.get("notes")?.trim() || null,
    status: "pending"
  };
  try{
    await createDog(payload);
    els.forms.newDog.reset();
    setMsg(els.newDogMsg, "Записът е изпратен за одобрение.", true, true);
  }catch(err){
    setMsg(els.newDogMsg, err.message||"Грешка при изпращане.", false);
  }
});

function setMsg(target, text, ok=true, show=false){
  const el = typeof target==="string" ? document.getElementById(target) : target;
  el.hidden = !text && !show;
  el.textContent = text;
  el.className = "msg " + (ok?"ok":"err");
}

// ===== BOOT =====
onAuthChanged(async ()=>{ await refreshAuthUI(); handleRoute(); });
await refreshAuthUI();
handleRoute();
