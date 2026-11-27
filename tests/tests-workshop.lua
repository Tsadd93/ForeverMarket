-- Lua 5.1 integration simulation. Every module below is the installable addon source.
local frames,buttons,tabs={}, {}, {}
local clock,who,wallet=100,'smith',100000
local bags,names,bound,owned={}, {}, {}, {}
local function frame(kind,parent)
  local f={shown=true,parent=parent,scripts={}}
  local function noop() end
  for _,k in ipairs({'EnableMouseWheel','SetVerticalScroll','ClearAllPoints','SetPoint','SetSize','SetHeight','SetWidth','SetJustifyH','SetWordWrap','SetAutoFocus','SetFrameLevel','EnableMouse','SetHighlightTexture','SetScrollChild','ClearFocus','SetTextColor','SetBackdrop','SetBackdropColor','SetBackdropBorderColor','SetTexture','SetColorTexture','SetAtlas','SetFrameStrata'}) do f[k]=noop end
  f.SetText=function(self,x)self.text=tostring(x)end
  f.GetText=function(self)return self.text end
  f.SetScript=function(self,k,fn)self.scripts[k]=fn end
  f.HookScript=f.SetScript
  f.RegisterEvent=function(self,k)self[k]=true end
  f.GetFrameLevel=function()return 1 end
  f.GetVerticalScroll=function()return 0 end;f.GetVerticalScrollRange=f.GetVerticalScroll;f.GetHeight=function()return 400 end
  f.SetEnabled=function(self,b)self.enabled=b end
  f.IsVisible=function(self)return self.shown and (not parent or parent:IsVisible())end
  f.Show=function(self)self.shown=true;if self.scripts.OnShow then self.scripts.OnShow(self) end end
  f.Hide=function(self)self.shown=false;if self.scripts.OnHide then self.scripts.OnHide(self) end end
  f.SetShown=function(self,b)self.shown=b end
  f.CreateFontString=function()return frame('Font')end
  f.CreateTexture=f.CreateFontString
  if kind=='Button' then buttons[#buttons+1]=f end
  return f
end
function CreateFrame(kind,_,p)local f=frame(kind,p);frames[#frames+1]=f;return f end
local function dispatch(e,...)
  for _,f in ipairs(frames) do if f[e] and f.scripts.OnEvent then f.scripts.OnEvent(f,e,...) end end
end
GetTime=function()return clock end
time=function()return clock+1800000000 end
date=function(fmt,ts)return os.date(fmt,ts or time())end
GetRealmName=function()return 'Test' end
GetCurrentRegion=function()return 1 end
UnitFactionGroup=function()return 'Horde' end
UnitGUID=function()return who end
UnitName=function()return who end
GetMoney=function()return wallet end
SlashCmdList={}
C_Item={GetItemCount=function(id)return bags[id] or 0 end,GetItemNameByID=function(id)return names[id] or tostring(id)end,
 GetItemInfo=function(id)return 'Item',nil,1,1,1,nil,nil,20,nil,nil,5,7,nil,bound[id] or 0 end}
local requests,confirms=0,0
C_AuctionHouse={GetItemKeyInfo=function()return{isCommodity=true}end,MakeItemKey=function(id)return {itemID=id}end,
 StartCommoditiesPurchase=function()requests=requests+1 end,ConfirmCommoditiesPurchase=function()confirms=confirms+1 end,
 CancelCommoditiesPurchase=function()end,GetNumOwnedAuctions=function()return #owned end,GetOwnedAuctionInfo=function(i)return owned[i]end}
local function loadPart(name)dofile('src/'..name..'.lua')end
loadPart('History');loadPart('Market');loadPart('Valuation');loadPart('Crafting');loadPart('BuyTab')
local M=ForeverMarketTools
ForeverMarketDB={};ForeverMarketRisk=nil
assert(M.settings().cutBP==500)
ForeverMarketDB={buyTargetBP=750};ForeverMarketRisk={cutBP=1100,marginBP=2000,lostDepositPerUnit=3}
assert(M.settings().cutBP==1100 and ForeverMarketMarginBP()==750 and ForeverMarketDepositLoss(4)==12)
ForeverMarketRisk={cutBP=1200,lostDepositPerUnit=9}
assert(ForeverMarketKeepBP()==8900 and ForeverMarketDepositLoss(4)==12)
M.settings().cutBP=500;M.settings().lostDepositPerUnit=0
print('PASS: standalone defaults, existing target and migration, independent fee settings')
local book={}
ForeverMarketDB.__depth={[M.scope()]=book}
local function depth(id,p,n)
  book[id]={at=time(),low=p,lowQty=n,floorPrice=p,levels={{p,n}}}
end
local mat,out=10,100
depth(mat,2000,100);depth(out,30002,10)
local recipes={};local professions={'Blacksmithing','Alchemy','Tailoring','Leatherworking','Engineering','Cooking','First Aid','Mining','Enchanting','Jewelcrafting','Inscription'}
for i,name in ipairs(professions) do recipes[i]={name=name,output=out,learned=true} end
recipes[99]={name='Unlearned',output=out,learned=false}
C_TradeSkillUI={
 GetAllRecipeIDs=function()local t={99};for i in ipairs(professions) do t[#t+1]=i end;return t end,
 GetRecipeInfo=function(i)return recipes[i]end,
 GetRecipeSchematic=function(i)return {quantityMin=1,quantityMax=1,outputItemID=recipes[i].output,reagentSlotSchematics={{required=true,quantityRequired=2,reagents={{itemID=mat}}}}} end}
M.capture(false)
assert(not M.account().recipes.s99)
for i in ipairs(professions) do local e=M.estimate(M.account().recipes['s'..i],1)
 assert(e and e.cash==4000 and e.profit==24500 and e.net==28500 and e.extra==24500,professions[i])
end
local r=M.account().recipes.s1
assert(M.queue('s1',1) and M.queue('s2',1) and M.materials()[mat]==4)
bags[mat]=1;assert(M.missing(mat,4)==3);bags[mat]=nil
assert(M.queue('s2',0));assert(M.reserve()==4000)
book[mat].levels={{100,1},{3900,2}}
assert(M.cost(mat,2)==4000 and M.cost(mat,4)==nil)
depth(mat,2000,100)
bags[mat]=2;local e=M.estimate(r,1);assert(e.cash==0 and e.extra==28500-ForeverMarketSaleNet(1998*2));bags[mat]=nil
bound[out]=1;assert(not M.estimate(r,1));bound[out]=nil
r.ready=time()+10;assert(not M.estimate(r,1));r.ready=time()
r.output=nil;assert(not M.estimate(r,1));r.output=out
r.yield=2;assert(M.estimate(r,1).net==57000);r.yield=1
who='alt';assert(next(M.account().recipes)==nil and next(M.materials())==nil);who='smith'
print('PASS: learned recipes, character isolation, full tier quantities, shared reagents, owned materials, services, bound output, cooldown and yield')
-- Legacy trade and craft windows, including headers and a profession with no recipes.
C_TradeSkillUI=nil
GetTradeSkillLine=function()return 'Leatherworking'end
GetNumTradeSkills=function()return 2 end
GetTradeSkillInfo=function(i)if i==1 then return 'Header','header' end;return 'Boots','optimal' end
GetTradeSkillRecipeLink=function()return '|Henchant:999|h' end
GetTradeSkillItemLink=function()return 'item:100'end
GetTradeSkillNumReagents=function()return 1 end
GetTradeSkillReagentInfo=function()return 'Material',nil,2 end
GetTradeSkillReagentItemLink=function()return 'item:10'end
GetTradeSkillNumMade=function()return 1,2 end
M.capture(false);assert(M.account().recipes.s999.maxYield==2)
GetNumCrafts=function()return 1 end;GetCraftDisplaySkillLine=function()return 'Enchanting' end
GetCraftInfo=function()return 'Enchant Bracer',nil,'optimal'end
GetCraftNumReagents=GetTradeSkillNumReagents;GetCraftReagentInfo=GetTradeSkillReagentInfo;GetCraftReagentItemLink=GetTradeSkillReagentItemLink
M.capture(true);assert(not M.estimate(M.account().recipes['Enchanting/Enchant Bracer'],1))
GetNumTradeSkills=function()return 0 end;M.capture(false)
print('PASS: legacy trade window, enchant service window, empty gathering skill and per-character recipe retention')
AuctionHouseFrame=frame();AuctionHouseFrame.AuctionsFrame=frame()
ForeverMarketResults=function()end
ForeverMarketHover=function()return frame()end
ForeverMarketTab=function(_,p,name)tabs[name]=p;p.selectTab=function()for _,v in pairs(tabs)do v:Hide()end;p:Show()end end
loadPart('Workshop');dispatch('AUCTION_HOUSE_SHOW')
M.openMaterials()
assert(M.startMaterial(mat));dispatch('COMMODITY_PRICE_UPDATED',2001,4002)
assert(not M.quote and confirms==0)
assert(M.startMaterial(mat));dispatch('COMMODITY_PRICE_UPDATED',2000,4000)
assert(M.confirmMaterial());assert(not M.confirmMaterial() and confirms==1)
ForeverMarketFundActivity('purchase',{itemId=mat,quantity=2,total=4000})
assert(ForeverMarketFundCash()==6000 and M.account().transit[mat]==2 and M.missing(mat,2)==0)
M.onActivity('purchased_item_received',{itemId=mat,quantity=2});bags[mat]=2
dispatch('UNIT_SPELLCAST_START','player','cast',1)
bags[mat]=0;bags[out]=1
dispatch('UNIT_SPELLCAST_SUCCEEDED','player','cast',1)
assert(not M.account().build.s1 and ForeverMarketTradingFund().held[out].cost==4000)
ForeverMarketFundPost(out,1,30000,20,out)
local post={itemId=out,quantity=1,total=30000,deposit=20,name='Product',auctionId=7,at=time()}
ForeverMarketFundActivity('posted',post);M.onActivity('posted',post)
ForeverMarketFundActivity('sale_notice',{auctionId=7});M.onActivity('sale_notice',{auctionId=7})
local payout={invoiceType='seller',name='Product',quantity=1,amount=28520,fee=1500,deposit=20,at=time()}
M.mailSnapshot({{name='Product',qty=1,amount=28520,key='product'}})
local _,incoming,_,waiting=M.saleTotals();assert(incoming==28520 and waiting==0)
payout.mailRevision=M.account().mailRevision
ForeverMarketFundActivity('proceeds_collected',payout);M.onActivity('proceeds_collected',payout)
assert(ForeverMarketFundCash()==34500)
local _,pending,collected=M.saleTotals();assert(pending==0 and collected==28520)
owned={{status=0,buyoutAmount=3000,quantity=3},{status=1,buyoutAmount=500,quantity=1}}
assert(M.saleTotals()==3000)
owned[1].quantity=2;owned[1].buyoutAmount=2000;assert(M.saleTotals()==2000)
owned={};assert(M.saleTotals()==0)
print('PASS: price rise, explicit confirmation, budget, duplicate click, mailbox, craft, returned deposit and exact 2g45s fund gain, partial listing and cancellation')
local lines={}
local tip={AddDoubleLine=function(_,x,y)lines[x]=y end,AddLine=function()end,Show=function()end}
C_Container={GetContainerItemInfo=function()return {itemID=out,stackCount=5} end}
ItemLocation={CreateFromBagAndSlot=function()return {} end}
C_AuctionHouse.GetItemKeyFromItem=function()return {itemID=out} end
C_AuctionHouse.GetItemCommodityStatus=function()return 2 end
Enum={ItemCommodityStatus={Item=1}}
M.tooltip(tip,0,1)
assert(lines['Post at']==ForeverMarketCoins(30000)..'   /   '..ForeverMarketCoins(150000))
assert(lines['After AH cut']==ForeverMarketCoins(28500)..'   /   '..ForeverMarketCoins(142500))
assert(lines.Vendor==ForeverMarketCoins(5)..'   /   '..ForeverMarketCoins(25))
local postCall
Enum.TooltipDataType={Item=0}
TooltipDataProcessor={AddTooltipPostCall=function(kind,fn)assert(kind==0);postCall=fn end}
M.installItemTooltips()
local function resetTip() for k in pairs(lines) do lines[k]=nil end end
resetTip();postCall(tip,{hyperlink='item:'..out,id=out})
assert(lines['AH estimate']==ForeverMarketCoins(30000) and lines.Vendor==ForeverMarketCoins(5) and lines['Forever Market']=='Per item')
tip.GetProcessingTooltipInfo=function()return {getterName='GetBagItem',getterArgs={0,1}} end
resetTip();postCall(tip,{id=out});assert(lines['Post at']==ForeverMarketCoins(30000)..'   /   '..ForeverMarketCoins(150000))
tip.GetProcessingTooltipInfo=nil
TooltipDataProcessor=nil
ItemRefTooltip={HasScript=function()return true end,HookScript=function(_,_,fn)postCall=fn end,GetOwner=function()return nil end,GetItem=function()return 'Product','item:'..out end,AddDoubleLine=tip.AddDoubleLine,AddLine=tip.AddLine}
M.installItemTooltips();resetTip();postCall(ItemRefTooltip);assert(lines['AH estimate']==ForeverMarketCoins(30000));ItemRefTooltip=nil
print('PASS: modern linked-item and bag paths; legacy clicked chat item')
print('PASS: production bag tooltip per item/stack, AH cut and vendor values')


-- Confirm the protected Sell path checks reservations again at the actual click.
local seenRows={}
ForeverMarketHover=function(_,_,_,row)seenRows[#seenRows+1]=row;return frame()end
ForeverMarketRowIcon=function(id)return tostring(id)end
local slots={{itemID=mat,stackCount=2,hyperlink='item:10'},{itemID=out,stackCount=1,hyperlink='item:100'}}
bags[mat]=2;bags[out]=1
C_Container.GetContainerNumSlots=function(bag)return bag==0 and #slots or 0 end
C_Container.GetContainerItemInfo=function(_,slot)return slots[slot]end
ItemLocation.CreateFromBagAndSlot=function(_,bag,slot)return {slot=slot}end
C_AuctionHouse.GetItemKeyFromItem=function(loc)return {itemID=slots[loc.slot].itemID} end
C_AuctionHouse.IsSellItemValid=function()return true end
C_AuctionHouse.CalculateCommodityDeposit=function()return 10 end
Enum.ItemCommodityStatus.Commodity=2
book[mat].floorQty=100;book[out].floorQty=10
local posts=0
C_AuctionHouse.PostCommodity=function(loc,_,n,p)posts=posts+1;assert(slots[loc.slot].itemID==out and n==1 and p==30000)end
loadPart('SellTab');dispatch('AUCTION_HOUSE_SHOW')
M.queue('s1',1)
tabs['Market Sell'].selectTab()
assert(seenRows[1].slot.k.itemID==out and seenRows[2].detail.text=='Reserved for crafting')
seenRows[2].post.scripts.OnClick();assert(posts==0)
seenRows[1].post.scripts.OnMouseDown();seenRows[1].post.scripts.OnClick();assert(posts==1)
M.queue('s1',0)
print('PASS: reserved reagents stay below ready posts, cannot be posted, one click posts at the tooltip price')
dispatch('AUCTION_HOUSE_AUCTION_CREATED')
slots[2].stackCount=20;bags[out]=20
local depositQty
C_AuctionHouse.CalculateCommodityDeposit=function(_,_,qty)depositQty=qty;return qty end
dispatch('BAG_UPDATE_DELAYED')
local function outRow() for _,row in ipairs(seenRows) do if row.slot and row.slot.k.itemID==out then return row end end end
local function editQuantity(n)
  local box=outRow().qty;box:SetText(n);box.scripts.OnTextChanged(box,true)
end
for _,bad in ipairs({'0','','21','1.5','1e1'}) do
  editQuantity(bad);assert(outRow().hold);outRow().post.scripts.OnClick();assert(posts==1)
end
editQuantity('16');assert(outRow().price.text==ForeverMarketCoins(16*30000))
-- A bag change between quote and click must require another review.
slots[2].stackCount=19;outRow().post.scripts.OnClick();assert(posts==1)
slots[2].stackCount=20;dispatch('BAG_UPDATE_DELAYED')
C_AuctionHouse.PostCommodity=function(loc,duration,n,p)
  assert(loc.slot==2 and duration==1 and n==16 and p==30000 and depositQty==16)
  posts=posts+1;slots[2].stackCount=slots[2].stackCount-n
end
outRow().post.scripts.OnMouseDown();outRow().post.scripts.OnClick()
assert(posts==2 and slots[2].stackCount==4)
dispatch('AUCTION_HOUSE_AUCTION_CREATED')
assert(outRow().qty:GetText()=='4')
print('PASS: edit 20 to 16, recalculate deposit and stack total, reject invalid and changed stacks, retain four')


-- Individually auctioned materials: confirm only the exact live auction, reject replacement.
bags[mat]=0;M.queue('s1',1);local offer={auctionID=551,itemKey={itemID=mat},quantity=1,buyoutAmount=1900}
C_AuctionHouse.GetItemKeyInfo=function()return {isCommodity=false} end
C_AuctionHouse.GetNumItemSearchResults=function()return 1 end
C_AuctionHouse.GetItemSearchResultInfo=function()return offer end
C_AuctionHouse.SendSearchQuery=function()end
local bids=0;C_AuctionHouse.PlaceBid=function(id,p)assert(id==551 and p==1900);bids=bids+1 end
M.openMaterials();assert(M.startMaterial(mat));dispatch('ITEM_SEARCH_RESULTS_UPDATED',{itemID=mat})
offer.buyoutAmount=2100;assert(not M.confirmMaterial() and bids==0)
offer.buyoutAmount=1900
assert(M.startMaterial(mat));dispatch('ITEM_SEARCH_RESULTS_UPDATED',{itemID=mat});assert(M.confirmMaterial() and bids==1)
assert(M.missing(mat,2)==1)
ForeverMarketFundActivity('purchase',{itemId=mat,auctionId=551,quantity=1,total=1900})
assert(M.missing(mat,2)==1)
print('PASS: equipment-style reagent auction, stale listing rejection and in-flight quantity reservation')

local account=M.account();local before=account.collected[date('%Y-%m-%d')]
M.mailSnapshot({{key='A',name='Twins',qty=1,amount=25},{key='A',name='Twins',qty=1,amount=25}})
local revision=account.mailRevision
M.mailSnapshot({{key='A',name='Twins',qty=1,amount=25}})
M.onActivity('proceeds_collected',{mailRevision=revision,name='Twins',quantity=1,amount=25,invoiceType='seller',at=time()})
local _,unpaid,earned=M.saleTotals();assert(unpaid==25 and earned==before+25)
local saved=ForeverMarketDB
loadPart('Valuation');loadPart('Crafting');M=ForeverMarketTools
assert(ForeverMarketDB==saved and M.account().build.s1==1 and M.saleTotals()==0)
local _,unpaidAgain,earnedAgain=M.saleTotals();assert(unpaidAgain==unpaid and earnedAgain==earned)
print('PASS: identical payouts with reordered wallet/mailbox events and persistence across module reload')


loadPart('Manager')
assert(M.importList('FM1;10,7,100;100,5,200'))
assert(M.exportList()=='FM1;10,7,100;100,5,200' or M.exportList()=='FM1;100,5,200;10,7,100')
assert(not M.importList('FM1;10,2,3;invalid') and M.restockList()[10].keep==7)
assert(M.materials()[10]>=7)
M.trackAcquisition('Ore',20)
M.recordMarket('purchase',{name='Ore',quantity=20,total=1000})
M.settleLot({},{name='Ore',quantity=12,amount=1260,deposit=60},12,600)
M.recordMarket('proceeds_collected',{name='Ore',invoiceType='seller',at=time(),quantity=12,amount=1260})
assert(M.saleCount('Ore')==12)
local ledger=M.account().manager.ledger.Ore
assert(ledger.tracked-ledger.matched==8 and ledger.earned==600 and ledger.proceeds==1260)
M.account().manager.rules['class7']='Keep';assert(M.rule(mat)=='Keep')
M.account().manager.rules[mat]='Quick';assert(M.rule(mat)=='Quick')
ForeverMarketSetVenue(true);assert(M.scope()=='Test [Neutral AH]|Horde' and not next(ForeverMarketHistory()))
ForeverMarketObserve('2589',16,1);ForeverMarketSetVenue(false)
assert(not ForeverMarketHistory()['2589'])
print('PASS: restock sharing, atomic import, sale speed, partial realized profit, rule precedence and neutral isolation')

hooksecurefunc=function()end
owned={{auctionID=987,itemKey={itemID=mat},status=0,quantity=2,buyoutAmount=60}}
C_AuctionHouse.CanCancelAuction=function()return true end
C_AuctionHouse.GetCancelCost=function()return 7 end
local cancels=0
C_AuctionHouse.CancelAuction=function(id)assert(id==987);cancels=cancels+1 end
M.openManager()
local function clickManager(text)
  for i=#buttons,1,-1 do local b=buttons[i];if b.text==text and b:IsVisible() then b.scripts.OnClick(b);return end end
  error('Missing button '..text)
end
clickManager('Cancel');assert(cancels==0)
C_AuctionHouse.GetCancelCost=function()return 8 end
clickManager('Confirm');assert(cancels==0)
clickManager('Confirm');assert(cancels==1)
clickManager('Shopping');clickManager('Ledger');clickManager('Rules')
GetNumLootItems=function()return 1 end
GetLootSlotLink=function()return 'item:'..mat end
GetLootSlotInfo=function()return nil,nil,2 end
dispatch('UNIT_SPELLCAST_START','player','cast1',13262)
dispatch('UNIT_SPELLCAST_SUCCEEDED','player','cast1',13262)
dispatch('LOOT_OPENED')
slots[1].stackCount=slots[1].stackCount+2;slots[2].stackCount=slots[2].stackCount-1
dispatch('LOOT_CLOSED')
local sample=M.account().manager.samples[out]
assert(sample and sample.count==1 and sample.outputs[mat]==2)
print('PASS: manager navigation, changed cancellation fee reconfirmation and measured disenchant yields')

loadPart('TradeDesk')
assert(M.goldInput('3g 8s 5c')==30805 and M.goldInput('1.25')==12500)
assert(not M.goldInput('3s4s') and not M.goldInput('oops'))
local book={books={[10]={low=4,lowQty=2,floorPrice=6,floorQty=10},[100]={low=9,lowQty=1,floorPrice=9,floorQty=1}}}
local find=M.findOffers({term='item:10',max=5,vendor=true},book)
assert(#find==1 and find[1].id==10)
assert(#M.findOffers({term='',max=3},book)==0)
assert(M.applyGroup('FMG1;10,100;6;25;8;50;16;2'))
assert(M.group(10).stock==50 and M.group(10).margin==8 and M.postOptions(100).duration==2)
assert(not M.applyGroup('FMG1;10,,100;1;2;3;4;5;1') and M.group(10).stock==50)
assert(M.favorite(10) and M.restockList()[10].keep==6 and M.postOptions(100).size==16)
who='bankalt';dispatch('PLAYER_ENTERING_WORLD')
who='smith';dispatch('PLAYER_ENTERING_WORLD')
local transfer,buy=M.transferPlan(mat,20)
assert(transfer:find('bankalt',1,true) and buy==20-slots[1].stackCount)
M.account().useTransfers=true;assert(M.missing(mat,20)<=buy);M.account().useTransfers=false
ForeverMarketSnapshot=function()book.at=GetTime();return book end
M.openDesk();clickManager('Save search');clickManager('Saved');clickManager('Trade groups');clickManager('Back')
print('PASS: Browse and saved search, vendor arithmetic, group validation, stock cap and duration, transferable stock across characters')


C_AuctionHouse.GetItemKeyInfo=function()return {isCommodity=true} end
local oldkeep=M.restockList()[mat]
M.restockList()[mat]=nil
loadPart('Workshop');M.openMaterials()
local initialConfirms=confirms
assert(M.startMaterial(mat,{n=2,cap=17}))
dispatch('COMMODITY_PRICE_UPDATED',18,36)
assert(not M.quote and confirms==initialConfirms)
assert(M.startMaterial(mat,{n=2,cap=17}))
dispatch('COMMODITY_PRICE_UPDATED',17,34)
assert(M.quote.direct and M.quote.total==34)
assert(M.confirmMaterial() and confirms==initialConfirms+1 and M.restockList()[mat]==nil)
M.restockList()[mat]=oldkeep
print('PASS: standalone shopping rejects a changed live price, confirms exact quantity and preserves restock targets')


local filtered,cursor=M.findOffers({term='',max=0},book,{},nil,1)
while cursor do filtered,cursor=M.findOffers({term='',max=0},book,filtered,cursor,1) end
assert(#filtered==2 and filtered[1].id==mat)
M.account().manager.rules[out]="Quick"
local first=posts
slots[2].stackCount=20;bags[out]=20
M.restockList()[out]=nil;M.restockList()[mat]={keep=999,cap=0}
book.books[out].floorPrice=30002;book.books[out].floorQty=20;book.books[out].low=30002
C_AuctionHouse.CalculateCommodityDeposit=function(_,d,n) if n==16 then assert(d==2) end;return 10 end
C_AuctionHouse.PostCommodity=function(loc,d,n,p)assert(loc.slot==2 and d==2 and n==16);posts=posts+1;slots[2].stackCount=4 end
tabs['Market Sell'].selectTab();dispatch('BAG_UPDATE_DELAYED')
local postNext
for _,b in ipairs(buttons) do if b.text=='Post next' and b:IsVisible() then postNext=b end end
assert(postNext and outRow().qty:GetText()=='16')
postNext.scripts.OnMouseDown();postNext.scripts.OnClick()
assert(posts==first+1 and slots[2].stackCount==4)
print('PASS: paged search returns each item once and Post next honors the group quantity and 24-hour deposit')


dispatch('AUCTION_HOUSE_AUCTION_CREATED')
local pin=outRow().quote;assert(pin and pin.floorPrice)
clock=clock+180
dispatch('BAG_UPDATE_DELAYED');assert(outRow().quote==pin and not outRow().needsCheck)
tabs['Market Sell'].selectTab();assert(outRow().quote==pin)
outRow().hover.scripts.OnMouseUp(nil,'RightButton');assert(outRow().needsCheck)
print('PASS: Sell quote survives three minutes, bag refresh and tab reopen; right-click releases it')

local a=M.account()
a.sales[923]={qty=10,amount=2000,deposit=60}
owned={{auctionID=923,status=0,quantity=7,buyoutAmount=200},{status=0,quantity=3,unitPrice=75},{status=1,quantity=1,bidder='Buyer',bidAmount=210,buyoutAmount=300}}
local gross,_,_,_,sold=M.saleTotals();assert(gross==1625 and sold==210)
local day=date('%Y-%m-%d',time())
a.collected[day]=0;a.receiptsRebuilt=nil
local function evt(kind,amount,gold)
 return {kind=kind,character=UnitName('player'),realm=GetRealmName(),faction='Horde',region=1,at=time(),name='Ore',invoiceType='seller',amount=amount,gold=gold}
end
ForeverMarketActivity={events={evt('collection_requested',690,1000),evt('collection_requested',166,1000),evt('wallet',nil,1690),evt('proceeds_collected',166,1856),evt('wallet',nil,1856)}}
M.restoreCollected();M.restoreCollected();assert(a.collected[day]==856)
print('PASS: remaining listing quantities, bid settlement and idempotent wallet-history repair')

