<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import SideNavSB from '@/components/SideNavSB.vue'

const route = useRoute()
const r = useRouter()

const sidebarOpen = ref(false)
const toggleSidebar = () => (sidebarOpen.value = !sidebarOpen.value)
watch(() => route.fullPath, () => (sidebarOpen.value = false))

const RAW_BASE = (import.meta.env.VITE_API_BASE || 'http://localhost:3001').replace(/\/+$/, '')
const API_HOST = RAW_BASE.replace(/\/api$/i, '')
const wallet = () => (localStorage.getItem('walletAddress') || '').toString()

async function api(path, options = {}) {
  const full = path.startsWith('/api') ? path : `/api${path.startsWith('/') ? path : `/${path}`}`
  const res = await fetch(`${API_HOST}${full}`, {
    ...options,
    headers: {
      'content-type': 'application/json',
      ...(options.headers || {}),
      'x-wallet-address': wallet()
    }
  })
  const data = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`)
  return data
}

const ev = ref(null)
const loading = ref(true)
const errorMsg = ref('')
const buying = ref(false)
const buyMsg = ref('')

async function buyTicket() {
  if (!ev.value) return
  if (!wallet()) {
    buyMsg.value = 'Wallet belum terhubung.'
    return
  }

  try {
    buying.value = true
    buyMsg.value = ''

    // panggil backend /purchase
    await api('/purchase', {
      method: 'POST',
      body: JSON.stringify({
        amount: Number(ev.value.price_pol || 0),
        ref_id: ev.value.id, // simpan id event sebagai referensi
        description: `Purchase ticket for ${ev.value.title || 'event'}`
      })
    })

    buyMsg.value = 'Tiket berhasil dibeli! Lihat di halaman History/Profile.'
  } catch (e) {
    buyMsg.value = `Gagal membeli tiket: ${e?.message || e}`
  } finally {
    buying.value = false
  }
}


const dateText = computed(() => {
  const d = ev.value?.date_iso ? new Date(ev.value.date_iso) : null
  if (!d) return '-'
  const ds = d.toLocaleDateString('id-ID', { day:'2-digit', month:'2-digit', year:'2-digit' })
  const ts = d.toLocaleTimeString('id-ID', { hour:'2-digit', minute:'2-digit', second:'2-digit' })
  return `${ds}, ${ts.replaceAll('.',':')}`.replace(/:/g,'.')
})

const priceText = computed(() => {
  const n = Number(ev.value?.price_pol || 0)
  return `${n.toLocaleString('en-US', { maximumFractionDigits: 6 })} POL`
})

const ticketsRemaining = computed(() => {
  if (!ev.value) return null
  const total = Number(ev.value.total_tickets ?? 0)
  const sold  = Number(ev.value.sold_tickets ?? 0)
  const remaining = total - sold
  if (!Number.isFinite(remaining) || remaining < 0) return 0
  return remaining
})

const isSoldOut = computed(() => {
  const total = Number(ev.value?.total_tickets ?? 0)
  return total > 0 && ticketsRemaining.value === 0
})

const heroBg = computed(() => `url(/Background.png)`)
const posterBg = computed(() => `url(${ev.value?.image_url || '/poster_fallback.jpg'})`)

function backToHome(){ r.push({ name: 'home' }) }

onMounted(async () => {
  try {
    loading.value = true
    const id = String(route.params.id || '')
    ev.value = await api(`/api/events/${id}`)
  } catch (e) {
    errorMsg.value = String(e.message || e)
  } finally {
    loading.value = false
  }
})
</script>

<template>
  <div class="event-page">
    <header class="topbar">
      <button class="back" @click="backToHome">← Back</button>
      <div class="brand"><img src="/logo_with_text.png" alt="Tickety" /></div>
      <h1 class="title">Event</h1>
      <button class="hamburger" aria-label="Toggle menu" @click="toggleSidebar"><span/><span/><span/></button>
    </header>

    <SideNavSB v-model="sidebarOpen" extraClass="sb-topright" />

    <main>
      <div v-if="errorMsg" class="alert error">{{ errorMsg }}</div>
      <div v-else-if="loading" class="loading">Loading…</div>

      <section v-else class="hero" :style="{ '--hero': heroBg }">
        <div class="hero-inner">
          <div class="poster">
            <div class="poster-img" :style="{ backgroundImage: posterBg }"></div>
            <div class="poster-grad"></div>
          </div>

          <div class="info">
            <h2 class="event-title">{{ ev.title }}</h2>
            <div class="meta">
              <div class="row"><span class="k">Location:</span><span class="v">{{ ev.venue }}</span></div>
              <div class="row"><span class="k">Date:</span><span class="v">{{ dateText }}</span></div>
            </div>
            <p class="desc">{{ ev.description || 'No description.' }}</p>
          </div>

          <aside class="pricebox">
            <div class="label">Price</div>
            <div class="price">{{ priceText }}</div>

            <div class="stock" v-if="ev.total_tickets > 0">
              <span v-if="!isSoldOut">Tickets left: {{ ticketsRemaining }}</span>
              <span v-else class="sold-out">Sold out</span>
            </div>

            <button
              class="cta"
              :disabled="isSoldOut || buying"
              @click="buyTicket"
            >
              <span v-if="isSoldOut">SOLD OUT</span>
              <span v-else-if="buying">PROCESSING…</span>
              <span v-else>BUY TICKET</span>
            </button>

            <p v-if="buyMsg" class="buy-msg">{{ buyMsg }}</p>
          </aside>
        </div>
      </section>
    </main>
  </div>
</template>

<style scoped>
.event-page{
  --ink:#e6e8ef; --accent:#f0b35a; --topbar:#0b0d12; --border:#2a3342;
  --topbar-h:64px;
  background:#0b0f17; color:var(--ink); min-height:100vh;
}
.topbar{
  position:sticky; top:0; z-index:20;
  display:grid; grid-template-columns:auto 120px 1fr 48px; align-items:center; gap:12px;
  height:var(--topbar-h);
  padding:14px 18px; background:var(--topbar);
  border-bottom:1px solid rgba(255,255,255,.08);
}
.brand img{ height:48px; width:auto; display:block; }
.title{ margin:0; font-weight:900; letter-spacing:.02em; font-size:clamp(18px,2.4vw,28px); color:var(--accent) }
.hamburger{ width:44px; height:44px; display:flex; align-items:center; justify-content:center; background:rgba(255,255,255,.06); border:1px solid rgba(255,255,255,.12); border-radius:10px; cursor:pointer }
.hamburger span{ width:18px; height:2px; background:#fff; display:block; margin:2px 0; border-radius:2px }
.back{ border:1px solid #232747; background:#F4F1DE; color:#232747; border-radius:10px; padding:8px 12px; cursor:pointer; font-weight:800 }
.loading{ padding:24px 22px }
.alert.error{ margin:16px 22px; padding:10px 14px; background:#9f3a38; border-radius:10px }
.hero{
  position:relative;
  min-height:calc(100vh - var(--topbar-h));
  display:flex; align-items:center;
  background:#0b0f17
}
.hero::before{
  content:"";
  position:absolute; inset:0;
  background:
    linear-gradient(180deg, rgba(0,0,0,.22) 0%, rgba(0,0,0,.7) 85%),
    linear-gradient(90deg, rgba(165,34,34,.50) 0%, rgba(0,0,0,0) 45%),
    var(--hero);
  background-size:cover;
  background-position:center top;
  filter:brightness(.95)
}
.hero-inner{
  position:relative; z-index:1;
  max-width:1200px; margin:0 auto; padding:48px 22px;
  width:100%;
  display:grid; grid-template-columns:360px 1fr 260px; gap:28px; align-items:center
}
.poster{
  position:relative; width:100%; height:300px; border-radius:18px; overflow:hidden;
  box-shadow:0 18px 42px rgba(0,0,0,.46)
}
.poster-img{ position:absolute; inset:0; background-size:cover; background-position:center }
.poster-grad{ position:absolute; inset:0; background:linear-gradient(180deg, rgba(0,0,0,0) 35%, rgba(179,31,31,.65) 100%); mix-blend-mode:multiply }
.info .event-title{ margin:0 0 12px; font-weight:900; color:#fff; letter-spacing:.15em; font-size:44px }
.meta{ margin:6px 0 10px }
.row{ display:flex; gap:10px; margin:6px 0 }
.k{ width:100px; font-weight:800 }
.v{ font-weight:700; color:#d6e1ff }
.desc{ margin-top:8px; max-width:640px; line-height:1.55; color:#e3e7ef }
.pricebox{
  align-self:start; background:rgba(15,19,27,.9); border:1px solid var(--border); border-radius:16px;
  padding:18px; min-width:240px; box-shadow:0 16px 36px rgba(0,0,0,.36);
  display:grid; gap:12px
}
.pricebox .label{ opacity:.85 }
.pricebox .price{ font-size:30px; font-weight:900 }
.cta{ padding:10px 14px; border-radius:12px; border:1px solid transparent; background:#F4B23D; color:#281c06; font-weight:900; cursor:pointer }
.event-page :deep(.sb-card.sb-topright){
  position:fixed;
  top:calc(var(--topbar-h) + 10px);
  right:18px; bottom:18px; left:auto;
  width:min(86vw, 320px);
  max-height:calc(100svh - (var(--topbar-h) + 10px) - 18px);
  overflow:auto;
  z-index:1050
}

.stock{
  margin-top:8px;
  font-size:13px;
  font-weight:600;
  color:#e3e7ef;
}
.stock .sold-out{
  color:#ff6b6b;
}
.buy-msg{
  margin-top:8px;
  font-size:12px;
}

.event-page :deep(.sb-backdrop){ display:none }
@media (max-width:1100px){
  .hero-inner{ grid-template-columns:1fr }
  .poster{ height:240px }
  .pricebox{ justify-self:start }
}
@media (max-width:720px){
  .event-page{ --topbar-h:56px }
  .brand img{ height:40px; }
  .event-page :deep(.sb-card.sb-topright){
    top:0; right:0; bottom:0; left:auto;
    width:min(86vw, 340px);
    border-radius:16px 0 0 16px; padding:18px 16px;
    box-shadow:-12px 0 36px rgba(0,0,0,.28)
  }
  .event-page :deep(.sb-backdrop){
    position:fixed; inset:0; background:rgba(0,0,0,.50);
    backdrop-filter:blur(2px); z-index:1000; display:block
  }
}
</style>
