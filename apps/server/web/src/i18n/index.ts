import i18n from "i18next"
import { initReactI18next } from "react-i18next"

import en from "./en.json"
import zh from "./zh.json"

const savedLang = localStorage.getItem("nanolink_lang") || "en"

i18n.use(initReactI18next).init({
  resources: {
    en: { translation: en },
    zh: { translation: zh },
  },
  lng: savedLang,
  fallbackLng: "en",
  interpolation: {
    escapeValue: false,
  },
})

export function setLanguage(lang: string) {
  i18n.changeLanguage(lang)
  localStorage.setItem("nanolink_lang", lang)
}

export function getLanguage(): string {
  return i18n.language
}

export default i18n
