ForeverMarketTools={}
local M=ForeverMarketTools
local now=100*86400
time=function()return now end
GetRealmID=function()return 12 end
GetCurrentRegion=function()return 1 end
UnitFactionGroup=function()return 'Horde' end
UnitGUID=function()return 'Player-12-abc' end
ForeverMarketVenueRealm=function()return 'Realm 12' end
ForeverMarketDB={}
local history={['5']={floors={[96]=10,[97]=11,[98]=12,[99]=13,[100]=9999},bulk={price=13,at=now}}}
ForeverMarketHistory=function()return history end
local scanned=false
ForeverMarketHasScan=function()return scanned end
local account={desk={groups={}}}
M.account=function()return account end
M.group=function(id)return account.desk.groups[id] end
M.importedRules=function(g)return g.program end
M.invalidate=function()end
dofile('src/PriceRules.lua')
dofile('src/MarketAnalysis.lua')
local stats=M.priceStatistics(5,7)
assert(stats.n==5 and stats.excluded==1 and stats.filtered==11.5 and stats.median==12 and stats.bins[5]==1)
assert(not M.exportReferencePack())
scanned=true
local pack=assert(M.exportReferencePack())
assert(M.referencePack(pack).count==1)
assert(not M.referencePack(pack:gsub('Horde','Alliance')))
assert(not M.referencePack(pack..'\n5,1,'..now))
assert(not M.referencePack(pack..'\n6,1,1'))
M.importReferencePack(pack)
assert(M.sharedReferences(5)[1].price==13)
ForeverMarketRegionPrices={[5]={700,0,10,now}}
assert(M.regionReference(5)[2]==0 and #M.sharedReferences(5)==2)
now=now+8*86400
assert(not M.regionReference(5) and #M.sharedReferences(5)==0)
assert(M.setNamedFormula('user_price','25s'):match('Saved'))
assert(M.savePriceProgram({5},'sell','user_price;2g'):match('Saved'))
assert(M.savePriceProgram({5},'buy','1g'):match('Saved'))
assert(#account.desk.groups[5].program.sell==2 and #account.desk.groups[5].program.buy==1)
assert(not M.setNamedFormula('user_price','user_price'):match('^Saved'))
assert(not M.customProgram('invalid_source'))
print('PASS: daily models, venue isolation, reference expiry, first scan, named and ordered rule persistence')

-- A full-region snapshot is selected once per report, even for thousands of IDs.
local selections=0
local feed={at=now,items={}}
for id=1,5000 do feed.items[id]={100+id,1,2} end
M.fullRegion=function() selections=selections+1;return feed end
assert(#M.sharedReferences()==5000 and selections==1)
local single=M.sharedReferences(4000)
assert(#single==1 and single[1].id==4000 and single[1].price==4100 and selections==2)
