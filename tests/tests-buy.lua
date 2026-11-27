local callbacks,buttons={},{}
local elapsed=20
function GetTime()return elapsed end
function time()return 100*86400 end
function GetMoney()return 50000 end
function UnitGUID()return 'TestCharacter' end
function GetCoinTextureString(n)return tostring(n)end
local panel
local function frame()
 local f={}
 for _,k in ipairs({'SetSize','SetPoint','SetHeight','SetAutoFocus','SetScrollChild','SetEnabled','SetShown','Hide','ClearFocus','RegisterEvent'}) do f[k]=function()end end
 function f:SetText(s)self.text=s end
 function f:GetText() return self.text end
 function f:SetScript(k,v)self[k]=v end
 function f:IsVisible()return true end
 f.GetFrameLevel=function()return 2 end;f.CreateTexture=frame
 for _,k in ipairs({'SetFrameLevel','EnableMouse','SetHighlightTexture','SetWidth','SetJustifyH','SetBackdrop','SetBackdropColor','SetBackdropBorderColor','SetTextColor','SetTexture','SetWordWrap'}) do f[k]=function()end end
 f.CreateFontString=frame
 return f
end
function CreateFrame(t)
 local f=frame();f.kind=t;buttons[#buttons+1]=f;return f
end
ForeverMarketTab=function(_,p)panel=p end
AuctionHouseFrame={}
local db={['2589']={m=16,h={['99']=100,['98']=100,['97']=100}}}
ForeverMarketHistory=function()return db end
C_Item={GetItemInfo=function()return "Cloth",nil,1,nil,nil,nil,nil,20,nil,nil,1 end,GetItemInfoInstant=function()return 2589,nil,nil,nil,nil,7 end,GetItemNameByID=function()return 'Linen Cloth' end}
local confirms=0
C_AuctionHouse={IsThrottledMessageSystemReady=function()return true end,MakeItemKey=function(id)return {itemID=id}end,SendSearchQuery=function()end,
 GetNumCommoditySearchResults=function()return 2 end,GetCommoditySearchResultInfo=function(_,i)return ({ {unitPrice=16,quantity=1},{unitPrice=87,quantity=465} })[i]end,
 CalculateCommodityDeposit=function()return 1 end,StartCommoditiesPurchase=function(id,n)assert(id==2589 and n==1)end,CancelCommoditiesPurchase=function()end,
 ConfirmCommoditiesPurchase=function(id,n)assert(id==2589 and n==1);confirms=confirms+1 end}
ForeverMarketRisk={cutBP=1500} -- exercise the pre-update conservative fee profile
SlashCmdList={};dofile('src/Market.lua');GetCoinTextureString=nil
dofile('src/Activity.lua')
dofile('src/BuyTab.lua')
local dispatch=buttons[#buttons].OnEvent
local observedRows={}
local observedRow
local hover=ForeverMarketHover
ForeverMarketHover=function(parent,y,width,row)
 observedRows[#observedRows+1]=row
 observedRow=row
 return hover(parent,y,width,row)
end
dispatch(nil,'AUCTION_HOUSE_SHOW')
local start,stop,target,edit,set
for _,b in ipairs(buttons) do
 if b.text=='Start' then start=b elseif b.text=='Stop' then stop=b elseif b.text=='Set fund (gold)' then set=b
 elseif b.kind=='EditBox' then if not edit then edit=b else target=b end end
end
local function begin() panel:OnShow();start:OnClick() end
begin()
local function load()
 panel:OnUpdate(1);dispatch(nil,'COMMODITY_SEARCH_RESULTS_UPDATED',2589)
 for _,b in ipairs(buttons)do if b.text=='Buy' then return b end end
end
local buy=load();assert(observedRow.cost.text==ForeverMarketCoins(16) and observedRow.profit.text==ForeverMarketCoins(56));buy:OnEnter();dispatch(nil,'COMMODITY_PRICE_UPDATED',87,87);assert(confirms==0)
panel:OnHide();elapsed=elapsed+2;begin();buy=load();buy:OnEnter();buy:OnMouseDown();dispatch(nil,'COMMODITY_PRICE_UPDATED',15,15);assert(observedRow.cost.text==ForeverMarketCoins(15) and observedRow.profit.text==ForeverMarketCoins(57));buy:OnClick();assert(confirms==0);dispatch(nil,'COMMODITY_PRICE_UPDATED',16,16);buy:OnClick();buy:OnClick();assert(confirms==1)
ForeverMarketFundActivity('purchase',{itemId=2589,quantity=1,total=16});assert(ForeverMarketFundCash()==9984)
ForeverMarketFundPost(2589,1,85)
ForeverMarketFundActivity('posted',{itemId=2589,quantity=1,total=85,name='Linen Cloth',auctionId=42});assert(ForeverMarketFundCash()==9983)
ForeverMarketFundActivity('sale_notice',{auctionId=42});assert(ForeverMarketFundCash()==9983)
ForeverMarketFundActivity('proceeds_collected',{invoiceType='seller',name='Linen Cloth',amount=82,deposit=1,fee=4,quantity=1});assert(ForeverMarketFundCash()==10065)
print('PASS: shopping list, undercut quantity, price-rise cancellation, click confirmation, duplicate click, deposit and collected profit')

db['2592']={m=16,h={['99']=100,['98']=100,['97']=100}}
elapsed=elapsed+2;panel:OnHide();begin()
panel:OnUpdate(1);dispatch(nil,'COMMODITY_SEARCH_RESULTS_UPDATED',2589)
elapsed=elapsed+2;panel:OnUpdate(1);dispatch(nil,'COMMODITY_SEARCH_RESULTS_UPDATED',2592)
assert(observedRows[1].pick.v.id==2589 and observedRows[2].pick.v.id==2592)
elapsed=elapsed+58;panel:OnUpdate(1)
assert(observedRows[1].pick.v.id==2592 and observedRows[2].pick.inactive=='Rechecking price')
C_AuctionHouse.GetNumCommoditySearchResults=function()return 0 end
dispatch(nil,'COMMODITY_SEARCH_RESULTS_UPDATED',2589)
assert(observedRows[2].pick.inactive=='No live offer')
observedRows[2].btn:OnClick();assert(confirms==1)
print('PASS: expiring row moves below available buys, stays visible after empty result, blocks purchase')

db['2592']=nil
C_AuctionHouse.GetNumCommoditySearchResults=function()return 1 end
C_AuctionHouse.GetCommoditySearchResultInfo=function()return {unitPrice=16,quantity=45} end
elapsed=elapsed+2;panel:OnHide();begin();panel:OnUpdate(1)
dispatch(nil,'COMMODITY_SEARCH_RESULTS_UPDATED',2589)
assert(not observedRows[1].pick,'historical discount without a live resale spread must not be offered')
C_AuctionHouse.GetNumCommoditySearchResults=function()return 2 end
C_AuctionHouse.GetCommoditySearchResultInfo=function(_,i)return ({ {unitPrice=16,quantity=4},{unitPrice=87,quantity=465} })[i] end
elapsed=elapsed+2;panel:OnHide();begin();panel:OnUpdate(1);dispatch(nil,'COMMODITY_SEARCH_RESULTS_UPDATED',2589)
local stack=observedRows[1]
assert(stack.pick.n==4 and stack.cost.text==ForeverMarketCoins(64) and stack.profit.text==ForeverMarketCoins(225))
C_Item.GetItemInfo=function()return 'Cloth',nil,1,nil,nil,nil,nil,20,nil,nil,73 end
elapsed=elapsed+2;panel:OnHide();begin();panel:OnUpdate(1);dispatch(nil,'COMMODITY_SEARCH_RESULTS_UPDATED',2589)
assert(not observedRows[1].pick,'vendor-favored stack must not become a buy')
print('PASS: current bulk ask caps exits, multi-unit net profit includes fees and deposit, vendor-favored buys excluded')

local saved=ForeverMarketDB.__funds.TestCharacter
saved.seed=50000;saved.cash=296;saved.held[2589]={n=2,reserve=100,cost=32}
edit:SetText('2');set:OnClick()
assert(saved.cash==20000 and saved.held[2589].reserve==100)
set:OnClick();assert(saved.cash==20000)
panel:OnHide();begin();assert(tonumber(edit:GetText())==2)
print('PASS: setting 2G with 2S 96C remaining, repeat click and tab reopen')

local sent=0
C_AuctionHouse.SendSearchQuery=function()sent=sent+1 end
local ready=false
C_AuctionHouse.IsThrottledMessageSystemReady=function()return ready end
set:OnClick();assert(sent==0)
stop:OnClick();ready=true;panel:OnUpdate(1);assert(sent==0);start:OnClick();assert(sent==1)
set:OnClick();assert(sent==1,'setting the fund must not start a search');start:OnClick();assert(sent==2)
print('PASS: Set fund saves separately; stopped scans send nothing; Start issues a new search')

-- A later-ranked affordable item has a recently observed gap; verify it first.
GetRealmName=function()return 'Test' end
UnitFactionGroup=function()return 'Horde' end
ForeverMarketDB.__depth={['Test|Horde']={[2592]={at=time(),low=18,lowQty=2,floorPrice=87}}}
db['2592']={m=80,h={['99']=100,['98']=100,['97']=100}}
local requested={}
C_AuctionHouse.SendSearchQuery=function(k)requested[#requested+1]=k.itemID end
start:OnClick();assert(#requested==1 and requested[1]==2592)
elapsed=elapsed+.11;panel:OnUpdate(.11);assert(#requested==1,'never overlap requests')
dispatch(nil,'COMMODITY_SEARCH_RESULTS_UPDATED',2592)
ready=false;elapsed=elapsed+.11;panel:OnUpdate(.11);assert(#requested==1,'respect throttle after result')
ready=true;dispatch(nil,'AUCTION_HOUSE_THROTTLED_SYSTEM_READY');elapsed=elapsed+.016;panel:OnUpdate(.016)
assert(#requested==2 and requested[2]==2589,'no fixed one-second delay between completed searches')
print('PASS: recent profitable spread first, next check within one second, no overlap or throttle bypass')

ForeverMarketDB.__depth=nil
GetCurrentRegion=function()return 1 end
ForeverMarketResearch={region=1,realm='Test',faction='Horde',at=time(),items={[2592]={rank=1,ceiling=80}}}
requested={};start:OnClick();assert(requested[1]==2592,'desktop research should reorder eligible candidates')
ForeverMarketResearch.realm='Other'
requested={};start:OnClick();assert(requested[1]==2589,'ignore other realm research')
print('PASS: matched market research changes scan order, other realm ignored')

-- Drive the normal scan through 200 flat books before a small profitable stack.
ForeverMarketResearch=nil
db={}
for id=1001,1201 do db[tostring(id)]={m=4,h={['99']=100,['98']=100,['97']=100}} end
local current,full,cached,more=nil,true,false,0
C_AuctionHouse.SendSearchQuery=function(k)current=k.itemID end
C_AuctionHouse.HasFullCommoditySearchResults=function()return full end
C_AuctionHouse.RequestMoreCommoditySearchResults=function(id)assert(id==1201);more=more+1 end
C_AuctionHouse.GetNumCommoditySearchResults=function()return current==1201 and full and 2 or 1 end
C_AuctionHouse.GetCommoditySearchResultInfo=function(_,i)
 if i==1 then return {unitPrice=4,quantity=4} else return {unitPrice=9,quantity=200} end
end
C_Item.GetItemInfo=function(id)
 if id==1201 and not cached then return 'Material',nil,2 end
 return 'Material',nil,2,nil,nil,nil,nil,20,nil,nil,0
end
panel:OnHide();begin()
for id=1001,1200 do
 elapsed=elapsed+.2;panel:OnUpdate(.2);assert(current==id)
 dispatch(nil,'COMMODITY_SEARCH_RESULTS_UPDATED',id)
 assert(not observedRows[1].pick)
end
elapsed=elapsed+.2;panel:OnUpdate(.2);assert(current==1201)
full=false;dispatch(nil,'COMMODITY_SEARCH_RESULTS_UPDATED',1201);assert(more==1 and not observedRows[1].pick)
full=true;dispatch(nil,'COMMODITY_SEARCH_RESULTS_ADDED',1201);assert(not observedRows[1].pick)
cached=true;elapsed=elapsed+.6;panel:OnUpdate(.6)
local deal=observedRows[1];assert(deal.pick.v.id==1201 and deal.pick.n==4 and deal.buyTotal==16 and deal.profit.text==ForeverMarketCoins(7))
print('PASS: 200 legitimate rejections, then a live Buy row after paging and item data load, with exact stack margin')

db={[tostring(1201)]={m=50,h={['99']=100,['98']=100,['97']=100}}}
C_AuctionHouse.GetCommoditySearchResultInfo=function(_,i)
 if i==1 then return {unitPrice=50,quantity=2} else return {unitPrice=65,quantity=200} end
end
for _,bp in ipairs({2000,1500}) do
 ForeverMarketDB.buyTargetBP=nil;ForeverMarketRisk={marginBP=bp,cutBP=500}
 panel:OnHide();begin();panel:OnUpdate(1);dispatch(nil,'COMMODITY_SEARCH_RESULTS_UPDATED',1201)
 local p=observedRows[1].pick
 if bp==2000 then assert(not p) else assert(p and p.n==2 and observedRows[1].profit.text==ForeverMarketCoins(19)) end
end
print('PASS: same offer rejected at 20% and shown at 15% with configured 5% fee and one-copper deposit')

-- Ten at 100c, followed by ample supply at 115c: too small a jump for
-- Sell's outlier rule but enough for a 5% flip after fees and deposit.
db['1201']={m=100,h={['99']=200,['98']=200,['97']=200}}
C_AuctionHouse.GetCommoditySearchResultInfo=function(_,i)
 return i==1 and {unitPrice=100,quantity=10} or {unitPrice=115,quantity=200}
end
ForeverMarketRisk={marginBP=500,cutBP=500};ForeverMarketDB.buyTargetBP=nil
local before=saved.cash
for _,cash in ipairs({999,1001}) do
 saved.cash=cash+100 -- 100c already reserved by the fixture
 panel:OnHide();begin();panel:OnUpdate(1);dispatch(nil,'COMMODITY_SEARCH_RESULTS_UPDATED',1201)
 local p=observedRows[1].pick
 if cash==999 then assert(not p,'partial tier leaves cheaper competition')
 else assert(p and p.n==10 and observedRows[1].profit.text==ForeverMarketCoins(73)) end
end
saved.cash=before
print('PASS: modest live spread qualifies at 5% only when the full cheap tier fits the fund')
-- An actual repeat-listing allowance reduces profit even when the sale
-- deposit is refunded; it must not release any of the required posting cash.
ForeverMarketRisk.lostDepositPerUnit=4
panel:OnHide();begin();panel:OnUpdate(1);dispatch(nil,'COMMODITY_SEARCH_RESULTS_UPDATED',1201)
assert(not observedRows[1].pick,'expected failed listings must still reduce net return')
ForeverMarketRisk.lostDepositPerUnit=0
-- An individual auction must use a comparable variant and its own buyout ID.
local gearID=10405
local gearKey={itemID=gearID,itemLevel=17,itemSuffix=0}
local gearLink='|Hitem:10405::::::::::::|h[Bandit Shoulders]|h'
db={['g:10405:17']={m=150,h={['99']=2000,['98']=2000,['97']=2000}}}
C_Item.GetItemInfoInstant=function()return gearID,nil,nil,nil,nil,4 end
C_Item.GetItemInfo=function()return 'Bandit Shoulders',nil,2,nil,nil,nil,nil,1,nil,nil,30 end
C_AuctionHouse.GetItemKeyInfo=function()return {isCommodity=false} end
C_AuctionHouse.SendSellSearchQuery=function(key,sort)assert(key.itemID==gearID and sort[1].sortOrder==4)end
local lots={
 {auctionID=99,itemKey=gearKey,itemLink=gearLink,buyoutAmount=150},
 {auctionID=100,itemKey=gearKey,itemLink=gearLink,buyoutAmount=1200},
 {auctionID=101,itemKey={itemID=gearID,itemLevel=12},itemLink=gearLink,buyoutAmount=1},
 {auctionID=102,itemKey=gearKey,itemLink=gearLink,buyoutAmount=1900,containsOwnerItem=true}}
C_AuctionHouse.GetNumItemSearchResults=function()return #lots end
C_AuctionHouse.GetItemSearchResultInfo=function(_,i)return lots[i] end
C_AuctionHouse.HasFullItemSearchResults=function()return true end
local orders=0
C_AuctionHouse.PlaceBid=function(id,total)assert(id==99 and total==150);orders=orders+1 end
local function gearScan()
 panel:OnHide();begin();panel:OnUpdate(1);dispatch(nil,'ITEM_SEARCH_RESULTS_UPDATED',gearKey)
end
gearScan()
assert(observedRows[1].pick.v.auctionID==99 and observedRows[1].buyTotal==150)
lots[1].buyoutAmount=151;observedRows[1].btn:OnClick();assert(orders==0)
lots[1].buyoutAmount=150;gearScan()
local oldCash=ForeverMarketFundCash()
observedRows[1].btn:OnClick();observedRows[1].btn:OnClick()
assert(orders==1 and oldCash==ForeverMarketFundCash())
ForeverMarketActivity={sequence=0,install='fixture',events={}}
UnitName=function()return 'Tester' end
dispatch(nil,'AUCTION_HOUSE_PURCHASE_COMPLETED',100)
assert(oldCash==ForeverMarketFundCash())
dispatch(nil,'AUCTION_HOUSE_PURCHASE_COMPLETED',99);dispatch(nil,'AUCTION_HOUSE_PURCHASE_COMPLETED',99)
local tracked=ForeverMarketVariant(gearKey,gearLink)
assert(ForeverMarketFundCash()==oldCash-150 and ForeverMarketFundHolding(tracked)==1)
ForeverMarketFundPost(tracked,1,1198,9,gearID)
ForeverMarketFundActivity('posted',{itemId=gearID,quantity=1,total=1198,name='Bandit Shoulders',auctionId=211})
assert(ForeverMarketFundHolding(tracked)==0 and ForeverMarketFundCash()==oldCash-159)
print('PASS: equipment search, variant matching, exact buyout, changed offer, duplicate click, confirmed fund and resale deposit')

-- Drive the category path via the same events the live auction house emits.
db={}
for _,id in ipairs({2001,2002,2003,2004,2005}) do
 db[tostring(id)]={m=150,h={['99']=2000,['98']=2000,['97']=2000}}
end
C_Item.GetItemInfoInstant=function(id)
 return id,nil,nil,'INVTYPE_WEAPON',nil,2,id==2005 and 8 or 7
end
local categoriesSent,details={},{}
local pages,complete,morePages={},false,0
C_AuctionHouse.SendBrowseQuery=function(query)
 categoriesSent[#categoriesSent+1]=query.itemClassFilters[1]
end
C_AuctionHouse.GetBrowseResults=function()return pages end
C_AuctionHouse.HasFullBrowseResults=function()return complete end
C_AuctionHouse.RequestMoreBrowseResults=function()morePages=morePages+1 end
C_AuctionHouse.SendSellSearchQuery=function(key)details[#details+1]=key.itemID end
local function update() elapsed=elapsed+.2;panel:OnUpdate(.2) end
panel:OnHide();begin();update()
assert(#categoriesSent==1 and categoriesSent[1].classID==2 and categoriesSent[1].subClassID==7)
pages={{itemKey={itemID=2001},minPrice=999999},{itemKey={itemID=2002},minPrice=150}}
dispatch(nil,'AUCTION_HOUSE_BROWSE_RESULTS_UPDATED');update()
assert(morePages==1 and #details==0)
complete=true
pages[#pages+1]={itemKey={itemID=2003},minPrice=50}
dispatch(nil,'AUCTION_HOUSE_BROWSE_RESULTS_ADDED');update()
assert(details[1]==2003)
lots={}
dispatch(nil,'ITEM_SEARCH_RESULTS_UPDATED',{itemID=2003});update()
assert(details[2]==2002)
dispatch(nil,'ITEM_SEARCH_RESULTS_UPDATED',{itemID=2002});update()
assert(#details==2 and #categoriesSent==2 and categoriesSent[2].subClassID==8)
elapsed=elapsed+9;update()
assert(details[3]==2005,'timed-out category still receives detailed lookup')
print('PASS: paged sword category, affordable discounts first, expensive and absent items skipped, second category timeout falls back')

-- Replication and Buy use the same scanner entry points as the live UI.
-- The snapshot contains a cheap singleton and a deep resale tier.
local bulkCalls,bulkReads,batchCalls=0,0,0
C_Item.GetItemInfoInstant=function(id)return id,nil,nil,nil,nil,7 end
db={}
for id=3100,3202 do
 db[tostring(id)]={m=80,h={['99']=100,['98']=100,['97']=100}}
end
local historyWrites=0
ForeverMarketObserve=function()historyWrites=historyWrites+1 end
ForeverMarketHistoryKey=function(k)return tostring(k.itemID)end
C_AuctionHouse.ReplicateItems=function()bulkCalls=bulkCalls+1 end
C_AuctionHouse.GetNumReplicateItems=function()return 3 end
C_AuctionHouse.GetReplicateItemInfo=function(i)
 bulkReads=bulkReads+1
 local p=({{1,16,3100},{465,87*465,3100},{30,90*30,3101}})[i+1]
 return nil,nil,p[1],nil,nil,nil,nil,nil,nil,p[2],nil,nil,nil,nil,nil,nil,p[3]
end
C_AuctionHouse.GetItemKeyInfo=function()return {isCommodity=true}end
C_AuctionHouse.SearchForItemKeys=function(keys)assert(#keys<=100);batchCalls=batchCalls+1 end
C_AuctionHouse.GetNumCommoditySearchResults=function()return 2 end
C_AuctionHouse.GetCommoditySearchResultInfo=function(_,i)
 return i==1 and {unitPrice=16,quantity=1} or {unitPrice=87,quantity=465}
end
C_AuctionHouse.HasFullCommoditySearchResults=function()return true end
C_Item.GetItemInfo=function()return 'Cloth',nil,1,nil,nil,nil,nil,20,nil,nil,1 end
dofile('src/Snapshot.lua')
local bulkFrame=buttons[#buttons]
local liveRequests={}
C_AuctionHouse.SendSearchQuery=function(k)liveRequests[#liveRequests+1]=k.itemID end
panel:OnHide();panel:OnShow();target:SetText('10');start:OnClick()
assert(bulkCalls==1 and #liveRequests==0)
bulkFrame:OnEvent('REPLICATE_ITEM_LIST_UPDATE');bulkFrame:OnUpdate();bulkFrame:OnUpdate();update()
assert(liveRequests[1]==3100 and bulkReads==3 and historyWrites==2)
assert(not observedRows[1].pick,'snapshot alone cannot show a buy')
dispatch(nil,'COMMODITY_SEARCH_RESULTS_UPDATED',3100)
assert(observedRows[1].pick.v.id==3100)
update();assert(batchCalls==0,'fresh snapshot must finish without browsing rejected items again')
target:SetText('5');start:OnClick()
assert(bulkCalls==1 and bulkReads==3 and liveRequests[2]==3100 and ForeverMarketMarginBP()==500)
stop:OnClick();update();assert(#liveRequests==2)
elapsed=elapsed+65
start:OnClick();assert(liveRequests[3]==3100)
dispatch(nil,'COMMODITY_SEARCH_RESULTS_UPDATED',3100);update()
assert(batchCalls==1,'older snapshot should refresh deferred commodities by batch')
local beforeTimeouts=#liveRequests
dispatch(nil,'AUCTION_HOUSE_BROWSE_FAILURE');update()
pages={};complete=true;dispatch(nil,'AUCTION_HOUSE_BROWSE_RESULTS_UPDATED');update()
assert(batchCalls==3,'failed large batch should retry after the smaller batch')
dispatch(nil,'AUCTION_HOUSE_BROWSE_FAILURE');update()
assert(batchCalls==3 and #liveRequests==beforeTimeouts,'failed batches must not expand into individual searches')
stop:OnClick()
dofile('src/Snapshot.lua')
assert(ForeverMarketSnapshot().rows==3 and bulkCalls==1,'same-market saved snapshot should survive a UI reload')
print('PASS: shared bulk snapshot, per-unit price tiers, ranked live verification, 100-key batches, local margin restart, stop')

-- Run the production filter at the entrance to the direct lookup path.
ForeverMarketSnapshot=nil
C_AuctionHouse.SendBrowseQuery=nil
db={}
local cases={
  [4471]={1,7},[2901]={1,2},[7005]={1,2},[5956]={1,2},[2320]={1,7},
  [40001]={0,15},[40002]={1,4},[40003]={1,7},[40004]={2,4},
  [40005]={0,15},[40006]={1,9},[40007]={1,4},[40008]={1,4},[40009]={0,15}
}
for id in pairs(cases) do
 local r={m=100,h={},a={}}
 for day=94,99 do r.h[day]=20000;r.a[day]=(id==40005 or id==40007 or id==40008 or id<40000) and 2 or 80 end
 db[tostring(id)]=r
end
local cachedFilter=false
C_Item.GetItemInfo=function(id)
 if id==40009 and not cachedFilter then return nil end
 local data=cases[id];return 'Item',nil,data[1],nil,nil,nil,nil,20,nil,nil,id==40008 and 4000 or 100,data[2]
end
local sentIDs={}
C_AuctionHouse.SendSearchQuery=function(k)sentIDs[k.itemID]=true end
C_AuctionHouse.GetNumCommoditySearchResults=function()return 0 end
start:OnClick()
assert(not next(sentIDs),'unknown quality is resolved before dispatch')
cachedFilter=true
for i=1,10 do
 elapsed=elapsed+.5;panel:OnUpdate(.5)
 for id in pairs(sentIDs) do dispatch(nil,'COMMODITY_SEARCH_RESULTS_UPDATED',id) end
end
for id in pairs(cases) do
 local expected=id==40003 or id==40004 or id==40005 or id==40006 or id==40007
 assert((sentIDs[id]==true)==expected,'unexpected buy eligibility '..id)
end
print('PASS: routine tools, grey junk and common gear excluded before AH lookup; materials, recipes and scarce valuable items retained')
-- Do useful work during a delayed bulk response, then adopt it between queries.
local slowStart=elapsed
ForeverMarketSnapshot=function()return nil,'pending'end
local books={}
ForeverMarketReadySnapshot=function()return {at=slowStart,books=books} end
start:OnClick()
assert(ForeverMarketDB.lastBuyScan.state=='pending')
elapsed=elapsed+3.1;panel:OnUpdate(.6)
assert(ForeverMarketDB.lastBuyScan.source=='browse')
if ForeverMarketDB.lastBuyScan.item then
 dispatch(nil,'COMMODITY_SEARCH_RESULTS_UPDATED',ForeverMarketDB.lastBuyScan.item)
end
elapsed=elapsed+1.1;panel:OnUpdate(.6)
assert(ForeverMarketDB.lastBuyScan.source=='bulk' and ForeverMarketDB.lastBuyScan.finished)
print('PASS: late snapshot handoff and persisted scan report')


ForeverMarketSnapshot=nil
ForeverMarketReadySnapshot=nil
db={}
for _,id in ipairs({6889,40003,40004}) do
 db[tostring(id)]={m=20,h={[99]=100,[98]=100,[97]=100}}
end
C_Item.GetItemInfo=function()return 'Material',nil,1,nil,nil,nil,nil,20,nil,nil,0,7 end
NUM_BAG_SLOTS=0
C_Container={GetContainerNumSlots=function()return 2 end,GetContainerItemInfo=function(_,slot)
 if slot==1 then return {itemID=40003,stackCount=20} end
 return {itemID=6889,stackCount=38}
end}
local ordered={}
C_AuctionHouse.SendSearchQuery=function(k)ordered[#ordered+1]=k.itemID end
C_AuctionHouse.GetNumOwnedAuctions=function()return 0 end
start:OnClick()
for i=1,10 do
 elapsed=elapsed+1;panel:OnUpdate(1)
 if ordered[#ordered] then dispatch(nil,'COMMODITY_SEARCH_RESULTS_UPDATED',ordered[#ordered]) end
end
assert(ordered[1]==6889 and ordered[2]==40004 and #ordered==2,'staple searched first, full stack skipped, broad search continues')
C_AuctionHouse.GetNumOwnedAuctions=function()return 1 end
C_AuctionHouse.GetOwnedAuctionInfo=function()return {itemKey={itemID=6889},quantity=2,status=0} end
ordered={}
start:OnClick()
for i=1,4 do elapsed=elapsed+1;panel:OnUpdate(1);dispatch(nil,'COMMODITY_SEARCH_RESULTS_UPDATED',40004) end
assert(#ordered==1 and ordered[1]==40004,'active listings count with bag stock toward the two-stack cap')
print('PASS: staple priority, bag stock limit, owned auctions, and remaining eligible market coverage')

-- An isolated spike must not hide a stack that clears the net margin in total.
ForeverMarketRisk={cutBP=500,lostDepositPerUnit=0}
local observations={[93]=900,[94]=7,[95]=7,[96]=7,[97]=7,[98]=7,[99]=7}
db={['41001']={m=3,h=observations},['41002']={m=3,h={[92]=70,[93]=70,[94]=70,[95]=70,[96]=70,[97]=4,[98]=4,[99]=4}}}
local smallBook={low=3,lowQty=10,nextPrice=6,nextQty=50}
ForeverMarketSnapshot=function()return {at=elapsed,books={[41001]=smallBook,[41002]=smallBook}} end
C_AuctionHouse.GetNumCommoditySearchResults=function()return 2 end
C_AuctionHouse.GetCommoditySearchResultInfo=function(_,i)return i==1 and {unitPrice=3,quantity=10} or {unitPrice=6,quantity=50} end
ordered={}
target:SetText('5');start:OnClick();update()
assert(ordered[1]==41001,'bulk snapshot should check stack with one historical spike')
dispatch(nil,'COMMODITY_SEARCH_RESULTS_UPDATED',41001)
assert(observedRows[1].pick and observedRows[1].pick.n==10 and observedRows[1].profit.text==ForeverMarketCoins(8))
-- Stable enough over the whole history, but the three latest days lowered the resale ceiling.
db={['41003']={m=3,h={[92]=7,[93]=7,[94]=7,[95]=7,[96]=7,[97]=4,[98]=4,[99]=4}}}
ForeverMarketSnapshot=function()return {at=elapsed,books={[41003]=smallBook}} end
ordered={};start:OnClick();update()
assert(#ordered==0,'recent fall should cap the resale estimate')
print('PASS: isolated spike, full-stack fee rounding and recent downward repricing')

local priorHistory=ForeverMarketHistory
dofile('src/History.lua')
ForeverMarketHistory=priorHistory
local floors={}
for day=65,99 do floors[day]=100 end
for _,day in ipairs({73,81,89}) do floors[day]=70 end
local model=assert(ForeverMarketRecovery(floors,100));assert(model.wins==3 and model.entry==85 and model.exit==93)
floors[100]=10000;assert(ForeverMarketRecovery(floors,100).exit==93)
assert(not ForeverMarketRecovery({[99]=10},100))
local falling={};for day,p in pairs(floors) do falling[day]=day>=94 and 60 or p end
assert(not ForeverMarketRecovery(falling,100))
db={['41001']={m=70,h=floors,floors=floors}}
local dip={low=70,lowQty=100,floorPrice=70,floorQty=100}
ForeverMarketSnapshot=function()return {at=elapsed,books={[41001]=dip}} end
C_AuctionHouse.GetNumCommoditySearchResults=function()return 1 end
C_AuctionHouse.GetCommoditySearchResultInfo=function()return {unitPrice=70,quantity=100} end
local invest
for _,b in ipairs(buttons) do if b.text=='Invest' then invest=b end end
edit:SetText('1');set:OnClick()
ordered={};invest:OnClick();update();dispatch(nil,'COMMODITY_SEARCH_RESULTS_UPDATED',41001)
local pick=observedRows[1].pick
assert(pick and pick.v.model and pick.n<100 and pick.n*70+pick.dep<=2000)
C_AuctionHouse.GetCommoditySearchResultInfo=function()return {unitPrice=90,quantity=100} end
invest:OnClick();update();dispatch(nil,'COMMODITY_SEARCH_RESULTS_UPDATED',41001)
assert(not observedRows[1].pick or observedRows[1].pick.inactive)
print('PASS: investment replay, prior-day isolation, decline rejection, partial-tier purchase, budget and live price gate')

