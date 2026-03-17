import { defineConfig } from 'vite';

export default defineConfig({
  root: '.',
  build: {
    outDir: 'dist',
    target: 'es2022',
  },
  server: {
    port: 3000,
    proxy: {
      '/ws': {
        target: 'ws://localhost:9504',
        ws: true,
      },
      '/health': {
        target: 'http://localhost:9504',
      },
      '/api': {
        target: 'http://localhost:9504',
      },
      '/engine': {
        target: 'http://localhost:9500',
        rewrite: (path: string) => path.replace(/^\/engine/, ''),
      },
    },
  },
});
