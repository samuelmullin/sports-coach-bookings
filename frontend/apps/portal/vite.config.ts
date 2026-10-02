import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

export default defineConfig({
  base: '/',
  plugins: [react()],
  server: {
    port: 5174,
    proxy: {
      '/api': 'http://localhost:4000',
    },
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    rollupOptions: {
      output: {
        // Stable vendor chunks: they change far less often than app code, so
        // browsers keep them cached across deploys.
        manualChunks(id) {
          if (!id.includes('node_modules')) return undefined;
          if (
            /[\\/]node_modules[\\/](react|react-dom|react-router|react-router-dom|scheduler)[\\/]/.test(
              id,
            )
          )
            return 'vendor-react';
          if (id.includes('@tanstack')) return 'vendor-query';
          if (id.includes('i18next')) return 'vendor-i18n';
          if (id.includes('@radix-ui') || id.includes('lucide-react')) return 'vendor-ui';
          return undefined;
        },
      },
    },
  },
});
