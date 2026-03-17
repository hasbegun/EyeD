import { Router } from '@vaadin/router';

export function initRouter(outlet: HTMLElement) {
  const router = new Router(outlet);
  router.setRoutes([
    {
      path: '/',
      redirect: '/dashboard',
    },
    {
      path: '/dashboard',
      component: 'view-dashboard',
      action: async () => { await import('./views/view-dashboard.js'); },
    },
    {
      path: '/devices',
      component: 'view-devices',
      action: async () => { await import('./views/view-devices.js'); },
    },
    {
      path: '/enrollment',
      component: 'view-enrollment',
      action: async () => { await import('./views/view-enrollment.js'); },
    },
    {
      path: '/analysis',
      component: 'view-run',
      action: async () => { await import('./views/view-run.js'); },
    },
    {
      path: '/history',
      component: 'view-history',
      action: async () => { await import('./views/view-history.js'); },
    },
    {
      path: '/admin',
      component: 'view-admin',
      action: async () => { await import('./views/view-admin.js'); },
    },
    {
      path: '(.*)',
      component: 'view-not-found',
      action: async () => { await import('./views/view-not-found.js'); },
    },
  ]);
}
