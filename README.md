# Forever Market

An auction house and profession addon for World of Warcraft Forever. Scan your realm, inspect the value of a stack in your bags, find resale opportunities within your budget, and price crafts using your learned recipes.

## Install with WowUp

Select **WoW Forever**, open **Get Addons → Install from URL**, and paste **https://github.com/drixthegamer/ForeverMarket**. For a manual install, extract the release ZIP into your Forever client's Interface/AddOns folder.

## Updates and version checks

Open **My Addons** in WowUp to update an existing GitHub installation. In game, Forever Market announces a newer version when a guild or group member running a version-aware build reports it. The notice appears once per newer version. Type `/fm version` to see your installed version and the latest version reported to you.

Live sync to the optional desktop dashboard is off by default. Type `/fm sync on` to show the colored data strip or `/fm sync off` to hide it. You can also toggle it in **Manage auctions**. With the strip off, your in-game ledger still tracks activity and the dashboard can import saved data after a reload or logout.

Item prices appear on standard item tooltips, including chat links. Bag tooltips show both unit and stack values. Links without a stack count show unit values.

## Auction tools

At the auction house, use `/fm manage` to review undercuts, inspect an item's ledger, and open **Browse** for saved searches, vendor deals, and live purchase quotes. **Market Sell** supports editable quantities and **Post next**. **Market Buy → Watch** checks favorite items. Craft planning can use last-seen inventory across characters, and trade groups share stocking and posting settings.

### Holding investments and reviewing sales

Use **Market Buy → Invest** to look for commodity price dips. The model requires at least 14 observed bulk-price days, three earlier recoveries, and at least 80% of qualifying historical dips returning to 95% of their previous baseline within three days. It checks the current bulk price and your margin after fees. Investment inventory uses up to 20% of available trading capital under this strategy. Hover over a result for its history. The recovery target is an estimated future exit.

Market Sell remembers quotes separately for each auction market. Right-click an item name to check it again, or click **Refresh** to recheck the list. Auctions shows active listings, gross sold value, last-seen sale mail, estimated pending proceeds when identifiable, and wallet-confirmed collections for the current character.

**Manage auctions → Ledger → Fund flips** tracks confirmed Market Buy purchases from version 0.12.0 onward. Open a purchase to compare forecast and realized profit, remaining inventory cost, and wallet collections. Identical units are attributed in purchase order. Mail receipts lack auction IDs, so indistinguishable same-price sales use posting order among eligible sales. Outside-fund sales stay in the item ledger.

Market Buy weighs recent sales, time to sale, expirations and older unresolved listings when prioritizing eligible offers. A gold exclamation mark in Market Sell flags an item that expired in the past 14 days. Hover for its return count and any confirmed fund deposits lost.

**Ledger → Investment tests** shows whether later bulk quotes reached a displayed investment's original exit within three days. It counts hits, observed misses and incomplete windows separately. Actual proceeds appear under **Fund flips** when you collect the mail.

### Planning a session

Use **Scan tools → Scan report** in Market Buy (or `/fm scanstatus`) for progress, first-deal time, rejection counts and up to three near misses. **Resume** continues an interrupted scan in the same session and venue. **Find flips** runs a new pass, including items screened out at an earlier budget. Verified offers compete for the fund as individual purchases and as several alternative baskets.

Click a Buy or Sell item name for a persistent item tooltip. Where available, it shows the observed ask, source and age, net proceeds, vendor price, and the current character's quantity-weighted sale price from paid invoices over the past 14 days. Receipts identify items by name. **Market Sell → Price** switches the default between matching bulk and undercutting. Item margin rules can already specify matching. Posting comparisons count sale notifications and report time to the first notification. These are observations of your own listings.

**Craft → Restock** targets three days of stock from the last seven days of collected unit sales. It accounts for bags, auctions, queued output, reagent depth and available funds. Review the suggested quantity and click **Add** to queue it. Recipe tooltips compare buying the finished output, crafting it, and selling the materials. When sales history is empty, use the manual Recipes tab.

Invest compares subsequent bulk quotes against the frozen exit on the next three UTC market days. Incomplete windows without an observed recovery are tracked separately in forward tests. Beta clients with a blank realm name use a realm identifier. A legacy blank history is recovered automatically when saved character identities agree on the current realm.

## Market tools

Open **Tools** from the manager or type `/fm tools`.

- **Basket** combines shopping requirements for this character and shows quantities already covered, live availability and the cost of a partial fill. Review the quantity and confirm the live quote. **Vendor deals** checks offers against vendor proceeds.
- **Mail & bank** lets you choose a known bank alt, reserve quantities and prepare a shipment. Check the draft and send it through the normal mailbox. At the bank, use the withdrawal list to gather missing stock.
- **Supply plan** compares buying, vendor bundles and crafting with recipes recorded across your characters. Open professions on each crafter and visit banks and merchants to record stock and offers. Save a plan for the craft order and add its auction ingredients to your shopping list.
- **History** charts seven or thirty days of observed asks, available quantities and your paid sales when available. Shift-click an item name on Market Buy or Sell to open its chart.
- **Farming** records timed loot sessions. Compare estimated hourly vendor or auction returns with proceeds actually attributed to the session. When identical farmed and pre-existing items mix, attribution uses the recorded quantities in order.
- **Import** previews supported Auctionator shopping lists and TSM item-ID lists before saving. Review skipped entries and unresolved names before applying. Pricing formulas and advanced search filters require separate setup.

The starter reference covers 100 commodities on the sampled US Horde Forever market. It expires after 21 days. Other markets can use local scans and live vendor deals. In the manager, review undercuts alongside competing quantity, deposit cost and recent sales before deciding whether to relist.

## Mixed shopping lists, posting rules and deal alerts

**First-session pricing.** On the sampled US Horde market, tooltips can use 2,950 additional dated base-item references after your first completed scan. These are display estimates. Starter buy candidates still use the narrower commodity sample and live confirmation. A paid sale shows the gross unit price on your latest qualifying invoice in the last 14 days, identified by character, market and item name. Variants can share an invoice name.

**Shopping.** In Browse, enter a category or search term, price limit, quality and target quantity. Click **Add filter to basket**. In **Tools → Basket**, choose **Run shopping list**. Exact item targets take precedence when rules overlap. Each filter applies its quantity to each matching item. The importer accepts Auctionator level, item-level, price, quality and quantity filters and category paths recognized by the client. Review skipped fields in the preview.

**Posting.** In **Browse → Trade groups**, enter four whole numbers in **Craft % / realm % / keep / listed cap**. For example, `120/80/4/10` floors your unit price at the higher of 120% of known material cost and 80% of recent realm bulk asks, keeps four units in bags and allows up to ten units listed. Zero disables that individual rule. Missing prices hold the item. **Apply & copy** creates a shareable Forever Market group. Existing FMG1 groups still work.

**Bank and mail.** Open **Tools → Mail & bank** while at your personal bank or on a viewable guild bank tab with withdrawals available. Click **Withdraw** for the displayed quantity. Each transfer requires a free general bag slot. An explicit item route can also stage personal-bank stock for its assigned recipient. At the mailbox the same queue groups attachments by recipient and updates after bag and mail changes.

**Continuous scanning.** Under **Market Buy → Scan tools**, **Watch favorites** repeats your favorites. **Watch market** searches broadly among eligible items and alerts in chat when it verifies an affordable deal. **Stop** or closing the tab ends the scan. Radar alerts again when the price improves, more units qualify, or a qualifying offer returns. All purchases require a click.

**Live comparison.** Open Market Buy, set the fund and target, and type `/fm benchmark` to check up to 50 eligible items once. Once a full sample is available, subsequent runs use the same IDs for the venue. `/fm benchlist` displays the names for copying into another shopping addon. `/fm watchreport` reports time to first deal, elapsed time, checked items and unanswered lookups for recent completed passes. Comparisons should use the same cash, price criteria and venue. Listings can change between runs.

## From purchase to payout

Market Buy checks ordinary flips against protected items, crafting and bag reserves, group posting caps and floors, existing fund costs, vendor value and pinned Sell quotes. The quantity uses recent paid units on your market, your existing stock and outstanding orders. Sparse history starts with a small trial of up to five units, or one after an expiration without a recent paid sale. If the flip needs the whole cheap tier to clear and you can only sell part of it, Buy skips it. Invest retains its separate recovery and capital rules. Hover over a Buy row for its demand figures, or use `/fm scanstatus` for an example of a rejected resale.

Basket totals add the quantities available within your targets, caps, observed supply and spendable cash, in the displayed item order. An accepted live quote updates the total. Remaining units are displayed separately.

Click the four balances on Market Buy for **Spendable**, **Stock cost**, **Due est.** and **Realized**. Spendable explains the cash balance, reservations, outstanding deposits and any reconciliation difference. Its journal keeps the latest 500 cash movements and carries earlier movements into an opening balance. Existing funds start the journal at their current cash. Sold stock stays at cost for reconciliation until collection. Pending proceeds are estimates. The realized ledger includes matched payouts and confirmed losses, and lists receipts outside matched fund sales separately.

## Home, trading results and gear prices

Open **Market Scan → Market home** or type `/fm home` to reach buying, selling, auction review and Results. **Market Sell → Preview** lists the price or hold reason for each stack before posting. The preview reflects the current sell checks. Open **Results** or type `/fm results` to switch between 7 and 30 days and between flips and investments.

Results groups purchases by purchase date and follows their payouts through today. Purchase cost includes the entire purchase. Profit collected deducts the cost of paid units and confirmed losses. Stock at cost shows the remainder still awaiting payout. Forecast comparisons cover paid units. First payout shows the median time from purchase to its first confirmed collection, using purchases with a recorded first payout. Older purchases without that timestamp still count toward the gold totals.

Gear tooltips show median asking prices for the same item, level and suffix when item searches have captured them. Other suffixes at the same level have a separate middle range. Daily samples prevent one busy day from dominating the estimate. Mail receipts identify sales by name. Group posting rules now use the median daily bulk ask for their realm-price floor.

Market Buy starts cautiously on an item with no paid sales. It can raise the trial quantity after repeat sales with fast observed turnover and no recent expirations. Radar alerts when a verified unit price improves, affordable quantity grows, or a deal qualifies again after a checked offer disappears. At the end of a scan, **Retry** checks unanswered items first by estimated opportunity where available.

## Selling sessions, price watches and switching addons

Open **Market home** or type `/fm home`. **Selling session** remembers your current step for this character and auction market. Open it above Market Sell to post a reviewed stack or inspect a held stack. Use **Go to step** for undercut review. At the mailbox, **Collect** rechecks the displayed returned attachment and its COD before requesting it. Advance to relisting when ready. **Time a selling pass** records elapsed time and confirmed posts across auction interfaces. Clients that expose mouse events also count clicks while the auction house or mailbox is visible.

**Price watches** (`/fm watch`) accepts a link, item ID or name and a maximum unit price such as `40c`. Right-click a Browse result to select it, or right-click a recipe in Craft to watch reagents at their latest scanned asks. Existing ceilings are preserved. **Start watching** checks exact item IDs in rotating name searches while the page and auction house are open. Other browse searches pause the monitor. Choose a watch and **Check live quote** to request one unit. **Confirm purchase** rechecks the displayed total. The watch lists how often a requested quote was within its ceiling.

**Realm coverage** summarizes local pricing by category, including how many base items have at least three bulk-price days in the last fourteen. **Disenchant deals** compares the purchase ask with vendor value, repost net, and expected material proceeds from your own observed yields. Review the yield count, average material quantities and prices before buying. Sparse samples can give misleading returns.

**Import** previews current TSM version 2 group exports, supported legacy AceSerializer exports, plain group paths and optionally a loaded TSM profile. Enter the profile name at right for **Read TSM profile**. Preview shows group membership, mapped settings and calculated posting floors. **Show skipped** lists unsupported formulas, variants, custom sources and unresolved operations. Supported rules include fixed buy ceilings, posting floors, a maximum of supported floor expressions, crafting-cost percentages, stack sizes, durations and selected restock, mailing and bank quantities. New imports keep the original market source by default. A missing required input holds the affected action. **Review choices** offers local-price presets, ordered-operation choices and known mail recipients. Choosing **Use local** substitutes your realm’s median bulk ask for the imported market price sources throughout that import. Existing 0.18 groups keep their pricing until you reimport them.

The importer resolves named price definitions, arithmetic, percentages, nested min/max/avg, first-valid fallbacks and ifgt/ifgte/iflt/iflte/ifeq conditions for shopping ceilings and posting floors. The preview shows the chosen operation and compares its price with the scanned ask or proposed posting price. Imported posting floors hold listings priced below the floor. A false condition without an else can advance to the next operation. A missing comparison input holds the decision. Ambiguous assignments can be narrowed to one named operation. Unsupported price formulas can be assigned a replacement floor or ceiling in **Review choices**. Recipient mappings and formula replacements apply to all matching groups and are remembered on Apply. Applying overlays the displayed settings on your current per-item rules. **Group rules** on Home previews plain-language presets for an item or imported group before applying them.

**Scan outcomes** (`/fm trials`) records completed and interrupted passes, including zero deals, starting cash, first-deal timing, elapsed time and unanswered lookups. Matched purchases made after the update keep their originating scan. Seven-day profit counts money actually collected in the first seven days after each purchase, allocated cost, and confirmed losses. Remaining inventory is shown at cost. A zero-purchase scan has no realized profit.

From **Scan outcomes**, choose **Test 1 gold**, **Test 5 gold**, or **Test 50 gold** at an auctioneer. **Test all three** runs the three budgets in succession while Market Buy stays open. These read-only benchmarks run the scanner with a hypothetical budget and keep your real fund unchanged. Use **Compare** to enter another addon's qualifying IDs and elapsed seconds for the same sampled list, price criteria and venue. Differences between consecutive runs can include listing changes. Timed comparisons and seven-day collection results require actual player sessions.

## Optional Windows dashboard

[Download Forever Market Desktop for Windows x64](https://github.com/drixthegamer/ForeverMarket/releases/download/desktop-v0.9.0/ForeverMarket-Desktop-0.9.0-win-x64.exe) and double-click the EXE. It includes the addon and offline Microsoft runtime installers. On first launch, select your WoW Forever client folder if prompted.

To connect your character, run an auction scan in WoW, then use `/fm export` and `/reload`. In the dashboard’s **Connections** tab, choose your TSM region, realm type, and faction and click **Link to selected market**. Live TSM pricing requires internet access.

## First session

1. Open a learned profession window to capture recipes on the current character.
2. At an auctioneer, open **Market Scan** and start a scan. Hover over a bag item to see vendor value and available auction pricing.
3. In **Market Sell**, review the stack quantity and suggested posting price. The scanner checks bulk supply so one unusually cheap unit need not set the price for the entire stack.
4. In **Market Buy**, set your trading fund and minimum estimated return. Start a scan to check live offers. On a matching market, a recent bundled reference can help identify candidates while local scan history builds. Buy checks still require a live offer.
5. In **Craft**, review material costs and estimated proceeds. Add recipes to your build list and use **Materials** to shop for the missing quantities.

Purchases and posts require player input. Estimated proceeds depend on an item selling. All core features work with the game addon alone.

## Publishing an addon update

Update the version in `ForeverMarket.toc` alongside addon changes on main. The release workflow runs the Lua simulations, compiles the bundled addon, and publishes the matching tagged Forever ZIP. Existing release versions are immutable.

### Quick quotes, cancel queue and price integrations (0.20.0)

* At the auctioneer, open `/fm watch`, save unit-price ceilings, switch **Quick quotes** on and click **Start watching**. Keep Watches open. When an ask qualifies, the addon stages a single-item gear quote or highlights a commodity for **Get firm quote**. It sounds the ready check if enabled in WoW. Click **Confirm purchase** while the quote is current. Watch speed depends on the number of items, competition and the AH throttle. Market Buy also has a broader market watch.
* **My Auctions > Manage auctions > Scan cancels** walks your active buyouts in a stable order. **Cancel shown** submits one cancellation. The status shows the competitor's unit price and the deposit at risk. The queue waits for removal, then advances. It skips bids, unknown deposits, positive cancellation fees, mismatched variants, incomplete or unanswered searches and relists below the vendor threshold. A shared book serves consecutive matching listings for up to ten seconds. The result counts removed and skipped listings.
* Addon authors can declare `## OptionalDeps: ForeverMarket` and call `ForeverMarketAPI.GetPrice(itemIDOrLink, maxAgeSeconds)`. It returns the base item's unit market price in copper, observation timestamp and source, or nil if unavailable. The optional age limit applies to historical estimates too. Linked gear returns a base-item estimate. GECTemplate bridge consumers can use `{forevermarket.price(2589)}` and `{forevermarket.age(2589)}`. Other consumers can add Forever Market to their price-provider list.
* Imported formulas can reference TSM shopping, auctioning and sniper operation prices plus supported purchase, sale, material and vendor sources when the TSM addon supplies them. Missing inputs remain unresolved. Standalone players can keep using native presets and local history.

### Selling, buying reagents and refreshing prices

On Market Sell, check the box beside an item to protect every stack of that item on this character. Uncheck it on any stack to allow posting again. Post next and Post held both respect protection.

On Craft > Build list, the reagent rows combine requirements across queued recipes. Click Check beside a missing reagent, review the live quantity and total, then click Buy. Covered reagents stay visible. The recipe rows still let you remove a planned craft.

Click Scan market for a fresh pass. When the realm snapshot is on cooldown, the addon requests current browse results and saves the observed asks and supply. The server controls how quickly those results arrive.

### Dashboard and auction analytics

Type `/fm` or `/fm dash` anywhere to open the full dashboard. Overview balances drill down into their records. Sales & profit, Item history, Watchlist and Research offer 7-, 14- and 30-day views. Forward-test totals are labeled lifetime. The Tools section opens trading workflows; Settings includes fund allocation, profit target, fees, stock and optional live sync. The auction house Analytics tab offers browsing and item lookup only. `/fm analytics` also opens reports away from the auctioneer.

Desktop 0.9.0 includes the latest matching simulation summary with the existing ranked research feed; reload WoW after sync. Modeled profits are distinct from collected gold. Local reports work independently. Auction-house closure schedules a batched export. `/fm export` explicitly requests one; logout or reload saves the latest data.

Market Sell marks a full stack red with **SELL** in the native bags when the vendor pays at least the estimated auction return. Use **Clear vendor marks** beside an open bag to dismiss the current recommendations. A new price check can flag a stack again.


## First scan, route planning, and trading evidence (0.24.0)

Open Market Scan and finish one scan at the auctioneer for each market. The dashboard prompts on first use. An already saved complete market snapshot counts. Incomplete scans do not unlock advice. The sampled starter feed can provide a dated tooltip reference after onboarding. A seeded Buy lead also needs a recent local bulk observation and a live check.

Buy rows show fourteen-day sale notices and expirations with mean time to sale where matched postings exist. An item without recorded outcomes shows its observed price days. These figures describe recorded market activity for your account.

In Farming, choose **Routes by gold/hour**. Finished runs with the same route name and zone are combined. Loot is repriced at current local estimates, weighted by total recording time. **Details** shows observed gathering methods, price coverage, actual proceeds and vendor value. A route with missing prices can be underestimated.

In Import, preview a TSM group and click **Compare** beside an item. The original operation expressions are evaluated by TSM when its API is available. Forever Market shows its imported ceiling/floor and the price decision against the same snapshot. Original operation constraints outside the supported translation still require review in Show skipped.

Scan outcomes supports recording a paired external scan. Enter total seconds alone or total / first deal / unanswered, with a dash for no first deal. The [field results](FIELD-RESULTS.md) distinguish captured trading receipts, realized returns, interrupted scans and missing comparisons.

### Shopping, shared prices and custom rules in 0.25

At an auctioneer, use **/fm sell** and switch **All items** to **Ready only** to work through postable stacks. Use **/fm shop** to pick a saved shopping list and check the quantities you still need. Review the live offer before clicking Buy.

**/fm rules** previews a buying ceiling or selling floor for one item or an imported group path. For example, `iflt(fmbags,20,80% fmmedian);1c` uses 80% of the local median while you hold fewer than 20 units and the median is available. The fallback ceiling is one copper. Choose Buy or Sell, preview, then apply. Use a name such as `user_ore` to save a reusable expression. Reapply dependent rules after editing a named expression. TSM-specific sources outside the standalone set require TSM or a configured fallback.

On **Market Scan**, click a heading to sort and right-drag a heading to resize its column. **Compare asks** cycles the last column through the median, exponential moving average and outlier-filtered mean of local daily bulk asks. A reading of 80% means the current lowest ask is four fifths of that model price. Click an item and choose **Price analysis** for the observation count, range and distribution. Missing days contribute no samples. A single observed day supplies little evidence for a flip.

**/fm references** shows dated prices before the first scan. You can copy or import a realm price pack or request an item quote from a guildmate running Forever Market with guild replies enabled. Peer packs must match region, realm, faction and auction venue and expire in seven days. The release also includes a regional sample of up to 1,000 high-volume items per supported region from [TradeSkillMaster public data](https://tradeskillmaster.com/public-data). Select **Sales** for the regional sale rate and units sold per day. Sample observations expire after seven days. Maintainers can refresh the bundled snapshot with `python refresh_region_prices.py` before packaging. A completed local scan unlocks trading advice, and Buy checks the live offer.
