// Synchronize the 2026-10-10 packaging correction and its static data mirrors.
// Safe to rerun; it never touches customer history or application queue state.
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve('格志京东客服知识库-2026-10-04');
const read = (name) => fs.readFileSync(path.join(root, name), 'utf8');
const json = (name) => JSON.parse(read(name));
const write = (name, value) => fs.writeFileSync(path.join(root, name), value);
const writeJson = (name, value) => write(name, `${JSON.stringify(value, null, 2)}\n`);
const normalize = (text) => text.toLowerCase().replace(/\s+/g, '');
const cards = json('rag_cards/customer_service_rag_cards.json');
const chunks = read('rag_cards/source_chunks.jsonl').trim().split('\n').map(JSON.parse);
const changed = new Set([
  'dot_matrix_all_models_two_free_test_sheets_20261010',
  'ak80_confirmed_ak890_package_correction_20261010',
]);
for (const id of changed) {
  if (!cards.some((card) => card.id === id)) throw new Error(`Missing card ${id}`);
}
const catalog = chunks.find((chunk) => chunk.id.startsWith('src_product_model_feature_catalog_kb_0012_'));
if (!catalog) throw new Error('Missing catalog packaging source chunk');
catalog.content = read('product_model_feature_catalog_kb.md').split('## 7. ')[1]
  .split('\n').slice(1).join('\n').split('\n## ')[0].trim();
changed.add(catalog.id);
const sourceFile = 'dot_matrix_standard_test_paper_kb.md';
const newChunk = {
  id: 'src_dot_matrix_standard_test_paper_20261010',
  type: 'source_chunk', source_file: sourceFile,
  title: '所有针式打印机标准赠送两张测试纸及已确认AK80误写更正',
  product_line: 'dot_matrix_printer', intent: 'presale_package_contents',
  risk_level: 'low', content: read(sourceFile).trim(),
};
const chunkPosition = chunks.findIndex((chunk) => chunk.id === newChunk.id);
if (chunkPosition < 0) chunks.push(newChunk);
else chunks[chunkPosition] = newChunk;
changed.add(newChunk.id);
const routes = json('rag_cards/high_frequency_queries.json');
for (const [query, cardId] of [
  ['所有针式打印机都送纸吗', 'dot_matrix_all_models_two_free_test_sheets_20261010'],
  ['针式打印机标准送几张测试纸', 'dot_matrix_all_models_two_free_test_sheets_20261010'],
  ['ak80 tg890 有送纸吗', 'ak80_confirmed_ak890_package_correction_20261010'],
  ['AK890和TG890送纸吗', 'ak80_confirmed_ak890_package_correction_20261010'],
]) {
  if (!routes.queries.some((route) => normalize(route.query) === normalize(query))) {
    routes.queries.push({query, card_id: cardId, platforms: ['JD']});
  }
}
const index = json('rag_index/customer_service_rag_index.json');
index.cards = cards;
index.source_chunks = chunks;
index.high_frequency = Object.fromEntries(routes.queries.map((route) => [normalize(route.query), route.card_id]));
for (const [term, ids] of Object.entries(index.keyword_index)) {
  const remaining = ids.filter((id) => !changed.has(id));
  if (remaining.length) index.keyword_index[term] = remaining;
  else delete index.keyword_index[term];
}
const ngrams = (record) => {
  const text = normalize([record.id, record.issue, record.title,
    ...(record.models ?? []), ...(record.keywords ?? []), ...(record.synonyms ?? []),
    record.reply_template, record.content].filter(Boolean).join(' '));
  const counts = new Map();
  for (let n = 2; n <= 4; n++) {
    for (let offset = 0; offset <= text.length - n; offset++) {
      const gram = text.slice(offset, offset + n);
      counts.set(gram, (counts.get(gram) ?? 0) + 1);
    }
  }
  return counts;
};
const updated = [...cards, ...chunks].filter((record) => changed.has(record.id));
for (const record of updated) {
  for (const term of [record.issue, record.title, ...(record.models ?? []),
    ...(record.keywords ?? []), ...(record.synonyms ?? [])].filter(Boolean)) {
    const key = normalize(term);
    const ids = index.keyword_index[key] ?? [];
    if (!ids.includes(record.id)) ids.push(record.id);
    index.keyword_index[key] = ids;
  }
}
// Refresh affected char-ngram vectors, preserving the unrelated fallback index.
const countsById = new Map(updated.map((record) => [record.id, ngrams(record)]));
const frequencies = new Map();
for (const record of [...cards, ...chunks]) {
  const terms = countsById.has(record.id)
    ? countsById.get(record.id).keys() : Object.keys(index.vectors[record.id] ?? {});
  for (const term of terms) frequencies.set(term, (frequencies.get(term) ?? 0) + 1);
}
for (const [id, counts] of countsById) {
  const vector = {};
  let squaredNorm = 0;
  for (const [term, count] of counts) {
    const weight = count * (Math.log((1 + cards.length + chunks.length) / (1 + frequencies.get(term))) + 1);
    vector[term] = weight;
    squaredNorm += weight * weight;
  }
  const norm = Math.sqrt(squaredNorm);
  for (const term of Object.keys(vector)) vector[term] /= norm;
  index.vectors[id] = vector;
}
index.vectorizer.note = 'Packaging records refreshed 2026-10-10 with smoothed IDF and L2-normalized char-ngram TF-IDF. Unrelated fallback vectors preserved; Flutter uses live retrieval.';
const manifest = json('flutter_dataset_manifest.json');
manifest.counts.active_cards = cards.filter((card) => card.status === 'active').length;
manifest.counts.source_chunks = chunks.length;
manifest.counts.high_frequency_routes = routes.queries.length;
write('rag_cards/customer_service_rag_cards.jsonl', `${cards.map((card) => JSON.stringify(card)).join('\n')}\n`);
// Keep the source bundle's existing spaced JSONL format to limit audit diffs.
const spacedJson = (value) => JSON.stringify(value).replace(
  /("(?:\\.|[^"\\])*")|([,:])/g,
  (match, quoted, separator) => quoted ?? `${separator} `,
);
write('rag_cards/source_chunks.jsonl', `${chunks.map(spacedJson).join('\n')}\n`);
writeJson('rag_cards/high_frequency_queries.json', routes);
writeJson('rag_index/customer_service_rag_index.json', index);
writeJson('flutter_dataset_manifest.json', manifest);
console.log(`Synchronized ${cards.length} cards, ${chunks.length} source chunks, ${routes.queries.length} routes.`);
