/**
 * Smoke profile: 5 VUs × 30 s — "does it work at all?"
 * Runs all 8 scenarios at minimal concurrency. All SLOs must pass.
 */
import { sleep } from 'k6';
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

export const options = {
  scenarios: {
    otp_request:  { executor: 'constant-vus', vus: 1, duration: '30s', exec: 'otpRequestTest',  gracefulStop: '5s' },
    otp_verify:   { executor: 'constant-vus', vus: 1, duration: '30s', exec: 'otpVerifyTest',   gracefulStop: '5s' },
    categories:   { executor: 'constant-vus', vus: 1, duration: '30s', exec: 'categoriesTest',  gracefulStop: '5s' },
    products:     { executor: 'constant-vus', vus: 1, duration: '30s', exec: 'productsTest',    gracefulStop: '5s' },
    search:       { executor: 'constant-vus', vus: 1, duration: '30s', exec: 'searchTest',      gracefulStop: '5s' },
    addresses:    { executor: 'constant-vus', vus: 1, duration: '30s', exec: 'addressesTest',   gracefulStop: '5s' },
    cart:         { executor: 'constant-vus', vus: 1, duration: '30s', exec: 'cartTest',        gracefulStop: '5s' },
    checkout:     { executor: 'constant-vus', vus: 1, duration: '30s', exec: 'checkoutTest',    gracefulStop: '5s' },
  },
  thresholds:         SLO_THRESHOLDS,
  summaryTrendStats:  SUMMARY_TREND_STATS,
};

export {
  otpRequestTest, otpVerifyTest, categoriesTest, productsTest,
  searchTest, addressesTest, cartTest, checkoutTest,
  handleSummary,
};
