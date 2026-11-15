// Usage: node loadtest.js <api-base-url> [concurrency=20] [seconds=60]
// Needs Node 18+. Run it from an instance in the same VPC (reach it with SSM Session Manager).
const base = process.argv[2] || 'http://localhost:3000';
const conc = +process.argv[3] || 20;
const secs = +process.argv[4] || 60;
const ri = (n) => 1 + Math.floor(Math.random() * n);
const mix = [
  { name: 'customer_loans', w: 60, run: () => fetch(`${base}/api/customers/${ri(100000)}/loans`) },
  { name: 'loan_repayments', w: 25, run: () => fetch(`${base}/api/loans/${ri(300000)}/repayments`) },
  { name: 'loan_application', w: 10, run: () => fetch(`${base}/api/loans`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ customer_id: ri(100000), principal: 20000 + ri(80000) }) }) },
  { name: 'portfolio_report', w: 5, run: () => fetch(`${base}/api/reports/portfolio`) },
];
const pick = () => { let r = Math.random() * 100; for (const m of mix) { if ((r -= m.w) < 0) return m; } return mix[0]; };
const res = Object.fromEntries(mix.map((m) => [m.name, { t: [], err: 0 }]));
const end = Date.now() + secs * 1000;
async function worker() {
  while (Date.now() < end) {
    const m = pick(); const t = performance.now();
    try { const r = await m.run(); await r.arrayBuffer(); if (!r.ok) res[m.name].err++; } catch { res[m.name].err++; }
    res[m.name].t.push(performance.now() - t);
  }
}
const pct = (a, p) => a.length ? a.sort((x, y) => x - y)[Math.min(a.length - 1, Math.floor(a.length * p))] : 0;
(async () => {
  console.log(`Load test: ${base}  concurrency=${conc}  duration=${secs}s`);
  await Promise.all(Array.from({ length: conc }, worker));
  const out = {}; let total = 0;
  for (const [k, v] of Object.entries(res)) {
    total += v.t.length;
    out[k] = { requests: v.t.length, errors: v.err, p50_ms: Math.round(pct(v.t, .5)), p95_ms: Math.round(pct(v.t, .95)), p99_ms: Math.round(pct(v.t, .99)) };
  }
  console.table(out);
  console.log(`Total requests: ${total}  Throughput: ${(total / secs).toFixed(1)} req/s`);
  require('fs').writeFileSync(`loadtest-${new Date().toISOString().replace(/[:.]/g, '-')}.json`, JSON.stringify(out, null, 2));
})();
