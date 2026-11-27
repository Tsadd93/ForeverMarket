local M=ForeverMarketTools
local money=ForeverMarketCoins
local function name(id) return C_Item.GetItemNameByID(id) or ('Item '..id) end
local function count(t,id,n) t[id]=(t[id] or 0)+n end
local function recipient(a)
  return a.stockAddress or a.stockName
end
local function activeAH() return AuctionHouseFrame and AuctionHouseFrame:IsShown() end
function M.shoppingTrip()
  local rows,total,unknown,remaining={},0,0,0
  local a=M.account()
  local targets=M.tripTargets and M.tripTargets() or M.restockList()
  local ids,labels={},{}
  for id in pairs(targets) do ids[#ids+1]=id;labels[id]=name(id) end
  table.sort(ids,function(x,y)if labels[x]==labels[y] then return x<y end return labels[x]<labels[y] end)
  local cash=ForeverMarketSpendable and ForeverMarketSpendable(true) or math.huge
  for _,id in ipairs(ids) do
    local r=targets[id]
    local bank,mail=0,0
    for _,s in ipairs(M.sources(id)) do
      if s.own and time()-s.at<7*86400 then
        if s.place=='bank' then bank=s.n elseif s.place=='mail' then mail=s.n end
      end
    end
    local ordered=0
    for _,o in pairs(ForeverMarketTradingFund().itemOrders or {}) do if o.id==id then ordered=ordered+o.n end end
    local missing=math.max(0,r.keep-M.bagCount(id)-bank-math.max(mail,a.transit[id] or 0)-ordered)
    local cost=M.cost(id,missing)
    local n=missing
    if missing>0 and (not cost or cost>cash or r.cap>0 and cost>r.cap*missing) then
      local lo,hi=0,missing
      while lo<hi do
        local mid=math.ceil((lo+hi)/2);local price=M.cost(id,mid)
        if price and price<=cash and (r.cap==0 or price<=r.cap*mid) then lo=mid else hi=mid-1 end
      end
      n=lo
    end
    local info=C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(id))
    if info and not info.isCommodity then n=math.min(n,1) end
    local subtotal=M.cost(id,n) or 0
    local q=M.quote
    local display=q and q.trip and q.id==id and q.n==n and q.total and q.total<=subtotal and q.total or subtotal
    cash=cash-display;total=total+display;remaining=remaining+missing-n
    if n<missing then unknown=unknown+1 end
    rows[#rows+1]={id=id,name=labels[id],missing=missing,n=n,cost=cost,subtotal=subtotal,bank=bank,mail=mail}
  end
  return rows,total,unknown,remaining
end
function M.buyTrip(id)
  if not activeAH() then return 'Open the auction house.' end
  for _,r in ipairs(M.shoppingTrip()) do if r.id==id then
    local q=M.quote
    if q and q.trip and q.id==id and q.total then
      if q.n>r.n or not r.subtotal or q.total>r.subtotal then M.cancelMaterial();return 'Stock or price changed. Refresh the quote.' end
      local ok,why=M.confirmMaterial();return why or (ok and 'Purchase submitted.')
    end
    if r.n==0 or not r.subtotal then return 'No uncovered quantity with a price.' end
    local ok,why=M.startMaterial(id,{n=r.n,cap=r.subtotal/r.n})
    if ok then M.quote.trip=true;M.quote.max=r.subtotal end
    return why or 'Requesting live quote.'
  end end
end

function M.readAuctionatorList(list)
  local api=Auctionator and Auctionator.API and Auctionator.API.v1
  if not api or not api.GetShoppingListItems then return nil,'Paste exported item lines or enable Auctionator for this import.' end
  local ok,items=pcall(api.GetShoppingListItems,'ForeverMarket',list)
  if not ok or type(items)~='table' then return nil,'Auctionator list not found.' end
  return table.concat(items,'\n')
end
function M.importPreview(raw,destination)
  if M.decodeGroup and type(destination)=='string' and #destination>0 and #destination<=48 then
    local ok,migration=pcall(M.decodeGroup,raw,destination)
    if ok and migration then return migration end
  end
  local p={list=destination,items={},filters={},skipped={},kind='Auctionator'}
  if raw:find('i:%d') then p.kind='TSM' end
  if #raw>32000 then p.skipped[1]='Input exceeds 32000 characters';return p end
  local function parse(s)
    s=s:match('^%s*(.-)%s*$')
    if s=='' or s:match('^%*%*%*') then return end
    local id,n
    if p.kind=='TSM' then id=tonumber(s:match('^i:(%d+)$'))
    else
      local fields={};for part in (s..'^'):gmatch('(.-)%^') do fields[#fields+1]=part end
      local label=fields[1]
      local advanced=false
      for i=2,#fields do if i~=14 and fields[i]~='' then advanced=true end end
      if advanced then
        local rule={term=label:gsub('^"(.*)"$','%1'),exactName=label:match('^".*"$')~=nil,max=0,units=1}
        local keys={[3]='minItemLevel',[4]='maxItemLevel',[5]='minLevel',[6]='level',[9]='minPrice',[10]='max',[11]='quality',[14]='units'}
        for i=2,#fields do
          if i==2 and fields[i]~='' then
            rule.categories=M.categoryFilters and M.categoryFilters(fields[i])
            if not rule.categories then p.skipped[#p.skipped+1]=s;return end
            rule.category=fields[i]
          elseif fields[i]~='' then
            local n=tonumber(fields[i]);local key=keys[i]
            if not key or not n or n<0 or n>1e7 or (i~=9 and i~=10 and n~=math.floor(n)) or (i==14 and n>9999) then p.skipped[#p.skipped+1]=s;return end
            if i==9 or i==10 then n=math.floor(n*10000+.5) end
            if n>0 or i==11 then rule[key]=n end
          end
        end
        p.filters[#p.filters+1]=rule;return
      end
      n=tonumber(fields[14]);if fields[14] and fields[14]~='' and not n then p.skipped[#p.skipped+1]=s;return end
      local base,q=label:match('^(.-)%s+[xX](%d+)$');if base then label=base;n=tonumber(q) end
      label=label:gsub('^"(.*)"$','%1')
      id=tonumber(label:match('item:(%d+)') or label:match('^(%d+)$'))
      if not id then local resolved,link=C_Item.GetItemInfo(label);if resolved and resolved:lower()==label:lower() then id=tonumber((link or ''):match('item:(%d+)')) end end
    end
    n=n or 1
    if not id or id<1 or id>2147483647 or n<1 or n>9999 or n~=math.floor(n) then p.skipped[#p.skipped+1]=s
    else p.items[id]=math.max(n,p.items[id] or 0) end
  end
  for s in raw:gmatch(p.kind=='TSM' and '[^,\r\n]+' or '[^\r\n]+') do parse(s) end
  return p
end
function M.applyPreview(p)
  if not p or (not next(p.items) and #(p.filters or {})==0) or not p.list or p.list=='' or #p.list>48 then return 'Choose a destination and preview recognized items.' end
  M.restockList()
  local m=M.account().manager
  local existing=M.account().filtersByList
  if #(p.filters or {})+#(existing and existing[p.list] or {})>30 then return 'Too many filters for this basket (maximum 30).' end
  local list=m.lists[p.list] or {};m.lists[p.list]=list;m.active=p.list
  for _,rule in ipairs(p.filters or {}) do M.addBasketFilter(rule,rule.units) end
  for id,n in pairs(p.items) do
    if not list[id] then list[id]={keep=n,cap=0} else list[id].keep=math.max(list[id].keep,n) end
  end
  if p.kind=='TSM' then
    local a=M.account();a.desk=a.desk or {favorites={},searches={},posting={},groups={}}
    a.desk.savedGroups=a.desk.savedGroups or {}
    local ids={};for id in pairs(p.items) do ids[#ids+1]=tostring(id) end;table.sort(ids)
    a.desk.savedGroups[p.list]='FMG1;'..table.concat(ids,',')..';0;0;5;20;0;1'
  end
  M.invalidate();return 'Imported into '..p.list
end

local function realmOps()
  local all=ForeverMarketDB.operations or {};ForeverMarketDB.operations=all
  local scope=M.inventoryScope()
  all[scope]=all[scope] or {routes={},vendors={}}
  return all[scope]
end
function M.clearRoute(id)
  local ops=realmOps()
  if id then ops.routes[id]=nil else ops.seller=nil end
  return 'Route cleared.'
end
function M.routeSeller()return realmOps().seller end
function M.protectedStock()
  local out={};local ops=realmOps()
  for id,r in pairs(ops.routes) do if r.keep>0 then out[id]=math.min(r.keep,M.bagCount(id)) end end
  local b=ForeverMarketDB.__sellBlacklist
  for id in pairs(b and b[UnitGUID('player')] or {}) do local n=M.bagCount(id);if n>0 then out[id]=n end end
  return out
end
function M.savedSupplyPlan()return realmOps().plan end
function M.saveSupplyPlan(chain)
  if not chain.cost then return 'Plan has unpriced steps.' end
  realmOps().plan=chain
  M.restockList();local m=M.account().manager
  local list={};local dest='Craft '..chain.id
  for _,step in ipairs(chain.steps) do if step.action=='Buy AH' then
    local r=list[step.id] or {keep=M.bagCount(step.id),cap=0}
    if not list[step.id] then
      local bank,mail=0,0
      for _,s in ipairs(M.sources(step.id)) do if s.own and time()-s.at<7*86400 then
        if s.place=='bank' then bank=s.n elseif s.place=='mail' then mail=s.n end end end
      r.keep=r.keep+bank+math.max(mail,M.account().transit[step.id] or 0)
    end
    r.keep=r.keep+step.n;list[step.id]=r
  end end
  m.lists[dest]=list;m.active=dest;M.invalidate()
  return 'Ordered plan saved for your characters. AH inputs are in Basket / '..dest
end
function M.setRoute(id,to,keep)
  if not to:match('^[^%s|]+$') or #to>64 then return 'Enter a character name.' end
  local valid=false
  for _,a in pairs(ForeverMarketDB.characters or {}) do if a.stockScope==M.inventoryScope() and recipient(a)==to then valid=true end end
  if not valid then return 'Visit the destination character once to record their identity.' end
  local ops=realmOps()
  if id then
    if not keep or keep<0 or keep~=math.floor(keep) then return 'Enter a nonnegative keep quantity.' end
    ops.routes[id]={to=to,keep=keep}
  else ops.seller=to end
  return 'Saved destination '..to
end
local function protected(id)
  local b=ForeverMarketDB.__sellBlacklist
  return b and b[UnitGUID('player')] and b[UnitGUID('player')][id]
end
function M.shipments()
  local ops=realmOps();local out={};local needs=M.materials()
  for bag=0,NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
    for slot=1,C_Container.GetContainerNumSlots(bag) do
      local item=C_Container.GetContainerItemInfo(bag,slot)
      if item and not item.isBound and not item.isLocked and not protected(item.itemID) then
        local id=item.itemID;local r=ops.routes[id];local to=r and r.to or ops.seller
        local _,_,_,_,_,_,_,_,_,_,_,_,_,bind=C_Item.GetItemInfo(item.hyperlink or id)
        if to and not (M.group and (M.group(id) or {}).mailHold) and to~=recipient(M.account()) and to~=UnitName('player') and bind~=nil and bind~=4 and bind~=1 then
          local g=M.group and M.group(id)
          local keep=math.max(r and r.keep or 0,needs[id] or 0,g and g.reserve or 0)
          local n=math.min(item.stackCount or 1,math.max(0,M.bagCount(id)-keep))
          if n>0 then out[#out+1]={id=id,to=to,n=n,bag=bag,slot=slot,stack=item.stackCount or 1,link=item.hyperlink};needs[id]=keep+n end
        end
      end
    end
  end
  table.sort(out,function(a,b)
    if a.to~=b.to then return a.to<b.to end
    if a.bag~=b.bag then return a.bag<b.bag end
    return a.slot<b.slot
  end)
  return out
end
function M.bankDispatchTo(id)
  local route=realmOps().routes[id]
  if route and not (M.group and (M.group(id) or {}).mailHold) and not protected(id) and route.to~=recipient(M.account()) and route.to~=UnitName('player') then return route.to end
end
function M.destinations()
  local list={}
  for _,a in pairs(ForeverMarketDB.characters or {}) do
    if a.stockScope==M.inventoryScope() and recipient(a) then list[#list+1]=recipient(a) end
  end
  table.sort(list);return list
end
function M.attachShipment(row)
  if not SendMailFrame or not SendMailFrame:IsShown() then return 'Open the Send Mail tab first.' end
  if CursorHasItem() then return 'Clear your cursor first.' end
  local to=SendMailNameEditBox:GetText()
  if to~='' and to~=row.to then return 'The draft is addressed to another character.' end
  local free
  for i=1,ATTACHMENTS_MAX_SEND or 12 do
    if not GetSendMailItem(i) then free=free or i elseif to~=row.to then return 'Review existing attachments first.' end
  end
  if not free then return 'Draft is full.' end
  for _,r in ipairs(M.shipments()) do
    if r.bag==row.bag and r.slot==row.slot and r.link==row.link and r.n==row.n and r.to==row.to then
      SendMailNameEditBox:SetText(r.to)
      if r.n==r.stack then C_Container.PickupContainerItem(r.bag,r.slot) else C_Container.SplitContainerItem(r.bag,r.slot,r.n) end
      if not CursorHasItem() then return 'The client could not pick up this quantity.' end
      ClickSendMailItemButton(free)
      if CursorHasItem() then ClearCursor();return 'Attachment failed.' end
      return 'Review attachments, recipient and postage, then click Blizzard Send.'
    end
  end
  return 'Bag contents changed. Refresh.'
end

local function recipeIndex()
  local byID,seen={},{}
  for guid,a in pairs(ForeverMarketDB.characters or {}) do
    if guid==UnitGUID('player') or a.stockScope==M.inventoryScope() then
      for _,r in pairs(a.recipes or {}) do
        if r.output and not r.issue and (r.ready or 0)<=time() then
          local bind=select(14,C_Item.GetItemInfo(r.output))
          if guid==UnitGUID('player') or (bind~=nil and bind~=1 and bind~=4) then
            byID[r.output]=byID[r.output] or {}
            local key=r.output..'/'..r.key
            if not seen[key] then
              local known={r=r,who=a.stockName or UnitName('player')};seen[key]=known;table.insert(byID[r.output],known)
            elseif guid==UnitGUID('player') then seen[key].r=r;seen[key].who=UnitName('player') end
          end
        end
      end
    end
  end
  return byID
end
function M.supplyPlan(id,n)
  local recipes=recipeIndex();local ops=realmOps();local visited=0;local limited=false
  local function copy(t)local v={};for k,x in pairs(t) do v[k]=x end;return v end
  local locations={}
  local function inventory(item)
    if locations[item] then return locations[item] end
    local list={{label='Current bags',n=M.bagCount(item)}}
    for _,s in ipairs(M.sources(item)) do
      if time()-s.at<=7*86400 and (s.place=='bank' or not s.own and s.place=='bags') then
        list[#list+1]={label=s.who..' '..s.place,n=s.n}
      end
    end
    locations[item]=list;return list
  end
  local function solve(item,qty,state,path,depth)
    visited=visited+1
    local lines={};local cost=0
    local places=inventory(item)
    if state[item]==nil then
      state[item]=0;for _,place in ipairs(places) do state[item]=state[item]+place.n end
    end
    local use=math.min(qty,state[item]);state[item]=state[item]-use;qty=qty-use
    local key='used/'..item;local skip=state[key] or 0
    for _,place in ipairs(places) do
      if use==0 then break end
      local take=math.min(use,math.max(0,place.n-skip))
      skip=math.max(0,skip-place.n)
      if take>0 then
        lines[#lines+1]={id=item,n=take,action='Use stock',detail=place.label}
        state[key]=(state[key] or 0)+take;use=use-take
      end
    end
    if use>0 then lines[#lines+1]={id=item,n=use,action='Use surplus',detail='From earlier plan steps'} end
    if qty==0 then return cost,lines,state end
    local bought=state[-item] or 0
    local before=M.cost(item,bought);local after=M.cost(item,bought+qty)
    local best=before and after and after-before
    local result=copy(lines);result[#result+1]={id=item,n=qty,action='Buy AH',cost=best}
    local bestState=copy(state);bestState[-item]=bought+qty
    local vendor=ops.vendors[item]
    local packs=vendor and math.ceil(qty/(vendor.bundle or 1))
    if vendor and time()-vendor.at<=7*86400 and vendor.price*packs<(best or math.huge) then
      best=vendor.price*packs;bestState=copy(state);bestState[item]=bestState[item]+packs*(vendor.bundle or 1)-qty;result=copy(lines);result[#result+1]={id=item,n=qty,action='Buy vendor',cost=best,detail=(vendor.name or 'Merchant')..' / '..packs..' bundles'}
    end
    if not path[item] and recipes[item] and (depth>=8 or visited>3000) then limited=true end
    if depth<8 and visited<=3000 and not path[item] then
      path[item]=true
      for _,known in ipairs(recipes[item] or {}) do
        local r=known.r;local batches=math.ceil(qty/math.max(1,r.yield or 1))
        local ingredients=M.inputs(r,batches);local nextState=copy(state);local steps=copy(lines);local sum=0
        if ingredients and next(ingredients) then
          for mat,amount in pairs(ingredients) do
            local c,sub,updated=solve(mat,amount*batches,nextState,path,depth+1)
            if not c then sum=nil;break end
            sum=sum+c;nextState=updated;for _,step in ipairs(sub) do steps[#steps+1]=step end
          end
          if sum and sum<(best or math.huge) then
            best=sum;bestState=nextState;bestState[item]=(bestState[item] or 0)+batches*(r.yield or 1)-qty
            steps[#steps+1]={id=item,n=batches,action='Craft',detail=known.who..' / '..r.name};result=steps
          end
        end
      end
      path[item]=nil
    end
    return best,result,bestState
  end
  local cost,steps=solve(id,n,{},{},0)
  return cost,steps,limited
end

function M.historySeries(id,days)
  local h=ForeverMarketHistory()[tostring(id)] or {}
  local today=math.floor(time()/86400);local series={}
  for i=1,days do
    local day=today-days+i
    series[i]={day=day,ask=h.floors and h.floors[day],high=h.bulkHigh and h.bulkHigh[day],units=h.a and h.a[day]}
  end
  local item=name(id)
  for _,e in ipairs(ForeverMarketActivity and ForeverMarketActivity.events or {}) do
    if e.kind=='proceeds_collected' and e.invoiceType=='seller' and e.name==item and e.region==GetCurrentRegion() and ForeverMarketEventRealm(e)==ForeverMarketVenueRealm() and e.faction==UnitFactionGroup('player') and e.character==UnitName('player') and e.amount and e.fee and e.deposit and (e.quantity or 0)>0 then
      local b=series[math.floor(e.at/86400)-today+days]
      if b then b.gross=(b.gross or 0)+e.amount+e.fee-e.deposit;b.sold=(b.sold or 0)+e.quantity;b.sale=b.gross/b.sold end
    end
  end
  return series
end

-- Baseline gathering leads. A recorded route takes precedence for its item.
local farmLeads={
  [2770]='Mining: copper veins', [2771]='Mining: Hillsbrad Foothills',
  [2772]='Mining: iron deposits', [3858]='Mining: The Hinterlands',
  [10620]='Mining: thorium veins',
  [2589]='Loot: low-level humanoids', [2592]='Loot: humanoids (wool)',
  [4306]='Loot: humanoids (silk)', [4338]='Loot: humanoids (mageweave)',
  [14047]='Loot: high-level humanoids',
  [2318]='Skinning: low-level beasts', [2319]='Skinning: medium leather',
  [4234]='Skinning: heavy leather', [4304]='Skinning: thick leather',
  [8170]='Skinning: high-level beasts',
}
for _,id in ipairs({765,2447,2449,785,2450,2452,2453,3820,3355,3356,3357,
  3358,3818,3819,3821,4625,8831,8836,8838,8839,8845,8846,13463,13464,
  13465,13466,13467,13468}) do farmLeads[id]='Herbalism: gather this herb' end

function M.farmTargets()
  if ForeverMarketHasScan and not ForeverMarketHasScan() then return {} end
  local leads={}
  for id,lead in pairs(farmLeads) do leads[id]=lead end
  for _,session in ipairs(M.account().farming or {}) do
    for id,item in pairs(session.items or {}) do
      if tonumber(id) and (item.n or 0)>0 then leads[tonumber(id)]='Recorded: '..session.label end
    end
  end
  local history=ForeverMarketHistory()
  local today=math.floor(time()/86400)
  local rows={}
  for id,lead in pairs(leads) do
    local h=history[tostring(id)]
    if h and h.day and h.day>=today-2 and h.day<=today and h.m and h.m>0 then
      local prices={}
      local latest=h.floors and h.floors[h.day] or h.m
      for day=today-6,today do
        local price=h.floors and h.floors[day] or h.l and h.l[day]
        if price and price>0 then prices[#prices+1]=price end
      end
      table.sort(prices)
      local n=#prices
      local reference=n>0 and (prices[math.ceil(n/2)]+prices[math.floor(n/2)+1])/2 or latest
      rows[#rows+1]={id=id,lead=lead,net=ForeverMarketSaleNet(math.min(latest,reference)),days=n}
    end
  end
  table.sort(rows,function(a,b)
    if a.net~=b.net then return a.net>b.net end
    if a.days~=b.days then return a.days>b.days end
    return a.id<b.id
  end)
  return rows
end

function M.farmRouteRanks()
  local prices,routes,sorted={},{},{}
  for _,item in ipairs(M.farmTargets()) do prices[item.id]=item.net end
  for _,s in ipairs(M.account().farming or {}) do
    if s.elapsed and s.elapsed>0 then
      local key=(s.zone or '')..'|'..s.label
      local r=routes[key]
      if not r then
        r={name=s.label,zone=s.zone,seconds=0,value=0,paid=0,runs=0,units=0,priced=0,vendor=0,methods={}}
        routes[key]=r;sorted[#sorted+1]=r
      end
      r.seconds=r.seconds+s.elapsed;r.runs=r.runs+1;r.paid=r.paid+(s.returned or 0);r.vendor=r.vendor+(s.vendor or 0)
      for id,item in pairs(s.items or {}) do
        local lead=farmLeads[tonumber(id)]
        local method=lead and lead:match('^([^:]+)')
        if method then r.methods[method]=true end
        local n=item.n or 0;r.units=r.units+n
        if prices[tonumber(id)] then r.priced=r.priced+n;r.value=r.value+n*prices[tonumber(id)] end
      end
      r.hour=r.value*3600/r.seconds
    end
  end
  table.sort(sorted,function(a,b)
    if a.hour~=b.hour then return a.hour>b.hour end
    if a.seconds~=b.seconds then return a.seconds>b.seconds end
    return (a.name..(a.zone or ''))<(b.name..(b.zone or ''))
  end)
  return sorted
end

local function sessions()
  local a=M.account();a.farming=a.farming or {};return a.farming
end
function M.farmStart(label)
  local a=M.account()
  if a.farmActive then return 'A session is already running.' end
  local s={label=label~='' and label or GetZoneText(),at=time(),zone=GetZoneText(),items={},returned=0}
  local list=sessions();list[#list+1]=s;a.farmActive=#list
  return 'Recording your loot in '..s.label
end
function M.farmStop()
  local a=M.account();local list=sessions();local s=list[a.farmActive]
  if not s then return 'No active session.' end
  s.elapsed=math.max(1,time()-s.at);a.farmActive=nil;return 'Saved '..s.label
end
function M.farmLoot(id,n)
  local a=M.account();local s=sessions()[a.farmActive]
  if not s then return end
  local r=s.items[id] or {n=0,held=0};s.items[id]=r;r.n=r.n+n;r.held=r.held+n
  local vendor=select(11,C_Item.GetItemInfo(id));local price=M.prices(id)
  if vendor then s.vendor=(s.vendor or 0)+vendor*n else s.unknownVendor=(s.unknownVendor or 0)+n end
  if price then s.market=(s.market or 0)+ForeverMarketSaleNet(price*n) else s.unknown=(s.unknown or 0)+n end
end
function M.farmActivity(kind,e)
  local a=M.account()
  if not a.farming or #a.farming==0 then return end
  local lots=a.farmLots or {};a.farmLots=lots
  if kind=='posted' and e.auctionId and e.quantity and e.quantity>0 and e.total and e.itemId then
    local fund=ForeverMarketTradingFund()
    local left=e.quantity;local shares={}
    for _,l in ipairs(fund.lots) do if l.auctionId==e.auctionId and l.n>0 then left=0;break end end
    for i,s in ipairs(a.farming) do
      local r=s.items[e.itemId];local n=math.min(left,r and r.held or 0)
      if n>0 then shares[#shares+1]={i=i,n=n};left=left-n;r.held=r.held-n end
    end
    lots[e.auctionId]={shares=shares,name=e.name,id=e.itemId,price=e.total/e.quantity,remaining=e.quantity,at=e.at}
  elseif kind=='sale_notice' and lots[e.auctionId] then lots[e.auctionId].sold=true
  elseif kind=='proceeds_collected' and e.invoiceType=='seller' and e.quantity and e.amount and e.fee and e.deposit then
    local match
    for _,l in pairs(lots) do
      if l.sold and l.remaining>=e.quantity and l.name==e.name and l.price*e.quantity==e.amount+e.fee-e.deposit then
        if match then return end;match=l
      end
    end
    if match then
      local left=e.quantity
      for _,s in ipairs(match.shares) do local n=math.min(s.n,left)
        local offset=e.quantity-left;local net=e.amount-e.deposit
        a.farming[s.i].returned=a.farming[s.i].returned+math.floor(net*(offset+n)/e.quantity)-math.floor(net*offset/e.quantity)
        s.n=s.n-n;left=left-n
      end
      match.remaining=match.remaining-e.quantity
    end
  elseif kind=='auction_expired' then
    local match
    for _,l in pairs(lots) do if not l.sold and l.id==e.itemId and l.remaining==e.quantity then if match then return end;match=l end end
    if match then for _,s in ipairs(match.shares) do count(a.farming[s.i].items[e.itemId],'held',s.n);s.n=0 end;match.remaining=0 end
  end
end

local pendingVendor
local function reconcileLoot()
  local list=M.account().farming
  if not list or pendingVendor then return end
  local room={}
  for _,session in ipairs(list) do for id,r in pairs(session.items) do
    if r.held>0 then
      if room[id]==nil then room[id]=M.bagCount(id) end
      r.held=math.min(room[id],r.held);room[id]=room[id]-r.held
    end
  end end
end
local reconcileAt
local function beforeVendorUse(bag,slot)
  if not MerchantFrame or not MerchantFrame:IsShown() or CursorHasItem() then return end
  if pendingVendor then pendingVendor=nil;return end
  local item=C_Container.GetContainerItemInfo(bag,slot)
  if not item then return end
  local price=select(11,C_Item.GetItemInfo(item.itemID))
  if not price or price<=0 then return end
  pendingVendor={id=item.itemID,n=item.stackCount or 1,price=price,at=GetTime(),cash=GetMoney(),held=M.bagCount(item.itemID)}
end
-- A secure post-hook may run before or after the wallet/bag updates. Only
-- credit observations where both independent deltas subsequently match.
local function settleVendor()
  local v=pendingVendor
  if not v then return end
  if GetTime()-v.at>4 then pendingVendor=nil;return end
  if GetMoney()-v.cash~=v.price*v.n or v.held-M.bagCount(v.id)~=v.n then return end
  local left=v.n
  for _,s in ipairs(M.account().farming or {}) do
    local item=s.items[v.id];local take=math.min(left,item and item.held or 0)
    if take>0 then item.held=item.held-take;s.returned=s.returned+v.price*take;left=left-take end
  end
  pendingVendor=nil
end
local events=CreateFrame('Frame')
if hooksecurefunc and C_Container and C_Container.UseContainerItem then hooksecurefunc(C_Container,'UseContainerItem',function(bag,slot)
  if M.account().farming then beforeVendorUse(bag,slot) end
end) end
for _,ev in ipairs({'MERCHANT_SHOW','CHAT_MSG_LOOT','PLAYER_LOGOUT','BAG_UPDATE_DELAYED','PLAYER_MONEY','MERCHANT_CLOSED','MAIL_INBOX_UPDATE','OWNED_AUCTIONS_UPDATED','REPLICATE_ITEM_LIST_UPDATE'}) do pcall(events.RegisterEvent,events,ev) end
events:SetScript('OnUpdate',function()
  if reconcileAt and GetTime()>=reconcileAt then reconcileAt=nil;settleVendor();reconcileLoot() end
end)
local function lootPattern(format)
  if not format then return end
  local s=format:gsub('([%^%$%(%)%.%[%]%*%+%-%?])','%%%1'):gsub('%%%%','%%')
  return '^'..s:gsub('%%s','(.+)'):gsub('%%d','(%%d+)')..'$'
end
events:SetScript('OnEvent',function(_,ev,msg)
  if ev=='PLAYER_MONEY' or ev=='BAG_UPDATE_DELAYED' then M.tripDirty=true;settleVendor();if ev=='BAG_UPDATE_DELAYED' and M.account().farming then reconcileAt=GetTime()+2 end;return end
  if ev=='MERCHANT_CLOSED' then pendingVendor=nil;return end
  if ev=='MAIL_INBOX_UPDATE' or ev=='OWNED_AUCTIONS_UPDATED' or ev=='REPLICATE_ITEM_LIST_UPDATE' then M.tripDirty=true;return end
  if ev=='MERCHANT_SHOW' then
    if not GetMerchantNumItems then return end
    for i=1,GetMerchantNumItems() do
      local price,qty,available,extended
      if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local m=C_MerchantFrame.GetItemInfo(i)
        if m and m.isPurchasable then price,qty,available,extended=m.price,m.stackCount,m.numAvailable,m.hasExtendedCost end
      elseif GetMerchantItemInfo then
        local _,_,p,n,a,_,x=GetMerchantItemInfo(i);price,qty,available,extended=p,n,a,x
      end
      local id=GetMerchantItemID and GetMerchantItemID(i) or tonumber((GetMerchantItemLink and GetMerchantItemLink(i) or ''):match('item:(%d+)'))
      if id and price and qty and qty>0 and available==-1 and not extended then realmOps().vendors[id]={price=price,bundle=qty,name=UnitName('npc'),at=time()} end
    end
  elseif ev=='PLAYER_LOGOUT' then if M.account().farmActive then M.farmStop() end
  elseif msg and M.account().farmActive then
    for _,fmt in ipairs({LOOT_ITEM_SELF_MULTIPLE or '',LOOT_ITEM_SELF or ''}) do
      local link,n=msg:match(lootPattern(fmt))
      local id=link and tonumber(link:match('item:(%d+)'))
      if id then M.farmLoot(id,tonumber(n) or 1);break end
    end
  end
end)
