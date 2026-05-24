/**
 * Spike profile: instant 500 VUs for 1 min — burst handling.
 * ⚠️  WARN SALIH BEFORE RUNNING — hard burst to simulate flash sale.
 *
 * Only runs read-heavy scenarios (categories + products + search) since
 * writes under spike would saturate pgbouncer pool and give false negatives.
 * OTPs are excluded (rate limit would fire immediately at spike scale).
 */
import { SLO_THRESHOLDS, SUMMARY_TREND_STATS } from '../k6.config.js';
import { categoriesTest }  from '../scenarios/03-categories.js';
import { productsTest }    from '../scenarios/04-products.js';
import { searchTest }      from '../scenarios/05-search.js';
import { cartTest }        from '../scenarios/07-cart.js';
import { handleSummary }   from '../lib/summary.js';

// Very relaxed: we care about survival, not SLO compliance during spike.
const spikeThresholds = {
  'http_req_duration{type:read}':  ['p(99)<5000'],
  'http_req_failed':               ['rate<0.05'],
};

export const options = {
  scenarios: {
    categories: { executor: 'constant-vus', vus: 200, duration: '1m', exec: 'categoriesTest', gracefulStop: '10s' },
    products:   { executor: 'constant-vus', vus: 150, duration: '1m', exec: 'productsTest',   gracefulStop: '10s' },
    search:     { executor: 'constant-vus', vus: 100, duration: '1m', exec: 'searchTest',     gracefulStop: '10s' },
    cart:       { executor: 'constant-vus', vus:  50, duration: '1m', exec: 'cartTest',       gracefulStop: '10s' },
  },
  thresholds:        spikeThresholds,
  summaryTrendStats: SUMMARY_TREND_STATS,
};

export {
  categoriesTest, productsTest, searchTest, cartTest,
  handleSummary,
};
