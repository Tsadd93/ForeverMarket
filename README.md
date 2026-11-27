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

Use **Report** in Market Buy (or `/fm scanstatus`) for progress, first-deal time, rejection counts and up to three near misses. **Resume** continues an interrupted scan in the same session and venue. **Start** runs a new pass, including items screened out at an earlier budget. Verified offers compete for the fund as individual purchases and as several alternative baskets.

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

**First-session pricing.** On the sampled US Horde market, tooltips can use 2,950 additional dated base-item references while you build local history. These are display estimates. Starter buy candidates still use the narrower commodity sample and live confirmation. A paid sale shows the gross unit price on your latest qualifying invoice in the last 14 days, identified by character, market and item name. Variants can share an invoice name.

**Shopping.** In Browse, enter a category or search term, price limit, quality and target quantity. Click **Add filter to basket**. In **Tools → Basket**, choose **Run shopping list**. Exact item targets take precedence when rules overlap. Each filter applies its quantity to each matching item. The importer accepts Auctionator level, item-level, price, quality and quantity filters and category paths recognized by the client. Review skipped fields in the preview.

**Posting.** In **Browse → Trade groups**, enter four whole numbers in **Craft % / realm % / keep / listed cap**. For example, `120/80/4/10` floors your unit price at the higher of 120% of known material cost and 80% of recent realm bulk asks, keeps four units in bags and allows up to ten units listed. Zero disables that individual rule. Missing prices hold the item. **Apply & copy** creates a shareable Forever Market group. Existing FMG1 groups still work.

**Bank and mail.** Open **Tools → Mail & bank** while at your personal bank or on a viewable guild bank tab with withdrawals available. Click **Withdraw** for the displayed quantity. Each transfer requires a free general bag slot. An explicit item route can also stage personal-bank stock for its assigned recipient. At the mailbox the same queue groups attachments by recipient and updates after bag and mail changes.

**Continuous scanning.** Market Buy **Watch** repeats your favorites. **Radar** searches broadly among eligible items and alerts in chat when it verifies an affordable deal. **Stop** or closing the tab ends the scan. Radar alerts again when the price improves, more units qualify, or a qualifying offer returns. All purchases require a click.

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

## Optional Windows dashboard

[Download Forever Market Desktop for Windows x64](https://github.com/drixthegamer/ForeverMarket/releases/download/desktop-v0.8.0/ForeverMarket-Desktop-0.8.0-win-x64.exe) and double-click the EXE. It includes the addon and offline Microsoft runtime installers. On first launch, select your WoW Forever client folder if prompted.

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
