-- Isolated client adapter for the new standalone workflows.
local now=1795719072
time=function()return now end;GetTime=time
UnitName=function()return 'Rogue' end;UnitGUID=function()return 'player' end
GetCurrentRegion=function()return 1 end;UnitFactionGroup=function()return 'Horde' end
ForeverMarketVenueRealm=function()return 'Realm 6926'end
ForeverMarketEventRealm=function(e)return e.realm end
ForeverMarketCoins=tostring;ForeverMarketSaleNet=function(n)return math.floor(n*.95)end
CreateFrame=function()return {RegisterEvent=function()end,SetScript=function(self,k,fn)self[k]=fn;_G.event=fn end}end
GetZoneText=function()return 'Hillsbrad' end
local a={recipes={},build={},transit={},stockName='Rogue',stockScope='realm',stock={},manager={lists={Raid={[10]={keep=20,cap=20}}},active='Raid'}}
local alt={recipes={},stockName='Smith',stockScope='realm',stock={}}
ForeverMarketDB={characters={player=a,alt=alt},__sellBlacklist={player={[90]=true}}}
local inv={[10]=4,[90]=1}
local books={[10]={{10,2},{15,3}},[11]={{35,100}},[12]={{100,100}},[13]={{5,100}}}
local source={}
local M={account=function()return a end,inventoryScope=function()return 'realm'end,bagCount=function(id)return inv[id] or 0 end,
 restockList=function()return a.manager.lists[a.manager.active] end,materials=function()return {}end,invalidate=function()end,
 sources=function(id)return source[id] or {} end,inputs=function(r)return r.materials end,prices=function()return 10 end}
ForeverMarketTools=M
function M.cost(id,n)
 local total=0
 for _,t in ipairs(books[id] or {}) do local k=math.min(n,t[2]);total=total+k*t[1];n=n-k end
 return n==0 and total or nil
end
C_AuctionHouse={MakeItemKey=function(id)return {itemID=id}end,GetItemKeyInfo=function()return {isCommodity=true}end}
C_Item={GetItemNameByID=function(id)return 'Item '..id end,GetItemInfo=function(id)
 if id=='Linen Cloth' then return id,'item:10' end
 return 'Item '..id,'item:'..id,1,1,1,'Trade','Misc',20,'',0,2,7,0,0
end}
local fund={lots={},itemOrders={}};ForeverMarketTradingFund=function()return fund end
C_Container={GetContainerNumSlots=function(b)return b==0 and 2 or 0 end,GetContainerItemInfo=function(_,s)
 local id=s==1 and 10 or 90;return {itemID=id,hyperlink='item:'..id,stackCount=inv[id]}
end}
dofile('src/Operations.lua')
source[10]={{own=true,place='mail',n=3,at=now},{own=true,place='bank',n=2,at=now}}
a.transit[10]=3
local rows,total,unknown=M.shoppingTrip()
assert(rows[1].missing==11 and rows[1].n==5 and rows[1].subtotal==65 and unknown==1)
a.manager.lists.Raid[10].keep=13
rows,total,unknown=M.shoppingTrip();assert(total==50 and unknown==0)
print('PASS: partial tier supply, full basket total, bank/mail coverage without double-counting transit')
local p=M.importPreview('*** Raid\n"Linen Cloth" x5\nunknown filter^class','Imported')
assert(p.items[10]==5 and #p.skipped==1 and a.manager.lists.Imported==nil)
M.applyPreview(p);assert(a.manager.active=='Imported' and M.restockList()[10].keep==5)
p=M.importPreview('group:Ore,i:12,i:13,operation:skip','Ore');M.applyPreview(p)
assert(a.desk.savedGroups.Ore and not p.items[0] and #p.skipped==2)
print('PASS: preview, skips, quantity and item-only TSM import into named group')
assert(M.setRoute(nil,'Smith',0):find('Saved'))
M.setRoute(10,'Smith',3);local ship=M.shipments()
assert(#ship==1 and ship[1].n==1)
SendMailFrame={IsShown=function()return true end};SendMailNameEditBox={GetText=function()return 'Wrong' end}
CursorHasItem=function()return false end
assert(M.attachShipment(ship[1]):find('another character'))
print('PASS: routing respects protected items, keep quantities and existing recipient')
a.recipes.s={key='s',name='Bars',output=11,yield=1,materials={[13]=2}}
alt.recipes.b={key='b',name='Blade',output=12,yield=1,materials={[11]=2}}
local cash,steps=M.supplyPlan(12,2)
assert(cash==40 and steps[#steps].detail=='Smith / Blade' and steps[#steps-1].action=='Craft')
M.saveSupplyPlan({id=12,n=2,cost=cash,steps=steps});assert(M.restockList()[13].keep==8)
a.recipes.s.materials={[12]=1};assert(M.supplyPlan(12,1)==70)
print('PASS: cross-character recursive shopping and ordered crafts, cycle bounded')
ForeverMarketActivity={events={}}
ForeverMarketHistory=function()return {['10']={floors={[math.floor(now/86400)]=10},bulkHigh={},a={}}}end
local series=M.historySeries(10,30);assert(#series==30 and not series[29].ask and series[30].ask==10)
M.farmStart('Test');M.farmLoot(10,2);now=now+60;M.farmStop()
local s=a.farming[1];assert(s.elapsed==60 and s.vendor==4 and s.market==19)
M.farmActivity('posted',{auctionId=1,itemId=10,quantity=2,total=20,name='Cloth',at=now})
M.farmActivity('sale_notice',{auctionId=1})
M.farmActivity('proceeds_collected',{invoiceType='seller',quantity=2,amount=22,fee=1,deposit=3,name='Cloth'})
assert(s.returned==19)
print('PASS: chart missing days, timed loot, vendor and market estimates, confirmed farm proceeds')

source[10][2].who='Rogue'
local c,stock=M.supplyPlan(10,6)
assert(c==0 and stock[1].n==4 and stock[2].n==2 and stock[2].detail=='Rogue bank')
ForeverMarketActivity.events={{kind='proceeds_collected',invoiceType='seller',name='Item 10',region=1,
 realm='Realm 6926',faction='Horde',character='Rogue',amount=22,fee=1,deposit=3,quantity=2,at=now}}
assert(M.historySeries(10,7)[7].sale==10)
date=os.date
local function widget()
 local w={shown=true,text=''}
 function w:SetText(t)self.text=t end
 function w:GetText()return self.text end
 function w:Show()self.shown=true end
 function w:Hide()self.shown=false end
 function w:IsShown()return self.shown end
 function w:SetScript(k,v)self[k]=v end
 w.CreateTexture=widget;w.CreateFontString=widget
 return setmetatable(w,{__index=function(_,k)
   if k=='TitleText' then return nil end
   return function()end
 end})
end
CreateFrame=widget;M.cancelMaterial=function()end
dofile('src/ToolsWindow.lua')
for _,tab in ipairs({'Basket','Mail & bank','Supply plan','History','Farming','Import'}) do M.openTools(tab,10) end
print('PASS: standalone window renders all six tabs including chart and paid invoices')
