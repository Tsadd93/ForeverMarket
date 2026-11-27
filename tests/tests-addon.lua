local handlers, original, hook, prints = {}, nil, nil, {}
local clock=1800000000
function time() return clock end
function GetRealmName() return 'Test Realm' end
function UnitFactionGroup() return 'Horde' end
function GetCurrentRegion() return 1 end
function GetMoney() return 100000 end
function GetItemInfo(id) return 'Herb "Test"',nil,1,1,1,'Trade Goods',nil,20,nil,nil,10,7 end
function CreateFrame() return {RegisterEvent=function()end,SetScript=function(_,kind,f)handlers[kind]=f end} end
C_Timer={After=function(_,f)f()end}
SlashCmdList={}
local printed=print
function print(s) prints[#prints+1]=s end
dofile('src/History.lua')
dofile('src/Market.lua')
handlers.OnEvent(nil,'PLAYER_LOGIN')
assert(not next(ForeverMarketHistory()))
ForeverMarketObserve('123',700,8,850)
assert(ForeverMarketDB['Test Realm|Horde']['123'].price==700)
assert(ForeverMarketDB['Test Realm|Horde']['123'].at==clock)
local opened=0
ForeverMarketTools={openDashboard=function()opened=opened+1 end}
SlashCmdList.FOREVERMARKET();SlashCmdList.FOREVERMARKET('dash');assert(opened==2)
ForeverMarketTools=nil
SlashCmdList.FOREVERMARKET('export')
while handlers.OnUpdate do handlers.OnUpdate() end
assert(ForeverMarketExport:find('"realm":"Test Realm"',1,true))
assert(ForeverMarketExport:find('"price":700',1,true))
assert(ForeverMarketExport:find('Herb \\"Test\\"',1,true))
handlers.OnEvent(nil,'AUCTION_HOUSE_CLOSED')
assert(ForeverMarketHistory()['123'].bulk.price==850)
printed('PASS: native history, fresh install, export and exact timestamp')
-- Overlapping days and mirrored availability must not be double-counted.
C_AuctionHouse={GetItemKeyInfo=function(k)return {isCommodity=k.itemID==123} end}
local k={itemID=123,itemLevel=5}
local gear={itemID=987,itemLevel=15}
assert(ForeverMarketHistoryKey(k)=='123')
assert(ForeverMarketHistoryKey(gear)=='g:987:15')
clock=clock+100
ForeverMarketObserve('g:123:5',620,3)
ForeverMarketObserve('g:987:15',1700,1)
assert(ForeverMarketRepairHistory()==1 and ForeverMarketRepairHistory()==0)
local h=ForeverMarketHistory()['123'];local day=math.floor(clock/86400)
assert(h.m==620 and h.l[day]==620 and h.h[day]==700 and h.a[day]==8)
assert(ForeverMarketHistory()['g:987:15'].m==1700)
printed('PASS: commodity history consolidation, daily range, latest quote, equipment separation and repeat migration')

do
  GetRealmName=function()return ''end;GetRealmID=function()return 0 end
  UnitGUID=function()return 'Player-6926-test' end;UnitFactionGroup=function()return 'Horde' end;GetCurrentRegion=function()return 1 end
  dofile('src/History.lua')
  local old={['42']={h={[1]=5}}}
  ForeverMarketDB={characters={['Player-6926-test']={}},history={['1||Horde']=old}}
  assert(ForeverMarketHistory()==old and ForeverMarketDB.history['1|Realm 6926|Horde']==old)
  assert(ForeverMarketEventRealm({realm='',faction='Horde',region=1})=='Realm 6926')
  ForeverMarketDB={characters={['Player-6926-test']={},['Player-8888-alt']={}},history={['1||Horde']=old}}
  assert(ForeverMarketHistory()~=old and ForeverMarketDB.history['1||Horde']==old)
  local low,high={},{};for i=60,99 do low[i]=100;high[i]=100 end
  for _,i in ipairs({66,77,88}) do low[i]=70;for j=i+1,i+3 do low[j]=75;high[j]=95 end end
  local m=assert(ForeverMarketRecovery(low,100,high));assert(m.wins>=3)
  print('PASS: realm 0 GUID fallback, isolated mixed history, intraday recoveries on subsequent market days')
end
