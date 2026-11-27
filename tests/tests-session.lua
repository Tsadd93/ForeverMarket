dofile('src/ItemNames.lua')
local now=100
time=function()return now end;GetTime=time;GetCurrentRegion=function()return 1 end
local events={}
CreateFrame=function()
 return {RegisterEvent=function()end,SetScript=function(_,_,fn)events[#events+1]=fn end}
end
local actor={desk={groups={},posting={},favorites={},searches={}},manager={samples={[20]={count=2,outputs={[10]=5}}}}}
ForeverMarketDB={};ForeverMarketCoins=tostring;ForeverMarketSaleNet=function(v)return math.floor(v*.95)end
local M={account=function()return actor end,scope=function()return 'realm' end,prices=function()return 20 end,
 inputs=function(r)return r.materials end,invalidate=function()end,destinations=function()return {'Bank'} end}
ForeverMarketTools=M
AuctionHouseFrame={IsShown=function()return true end}
local rows,sent,observed={},0,0
C_AuctionHouse={IsThrottledMessageSystemReady=function()return true end,HasFullBrowseResults=function()return true end,
 GetBrowseResults=function()return rows end,SendBrowseQuery=function(q)sent=sent+1;assert(q.searchString=='Ore')end}
local snap={books={[10]={low=40}}}
ForeverMarketReadySnapshot=function()return snap end
ForeverMarketHistory=function()return {} end
C_Item={GetItemNameByID=function(id)return id==10 and 'Ore' or 'Gear'end}
dofile('src/TradeDesk.lua');dofile('src/Session.lua');dofile('src/SessionViews.lua');dofile('src/PriceRules.lua');dofile('src/Migration.lua')
local actualPrint=print
print=function()observed=observed+1 end
assert(M.setPriceWatch(10,40));M.monitorPrices(true)
local function sample(price)
 now=now+16;M.watchTick();rows=price and {{itemKey={itemID=10},totalQuantity=1,minPrice=price}} or {}
 events[#events-1](nil,'AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
end
sample(41);sample(40);sample(40);sample(39);sample(nil);sample(40)
assert(sent==6 and observed==3)
C_AuctionHouse.GetItemKeyInfo=function()return {isCommodity=false} end
M.session().snipe=true
local starts=0
M.startMaterial=function(id,order) starts=starts+1;assert(order.cap==39 and order.n==1);M.quote={};return true end
sample(41);assert(starts==0)
sample(39);assert(starts==1 and M.quote.watch and M.quote.snipe)
M.watchTick();assert(starts==1);M.quote=nil
C_AuctionHouse.GetItemKeyInfo=function()return {isCommodity=true} end
sample(38);assert(starts==1 and M.watchPreview.price==38)
events[#events-1](nil,'AUCTION_HOUSE_CLOSED');assert(not M.priceMonitorActive())
local msg=M.watchRecipe({materials={[10]=1,[11]=1}});assert(msg:find('1 existing') and msg:find('1 without'))
assert(M.disenchantValue(20)==47)
M.prices=function()return nil end;assert(not M.disenchantValue(20))
print=actualPrint
ForeverMarketLibDeflate=dofile('vendor/LibDeflate/LibDeflate.lua')
ForeverMarketLibSerialize=dofile('vendor/LibSerialize/LibSerialize.lua')
LibStub={NewLibrary=function()ForeverMarketAceSerializer={};return ForeverMarketAceSerializer end};dofile('vendor/AceSerializer/AceSerializer.lua');LibStub=nil
local paths={['i:10']='Gear`Ore',['i:11']='Gear',['i:12:1']='Gear'}
local links={Gear={Auctioning={'Post'},Crafting={'Craft'}},['Gear`Ore']={Shopping={'Shop'}}}
local ops={Auctioning={Post={minPrice='max(120% crafting, 2g)',duration=24,keepQuantity=4,unsupported='review me'}},
 Shopping={Shop={maxPrice='50s'}},Crafting={Craft={maxRestock=20,minRestock=2}}}
local raw=ForeverMarketLibSerialize:Serialize('TSM_EXPORT',2,'Gear',paths,{},links,ops,{})
local packed=ForeverMarketLibDeflate:EncodeForPrint(ForeverMarketLibDeflate:CompressDeflate(raw))
local p=assert(M.decodeGroup(packed,'Imported'))
assert(not next(actor.desk.groups) and #p.skipped==3 and p.rules['Gear`Ore'].program.sell[1].tree)
M.applyMigration(p)
assert(M.groupPurchaseAllowed(10,M.group(10),5000,true))
assert(not M.groupPurchaseAllowed(10,M.group(10),5001,true))
assert(actor.desk.groups[11].minBatch==2)
assert(M.session().groupPaths[10]=='Gear`Ore' and actor.desk.posting[10].duration==2)
local legacy=ForeverMarketAceSerializer:Serialize({groupExport='group:Gear,i:11,group:Gear`Ore,i:10',groupOperations=links,operations=ops})
assert(M.decodeGroup(legacy,'Another').rules.Gear.reserve==4)
assert(not M.decodeGroup('just ordinary text','Test'))
local g=M.runOutcomes({flips={{run=1,cost=100,n=4,weekNet=80,weekPaid=2,weekLost=3},{run=2,cost=80,n=2}}})
assert(g[1].spent==100 and g[1].open==50 and g[1].profit==27 and g[2].profit==0 and g[2].open==80)
local collected=0
MailFrame=AuctionHouseFrame;AUCTION_EXPIRED_MAIL_SUBJECT='Auction expired: %s'
GetInboxNumItems=function()return 1 end;GetInboxItem=function()return 'Ore',10,nil,2 end
local cod=0;GetInboxHeaderInfo=function()return nil,nil,'AH','Auction expired: Ore',nil,cod end
TakeInboxItem=function()collected=collected+1 end
local row=M.returnLetters()[1];cod=5;M.collectReturn(row);assert(collected==0)
cod=0;M.collectReturn(row);M.collectReturn(row);assert(collected==1)
print('PASS: live price ceilings, monitored transitions, reagent watches, conversion evidence, compressed and legacy migration, scan attribution and mailbox checks')
