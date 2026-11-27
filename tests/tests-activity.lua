local event,update,hooks={},nil,{}
local now,money=1800000000,10000
function time() return now end
function GetTime() return now end
function GetMoney() return money end
function UnitName() return 'Tester' end
function UnitGUID() return 'Player-1-ABC' end
function GetRealmName() return '' end
function UnitFactionGroup() return 'Horde' end
function GetCurrentRegion() return 1 end
function CreateFrame() return {RegisterEvent=function()end,SetScript=function(_,name,fn) if name=='OnEvent' then event=fn else update=fn end end} end
C_AuctionHouse={PostCommodity=function()end,StartCommoditiesPurchase=function()end,ConfirmCommoditiesPurchase=function()end}
C_Item={GetItemID=function()return 2589 end,GetItemNameByID=function()return 'Linen Cloth' end}
Enum={AuctionHouseNotification={AuctionSold=3}}
function hooksecurefunc(name,fn,handler) if handler then hooks[fn]=handler else hooks[name]=fn end end
function PlaceAuctionBid()end
function PostAuction()end
function TakeInboxMoney()end
function TakeInboxItem()end
local inventory=0
function GetItemCount() return inventory end
function GetInboxItem() return 'Herb',2447,nil,4 end
function GetAuctionItemInfo() return 'Herb',nil,3,nil,nil,nil,nil,nil,nil,401,nil,nil,nil,nil,nil,nil,2447 end
function GetAuctionSellItemInfo() return 'Herb' end
function GetAuctionSellItemLink() return 'item:2447' end
function GetAuctionDeposit(duration,bid,buyout,size,stacks) assert(duration==2 and bid==200 and buyout==300 and size==4 and stacks==1);return 9 end
function GetInboxNumItems() return 1 end
local invoiceType='seller'
function GetInboxInvoiceInfo() return invoiceType,'Herb','Buyer',300,300,9,15,0,nil,nil,4 end
function GetInboxHeaderInfo() return nil,nil,nil,'Auction successful',294 end
function ForeverMarketJSON(e) return e.name or 'event' end
ERR_AUCTION_BID_PLACED='Bid accepted';ERR_AUCTION_STARTED='Auction created';ERR_AUCTION_REMOVED='Cancelled'
dofile('src/Activity.lua')
local function last() return ForeverMarketActivity.events[#ForeverMarketActivity.events] end
local function count(kind) local n=0;for _,e in ipairs(ForeverMarketActivity.events)do if e.kind==kind then n=n+1 end end;return n end
event(nil,'PLAYER_LOGIN');event(nil,'AUCTION_HOUSE_SHOW')
hooks.PlaceAuctionBid('list',1,401);assert(count('purchase')==0)
event(nil,'CHAT_MSG_SYSTEM',ERR_AUCTION_BID_PLACED);assert(last().kind=='purchase' and last().total==401 and last().quantity==3)
event(nil,'CHAT_MSG_SYSTEM',ERR_AUCTION_BID_PLACED);assert(count('purchase')==1)
hooks.PlaceAuctionBid('list',1,401);event(nil,'UI_ERROR_MESSAGE');event(nil,'CHAT_MSG_SYSTEM',ERR_AUCTION_BID_PLACED);assert(count('purchase')==1)
hooks.PlaceAuctionBid('list',1,100);event(nil,'CHAT_MSG_SYSTEM',ERR_AUCTION_BID_PLACED);assert(last().kind=='bid')
hooks.PlaceAuctionBid('list',1,401);now=now+16;event(nil,'CHAT_MSG_SYSTEM',ERR_AUCTION_BID_PLACED);assert(count('purchase')==1)
hooks.PostAuction(200,300,2,4,2)
event(nil,'CHAT_MSG_SYSTEM',ERR_AUCTION_STARTED);assert(last().kind=='posted' and last().quantity==4 and last().deposit==9 and last().itemId==2447)
event(nil,'CHAT_MSG_SYSTEM',ERR_AUCTION_STARTED);event(nil,'CHAT_MSG_SYSTEM',ERR_AUCTION_STARTED);assert(count('posted')==2)
event(nil,'MAIL_SHOW');event(nil,'MAIL_INBOX_UPDATE');assert(count('invoice_observed')==1)
hooks.TakeInboxMoney(1);assert(count('proceeds_collected')==0);money=money+294;event(nil,'PLAYER_MONEY');assert(count('proceeds_collected')==1)
event(nil,'PLAYER_MONEY');assert(count('proceeds_collected')==1)
invoiceType='buyer';hooks.TakeInboxItem(1,1);assert(count('purchased_item_received')==0)
inventory=4;event(nil,'BAG_UPDATE_DELAYED');assert(count('purchased_item_received')==1)
event(nil,'BAG_UPDATE_DELAYED');assert(count('purchased_item_received')==1)
local ids={};for _,e in ipairs(ForeverMarketActivity.events)do assert(not ids[e.id]);ids[e.id]=true end
event(nil,'PLAYER_LOGOUT');assert(ForeverMarketActivityExport)
print('PASS: confirmation gating, errors, timeout, bid/buy separation, multi-stack posting, deposits, mail deduplication, collected gold and purchased-item receipt')

hooks.StartCommoditiesPurchase(2589,1);event(nil,'COMMODITY_PRICE_UPDATED',23,23)
hooks.ConfirmCommoditiesPurchase(2589,1);event(nil,'COMMODITY_PURCHASE_SUCCEEDED')
assert(last().kind=='purchase' and last().total==23 and last().quantity==1)
hooks.PostCommodity({},1,1,25);event(nil,'AUCTION_HOUSE_AUCTION_CREATED',42)
assert(last().kind=='posted' and last().total==25 and last().auctionId==42)
event(nil,'AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION',3,'Linen Cloth',42)
assert(last().kind=='sale_notice' and last().name=='Linen Cloth')
print('PASS: commodity confirmation, post and sale notification')
local book=ForeverMarketPriceDepth({[16]=1,[87]=465,[88]=888,[89]=205,[90]=458,[95]=182,[99]=75})
assert(book.low==16 and book.lowQty==1 and book.floorPrice==87 and book.floorQty==465)
assert(ForeverMarketPriceDepth({[16]=100,[87]=465}).floorPrice==16)
assert(ForeverMarketPriceDepth({[16]=1,[17]=465}).floorPrice==16)
local ladder={}
for i=1,40 do ladder[i]=2 end
local depth=ForeverMarketPriceDepth(ladder,true)
assert(depth.quantity==80 and depth.high==40 and #depth.levels==32 and depth.levels[32][1]==32)
assert(ForeverMarketPriceDepth(ladder).levels==nil)
print('PASS: isolated undercut, bulk supply, capped tiers and full-book quantity')

invoiceType='seller'
hooks.TakeInboxMoney(1);hooks.TakeInboxMoney(2)
local before=count('proceeds_collected')
money=money+588;event(nil,'PLAYER_MONEY');event(nil,'PLAYER_MONEY')
assert(count('proceeds_collected')==before+2)
print('PASS: two payouts confirmed by one wallet update, counted once')

local previous=count('proceeds_collected')
hooks.TakeInboxMoney(1);hooks.TakeInboxMoney(1);hooks.TakeInboxMoney(2)
money=money+294;event(nil,'PLAYER_MONEY')
assert(count('proceeds_collected')==previous+1)
money=money+294;event(nil,'PLAYER_MONEY')
assert(count('proceeds_collected')==previous+2)
print('PASS: duplicate collection hook and two staged wallet confirmations')


local visible,allocated=false,0
local function noop() end
UIParent={GetEffectiveScale=function() return 1 end}
function CreateFrame()
  allocated=allocated+1
  return {SetFrameStrata=noop,SetFrameLevel=noop,SetPoint=noop,SetSize=noop,EnableMouse=noop,SetScale=noop,
    Show=function() visible=true end,Hide=function() visible=false end,
    CreateTexture=function() return {SetSize=noop,SetPoint=noop,SetColorTexture=noop} end}
end
assert(not ForeverMarketLiveSync())
ForeverMarketActivityStatus();update(nil,1);assert(allocated==0)
assert(ForeverMarketLiveSync(true));ForeverMarketActivityStatus();update(nil,1);assert(visible and allocated==1)
assert(not ForeverMarketLiveSync(false));assert(not visible)
local posted=count('posted')
hooks.PostCommodity({},1,1,25);event(nil,'AUCTION_HOUSE_AUCTION_CREATED',43)
update(nil,1);assert(not visible and count('posted')==posted+1)
event(nil,'PLAYER_LOGOUT');assert(ForeverMarketActivityExport)
print('PASS: optical sync opt-in, immediate off, independent ledger and logout export')
