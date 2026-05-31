import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './i18n'
import './index.css'
import { AuthProvider } from './contexts/AuthContext'
import { DataProvider } from './contexts/DataContext'
import { SettingsProvider } from './store/settings'
import { RouterProvider } from './store/router'
import App from './App.tsx'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <AuthProvider>
      <SettingsProvider>
        <DataProvider>
          <RouterProvider>
            <App />
          </RouterProvider>
        </DataProvider>
      </SettingsProvider>
    </AuthProvider>
  </StrictMode>,
)
