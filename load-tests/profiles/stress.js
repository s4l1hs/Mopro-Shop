/**
 * Stress profile: ramp 0→200 VUs over 5 min, hold 5 min — find the knee.
 * ⚠️  WARN SALIH BEFORE RUNNING — impacts production if real users exist.
 *
 * Distribution mirrors baseline but scaled 4× to find saturation point.
 * Watch VDS CPU and memory during the hold phase.
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

function rampStages(peakVus) {
  return [
    { duration: '2m30s', target: Math.round(peakVus * 0.5) },
    { duration: '2m30s', target: peakVus },
    { duration: '5m',    target: peakVus },
    { duration: '30s',   target: 0 },
  ];
}

// Relaxed thresholds for stress: we want to observe degradation, not fail early.
const stressThresholds = {
  'http_req_duration{type:read}':  ['p(99)<3000'],
  'http_req_duration{type:write}': ['p(99)<5000'],
  'http_req_failed':               ['rate<0.02'],
};

export const options = {
  scenarios: {
    otp_request:  { executor: 'ramping-vus', stages: rampStages(10), exec: 'otpRequestTest',  gracefulRampDown: '30s' },
    otp_verify:   { executor: 'ramping-vus', stages: rampStages(12), exec: 'otpVerifyTest',   gracefulRampDown: '30s' },
    categories:   { executor: 'ramping-vus', stages: rampStages(40), exec: 'categoriesTest',  gracefulRampDown: '30s' },
    products:     { executor: 'ramping-vus', stages: rampStages(60), exec: 'productsTest',    gracefulRampDown: '30s' },
    search:       { executor: 'ramping-vus', stages: rampStages(60), exec: 'searchTest',      gracefulRampDown: '30s' },
    addresses:    { executor: 'ramping-vus', stages: rampStages(40), exec: 'addressesTest',   gracefulRampDown: '30s' },
    cart:         { executor: 'ramping-vus', stages: rampStages(50), exec: 'cartTest',        gracefulRampDown: '30s' },
    checkout:     { executor: 'ramping-vus', stages: rampStages(20), exec: 'checkoutTest',    gracefulRampDown: '30s' },
  },
  thresholds:        stressThresholds,
  summaryTrendStats: SUMMARY_TREND_STATS,
};

export {
  otpRequestTest, otpVerifyTest, categoriesTest, productsTest,
  searchTest, addressesTest, cartTest, checkoutTest,
  handleSummary,
};
