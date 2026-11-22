function CreateFrame()return{SetScript=function()end}end
function ForeverMarketPostPrice(p)return math.max(1,p-2)end
function ForeverMarketSaleNet(n)return math.floor(n*.95)end
function ForeverMarketDepositLoss(n)return 0 end
dofile('src/Bags.lua')
local function check(changes)
 local x={class=7,vendor=10,price=200,age=10,count=20};for k,v in pairs(changes or {})do x[k]=v end;return ForeverMarketBagDecision(x)
end
assert(check()=='ah')
assert(check({price=12})==nil)
assert(check({bound=true})==nil)
assert(check({quest=true})==nil)
assert(check({class=4})==nil)
assert(check({age=86401})=='check')
assert(check({age=-1})=='check')
assert(check({price=0})=='check')
assert(check({price=25,count=1})==nil)
print('PASS: bag markers, fees/deposit allowance, low-margin stacks, bound/quest exclusions, missing and stale prices')
