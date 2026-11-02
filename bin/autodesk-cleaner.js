#!/usr/bin/env node
// Launcher for `npx @cazorlas/autodesk-cleaner [args]`.
// Read-only modes (-Scan, -Readiness) run directly without elevation;
// everything else goes through Start-AutodeskCleaner.bat, which asks for UAC.
'use strict';
const { spawnSync } = require('child_process');
const path = require('path');

if (process.platform !== 'win32') {
  console.error('autodesk-cleaner chi chay tren Windows.');
  process.exit(1);
}

const root = path.join(__dirname, '..');
const args = process.argv.slice(2);
const readOnly = args.length > 0 && args.every((a) => /^-(Scan|Readiness)$/i.test(a));

let result;
if (readOnly) {
  result = spawnSync('powershell.exe',
    ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(root, 'AutodeskCleaner.ps1'), ...args],
    { stdio: 'inherit' });
} else {
  // .bat files must be started through a shell (Node >= 18.20 refuses them otherwise).
  const bat = path.join(root, 'Start-AutodeskCleaner.bat');
  const safeArgs = args.filter((a) => /^[-\w,.]+$/.test(a));
  result = spawnSync(`"${bat}"`, safeArgs, { stdio: 'inherit', shell: true });
}
process.exit(result.status === null ? 1 : result.status);
