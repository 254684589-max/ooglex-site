import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { existsSync } from 'node:fs';

export async function launchGlobeBrowser() {
  const upstream = process.env.GLOBE_UPSTREAM_DIR || '/tmp/ooglex-globe-build/src';
  const require = createRequire(resolve(upstream, 'package.json'));
  const module = require('puppeteer');
  const puppeteer = module.default || module;
  const executablePath = process.env.GLOBE_CHROME ||
    ['/usr/bin/google-chrome', '/usr/bin/chromium', '/opt/pw-browsers/chromium-1194/chrome-linux/chrome']
      .find(existsSync);
  return puppeteer.launch({
    ...(executablePath ? { executablePath } : {}),
    headless: true,
    args: ['--no-sandbox', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader']
  });
}
