// src/router/index.js
import { createRouter, createWebHistory } from 'vue-router'
import HomeView from '@/views/HomeView.vue'
import EventDetailView from '../views/EventDetailView.vue'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    { path: '/', name: 'login', component: () => import('@/views/Login_Page.vue') },
    { path: '/home', name: 'home', component: HomeView, meta: { requiresWallet: true } },
    { path: '/events/:id', name: 'event', component: EventDetailView },
    { path: '/about', name: 'about', component: () => import('@/views/AboutView.vue') },
    { path: '/profile', name: 'profile', component: () => import('@/views/Profile_Page.vue'), meta: { requiresAuth: true } },
    { path: '/logout', name: 'logout', component: () => import('@/views/LogoutConfirm.vue') },
    { path: '/wallet', name: 'wallet', component: () => import('@/views/Wallet_Page.vue') },
    { path: '/history', name: 'history', component: () => import('@/views/History_Page.vue') },
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
