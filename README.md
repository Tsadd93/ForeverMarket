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

## Optional Windows dashboard

[Download Forever Market Desktop for Windows x64](https://github.com/drixthegamer/ForeverMarket/releases/download/desktop-v0.8.0/ForeverMarket-Desktop-0.8.0-win-x64.exe) and double-click the EXE. It includes the addon and offline Microsoft runtime installers. On first launch, select your WoW Forever client folder if prompted.

To connect your character, run an auction scan in WoW, then use `/fm export` and `/reload`. In the dashboard’s **Connections** tab, choose your TSM region, realm type, and faction and click **Link to selected market**. Live TSM pricing requires internet access.

## First session

1. Open a learned profession window to capture recipes on the current character.
2. At an auctioneer, open **Market Scan** and start a scan. Hover over a bag item to see vendor value and available auction pricing.
3. In **Market Sell**, review the stack quantity and suggested posting price. The scanner checks bulk supply so one unusually cheap unit need not set the price for the entire stack.
4. In **Market Buy**, set your trading fund and minimum estimated return. Start a scan to check live offers. A fresh install needs at least three prior days of history for an item to qualify.
5. In **Craft**, review material costs and estimated proceeds. Add recipes to your build list and use **Materials** to shop for the missing quantities.

Purchases and posts require player input. Estimated proceeds depend on an item selling. All core features work with the game addon alone.

## Publishing an addon update

Update the version in `ForeverMarket.toc` alongside addon changes on main. The release workflow runs the Lua simulations, compiles the bundled addon, and publishes the matching tagged Forever ZIP. Existing release versions are immutable.
