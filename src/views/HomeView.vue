<script setup>
import '@/assets/home.css'
import { ref, reactive, computed, watch, onMounted, onBeforeUnmount } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import SideNavSB from '@/components/SideNavSB.vue'
import { useMetamask } from '@/composables/useMetamask'

const route = useRoute()
const r = useRouter()

const sidebarOpen = ref(false)
const toggleSidebar = () => (sidebarOpen.value = !sidebarOpen.value)
watch(() => route.fullPath, () => (sidebarOpen.value = false))

const { account } = useMetamask()
const rootStyle = computed(() => ({ '--hero-img': 'url(/Background.png)' }))

const RAW_BASE = (import.meta.env.VITE_API_BASE || 'http://localhost:3001').replace(/\/+$/, '')
const API_HOST = RAW_BASE.replace(/\/api$/i, '')
const getWallet = () => (account.value || localStorage.getItem('walletAddress') || '').toString()

function withWalletParam(url) {
  const w = getWallet()
  if (!w) return url
  return url + (url.includes('?') ? '&' : '?') + 'wallet=' + encodeURIComponent(w)
}

async function api(path, options = {}) {
  const full = path.startsWith('/api') ? path : `/api${path.startsWith('/') ? path : `/${path}`}`
  const method = String(options?.method || 'GET').toUpperCase()
  let url = `${API_HOST}${full}`
  if (method === 'GET') url = withWalletParam(url)
  const res = await fetch(url, {
    ...options,
    headers: {
      'content-type': 'application/json',
      ...(options.headers || {}),
      'x-wallet-address': getWallet()
    }
  })
  const data = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`)
  return data
}

async function uploadImageFile(file) {
  const fd = new FormData()
  fd.append('file', file)
  const res = await fetch(`${API_HOST}/api/upload`, {
    method: 'POST',
    headers: { 'x-wallet-address': getWallet() },
    body: fd
  })
  const data = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`)
  if (!data?.url || !/^https?:\/\//i.test(data.url)) throw new Error('Upload gagal: URL tidak valid')
  return data.url
}

const role = ref('user')
const isAdmin = computed(() => role.value === 'admin')
const heroTitle = computed(() => (isAdmin.value ? 'CREATE A NEW EVENT' : 'UPCOMING CONCERT'))

async function hydrateAccount() {
  if (!account.value && window?.ethereum) {
    try {
      const accs = await window.ethereum.request({ method: 'eth_accounts' })
      if (accs?.[0]) account.value = accs[0]
    } catch {}
  }
}

async function loadRole() {
  const w = getWallet()
  if (!w) { role.value = 'user'; return }
  try {
    const me = await api('/api/me')
    role.value = me?.role === 'admin' ? 'admin' : 'user'
  } catch {
    role.value = 'user'
  }
}

const loading = ref(false)
const errorMsg = ref('')
const events = ref([])

async function loadEvents() {
  loading.value = true; errorMsg.value = ''
  try {
    const qs = isAdmin.value ? '?all=1' : ''
    const res = await api(`/api/events${qs}`)
    events.value = Array.isArray(res?.items) ? res.items : []
  } catch (e) {
    errorMsg.value = String(e.message || e)
  } finally {
    loading.value = false
  }
}

function onAccountsChanged(accs) {
  account.value = accs?.[0] || ''
  loadRole(); loadEvents()
}
onMounted(async () => {
  await hydrateAccount()
  if (window?.ethereum?.on) window.ethereum.on('accountsChanged', onAccountsChanged)
  await loadRole()
  await loadEvents()
})
onBeforeUnmount(() => {
  if (window?.ethereum?.removeListener) window.ethereum.removeListener('accountsChanged', onAccountsChanged)
})
watch(account, async () => { await loadRole(); await loadEvents() })

const searchQuery = ref('')
const filteredEvents = computed(() => {
  const q = searchQuery.value.trim().toLowerCase()
  if (!q) return events.value
  return events.value.filter(ev =>
    [ev.title, ev.venue, ev.description].some(s => String(s || '').toLowerCase().includes(q))
  )
})

function buyTicket(ev) {
  r.push({ name: 'event', params: { id: ev.id } })
}

const showCreate = ref(false)
const showEdit = ref(false)

const newEvent = reactive({
  title: '', date_iso: '', venue: '', description: '',
  image_url: '', price_pol: 0, total_tickets: 0, listed: true
})
const newImageFile = ref(null)
const newImagePreview = ref('')
const uploading = ref(false)

function onNewImageChange(e) {
  const f = e?.target?.files?.[0]
  newImageFile.value = f || null
  if (newImagePreview.value) URL.revokeObjectURL(newImagePreview.value)
  newImagePreview.value = f ? URL.createObjectURL(f) : ''
}

function toIso(dtLocal) {
  if (!dtLocal) return ''
  const d = new Date(dtLocal)
  if (Number.isNaN(d.getTime())) throw new Error('Tanggal tidak valid')
  return d.toISOString()
}

async function createEvent() {
  try {
    if (!newEvent.title || !newEvent.date_iso || !newEvent.venue) throw new Error('Title/Date/Venue wajib')
    if (newImageFile.value && !newEvent.image_url) {
      uploading.value = true
      const url = await uploadImageFile(newImageFile.value)
      newEvent.image_url = url
    }
    const payload = {
      title: newEvent.title,
      date_iso: toIso(newEvent.date_iso),
      venue: newEvent.venue,
      description: newEvent.description || '',
      image_url: newEvent.image_url || null,
      price_pol: Number(newEvent.price_pol) || 0,
      total_tickets: Number(newEvent.total_tickets) || 0,
      listed: !!newEvent.listed
    }
    await api('/api/events', { method: 'POST', body: JSON.stringify(payload) })
    Object.assign(newEvent, { title: '', date_iso: '', venue: '', description: '', image_url: '', price_pol: 0, total_tickets: 0, listed: true })
    newImageFile.value = null
    if (newImagePreview.value) { URL.revokeObjectURL(newImagePreview.value); newImagePreview.value = '' }
    showCreate.value = false
    await loadEvents()
    alert('Event created.')
  } catch (e) {
    alert(`Create failed: ${e.message}`)
  } finally {
    uploading.value = false
  }
}

const editId = ref(null)
const edit = reactive({
  title: '', date_iso: '', venue: '', description: '',
  image_url: '', price_pol: 0, total_tickets: 0, listed: true
})

function startEdit(ev) {
  editId.value = ev.id
  edit.title = ev.title || ''
  try {
    const d = new Date(ev.date_iso)
    const p = n => String(n).padStart(2, '0')
    edit.date_iso = `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`
  } catch { edit.date_iso = '' }
  edit.venue = ev.venue || ''
  edit.description = ev.description || ''
  edit.image_url = ev.image_url || ''
  edit.price_pol = Number(ev.price_pol || 0)
  edit.total_tickets = Number(ev.total_tickets || 0)
  edit.listed = !!ev.listed
  showEdit.value = true
}
function cancelEdit() { showEdit.value = false; editId.value = null }

async function saveEdit() {
  try {
    const payload = {
      title: edit.title,
      date_iso: toIso(edit.date_iso),
      venue: edit.venue,
      description: edit.description,
      image_url: edit.image_url || null,
      price_pol: Number(edit.price_pol) || 0,
      total_tickets: Number(edit.total_tickets) || 0,
      listed: !!edit.listed
    }
    await api(`/api/events/${editId.value}`, { method: 'PUT', body: JSON.stringify(payload) })
    showEdit.value = false
    editId.value = null
    await loadEvents()
    alert('Event updated.')
  } catch (e) { alert(`Update failed: ${e.message}`) }
}

async function removeEvent(id) {
  if (!confirm('Delete this event?')) return
  try { await api(`/api/events/${id}`, { method: 'DELETE' }); await loadEvents(); alert('Deleted.') }
  catch (e) { alert(`Delete failed: ${e.message}`) }
}

async function toggleList(ev) {
  try { await api(`/api/events/${ev.id}/list`, { method: 'PATCH', body: JSON.stringify({ listed: !ev.listed }) }); await loadEvents() }
  catch (e) { alert(`List/Delist failed: ${e.message}`) }
}

function imgFor(ev) {
  return ev.image_url || (ev.title?.toLowerCase().includes('feast') ? imgFeast :
    ev.title?.toLowerCase().includes('sheila') ? imgSO7 : imgGigi)
}
</script>

<template>
  <div class="home-page" :style="rootStyle">
    <header class="topbar">
      <div class="brand"><img src="/logo_with_text.png" alt="Tickety" /></div>
      <form class="search search--top" @submit.prevent>
        <input class="search-input" v-model="searchQuery" type="search" placeholder="Search concerts, venues…" />
        <button class="search-btn" type="submit">🔍</button>
      </form>
      <button class="hamburger" @click.stop="toggleSidebar" aria-label="Toggle Sidebar"><span/><span/><span/></button>
    </header>

    <SideNavSB v-model="sidebarOpen" />

    <main class="container">
      <section class="hero">
        <div class="hero-bg" aria-hidden="true"></div>
        <h2 class="hero-title">{{ heroTitle }}</h2>
      </section>

      <div v-if="errorMsg" class="alert error">{{ errorMsg }}</div>

      <section class="cards">
        <article v-for="ev in filteredEvents" :key="ev.id" class="card">
          <div class="img-wrap">
            <div class="img" :style="{ backgroundImage: `url(${imgFor(ev)})` }"></div>
            <div class="img-overlay"></div>
            <div class="title">{{ ev.title }}</div>
            <div v-if="isAdmin" class="adm-tools">
              <button class="adm-btn" @click="startEdit(ev)" title="Edit">✎</button>
              <button class="adm-btn" @click="toggleList(ev)" :title="ev.listed ? 'Delist' : 'List'">
                {{ ev.listed ? '⛔' : '✅' }}
              </button>
              <button class="adm-btn danger" @click="removeEvent(ev.id)" title="Delete">🗑</button>
            </div>
          </div>
          <div class="meta">
            <div><span class="k">Location:</span> <span class="v">{{ ev.venue }}</span></div>
            <div><span class="k">Date:</span> <span class="v">{{ new Date(ev.date_iso).toLocaleString('id-ID') }}</span></div>
          </div>
          <p class="desc">{{ ev.description || '(Blank Text)' }}</p>
          <button class="buy" @click="buyTicket(ev)">BUY TICKET</button>
        </article>
      </section>
    </main>

    <button v-if="isAdmin" class="fab" title="Add event" aria-label="Create new event" @click="showCreate = true">＋<span class="sr-only">Create new event</span></button>

    <div v-if="showCreate" class="modal" @click.self="showCreate=false">
      <div class="modal-card">
        <button class="modal-x" aria-label="Close" @click="showCreate=false">×</button>
        <h3>Create Event</h3>
        <form class="form" @submit.prevent="createEvent">
          <div class="scroll">
            <label>Title <input v-model="newEvent.title" /></label>
            <label>Date (UTC) <input type="datetime-local" step="60" v-model="newEvent.date_iso" /></label>
            <label>Venue <input v-model="newEvent.venue" /></label>
            <label class="file"><span>Image</span><input type="file" accept="image/*" @change="onNewImageChange" /></label>
            <div v-if="newImagePreview || newEvent.image_url" class="img-preview" :style="{ backgroundImage: `url(${newImagePreview || newEvent.image_url})` }"></div>
            <label>Price (POL) <input type="number" min="0" step="0.0001" v-model.number="newEvent.price_pol" /></label>
            <label>Total Tickets <input type="number" min="0" step="1" v-model.number="newEvent.total_tickets" /></label>
            <label class="chk"><input type="checkbox" v-model="newEvent.listed" /> Listed</label>
            <label>Description <textarea rows="3" v-model="newEvent.description" /></label>
          </div>
          <div class="actions-bar">
            <button type="button" class="btn ghost" @click="showCreate=false">Cancel</button>
            <button type="submit" class="btn primary" :disabled="uploading">{{ uploading ? 'Uploading…' : 'Create' }}</button>
          </div>
        </form>
      </div>
    </div>

    <div v-if="showEdit" class="modal" @click.self="cancelEdit()">
      <div class="modal-card">
        <button class="modal-x" aria-label="Close" @click="cancelEdit()">×</button>
        <h3>Edit Event</h3>
        <form class="form" @submit.prevent="saveEdit">
          <div class="scroll">
            <label>Title <input v-model="edit.title" /></label>
            <label>Date (UTC) <input type="datetime-local" step="60" v-model="edit.date_iso" /></label>
            <label>Venue <input v-model="edit.venue" /></label>
            <label>Image URL <input v-model="edit.image_url" placeholder="https://..." /></label>
            <label>Price (POL) <input type="number" min="0" step="0.0001" v-model.number="edit.price_pol" /></label>
            <label>Total Tickets <input type="number" min="0" step="1" v-model.number="edit.total_tickets" /></label>
            <label class="chk"><input type="checkbox" v-model="edit.listed" /> Listed</label>
            <label>Description <textarea rows="3" v-model="edit.description" /></label>
          </div>
          <div class="actions-bar">
            <button type="button" class="btn ghost" @click="cancelEdit()">Cancel</button>
            <button type="submit" class="btn primary">Save</button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>

<style scoped>
.fab{
  position: fixed;
  right: max(20px, env(safe-area-inset-right));
  bottom: max(20px, env(safe-area-inset-bottom));
  width: 64px; height: 64px;
  border-radius: 999px;
  border: 1px solid var(--border);
  background: #F4F1DE;
  color: #1f2937;
  font-weight: 900;
  font-size: 32px;
  line-height: 0;
  cursor: pointer;
  box-shadow: 0 16px 34px rgba(0,0,0,.36);
  display: inline-flex;
  align-items: center;
  justify-content: center;
  z-index: 1200;
}
.fab:hover{ transform: translateY(-1px); box-shadow: 0 20px 40px rgba(0,0,0,.38) }
.fab:active{ transform: translateY(0);  box-shadow: 0 12px 28px rgba(0,0,0,.28) }

.sr-only{
  position: absolute; width:1px; height:1px; padding:0; margin:-1px;
  overflow:hidden; clip:rect(0,0,1,1); white-space:nowrap; border:0;
}

.adm-tools{   position:absolute; right:10px; top:10px; z-index:3; display:flex; gap:6px;}
.adm-btn{ background:rgba(0,0,0,.5); border:1px solid rgba(255,255,255,.18); color:#fff; border-radius:8px; padding:6px 8px; font-weight:700; cursor:pointer; }
.adm-btn.danger{ background:rgba(120,0,0,.6); border-color:rgba(255,255,255,.18); }

.modal{
  position: fixed; inset: 0; background: rgba(0,0,0,.45);
  z-index: 1400; display:grid; place-items:center; padding:16px;
  overflow: hidden;
}
.modal-card{
  position: relative;
  width: 100%; max-width: 560px;
  background:#F4F1DE; color:#232747;
  border: 1px solid #232747; border-radius: 14px; padding: 16px 16px 0;
  box-shadow: 0 18px 40px rgba(0,0,0,.45);
  display: flex; flex-direction: column;
  max-height: 86vh;
  overflow: hidden;
}
.modal-card h3{ margin: 0 0 10px; font-weight: 800; color:#232747 }
.modal-x{
  position: absolute; top: 10px; right: 10px;
  width: 36px; height: 36px; border-radius: 10px;
  border: 1px solid #232747; background: #232747; color:#F4F1DE;
  font-size: 22px; line-height: 0; cursor: pointer;
}

.form{ display:flex; flex-direction:column; flex:1 1 auto; min-height:0 }
.scroll{
  flex: 1 1 auto; min-height: 0;
  overflow: auto; padding-right: 4px;
  padding-bottom: 96px;
}
.form label{ display:grid; gap:6px; font-size: 14px; margin-bottom:10px; color:#232747 }
.form input, .form textarea{
  background:#ffffff; color:#232747; border:1px solid #232747;
  border-radius:10px; padding:10px 12px; outline:none;
}
.form label.file input[type="file"]{
  padding:10px; background:#ffffff; color:#232747; border:1px dashed #232747; border-radius:10px;
}
.img-preview{
  width:100%; height:180px; background-size:cover; background-position:center; border-radius:12px; border:1px solid #232747; margin-bottom:10px
}
.form .chk{ display:flex; align-items:center; gap:10px; color:#232747 }

.actions-bar{
  position: absolute; left: 0; right: 0; bottom: 0;
  display:flex; justify-content:flex-end; gap:10px;
  padding:12px 16px 14px;
  background:#F4F1DE;
  border-top: 1px solid #232747;
  z-index: 10;
}
.btn{ padding:10px 14px; border-radius: 10px; border:1px solid transparent; cursor:pointer }
.btn.ghost{ background:#F4F1DE; color:#232747; border:1px solid #232747 }
.btn.primary{ background:#232747; color:#F4F1DE; border:1px solid #232747 }

.cards{ display:grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap:24px; align-items: start;}
.card{ border:1px solid #2a3342; border-radius:18px; background:#6B0A00; overflow:hidden; display:flex; flex-direction:column; box-shadow: 0 16px 34 px rgba(0,0,0,.35); transition:transform .18s ease, box-shadow .18s ease;}
.card:hover{transform:translateY(-2px); box-shadow:0 22px 46px rgba(0,0,0,.45);}
.img-wrap{ position:relative; height:220px; overflow:hidden; isolation:isolate;}
.img{ position:absolute; inset:0; background-size:cover; background-position:center; transform: scale(1.02); }
.img::after{ content:""; position:absolute; inset:0; background: linear-gradient( 180deg, rgba(0,0,0,0) 40%, rgba(124,12,20,.65) 75%, rgba(124,12,20,.85) 100% );  z-index:1; }
.img-overlay{ position:absolute; inset:0; background: linear-gradient( 180deg, rgba(0,0,0,0) 0%, rgba(107,10,0,0.15) 25%, rgba(107,10,0,0.5) 60%, rgba(107,10,0,0.75) 100%
  ); z-index:1; }
.title{ position:absolute; left:50%; transform:translateX(-50%); bottom:16px; z-index:2; font-weight:900; font-size:20px; letter-spacing:.15em; text-transform:uppercase; color:#fff; text-shadow:0 2px 6px rgba(0,0,0,.6); }
.meta{ display:grid; gap:8px; padding:14px 16px 8px; font-size:14px; color:#e6e8ef; }
.meta .k{ font-weight:700; color:#f0b35a; margin-right:6px; }
.meta .v{ opacity:.95; }
.desc{ padding:0 16px 14px; font-size:13px; line-height:1.35; color:#cbd5e1; }
.buy{ margin:0 16px 18px; width:fit-content; padding:8px 12px; border-radius:6px; border:1px solid #49361a; background:#f0dcb8; color:#281c06; font-weight:900; font-size:13px; cursor:pointer; }
.buy:hover{ filter:brightness(.96); }
.img-gradient{ display:none !important; }

.home-page{ --topbar-h:64px }
.hero{
  position: relative;
  min-height: calc(100vh - var(--topbar-h));
  display: grid !important;
  place-items: center !important;
  margin-left: calc(50% - 50vw);
  margin-right: calc(50% - 50vw);
  width: 100vw;
}
.hero::before{ content:none }
.hero-bg{
  position:absolute; inset:0;
  background:
    linear-gradient(180deg, rgba(12,14,18,.10) 0%, rgba(12,14,18,.35) 35%, rgba(12,14,18,.68) 78%, rgba(12,14,18,.88) 100%),
    radial-gradient(80% 55% at 50% 8%, rgba(255,166,72,.28) 0%, rgba(255,166,72,.12) 40%, rgba(0,0,0,0) 70%),
    radial-gradient(120% 85% at 50% 60%, rgba(0,0,0,0) 60%, rgba(0,0,0,.35) 82%, rgba(0,0,0,.60) 100%),
    var(--hero-img);
  background-size: cover;
  background-position: center top;
  filter: brightness(.95);
}
.hero-title{
  position: relative;
  z-index: 1;
  text-align: center;
  color: #f4f6fb;
  font-weight: 900;
  letter-spacing: .15em;
  font-size: clamp(24px, 5.6vw, 72px);
  line-height: 1.15;
  padding: 16px;
}
@media (max-width: 640px){
  .hero-title{ letter-spacing: .18em; font-size: clamp(22px, 6.2vw, 42px) }
}
</style>
