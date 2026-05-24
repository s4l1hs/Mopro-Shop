/**
 * Baseline profile: 50 VUs × 5 min — typical launch-day traffic.
 *
 * Weighted scenario distribution (D4 / R4):
 *   40% reads   → categories (10 VU) + products (15 VU) + search (15 VU) = 40
 *   20% address → addresses CRUD (10 VU)
 *   25% cart    → cart operations (13 VU)
 *   10% checkout→ checkout initiate (5 VU)
 *    5% auth    → otp_request (2 VU) + otp_verify (3 VU) = 5
 *                                                         ──────
 *                                                         50 VU total
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

export const options = {
  scenarios: {
    otp_request:  { executor: 'constant-vus', vus:  2, duration: '5m', exec: 'otpRequestTest',  gracefulStop: '10s' },
    otp_verify:   { executor: 'constant-vus', vus:  3, duration: '5m', exec: 'otpVerifyTest',   gracefulStop: '10s' },
    categories:   { executor: 'constant-vus', vus: 10, duration: '5m', exec: 'categoriesTest',  gracefulStop: '10s' },
    products:     { executor: 'constant-vus', vus: 15, duration: '5m', exec: 'productsTest',    gracefulStop: '10s' },
    search:       { executor: 'constant-vus', vus: 15, duration: '5m', exec: 'searchTest',      gracefulStop: '10s' },
    addresses:    { executor: 'constant-vus', vus: 10, duration: '5m', exec: 'addressesTest',   gracefulStop: '10s' },
    cart:         { executor: 'constant-vus', vus: 13, duration: '5m', exec: 'cartTest',        gracefulStop: '10s' },
    checkout:     { executor: 'constant-vus', vus:  5, duration: '5m', exec: 'checkoutTest',    gracefulStop: '10s' },
  },
  thresholds:         SLO_THRESHOLDS,
  summaryTrendStats:  SUMMARY_TREND_STATS,
};

export {
  otpRequestTest, otpVerifyTest, categoriesTest, productsTest,
  searchTest, addressesTest, cartTest, checkoutTest,
  handleSummary,
};
