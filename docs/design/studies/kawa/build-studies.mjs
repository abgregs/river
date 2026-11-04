// Builds kawa-studies-r1.html, the tabbed motion study, from its template and data: node build-studies.mjs
import fs from 'fs';
const read = (f) => fs.readFileSync(new URL(f, import.meta.url), 'utf8').trim();
const html = read('./kawa-studies.template-r1.html').replace('/*MOTION_DATA*/null', read('./kawa-motion-r1.json'));
if (html.includes('_DATA*/')) throw new Error('a data placeholder was left in');
fs.writeFileSync(new URL('./kawa-studies-r1.html', import.meta.url), html + '\n');
