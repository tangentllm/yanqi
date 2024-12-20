import { chromium } from 'playwright'
import { mkdir } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const outDir = path.resolve(__dirname, '../../README.assets')
await mkdir(outDir, { recursive: true })

const browser = await chromium.launch({ headless: true })

async function freshPage() {
  const page = await browser.newPage({
    viewport: { width: 1440, height: 900 },
    deviceScaleFactor: 2,
  })
  await page.goto('http://localhost:5173', { waitUntil: 'networkidle', timeout: 60000 })
  await page.waitForTimeout(800)
  return page
}

// 1) 主界面空状态
{
  const page = await freshPage()
  await page.screenshot({ path: path.join(outDir, 'chat-home.png') })
  console.log('saved chat-home.png')
  await page.close()
}

// 2) 工具选择面板
{
  const page = await freshPage()
  await page.locator('button', { hasText: '工具' }).first().click()
  await page.waitForSelector('.tool-overlay', { state: 'visible', timeout: 10000 })
  await page.waitForTimeout(600)
  await page.screenshot({ path: path.join(outDir, 'tools-panel.png') })
  console.log('saved tools-panel.png')
  await page.close()
}

// 3) 系统设置 — 模型配置
{
  const page = await freshPage()
  await page.locator('button.settings-btn').click()
  await page.waitForTimeout(700)
  await page.screenshot({ path: path.join(outDir, 'settings-model.png') })
  console.log('saved settings-model.png')

  await page.getByRole('button', { name: '对话压缩' }).click()
  await page.waitForTimeout(500)
  await page.screenshot({ path: path.join(outDir, 'settings-compression.png') })
  console.log('saved settings-compression.png')
  await page.close()
}

await browser.close()
console.log('screenshots saved to', outDir)
