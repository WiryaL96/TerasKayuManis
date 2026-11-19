import {defineConfig} from '@playwright/test'
import dashboard from './playwright.dashboard.config.mjs'
export default defineConfig({...dashboard,testDir:'./tests/customer-ui'})
