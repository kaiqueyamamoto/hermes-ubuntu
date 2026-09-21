// Exemplo Playwright (Node): abre uma página e imprime o título.
//   node /opt/hermes-examples/playwright_exemplo.mjs [url]
import { createRequire } from "node:module";

// ESM ignora NODE_PATH; o require resolve o playwright instalado globalmente.
const { chromium } = createRequire(import.meta.url)("playwright");

const url = process.argv[2] ?? "https://example.com";
const browser = await chromium.launch();
const page = await browser.newPage();
await page.goto(url);
console.log(await page.title());
await browser.close();
