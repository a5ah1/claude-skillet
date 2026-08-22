#!/usr/bin/env node

/**
 * Generates a searchable Lucide icon index for LLM-assisted development.
 * Usage: node generate-lucide-index.mjs [output-path]
 * Default output: ./references/lucide-icon-index.json
 */

import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

const OUTPUT = resolve(process.argv[2] || './references/lucide-icon-index.json');

function kebabToPascal(s) {
  return s.split('-').map(p => p[0].toUpperCase() + p.slice(1)).join('');
}

async function fetchJSON(url) {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return r.json();
}

async function getIconTags() {
  const urls = [
    'https://unpkg.com/lucide-static@latest/tags.json',
    'https://raw.githubusercontent.com/lucide-icons/lucide/main/packages/lucide-static/tags.json'
  ];
  for (const url of urls) {
    try {
      console.log(`Fetching from ${url}...`);
      const data = await fetchJSON(url);
      console.log(`Found ${Object.keys(data).length} icons.`);
      return data;
    } catch (e) {
      console.warn(`  Failed: ${e.message}`);
    }
  }
  // Fallback: extract names from the installed lucide package
  try {
    console.log('Falling back to installed lucide package...');
    const mod = await import('lucide');
    const names = Object.keys(mod).filter(k => /^[A-Z]/.test(k) && k !== 'default');
    const tags = {};
    for (const name of names) {
      const kebab = name.replace(/([A-Z])/g, '-$1').toLowerCase().replace(/^-/, '');
      tags[kebab] = kebab.split('-');
    }
    console.log(`Extracted ${Object.keys(tags).length} icons from package.`);
    return tags;
  } catch (e) {
    console.error('All strategies failed. Ensure network access or that lucide is installed.');
    process.exit(1);
  }
}

async function main() {
  const tags = await getIconTags();

  const index = {};
  for (const [kebab, tagList] of Object.entries(tags)) {
    const pascal = kebabToPascal(kebab);
    const nameWords = kebab.split('-');
    index[pascal] = {
      kebab,
      keywords: [...new Set([...tagList, ...nameWords])]
    };
  }

  mkdirSync(dirname(OUTPUT), { recursive: true });
  writeFileSync(OUTPUT, JSON.stringify(index, null, 2));
  console.log(`\n✓ Icon index generated: ${Object.keys(index).length} icons → ${OUTPUT}`);
}

main().catch(e => { console.error('Error:', e.message); process.exit(1); });
