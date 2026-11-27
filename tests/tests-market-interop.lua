local now=100
time=function()return now end
GetTime=time
UnitFactionGroup=function()return 'Horde' end
local callbacks={}
CreateFrame=function()return {RegisterEvent=function()end,SetScript=function(_,_,fn)callbacks[#callbacks+1]=fn end} end
local tokens,registrations
LibStub={GetLibrary=function()return {Bridge=_G.bridge} end}
bridge={Register=function(key,feed)assert(key=='forevermarket');tokens=feed.tokens;registrations=(registrations or 0)+1 end}
local M={prices=function(id)if id==25 then return 88,80,'Last scan',90 end end}
ForeverMarketTools=M
ForeverMarketDB={}
dofile('src/PublicPrices.lua')
assert(ForeverMarketAPI.GetPrice('|Hitem:25:0|h[Ore]|h')==90)
assert(not ForeverMarketAPI.GetPrice(25,19) and not ForeverMarketAPI.GetPrice(26))
callbacks[1]();assert(registrations==1 and tokens.price.get(25)==90 and tokens.age.get(25)==0)
dofile('src/PriceRules.lua')
assert(M.compilePrice('min(auctioningopmin,smartavgbuy)'))
assert(not M.ruleSource(25,'smartavgbuy',true))
TSM_API={GetCustomPriceValue=function(key,item)assert(item=='i:25' and key=='smartavgbuy');return 890 end}
assert(M.ruleSource(25,'smartavgbuy',true)==890)
local key={itemID=25}
local rows={}
for i=1,3 do rows[i]={auctionID=i,itemKey=key,status=0,quantity=1,unitPrice=100} end
local clicks,queries=0,0
C_AuctionHouse={GetNumOwnedAuctions=function()return #rows end,GetOwnedAuctionInfo=function(i)return rows[i] end,
  IsThrottledMessageSystemReady=function()return true end,GetItemKeyInfo=function()return {isCommodity=true} end,
  SendSearchQuery=function()queries=queries+1 end,GetCancelCost=function()return 0 end,CanCancelAuction=function()return true end,
  HasFullCommoditySearchResults=function()return true end,GetNumCommoditySearchResults=function()return 1 end,
  GetCommoditySearchResultInfo=function()return {quantity=4,unitPrice=80} end,CancelAuction=function(id)assert(id==1);clicks=clicks+1 end}
M.account=function()return {sales={{deposit=5},{deposit=3},{deposit=2}}} end
M.recordMarket=function(kind,e)assert(kind=='cancel_confirmed' and e.auctionID==1);M.pendingCancel=nil end
M.listingGross=function(r)return r.quantity*r.unitPrice end
ForeverMarketVariant=function()end
ForeverMarketCoins=tostring
ForeverMarketPriceDepth=function(t)if t[80] then return {floorPrice=80} end end
ForeverMarketSaleNet=function(n)return n end
ForeverMarketPostPrice=function(n)return n-2 end
C_Item={GetItemInfo=function()return nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,10 end,GetItemNameByID=function()return 'Ore' end}
dofile('src/CancelQueue.lua')
M.startCancelQueue();M.cancelQueueTick();assert(queries==1 and clicks==0)
callbacks[2](nil,'COMMODITY_SEARCH_RESULTS_UPDATED',25)
local shown=M.cancelQueueReady();assert(shown and shown.deposit==5)
M.cancelQueueOne({});assert(clicks==0)
M.cancelQueueOne(shown);M.cancelQueueOne(shown);assert(clicks==1)
M.cancelQueueTick();assert(not M.cancelQueueReady())
table.remove(rows,1);M.cancelQueueTick();assert(not M.cancelQueueReady())
M.pendingCancel.removalNotice=true;M.cancelQueueTick();M.cancelQueueTick()
local nextRow=M.cancelQueueReady();assert(queries==1 and nextRow and nextRow.deposit==3)
rows[1].status=1;M.cancelQueueOne(nextRow);assert(clicks==1)
M.cancelQueueTick();M.cancelQueueTick();local third=M.cancelQueueReady();now=120
M.cancelQueueOne(third);assert(clicks==1 and not M.cancelQueueReady())
M.cancelQueueTick();C_AuctionHouse.GetCommoditySearchResultInfo=function()return {quantity=1,unitPrice=80,containsOwnerItem=true} end
callbacks[2](nil,'COMMODITY_SEARCH_RESULTS_UPDATED',25);assert(M.cancelQueueText():find('1 removed / 2 skipped',1,true))
