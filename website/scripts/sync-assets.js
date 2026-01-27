/* Recursively sync /docs/assets -> /website/static/assets
 * Preserves directory structure
 */

const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..', '..');
const sourceRoot = path.join(repoRoot, 'docs', 'assets');
const targetRoot = path.join(repoRoot, 'website', 'static', 'assets');

function copyRecursive(srcDir, dstDir) {
  if (!fs.existsSync(srcDir)) {
    console.warn(`[sync-assets] Source directory does not exist: ${srcDir}`);
    return;
  }

  fs.mkdirSync(dstDir, { recursive: true });

  for (const entry of fs.readdirSync(srcDir, { withFileTypes: true })) {
    const srcPath = path.join(srcDir, entry.name);
    const dstPath = path.join(dstDir, entry.name);

    if (entry.isDirectory()) {
      copyRecursive(srcPath, dstPath);
    } else if (entry.isFile()) {
      fs.copyFileSync(srcPath, dstPath);
      console.log(`[sync-assets] Copied: ${srcPath} -> ${dstPath}`);
    }
  }
}

copyRecursive(sourceRoot, targetRoot);
