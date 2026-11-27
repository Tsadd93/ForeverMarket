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
assert(rows[1].missing==11 and rows[1].n==5 and rows[1].subtotal==65 and total==65 and unknown==1)
ForeverMarketSpendable=function()return 30 end
local budgetRows,budgetTotal,_,budgetLeft=M.shoppingTrip()
assert(budgetRows[1].n==2 and budgetTotal==20 and budgetLeft==9)
ForeverMarketSpendable=nil
a.manager.lists.Raid[10].cap=11
local capRows,capTotal,_,capLeft=M.shoppingTrip()
assert(capRows[1].n==2 and capTotal==20 and capLeft==9)
a.manager.lists.Raid[10].cap=20
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
local surfaces={}
local function widget(kind,_,parent)
 local w={shown=true,text='',kind=kind,parent=parent}
 surfaces[#surfaces+1]=w
 function w:SetPoint(_,x,y)if type(x)=='number' then self.x=x;self.y=-y end end
 function w:SetSize(width,height)self.width=width;self.height=height end
 function w:SetWidth(width)self.width=width end
 function w:SetHeight(height)self.height=height end
 function w:SetScale(scale)self.scale=scale end
 function w:SetShown(v)self.shown=v end
 function w:SetText(t)self.text=t end
 function w:GetText()return self.text end
 function w:Show()self.shown=true end
 function w:Hide()self.shown=false end
 function w:IsShown()return self.shown end
 function w:SetScript(k,v)self[k]=v end
 function w:CreateTexture()return widget('Texture',nil,self)end
 function w:CreateFontString()return widget('Font',nil,self)end
 return setmetatable(w,{__index=function(_,k)
   if k=='TitleText' then return nil end
   return function()end
 end})
end
CreateFrame=widget;M.cancelMaterial=function()end
dofile('src/MarketDesk.lua')
local advanced=M.importPreview('ore^^^^^^^^0.001^0.002^2^^^4','OreSearch')
assert(#advanced.filters==1 and advanced.filters[1].minPrice==10 and advanced.filters[1].max==20)
M.applyPreview(advanced)
local snap={books={}};AuctionHouseFrame={IsShown=function()return true end}
ForeverMarketSnapshot=function()return snap end;ForeverMarketReadySnapshot=ForeverMarketSnapshot
M.findOffers=function(rule)return {{id=10}} end
M.runBasket();M.stepBasket();M.stepBasket()
assert(M.tripTargets()[10].keep==4 and M.tripTargets()[10].cap==20)
M.restockList()[10]={keep=7,cap=11}
assert(M.tripTargets()[10].keep==7 and M.tripTargets()[10].cap==11)
M.removeBasketFilter(1);M.restockList()[10]=nil
local current={reserve=2,postCap=4,craftPct=0,realmPct=80}
M.group=function()return current end
C_AuctionHouse.GetNumOwnedAuctions=function()return 1 end
C_AuctionHouse.GetOwnedAuctionInfo=function()return {itemKey={itemID=10},quantity=2,status=0}end
assert(M.policyFloor(10,true)==8 and M.checkPostPolicy(10,1,7,true):find('floor'))
assert(M.checkPostPolicy(10,3,20,true):find('reserve'))
current.reserve=0
assert(M.checkPostPolicy(10,3,20,true):find('cap') and not M.checkPostPolicy(10,2,20,true))
current.craftPct=120
assert(M.checkPostPolicy(10,1,20,true):find('recipe'))
M.clearRoute(10);M.bankOpen=true
M.restockList()[10]={keep=6,cap=0}
local oldSlots,oldInfo=C_Container.GetContainerNumSlots,C_Container.GetContainerItemInfo
C_Container.GetContainerNumSlots=function(b)return b==-1 and 1 or b==0 and 3 or 0 end
C_Container.GetContainerItemInfo=function(b,s)
  if b==-1 then return {itemID=10,stackCount=12} elseif s<3 then return oldInfo(b,s) end
end
C_Container.GetContainerNumFreeSlots=function()return 1,0 end
local cursor=false
CursorHasItem=function()return cursor end
C_Container.SplitContainerItem=function(b,s,n)assert(b==-1 and n==2);cursor=true end
C_Container.PickupContainerItem=function(b,s)assert(b==0 and s==3);cursor=false;inv[10]=6 end
local queue=M.bankQueue();assert(queue[1].n==2 and M.withdraw(queue[1]):find('requested') and #M.bankQueue()==0)
M.setRoute(10,'Smith',3);assert(M.bankQueue()[1].label:find('Smith'))
M.bankOpen=false;M.guildOpen=true;inv[10]=4
GetCurrentGuildBankTab=function()return 2 end
GetGuildBankTabInfo=function()return 'Guild tab',nil,true,true,5,0 end
GetGuildBankItemLink=function(_,s)if s==1 then return 'item:10' end end
GetGuildBankItemInfo=function()return nil,12,false end
assert(#M.bankQueue()==0)
GetGuildBankTabInfo=function()return 'Guild tab',nil,true,true,5,3 end
assert(M.bankQueue()[1].n==2 and M.bankQueue()[1].guild)
M.guildOpen=false;C_Container.GetContainerNumSlots=oldSlots;C_Container.GetContainerItemInfo=oldInfo
print('PASS: shopping filter migration, exact targets, posting floors, caps, personal and guild logistics')
dofile('src/ToolsWindow.lua')
for _,tab in ipairs({'Basket','Mail & bank','Supply plan','History','Farming','Import'}) do M.openTools(tab,10) end
print('PASS: standalone window renders all six tabs including chart and paid invoices')

fund.flips={{at=now-3600,n=4,sold=2,cost=100,net=80,lost=3,expected=40,name='Ore',firstPaid=now-1800},
 {at=now-8*86400,n=1,sold=0,cost=70,net=0,name='Cloth'},
 {at=now-7200,n=1,sold=1,cost=22,net=30,invest=true,name='Sash'}}
local r=M.tradeResults(7,false)
assert(r.spent==100 and r.open==50 and r.profit==27 and r.forecast==20 and r.timed==1 and r.delay==1800)
assert(M.tradeResults(30,false).spent==170 and M.tradeResults(7,true).profit==8 and not M.tradeResults(7,true).delay)
M.scope=function()return 'Realm 6926|Horde' end
C_Item.GetItemInfoInstant=function()return 77,nil,nil,'INVTYPE_WAIST' end
local k={itemID=77,itemLevel=18,itemSuffix=9}
local rows={{100,9},{120,9},{1000,9},{60,3}}
C_AuctionHouse.GetItemSearchResultInfo=function(_,i)local row=rows[i];return {itemKey={itemID=77,itemLevel=18,itemSuffix=row[2]},itemLink='item:77',quantity=1,buyoutAmount=row[1]} end
M.recordGearBook(k,#rows)
local g=M.gearEvidence(k,'item:77');assert(g.exact==120 and g.other==60 and g.last.rows==3 and g.days==1)
now=now+86400;rows={{140,9},{80,3}};M.recordGearBook(k,#rows);g=M.gearEvidence(k,'item:77')
assert(g.exact==130 and g.days==2 and g.low==60 and g.high==80 and g.otherDays==2)
dofile('src/Session.lua');dofile('src/PriceRules.lua');dofile('src/Migration.lua');dofile('src/SessionViews.lua')
ForeverMarketPostingPreview=function()return {ready=0,hold=0,checking=0,gross=0,rows={}} end
for _,resolution in ipairs({{1920,1080},{3840,2160}}) do
 UIParent={GetWidth=function()return resolution[1]/2.5 end,GetHeight=function()return resolution[2]/2.5 end}
 for _,tab in ipairs({'Home','Results','Preview','Basket','History','Import','Supply plan','Mail & bank','Farming','Watches','Realm coverage','Conversions','Conversion detail','Run detail','Comparison','Rule presets','Scan results','Sell session'}) do
  M.openTools(tab,10)
  local panel;for _,w in ipairs(surfaces) do if rawget(w,'width')==695 then panel=w;break end end
  assert(panel and panel.width*panel.scale<=UIParent:GetWidth() and panel.height*panel.scale<=UIParent:GetHeight())
  local rects={}
  for _,w in ipairs(surfaces) do
   if w.parent==panel and w.shown and rawget(w,'x') and rawget(w,'width') and
     (w.kind=='Button' or w.kind=='Font' and w.text~='') then
    local x,y,width,height=w.x,w.y,w.width,rawget(w,'height') or 16
    assert(x>=0 and y>=0 and x+width<=695 and y+height<=398,tab..' bounds: '..w.text)
    for _,b in ipairs(rects) do
     assert(x>=b[1]+b[3] or b[1]>=x+width or y>=b[2]+b[4] or b[2]>=y+height,tab..' overlap: '..w.text..' / '..b[5])
    end
    rects[#rects+1]={x,y,width,height,w.text}
   end
  end
 end
end
print('PASS: results cohorts, suffix evidence, nine Tools layouts at two simulated display sizes')
