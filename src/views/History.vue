<script setup>
import '@/assets/history.css'
import { ref, watch, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import SideNavSB from '@/components/SideNavSB.vue'

const route = useRoute()
const sidebarOpen = ref(false)
const toggleSidebar = () => (sidebarOpen.value = !sidebarOpen.value)
watch(() => route.fullPath, () => (sidebarOpen.value = false))

/* ==========
   STATE
========== */
const histories = ref([]) // [{ id, title, date, booking, price, status }]
const loading = ref(true)
const errorMsg = ref('')

/* ==========
   CONST
========== */
const hasMM = typeof window !== 'undefined' && !!window.ethereum
const POLYGON_CHAIN_ID_HEX = '0x89'
const API_BASE = (import.meta.env?.VITE_API_BASE || 'http://localhost:3001').replace(/\/+$/,'')
const CONTRACT = (import.meta.env?.VITE_TICKET_CONTRACT || '').trim().toLowerCase()
const START_BLOCK = Number(import.meta.env?.VITE_TICKET_START_BLOCK || 0) || 0

/* Transfer(address,address,uint256) keccak256 */
const TOPIC_TRANSFER = '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef'

/* ==========
   MM ACCOUNT
========== */
const account = ref('')
const chainId = ref('')

async function hydrateAccount() {
  if (!hasMM) return
  try {
    const [acc] = await window.ethereum.request({ method: 'eth_accounts' })
    account.value = acc || ''
    chainId.value = await window.ethereum.request({ method: 'eth_chainId' }).catch(() => '')
    if (account.value) await ensurePolygon()
  } catch {}
}

async function ensurePolygon() {
  if (!hasMM) return false
  if (chainId.value?.toLowerCase() === POLYGON_CHAIN_ID_HEX) return true
  try {
    await window.ethereum.request({
      method: 'wallet_switchEthereumChain',
      params: [{ chainId: POLYGON_CHAIN_ID_HEX }]
    })
    chainId.value = POLYGON_CHAIN_ID_HEX
    return true
  } catch (err) {
    if (err?.code === 4902) {
      try {
        await window.ethereum.request({
          method: 'wallet_addEthereumChain',
          params: [{
            chainId: POLYGON_CHAIN_ID_HEX,
            chainName: 'Polygon PoS',
            rpcUrls: ['https://polygon-rpc.com','https://rpc.ankr.com/polygon'],
            nativeCurrency: { name: 'POL', symbol: 'POL', decimals: 18 },
            blockExplorerUrls: ['https://polygonscan.com']
          }]
        })
        chainId.value = POLYGON_CHAIN_ID_HEX
        return true
      } catch {}
    }
    return false
  }
}

/* ==========
   HELPERS
========== */
function toTopicAddress(addr) {
  // topic padding: 32 bytes; address = 20 bytes (40 hex chars)
  // 0x + 24 zeros + address lowercase without 0x
  const hex = String(addr || '').toLowerCase().replace(/^0x/, '')
  return '0x' + '0'.repeat(24) + hex
}

function hexToDec(hexStr) {
  try { return BigInt(hexStr).toString(10) } catch { return '0' }
}

function hexBlock(n) {
  return '0x' + Math.max(0, Number(n || 0)).toString(16)
}

function fmtDate(ts) {
  try { return new Date(ts).toLocaleDateString('id-ID') } catch { return '' }
}

/* ==========
   BACKEND API
========== */
async function api(path, init){
  const url = path.startsWith('http') ? path : `${API_BASE}${path}`
  const headers = { ...(init?.headers || {}) }
  if (account.value) headers['x-wallet-address'] = account.value.toLowerCase()
  if (init?.body && !(init.body instanceof FormData)) headers['Content-Type'] = 'application/json'
  const res = await fetch(url, { ...init, headers })
  const txt = await res.text().catch(()=> '')
  let data = null; try { data = txt ? JSON.parse(txt) : null } catch { data = { message: txt } }
  if (!res.ok) throw new Error(data?.error || data?.message || 'Request failed')
  return data
}

/* ==========
   LOAD APP-LEDGER (Supabase via backend)
========== */
async function loadLedgerPurchases() {
  // Mengambil semua transaksi wallet (backend sudah filter berdasarkan header),
  // lalu hanya ambil yang purchase.
  const list = await api('/transactions')
  const items = (Array.isArray(list) ? list : [])
    .filter(x => (x?.kind || '').toLowerCase() === 'purchase')
    .map(x => ({
      _sortAt: +new Date(x.created_at),
      id: x.id,
      title: 'Ticket purchase',
      date: fmtDate(x.created_at),
      booking: (x.ref_id || x.id || '').toString().slice(0, 16),
      price: `${Math.abs(Number(x.amount) || 0)} POL`,
      status: (x.status || 'Successful')
    }))
  return items
}

/* ==========
   LOAD ON-CHAIN NFT TRANSFERS (ERC-721 → to = user)
========== */
async function loadOnchainTickets() {
  if (!hasMM || !account.value || !CONTRACT) return []
  const fromBlock = START_BLOCK ? hexBlock(START_BLOCK) : '0x0'
  const toBlock = 'latest'
  const topicTo = toTopicAddress(account.value)

  // eth_getLogs (tanpa ethers)
  const logs = await window.ethereum.request({
    method: 'eth_getLogs',
    params: [{
      address: CONTRACT,
      fromBlock,
      toBlock,
      topics: [TOPIC_TRANSFER, null, topicTo]
    }]
  })

  // perkaya dengan timestamp via eth_getBlockByNumber
  const out = []
  for (const lg of logs) {
    const blk = await window.ethereum.request({
      method: 'eth_getBlockByNumber',
      params: [lg.blockNumber, false]
    }).catch(() => null)

    const tokenId = hexToDec(lg.topics?.[3] || '0x0')
    const tsMs = blk?.timestamp ? Number(BigInt(blk.timestamp) * 1000n) : Date.now()
    out.push({
      _sortAt: tsMs,
      id: `${lg.transactionHash}-${tokenId}`,
      title: `NFT Ticket #${tokenId}`,
      date: fmtDate(tsMs),
      booking: (lg.transactionHash || '').slice(0, 16),
      price: '—',
      status: 'Successful'
    })
  }
  // terbaru dulu
  out.sort((a,b) => b._sortAt - a._sortAt)
  return out
}

/* ==========
   COMBINE + INIT
========== */
async function refreshHistory() {
  errorMsg.value = ''
  loading.value = true
  try {
    const [ledger, onchain] = await Promise.all([
      loadLedgerPurchases().catch(() => []),
      loadOnchainTickets().catch(() => [])
    ])
    const all = [...ledger, ...onchain].sort((a,b) => b._sortAt - a._sortAt)
    histories.value = all
  } catch (e) {
    errorMsg.value = String(e?.message || e)
  } finally {
    loading.value = false
  }
}

function onAccountsChanged(accs){
  account.value = accs?.[0] || ''
  refreshHistory()
}
function onChainChanged(cid){
  chainId.value = cid || ''
  refreshHistory()
}

function downloadTicket(row){ alert(`Downloading ticket: ${row.title} (${row.booking})`) }

/* ==========
   MOUNT
========== */
onMounted(async () => {
  await hydrateAccount()
  if (hasMM) {
    window.ethereum.on?.('accountsChanged', onAccountsChanged)
    window.ethereum.on?.('chainChanged', onChainChanged)
  }
  await refreshHistory()
})
</script>

<template>
  <div class="history-page">
    <header class="topbar">
      <div class="brand"><img src="/logo_with_text.png" alt="Tickety" /></div>
      <h1 class="title">History</h1>
      <button class="hamburger" aria-label="Toggle menu" @click="toggleSidebar"><span/><span/><span/></button>
    </header>

    <!-- Khusus history: tambah kelas 'sb-topright' agar posisi sesuai CSS -->
    <SideNavSB v-model="sidebarOpen" extraClass="sb-topright" />

    <main class="wrap">
      <h2 class="section-title">Latest Tickets</h2>

      <div v-if="loading" class="alert">Loading…</div>
      <div v-else-if="errorMsg" class="alert error">{{ errorMsg }}</div>

      <ul v-else class="list" role="list">
        <li v-for="row in histories" :key="row.id" class="item">
          <div class="header-line">
            <h3 class="event">{{ row.title }}</h3>
            <button class="btn" @click="downloadTicket(row)">DOWNLOAD TICKET</button>
          </div>
          <div class="meta">
            <p><strong>Date:</strong> {{ row.date }}</p>
            <p><strong>ID:</strong> {{ row.booking }}</p>
            <p><strong>Price:</strong> {{ row.price }}</p>
            <p><strong>Status:</strong> {{ row.status }}</p>
          </div>
        </li>

        <!-- Jika kosong: sisakan satu baris kosong/strip (opsional sesuai style Anda) -->
        <li v-if="!histories.length" class="item">
          <div class="header-line">
            <h3 class="event">—</h3>
            <button class="btn" disabled>DOWNLOAD TICKET</button>
          </div>
          <div class="meta">
            <p><strong>Date:</strong> —</p>
            <p><strong>ID:</strong> —</p>
            <p><strong>Price:</strong> —</p>
            <p><strong>Status:</strong> —</p>
          </div>
        </li>
      </ul>
    </main>
  </div>
</template>
