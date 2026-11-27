# Forever Market field results

The local production desktop ledger recorded 152 posting events, 9 purchase events, 122 sale notices, and 8 wallet collections between 2026-11-21 21:15 UTC and 2026-11-24 05:50 UTC. Recorded seller collections totaled **4g 91s 46c**. This is collected auction income. Purchase basis and lost deposits must be matched before reporting net trading profit.

The installed game's saved scan ledger contained one interrupted pass on 2026-11-27 08:35 UTC. Starting budget was 0g at a 5% target. Over 33 seconds it recorded zero detail checks, zero unanswered checks and zero deals. There were no purchases attributed to this pass, so attributed spend, inventory at cost and realized profit were all zero. This pass does not measure scanner speed with a funded account.

## Reproducing a competitive comparison

1. At the same auctioneer, open Market Buy and run the 1g, 5g and 50g benchmarks from Scan outcomes, with the same percentage target. Keep the window open until each pass completes.
2. Use `/fm benchlist` to copy the sampled items. Run the other addon's shopping scan on those IDs with the same budget, venue and price criteria. Record elapsed time, time to first actionable quote, unresolved lookups and qualifying IDs. Alternate which addon runs first on subsequent pairs to reduce listing-order bias.
3. In Scan outcomes open the run, then Compare. Record the competitor's results. Review common deals and deals found by only one scanner. Report incomplete pairs and zero-result passes too.
4. For actual trading, review matched seven-day collections, allocated costs, lost deposits and remaining inventory at cost in Run detail. Benchmark mode never purchases items.

As of this sample there were no saved paired competitor timings or matched seven-day purchases from a funded run. A speed ranking and a realized return on starting capital are still unmeasured.
