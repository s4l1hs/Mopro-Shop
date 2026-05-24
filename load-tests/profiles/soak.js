/**
 * Soak profile: 50 VUs × 30 min — memory leaks, connection pool exhaustion.
 * OPTIONAL for this phase. Run manually when stability is a concern.
 * Same load level as baseline but sustained for 30 minutes.
 */
import { SLO_THRESHOLDS, SUMMARY_TREND_STATS } from '../k6.config.js';
import { otpRequestTest }  from '../scenarios/01-otp-request.js';
import { otpVerifyTest }   from '../scenarios/02-otp-verify.js';
import { categoriesTest }  from '../scenarios/03-categories.js';
import { productsTest }    from '../scenarios/04-products.js';
import { searchTest }      from '../scenarios/05-search.js';
import { addressesTest }   from '../scenarios/06-addresses.js';
import { cartTest }        from '../scenarios/07-cart.js';
import { checkoutTest }    from '../scenarios/08-checkout.js';
import { handleSummary }   from '../lib/summary.js';

// Slightly relaxed p99 for long soak (GC pauses are normal).
const soakThresholds = {
  ...SLO_THRESHOLDS,
  'http_req_duration{type:read}':  ['p(50)<100', 'p(95)<300', 'p(99)<2000'],
  'http_req_duration{type:write}': ['p(50)<200', 'p(95)<500', 'p(99)<4000'],
};

export const options = {
  scenarios: {
    otp_request:  { executor: 'constant-vus', vus:  2, duration: '30m', exec: 'otpRequestTest',  gracefulStop: '30s' },
    otp_verify:   { executor: 'constant-vus', vus:  3, duration: '30m', exec: 'otpVerifyTest',   gracefulStop: '30s' },
    categories:   { executor: 'constant-vus', vus: 10, duration: '30m', exec: 'categoriesTest',  gracefulStop: '30s' },
    products:     { executor: 'constant-vus', vus: 15, duration: '30m', exec: 'productsTest',    gracefulStop: '30s' },
    search:       { executor: 'constant-vus', vus: 15, duration: '30m', exec: 'searchTest',      gracefulStop: '30s' },
    addresses:    { executor: 'constant-vus', vus: 10, duration: '30m', exec: 'addressesTest',   gracefulStop: '30s' },
    cart:         { executor: 'constant-vus', vus: 13, duration: '30m', exec: 'cartTest',        gracefulStop: '30s' },
    checkout:     { executor: 'constant-vus', vus:  5, duration: '30m', exec: 'checkoutTest',    gracefulStop: '30s' },
  },
  thresholds:        soakThresholds,
  summaryTrendStats: SUMMARY_TREND_STATS,
};

export {
  otpRequestTest, otpVerifyTest, categoriesTest, productsTest,
  searchTest, addressesTest, cartTest, checkoutTest,
  handleSummary,
};
