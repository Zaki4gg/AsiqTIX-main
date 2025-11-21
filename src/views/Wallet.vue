<script setup>
import '@/assets/wallet.css'
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { useRoute } from 'vue-router'
import SideNavSB from '@/components/SideNavSB.vue'
import { io } from 'socket.io-client'
import { supabase } from '@/lib/supabase'

/* ── Drawer ─────────────────────────────────────────────────────────────── */
const route = useRoute()
const sidebarOpen = ref(false)
const toggleSidebar = () => (sidebarOpen.value = !sidebarOpen.value)
watch(() => route.fullPath, () => (sidebarOpen.value = false))

/* ── MetaMask & saldo POL (native coin di Polygon) ──────────────────────── */
const hasMM = typeof window !== 'undefined' && !!window.ethereum
const account = ref('')
const chainId = ref('')
const balancePol = ref(0)                 // saldo dalam POL (bukan wei)
const lastBalancePol = ref(null)          // baseline untuk deteksi kenaikan saldo (top-up)
const walletSymbol = 'POL'
const walletAddress = computed(() => account.value || '')
const short = s => (s ? `${s.slice(0,6)}…${s.slice(-4)}` : '')

/* wei (hex) -> number POL */
function hexWeiToPol(weiHex) {
  const wei = BigInt(weiHex || '0x0')
  const denom = 10n ** 18n
  const whole = wei / denom
  const frac  = wei % denom
  const fracStr = frac.toString().padStart(18, '0').slice(0, 6) // 6 desimal
  return parseFloat(`${whole}.${fracStr}`)
}

/* pastikan jaringan Polygon (chainId 0x89) */
async function ensurePolygon() {
  if (!hasMM) return false
  if (chainId.value === '0x89') return true
  try {
    await window.ethereum.request({
      method: 'wallet_switchEthereumChain',
      params: [{ chainId: '0x89' }]
    })
    chainId.value = '0x89'
    return true
  } catch (err) {
    if (err?.code === 4902) {
      try {
        await window.ethereum.request({
          method: 'wallet_addEthereumChain',
          params: [{
            chainId: '0x89',
            chainName: 'Polygon PoS',
            rpcUrls: ['https://polygon-rpc.com','https://rpc.ankr.com/polygon'],
            nativeCurrency: { name: 'POL', symbol: 'POL', decimals: 18 },
            blockExplorerUrls: ['https://polygonscan.com']
          }]
        })
        chainId.value = '0x89'
        return true
      } catch { /* ignore */ }
    }
    return false
  }
}

/* ── Transactions: fetch + realtime ─────────────────────────────────────── */
const API_BASE = (import.meta.env?.VITE_API_BASE || 'http://localhost:3001').replace(/\/+$/,'')
const txs = ref([])
const txLoading = ref(false)
const txError = ref('')

async function api(path, init){
  const url = path.startsWith('http') ? path : `${API_BASE}${path}`
  const headers = { ...(init?.headers || {}), 'x-wallet-address': walletAddress.value.toLowerCase() }
  if (init?.body && !(init.body instanceof FormData)) headers['Content-Type'] = 'application/json'
  const res = await fetch(url, { ...init, headers })
  const txt = await res.text().catch(()=> '')
  let data = null; try { data = txt ? JSON.parse(txt) : null } catch { data = { message: txt } }
  if (!res.ok) throw new Error(data?.error || data?.message || 'Request failed')
  return data
}

async function loadTransactions(){
  txError.value = ''
  if (!walletAddress.value) { txs.value = []; return }
  try {
    txLoading.value = true
    const data = await api('/transactions')
    txs.value = Array.isArray(data) ? data : []
  } catch (e) {
    txError.value = String(e?.message || e)
  } finally {
    txLoading.value = false
  }
}

let socket = null
function startSocket(){
  stopSocket()
  if (!walletAddress.value) return
  socket = io(API_BASE, {
    transports: ['websocket'],
    auth: { address: walletAddress.value.toLowerCase() }
  })
  socket.on('tx:new', (tx) => {
    if (!tx || !tx.id) return
    if ((tx.wallet || '').toLowerCase() !== walletAddress.value.toLowerCase()) return
    if (txs.value.findIndex(t => t.id === tx.id) === -1) txs.value.unshift(tx)
  })
}
function stopSocket(){
  socket?.disconnect?.()
  socket = null
}

/* Catat top-up ke backend (app-ledger) berdasarkan selisih saldo) */
async function recordTopupDelta(deltaPol) {
  try {
    await api('/topup', {
      method: 'POST',
      body: JSON.stringify({
        amount: Number(deltaPol.toFixed(6))
      })
    })
    // biarkan socket yang memasukkan item baru; fallback reload
    if (!socket) await loadTransactions()
  } catch (e) {
    console.warn('recordTopupDelta failed:', e)
  }
}

/* ambil saldo POL + deteksi kenaikan (top-up) */
async function refreshBalance() {
  if (!hasMM || !account.value) { balancePol.value = 0; lastBalancePol.value = null; return }
  try {
    const weiHex = await window.ethereum.request({
      method: 'eth_getBalance',
      params: [account.value, 'latest']
    })
    const newBal = hexWeiToPol(weiHex)
    balancePol.value = newBal

    if (lastBalancePol.value === null) {
      lastBalancePol.value = newBal
    } else {
      const delta = newBal - lastBalancePol.value
      // ambang minimal agar tidak terpancing fluktuasi pembulatan
      if (delta > 0.000001) {
        await recordTopupDelta(delta)
        lastBalancePol.value = newBal
      } else if (delta < -0.000001) {
        // pengurangan saldo (pembelian) dicatat oleh alur pembelian, bukan di sini
        lastBalancePol.value = newBal
      }
    }
  } catch {
    balancePol.value = 0
  }
}

/* hydrate akun & chain dari MetaMask */
async function hydrate() {
  if (!hasMM) return
  try {
    const [acc] = await window.ethereum.request({ method: 'eth_accounts' })
    account.value = acc || ''
    chainId.value = await window.ethereum.request({ method: 'eth_chainId' }).catch(() => '')
    if (account.value) await ensurePolygon()
    await refreshBalance()
    if (account.value) {
      await loadTransactions()
      startSocket()
    }
  } catch {}
}

/* utils UI */
function copyAddr() {
  if (!account.value) return
  navigator.clipboard.writeText(account.value)
  alert('Copied.')
}

/* event dari MetaMask */
function onAccountsChanged(accs){
  account.value = accs?.[0] || ''
  lastBalancePol.value = null
  refreshBalance()
  if (account.value) {
    loadTransactions()
    startSocket()
  } else {
    txs.value = []
    stopSocket()
  }
}
function onChainChanged(cid){
  chainId.value = cid || ''
  lastBalancePol.value = null
  refreshBalance()
}

/* Top up → MetaMask Buy (VERSI B: buka tab baru, tanpa redirect tab sekarang) */
const TOPUP_URL = 'https://app.metamask.io/buy/build-quote'
function topUp(){
  const w = window.open(TOPUP_URL, '_blank', 'noopener,noreferrer')
  if (!w || w.closed || typeof w.closed === 'undefined') {
    const a = document.createElement('a')
    a.href = TOPUP_URL
    a.target = '_blank'
    a.rel = 'noopener noreferrer'
    a.style.display = 'none'
    document.body.appendChild(a)
    a.click()
    a.remove()
  }
}

/* ── Mount / Unmount ───────────────────────────────────────────────────── */
let balTimer = null
onMounted(async () => {
  await hydrate()
  if (hasMM) {
    window.ethereum.on?.('accountsChanged', onAccountsChanged)
    window.ethereum.on?.('chainChanged', onChainChanged)
  }
  balTimer = window.setInterval(refreshBalance, 15_000)
})
onUnmounted(() => {
  if (hasMM) {
    window.ethereum.removeListener?.('accountsChanged', onAccountsChanged)
    window.ethereum.removeListener?.('chainChanged', onChainChanged)
  }
  if (balTimer) clearInterval(balTimer)
  stopSocket()
})
</script>

<template>
  <div :class="['wallet-page', { 'has-sb': sidebarOpen }]">
    <header class="topbar">
      <div class="brand"><img src="/logo_with_text.png" alt="Tickety" /></div>
      <h1 class="title">Wallet</h1>
      <button class="hamburger" type="button" aria-label="Toggle sidebar" @click="toggleSidebar">
        <span/><span/><span/>
      </button>
    </header>

    <SideNavSB v-model="sidebarOpen" />

    <div class="container">
      <section class="panel">
        <section class="balance">
          <div>
            <div class="balance-value">
              {{ balancePol.toLocaleString('en-US', { maximumFractionDigits: 6 }) }} {{ walletSymbol }}
            </div>
            <div class="muted" style="margin-top:4px">Network: Polygon (PoS)</div>

            <div class="addr muted" style="margin-top:6px">
              <span :title="walletAddress">{{ short(walletAddress) || '-' }}</span>
            </div>

            <div class="btns" style="margin-top:10px">
              <button class="btn" @click="topUp">TOP UP</button>
              <button class="btn ghost" :disabled="!walletAddress" @click="copyAddr">COPY ADDRESS</button>
            </div>
          </div>
        </section>

        <hr class="sep" />

        <section>
          <h3 class="h-sub">Transaction</h3>

          <div v-if="txError" class="alert error">{{ txError }}</div>
          <div v-else-if="txLoading" class="alert">Loading…</div>

          <ul v-else class="tx-list" role="list">
            <li v-for="t in txs" :key="t.id" class="tx-item">
              <span class="tx-amount">
                {{ Number(t.amount) < 0 ? '-' : '+' }}
                {{ Math.abs(Number(t.amount)).toFixed(0) }}
              </span>
              <span class="tx-date">{{ new Date(t.created_at).toLocaleDateString('id-ID') }}</span>
            </li>

            <!-- kosong: sisakan strip saja -->
            <li v-if="!txs.length" class="tx-item">
              <span class="tx-amount">–</span>
              <span class="tx-date"></span>
            </li>
          </ul>
        </section>
      </section>
    </div>
  </div>
</template>

<style scoped>
/* tidak ada indikator harga tambahan */
</style>
