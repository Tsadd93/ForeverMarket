ForeverMarketTools={}
ForeverMarketDB={}
local M=ForeverMarketTools
local now=1800000000;time=function()return now end;date=os.date
GetCurrentRegion=function()return 1 end;UnitName=function()return 'Test' end;UnitFactionGroup=function()return 'Horde' end
ForeverMarketVenueRealm=function()return 'Realm 12' end;ForeverMarketEventRealm=function(e)return e.realm end
C_Item={GetItemNameByID=function()return 'Cloth' end,GetItemCount=function()return 2 end}
local groups={};M.account=function()return {desk={groups=groups}} end;M.group=function(i)return groups[i] end;M.invalidate=function()end
M.importedRules=function(g)return g.program end
dofile('src/PriceRules.lua');dofile('src/FeedSources.lua')
local function read(k)return M.ruleSource(8,k,false)end
ForeverMarketFeedRegion={region=1,at=now,items={[8]={120,0,25,150,80}}}
ForeverMarketFeedRealm={region=1,market='Realm 12|Horde',at=now,items={[8]={96,87,69}}}
assert(read('dbregionsalerate')==0 and read('dbregionsoldperday')==25 and read('dbregionsaleavg')==80 and read('dbregionmarketavg')==120 and read('dbregionhistorical')==150)
assert(read('dbmarket')==96 and read('dbminbuyout')==69 and read('dbhistorical')==87)
ForeverMarketFeedRealm.market='Realm 12|Alliance';assert(read('dbmarket')==nil)
assert(not read('avgbuy'));assert(read('numinventory')==2)
ForeverMarketActivity={events={}}
local function e(kind,fields)
 fields.kind=kind;fields.at=now+#ForeverMarketActivity.events;fields.character='Test';fields.region=1;fields.faction='Horde';fields.realm='Realm 12'
 table.insert(ForeverMarketActivity.events,fields)
end
e('purchase',{itemId=8,total=300,quantity=3});e('purchase',{itemId=8,total=50,quantity=1})
e('posted',{itemId=8});e('proceeds_collected',{invoiceType='seller',amount=101,deposit=5,fee=4,name='Cloth',quantity=2})
e('auction_expired',{itemId=8});assert(read('avgbuy')==87.5 and read('smartavgbuy')==75 and read('avgsell')==50 and read('numexpires')==1 and read('salerate')==1)
assert(M.setOperation(8,'auctioningopnormal','80% dbregionmarketavg'):match('Saved'));assert(read('auctioningopnormal')==96)
M.setOperation(8,'auctioningopmax','auctioningopmax');assert(not read('auctioningopmax'))
now=now+8*86400;assert(not read('dbregionmarketavg'))
local pack='FMREG1 1 '..now..' 1\n8,100,0,0,90,80'
assert(M.importRegionPack(pack):match('Imported'));assert(read('dbregionmarketavg')==100)
assert(not M.importRegionPack(pack:gsub(' 1\n',' 3\n')):match('Imported'));assert(read('dbregionmarketavg')==100)
StaticPopupDialogs={};local prompts=0;StaticPopup_Show=function()prompts=prompts+1 end
M.updatePrices(false);assert(prompts==0);now=now+8*86400;M.updatePrices(false);M.updatePrices(false);assert(prompts==1)
ReloadUI=function()end;StaticPopupDialogs.FM_UPDATE_PRICES.OnAccept();assert(ForeverMarketUpdateRequested==now*10+1)
print('PASS: all eight public price fields, venue isolation, ledger costs, missing sources, operation recursion, atomic regional import and expiry reminder')
