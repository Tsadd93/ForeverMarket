local M=ForeverMarketTools
local function linkID(link,kind)
  return link and tonumber(link:match((kind or 'item')..':(%d+)'))
end
local function save(r)
  if r.name and r.key then M.account().recipes[r.key]=r end
end
local function reagent(r,id,n)
  if not id or not n or n<1 then r.issue='Reagent data incomplete';return end
  r.materials[id]=(r.materials[id] or 0)+n
end
function M.capture(craftWindow)
  local a=C_TradeSkillUI
  if a and ((a.IsTradeSkillLinked and a.IsTradeSkillLinked()) or (a.IsTradeSkillGuild and a.IsTradeSkillGuild())) then return end
  local enumerate=a and (a.GetAllRecipeIDs or (not GetNumTradeSkills and a.GetFilteredRecipeIDs))
  local ids=enumerate and enumerate()
  if ids and #ids>0 and a.GetRecipeSchematic and a.GetRecipeInfo then
    for _,id in ipairs(ids) do
      local info=a.GetRecipeInfo(id)
      if info and info.learned then
        local s=a.GetRecipeSchematic(id,false)
        if s then
          local cd=a.GetRecipeCooldown and a.GetRecipeCooldown(id)
          local r={key='s'..id,spell=id,name=info.name or s.name,output=s.outputItemID,
            yield=s.quantityMin or 1,maxYield=s.quantityMax,materials={},ready=time()+(cd or 0)}
          for _,slot in ipairs(s.reagentSlotSchematics or {}) do
            if slot.required then
              local opts=slot.reagents or {}
              if #opts>1 and (slot.quantityRequired or 0)>0 and not next(slot.variableQuantities or {}) then
                local choices={}
                for _,o in ipairs(opts) do if o.itemID then choices[#choices+1]=o.itemID end end
                if #choices==0 then r.issue='Required currency / special reagent'
                else r.choices=r.choices or {};r.choices[#r.choices+1]={ids=choices,n=slot.quantityRequired} end
              elseif #opts~=1 then r.issue='Reagent choice required'
              else reagent(r,opts[1].itemID,slot.quantityRequired) end
            end
          end
          save(r)
        end
      elseif info and info.learned==false then
        local key='s'..id;local a=M.account()
        a.recipes[key]=nil;a.build[key]=nil
      end
    end
    M.invalidate();return
  end
  if IsTradeSkillLinked and IsTradeSkillLinked() then return end
  local function api(craft,trade)
    if craftWindow then return craft end
    return trade
  end
  local count=api(GetNumCrafts,GetNumTradeSkills)
  local info=api(GetCraftInfo,GetTradeSkillInfo)
  local output=api(GetCraftItemLink,GetTradeSkillItemLink)
  local size=api(GetCraftNumReagents,GetTradeSkillNumReagents)
  local mat=api(GetCraftReagentItemLink,GetTradeSkillReagentItemLink)
  local details=api(GetCraftReagentInfo,GetTradeSkillReagentInfo)
  local line=api(GetCraftDisplaySkillLine,GetTradeSkillLine)
  if not (count and info and size and mat and details and line) then return end
  local profession=line()
  if not profession or profession=='UNKNOWN' then return end
  for i=1,count() do
    local name,b,c=info(i);local kind=craftWindow and c or b
    if name and kind~='header' and kind~='subheader' and kind~='trivialheader' then
      local spellLink=not craftWindow and GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i)
      local spell=linkID(spellLink,'enchant') or linkID(spellLink,'spell') or linkID(spellLink,'trade')
      if not spell and C_Spell and C_Spell.GetSpellInfo then
        local si=C_Spell.GetSpellInfo(name);spell=si and si.spellID
      end
      local r={key=spell and 's'..spell or profession..'/'..name,spell=spell,name=name,output=output and linkID(output(i)),materials={},yield=1}
      if not craftWindow and GetTradeSkillNumMade then r.yield,r.maxYield=GetTradeSkillNumMade(i) end
      local cd=not craftWindow and GetTradeSkillCooldown and GetTradeSkillCooldown(i)
      r.ready=time()+(cd or 0)
      for j=1,size(i) do reagent(r,linkID(mat(i,j)),select(3,details(i,j))) end
      save(r)
    end
  end
  M.invalidate()
end
function M.inputs(r,batches)
  local used,selection={},{}
  for id,n in pairs(r.materials) do used[id]=n end
  local a=M.account();local chosen=a.selections and a.selections[r.key] or {}
  for i,slot in ipairs(r.choices or {}) do
    local best,price
    for _,id in ipairs(slot.ids) do
      local cost=M.cost(id,((used[id] or 0)+slot.n)*batches)
      if chosen[i]==id then best=id;break end
      if cost and (not price or cost<price) then best=id;price=cost end
    end
    if not best then return nil end
    selection[i]=best;used[best]=(used[best] or 0)+slot.n
  end
  return used,selection
end
local function requirements(r,batches,need)
  for id,n in pairs(M.inputs(r,batches) or {}) do need[id]=(need[id] or 0)+n*batches end
end
function M.materials()
  local a=M.account();local quantities={}
  for key,n in pairs(a.build) do
    if a.recipes[key] then requirements(a.recipes[key],n,quantities) end
  end
  if M.restockList then for id,r in pairs(M.restockList()) do quantities[id]=(quantities[id] or 0)+r.keep end end
  return quantities
end
function M.missing(id,n)
  local orders=ForeverMarketTradingFund and ForeverMarketTradingFund().itemOrders
  local pending=0
  for _,o in pairs(orders or {}) do if o.craft and o.id==id then pending=pending+o.n end end
  local need=math.max(0,n-M.bagCount(id)-(M.account().transit[id] or 0)-pending)
  if M.account().useTransfers and M.transferPlan then local _,buy=M.transferPlan(id,need);return buy end
  return need
end
function M.estimate(r,batches)
  if r.issue then return nil,r.issue end
  if not r.output then return nil,'Service / no auctionable output' end
  local inputs=M.inputs(r,batches)
  if not inputs then return nil,'Need reagent choice prices' end
  if not next(inputs) or not r.yield or r.yield<=0 then return nil,'Incomplete recipe' end
  if (r.ready or 0)>time() then return nil,'On cooldown' end
  local name,_,_,_,_,_,_,stack,_,_,_,_,_,bind=C_Item.GetItemInfo(r.output)
  if not name or bind==nil then
    if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(r.output) end
    return nil,'Loading output item'
  end
  if bind==1 or bind==4 or bind==7 or bind==8 or bind==9 then return nil,'Bound output' end
  local post,at=M.prices(r.output)
  if not post then return nil,'Output price unknown' end
  local cash,all,opportunity=0,0,0
  for id,per in pairs(inputs) do
    local n=per*batches
    local cost=M.cost(id,n)
    local missing=M.missing(id,n)
    local buy=M.cost(id,missing)
    if not cost or not buy then return nil,'Need material prices / supply' end
    cash=cash+buy;all=all+cost
    if n>missing then
      local p=M.prices(id)
      if not p then return nil,'Owned material value unknown' end
      local vendor=select(11,C_Item.GetItemInfo(id)) or 0
      local held=n-missing
      opportunity=opportunity+math.max(vendor*held,ForeverMarketSaleNet(p*held)-ForeverMarketDepositLoss(held))
    end
  end
  local units=r.yield*batches
  stack=math.max(1,stack or 1)
  local net=math.floor(units/stack)*ForeverMarketSaleNet(post*stack)+ForeverMarketSaleNet(post*(units%stack))-ForeverMarketDepositLoss(units)
  return {cash=cash,all=all,net=net,post=post,profit=net-all,extra=net-cash-opportunity,units=units,at=at}
end
local reserve,expires
function M.invalidate() reserve=nil end
function M.reserve()
  if reserve and GetTime()<expires then return reserve end
  local cost=0
  for id,n in pairs(M.materials()) do
    local price=M.cost(id,M.missing(id,n))
    if not price then cost=math.huge;break end
    cost=cost+price
  end
  reserve=cost;expires=GetTime()+1;return cost
end
function M.restockContext()
  local ctx={stock={},queued={},needs=M.materials(),budget=ForeverMarketSpendable and ForeverMarketSpendable(true) or GetMoney()}
  local api=C_AuctionHouse
  for i=1,api.GetNumOwnedAuctions() do
    local a=api.GetOwnedAuctionInfo(i)
    if a and a.itemKey and a.status==0 then local id=a.itemKey.itemID;ctx.stock[id]=(ctx.stock[id] or 0)+(a.quantity or 1) end
  end
  local account=M.account()
  for key,n in pairs(account.build) do
    local r=account.recipes[key]
    if r and r.output then ctx.queued[r.output]=(ctx.queued[r.output] or 0)+n*(r.yield or 1) end
  end
  for id,n in pairs(ctx.needs) do ctx.budget=ctx.budget-(M.cost(id,M.missing(id,n)) or math.huge) end
  return ctx
end
function M.restockCraft(r,ctx)
  if not r.output then return 0,'No auctionable output' end
  local name=C_Item.GetItemNameByID(r.output)
  local sales=M.saleCount and M.saleCount(name) or 0
  local stock=M.bagCount(r.output)+(ctx.stock[r.output] or 0)+(ctx.queued[r.output] or 0)
  local group=M.group and M.group(r.output)
  local needed=math.max(0,(group and group.craftStock or math.ceil(sales*3/7))-stock)
  local hi=math.min(999-(M.account().build[r.key] or 0),math.floor(needed/(r.yield or 1)))
  local lo,reason=0,sales==0 and 'No paid sales in 7 days' or 'Stock covers three days'
  while lo<hi do
    local n=math.ceil((lo+hi)/2)
    local e,why=M.estimate(r,n)
    local ok=e and e.extra>0 and e.profit>0
    if ok then
      local cash=0
      for id,per in pairs(M.inputs(r,n)) do
        local existing=ctx.needs[id] or 0
        local total=M.cost(id,M.missing(id,existing+n*per))
        local reserved=M.cost(id,M.missing(id,existing))
        cash=cash+(total and reserved and total-reserved or math.huge)
      end
      local finished=M.cost(r.output,e.units)
      if cash>ctx.budget then ok=false;why='Budget or reagent supply'
      elseif finished and finished<e.net-e.extra then ok=false;why='Cheaper to buy finished' end
    end
    if ok then lo=n else hi=n-1;reason=why or 'Materials pay better' end
  end
  if group and group.minBatch and lo*(r.yield or 1)<group.minBatch then return 0,'Below craft restock minimum' end
  return lo,lo>0 and (sales..' sold / 7d; '..stock..' stocked or queued') or reason
end
function M.queue(key,n)
  if n~=math.floor(n) or n<0 or n>999 then return false end
  local a=M.account()
  if not a.recipes[key] then return false end
  a.selections=a.selections or {}
  if n>0 and not a.build[key] then
    local r=a.recipes[key]
    if r.choices then
      local options,chosen=M.inputs(r,n)
      if not options then return false end
      a.selections[key]=chosen
    end
  elseif n==0 then a.selections[key]=nil end
  a.build[key]=n>0 and n or nil;M.invalidate();return true
end
local producing={}
function M.startCast(spell)
  local a=M.account();local key='s'..tostring(spell);local r=a.recipes[key]
  if a.build[key] and r and r.output then producing[spell]={before=M.bagCount(r.output),r=r} end
end
function M.settleCrafts()
  for spell,t in pairs(producing) do
    if t.success then
      local n=M.bagCount(t.r.output)-t.before
      if n>0 and n>=(t.r.yield or 1) and n<=(t.r.maxYield or t.r.yield or 1) then
        if t.cost>0 then
          local held=ForeverMarketTradingFund().held
          local h=held[t.r.output] or {n=0,cost=0,reserve=0,itemID=t.r.output}
          h.n=h.n+n;h.cost=h.cost+t.cost;held[t.r.output]=h
        end
        producing[spell]=nil
      elseif GetTime()-t.success>5 then producing[spell]=nil end
    end
  end
end
function M.completed(spell)
  local a=M.account();local key='s'..tostring(spell)
  if a.build[key] then
    local t=producing[spell]
    if t then
      t.success=GetTime();t.cost=0
      for id,n in pairs(M.inputs(t.r,1) or {}) do
        local lot=a.materialCosts and a.materialCosts[id]
        if lot and lot.n>0 then
          local take=math.min(n,lot.n);local cost=math.floor(lot.cost*take/lot.n)
          lot.n=lot.n-take;lot.cost=lot.cost-cost;t.cost=t.cost+cost
        end
      end
      M.settleCrafts()
    end
    M.queue(key,a.build[key]-1)
  end
end
-- A material purchase must still fit the fund at its current quote.
function M.startMaterial(id,order)
  local f=ForeverMarketTradingFund()
  if f.pending then return nil,'Waiting for the previous purchase' end
  local n=order and order.n or M.missing(id,M.materials()[id] or 0)
  local max=order and order.cap*n or M.cost(id,n)
  local rule=M.restockList and M.restockList()[id]
  if rule and rule.cap>0 and max and max>rule.cap*n then return nil,"Above shopping list price limit" end
  if order and max and n>0 and M.groupPurchaseAllowed and not M.groupPurchaseAllowed(id,M.group(id),max/n,true) then return nil,'Above group shopping ceiling' end
  if n==0 or not max then return nil,'Refresh market supply' end
  if max>ForeverMarketSpendable(true) then return nil,'Insufficient trading cash' end
  local item=C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(id))
  if not item then return nil,'Item data loading' end
  M.cancelMaterial()
  M.quote={id=id,n=n,max=max,at=GetTime(),direct=order~=nil}
  if item.isCommodity then C_AuctionHouse.StartCommoditiesPurchase(id,n)
  else
    local key=order and order.key and order.key.itemID==id and order.key or C_AuctionHouse.MakeItemKey(id)
    M.quote.key=key
    C_AuctionHouse.SendSearchQuery(key,{},false)
  end
  return true
end
function M.cancelMaterial()
  if M.quote then local item=M.quote.key;M.quote=nil;if not item then C_AuctionHouse.CancelCommoditiesPurchase() end end
end
function M.materialOffer(key)
  local q=M.quote
  if not q or not q.key or not key or key.itemID~=q.id then return end
  local best
  for i=1,C_AuctionHouse.GetNumItemSearchResults(key) do
    local r=C_AuctionHouse.GetItemSearchResultInfo(key,i)
    if r and r.itemKey and r.itemKey.itemID==q.id and (r.quantity or 1)==1 and not r.containsOwnerItem and not r.containsAccountItem and
       r.buyoutAmount and r.buyoutAmount>0 and r.buyoutAmount<=(q.direct and q.max or M.cost(q.id,1) or 0) and (not best or r.buyoutAmount<best.buyoutAmount) then best=r;if q.direct then q.link=r.itemLink or (C_AuctionHouse.GetItemSearchResultItemLink and C_AuctionHouse.GetItemSearchResultItemLink(key,i)) end end
  end
  return best
end
function M.confirmMaterial()
  local q=M.quote
  if not q or not q.total then return nil,'Awaiting live price' end
  local f=ForeverMarketTradingFund()
  local rule=M.restockList and M.restockList()[q.id]
  if rule and rule.cap>0 and q.total>rule.cap*(q.key and 1 or q.n) then M.cancelMaterial();return nil,"Above shopping list price limit" end
  if q.direct and M.groupPurchaseAllowed and not M.groupPurchaseAllowed(q.id,M.group(q.id),q.total/(q.key and 1 or q.n),true) then
    M.cancelMaterial();return nil,'Group shopping ceiling changed'
  end
  if f.pending or GetTime()-q.at>=9 or q.total>q.max or q.total>ForeverMarketSpendable(true)
      or not q.direct and q.n~=M.missing(q.id,M.materials()[q.id] or 0) then
    M.cancelMaterial();return nil,'Fund, quantity or price changed'
  end
  for key,n in pairs(M.account().build) do
    local r=M.account().recipes[key]
    if not q.direct and (M.inputs(r,n) or {})[q.id] then
      local e=M.estimate(r,n)
      if not e or e.profit<=0 or e.extra<=0 then M.cancelMaterial();return nil,'Review craft profitability' end
    end
  end
  if q.key then
    local r=M.materialOffer(q.key)
    if not r or r.auctionID~=q.auctionID or r.buyoutAmount~=q.total then M.cancelMaterial();return nil,'Auction changed' end
    f.itemOrders=f.itemOrders or {}
    if f.itemOrders[r.auctionID] then return nil,'Awaiting auction confirmation' end
    f.itemOrders[r.auctionID]={id=q.id,n=1,total=q.total,auctionID=r.auctionID,craft=true,dep=0,at=time()}
    M.quote=nil
    local ok=pcall(C_AuctionHouse.PlaceBid,r.auctionID,q.total)
    if not ok then f.itemOrders[r.auctionID]=nil;return nil,'Purchase failed' end
    return true
  end
  f.pending={id=q.id,n=q.n,total=q.total,dep=0,craft=true,at=time()}
  M.quote=nil
  local ok=pcall(C_AuctionHouse.ConfirmCommoditiesPurchase,q.id,q.n)
  if not ok then f.pending=nil;return nil,'Purchase failed' end
  return true
end
