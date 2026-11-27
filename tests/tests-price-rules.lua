local a={desk={favorites={},posting={},groups={},searches={}}}
local session={}
local history={['10']={floors={['100']=4400}}}
local guid='P'
time=function()return 100*86400 end;GetTime=function()return 100 end
UnitGUID=function()return guid end;CreateFrame=function()return {RegisterEvent=function()end,SetScript=function()end}end
C_Item={GetItemInfo=function()return 'Potion',nil,nil,12,nil,nil,nil,nil,nil,nil,100 end}
ForeverMarketHistory=function()return history end
ForeverMarketDB={characters={[guid]={recipes={{output=10,yield=1,materials={[11]=2}}}}}}
local M={account=function()return a end,session=function()return session end,scope=function()return 'Realm' end,
 inventoryScope=function()return 'realm' end,invalidate=function()end,destinations=function()return {'Bankalt'}end,
 inputs=function(r)return r.materials end,cost=function(_,n)return n*2000 end,bagCount=function()return 10 end}
ForeverMarketTools=M
dofile('src/TradeDesk.lua');dofile('src/MarketDesk.lua');dofile('src/PriceRules.lua');dofile('src/Migration.lua')
local function calc(src,values)
  local t=assert(M.compilePrice(src))
  return M.evaluatePrice(t,function(k)return values[k], 'Missing '..k end)
end
assert(calc('max(120% crafting, 2s)',{crafting=4000})==4800)
assert(calc('first(crafting, 2g)',{})==20000)
assert(calc('min(dbmarket, 4s 20c)',{})==420)
assert(calc('(6s - 2s) / 2 + 10c * 3',{})==230)
assert(calc('ifgt(itemlevel, 10, max(2s, vendorsell), 1s)',{itemlevel=12,vendorsell=500})==500)
assert(not calc('iflt(itemlevel, 10, 3g)',{itemlevel=12}))
assert(not calc('ifgt(dbmarket, 0, 5g, 3g)',{}))
assert(not calc('1g / 0',{}))
assert(not M.compilePrice('a',{a='b',b='a'}))
assert(not M.compilePrice('loadstring("x")'))
local prefix='p@Proof@userData@'
TradeSkillMasterDB={[prefix..'items']={['i:10']='Raid'},[prefix..'groupOperations']={Raid={Auctioning={'Post'},Shopping={'Cheap','Other'},Mailing={'Send'}}},
 [prefix..'operations']={Auctioning={Post={minPrice='myfloor'}},Shopping={Cheap={maxPrice='ifgt(dbmarket, 1g, 20s)'},Other={maxPrice='5s'}},
 Mailing={Send={target='FormerAlt',keepQty=4}}},
 [prefix..'customPriceSources']={myfloor='120% basecost',basecost='first(crafting, 2g)'}}
local p=assert(M.previewTSM('Proof'));assert(p.marketSources.dbmarket and p.recipients.FormerAlt==false)
assert(not next(a.desk.groups))
M.applyMigration(p)
assert(M.group(10).mailHold and M.policyFloor(10,true)==4800)
assert(M.checkPostPolicy(10,1,4400,true) and not M.checkPostPolicy(10,1,4800,true))
assert(not M.groupPurchaseAllowed(10,M.group(10),100,true)) -- Unknown first condition must hold.
TSM_API={GetCustomPriceValue=function()return 20000 end}
assert(M.groupPurchaseAllowed(10,M.group(10),2000,true) and not M.groupPurchaseAllowed(10,M.group(10),2001,true))
p.localPrices=true;p.recipients.FormerAlt='Bankalt'
local routed;M.setRoute=function(id,to,n)routed={id,to,n};return 'Saved destination '..to end
M.applyMigration(p)
assert(routed[1]==10 and routed[2]=='Bankalt' and routed[3]==4 and not M.group(10).mailHold)
assert(M.groupPurchaseAllowed(10,M.group(10),500,true) and not M.groupPurchaseAllowed(10,M.group(10),501,true))
local again=M.previewTSM('Proof');assert(again.localPrices and again.recipients.FormerAlt=='Bankalt')
local key=next(again.operationSets);again.overrides[key]='Other';local selected=again.rebuild()
assert(#selected.rules.Raid.program.buy==1 and selected.rules.Raid.program.buy[1].name=='Other')
TradeSkillMasterDB[prefix..'operations'].Auctioning.Post.minPrice='unsupported(3g)'
local fail=assert(M.previewTSM('Proof'));assert(next(fail.formulaChoices))
M.applyMigration(fail);local _,reason=M.policyFloor(10,true);assert(reason:find('Unsupported'))
local k=next(fail.formulaChoices);fail.replacements[k]='120% crafting'
local repaired=fail.rebuild();M.applyMigration(repaired);assert(M.policyFloor(10,true)==4800)
assert(M.previewTSM('Proof').replacements[k]=='120% crafting')
print('PASS: imported expressions, chained sources, ordered operations, strict holds, local substitution, recipient mapping and final transaction gates')
