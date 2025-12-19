import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  build: {
    outDir: 'dist',
    assetsDir: 'assets',
    rollupOptions: {
      output: {
        manualChunks: {
          'chart': ['chart.js', 'vue-chartjs']
        }
      }
    }
  },
  server: {
    proxy: {
      '/ws': {
        target: 'ws://localhost:9100',
        ws: true
      },
      '/api': {
        target: 'http://localhost:9100'
      }
    }
  }
})
