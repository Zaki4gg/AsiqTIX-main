// src/router/index.js
import { createRouter, createWebHistory } from 'vue-router'
import HomeView from '@/views/HomeView.vue'
import Login from '@/views/LoginPage.vue'
import Profile from '@/views/ProfilePage.vue'
import Logout from '@/views/LogoutConfirm.vue'
import Wallet from '@/views/WalletPage.vue'
import History from '@/views/HistoryPage.vue'
import EventDetailView from '../views/EventDetailView.vue'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    { path: '/', name: 'login', component: Login },
    { path: '/home', name: 'home', component: HomeView, meta: { requiresWallet: true } },
    { path: '/events/:id', name: 'event', component: EventDetailView },
    { path: '/profile', name: 'profile', component: Profile, meta: { requiresAuth: true } },
    { path: '/logout', name: 'logout', component: Logout },
    { path: '/wallet', name: 'wallet', component: Wallet },
    { path: '/history', name: 'history', component: History },
    { path: '/:pathMatch(.*)*', redirect: { name: 'login' } },
  ],
})

router.beforeEach((to) => {
  if (!to.meta.requiresWallet) return true
  const hasToken = !!localStorage.getItem('auth_token')
  const hasAddr  = !!localStorage.getItem('walletAddress')
  if (hasToken || hasAddr) return true
  return { name: 'login' }
})

export default router
