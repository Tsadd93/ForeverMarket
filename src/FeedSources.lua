local M=ForeverMarketTools
local week=7*86400
local function current(at) return at and at<=time() and time()-at<=week end
local function snapshot(kind)
  local data=kind=='realm' and ForeverMarketFeedRealm or nil
  if kind=='region' then
    data=ForeverMarketFeedRegion
    local manual=ForeverMarketDB and ForeverMarketDB.importedRegion
    if manual and manual.region==GetCurrentRegion() and (not data or data.region~=manual.region or manual.at>data.at) then data=manual end
  end
  if data and data.region==GetCurrentRegion() then
    if kind=='region' then return data end
    local faction=UnitFactionGroup('player');local realm=ForeverMarketVenueRealm()
    local mapped=ForeverMarketDesktopRealm and ForeverMarketDesktopRealm(realm,data.region,faction) or realm
    if data.market==mapped..'|'..faction then return data end
  end
end
local indices={dbregionmarketavg=1,dbregionsalerate=2,dbregionsoldperday=3,dbregionhistorical=4,dbregionsaleavg=5,dbmarket=1,dbhistorical=2,dbminbuyout=3}
local short={dbregionmarketavg=1,dbregionsalerate=2,dbregionsoldperday=3}
function M.feedValue(id,key)
  if not indices[key] then return end
  local kind=key:match('^dbregion') and 'region' or 'realm'
  local d=snapshot(kind);local row=d and current(d.at) and d.items[id]
  local n=row and row[indices[key]]
  if type(n)=='number' then return n,nil,kind..' feed / '..date('%b %d',d.at) end
  local b=short[key] and ForeverMarketRegionPrices and ForeverMarketRegionPrices[id]
  if b and current(b[4]) then return b[short[key]],nil,'regional sample / '..date('%b %d',b[4]) end
end
function M.fullRegion()
  local d=snapshot('region')
  if d and current(d.at) then return d end
end
local sampleAt
local function newest()
  if not sampleAt then local _,row=next(ForeverMarketRegionPrices or {});sampleAt=row and row[4] end
  local d=snapshot('region')
  return math.max(sampleAt or 0,d and d.at or 0)
end
function M.regionalStatus()
  local at=newest()
  return at==0 and 'No regional data loaded.' or (current(at) and 'Regional prices updated ' or 'Regional data expired / ')..date('%b %d',at)
end
function M.updatePrices(manual)
  local at=newest()
  local day=math.floor(time()/86400)
  if not manual and (current(at) or ForeverMarketDB.priceReminderDay==day) then return end
  if not StaticPopupDialogs or not StaticPopup_Show then return end
  ForeverMarketDB.priceReminderDay=day
  StaticPopupDialogs.FM_UPDATE_PRICES={
    text=M.regionalStatus()..'\n\nRun Forever Market Desktop. Reload to load staged prices and request a fresh check. If Desktop downloads newer prices afterward, reload once more when ready.',
    button1='Update & reload',button2='Use local scans',button3='Paste price pack',timeout=0,whileDead=true,hideOnEscape=true,
    OnAccept=function()ForeverMarketUpdateRequested=time()*10+GetCurrentRegion();ReloadUI()end,
    OnAlt=function()M.openTools('Shared prices')end}
  StaticPopup_Show('FM_UPDATE_PRICES')
end
-- Portable text interchange, using typed numerical data and upstream time.
function M.importRegionPack(text)
  if #text>4000000 then return 'Regional pack too large.' end
  local region,at,expected,body=text:match('^FMREG1 (%d+) (%d+) (%d+)\r?\n(.+)$')
  region,at=tonumber(region),tonumber(at)
  if region~=GetCurrentRegion() or not current(at) or at<newest() then return 'Wrong region, expired or older snapshot.' end
  local items,count={},0
  for line in body:gmatch('[^\r\n]+') do
    local id,rest=line:match('^(%d+),(.+)$');id=tonumber(id)
    if not id or id<1 or id>2147483647 or items[id] or count>=60000 then return 'Invalid regional pack.' end
    local vals={}
    for s in (rest..','):gmatch('(.-),') do
      local n=tonumber(s)
      if s=='-' then vals[#vals+1]=false
      elseif n and n>=0 and n<=1e12 and (#vals~=1 or n<=1) and (#vals==1 or #vals==2 or n>0 and n==math.floor(n)) then vals[#vals+1]=n
      else return 'Invalid regional value.' end
    end
    if #vals~=5 then return 'Invalid regional columns.' end
    items[id]=vals;count=count+1
  end
  if count==0 or count~=tonumber(expected) then return 'Incomplete regional pack.' end
  ForeverMarketDB.importedRegion={at=at,region=region,items=items}
  return 'Imported '..count..' regional items.'
end
local operations={auctioningopmin='Posting minimum',auctioningopnormal='Normal posting price',auctioningopmax='Posting maximum',shoppingopmax='Shopping ceiling',sniperopmax='Sniper ceiling'}
M.operationSources=operations
local resolving={}
function M.operationValue(id,key)
  if not operations[key] then return end
  if resolving[key] then return nil,'Circular operation '..key end
  local group=M.group(id) or {}
  local program=M.importedRules(group) or {}
  local tree=(group.sourceRules or {})[key] or (program.sources or {})[key]
  if not tree then
    local seq=key=='auctioningopmin' and program.sell or key=='shoppingopmax' and program.buy
    tree=seq and seq[1] and seq[1].tree
  end
  if not tree and key=='sniperopmax' and (group.watchCap or 0)>0 then return group.watchCap,nil,operations[key] end
  if not tree and key=='shoppingopmax' and (group.cap or 0)>0 then return group.cap,nil,operations[key] end
  if not tree and key=='auctioningopmin' and (group.fixedFloor or 0)>0 then return group.fixedFloor,nil,operations[key] end
  if not tree then return nil,'Set '..operations[key]..' for this item.' end
  resolving[key]=true
  local ok,v,why=pcall(M.evaluatePrice,tree,function(k)return M.ruleSource(id,k,false)end)
  resolving[key]=nil
  if ok and v and v>0 then return v,nil,operations[key] end
  return nil,ok and (why or 'Operation price unavailable') or 'Operation evaluation failed'
end
function M.setOperation(id,key,expr)
  if not operations[key] then return 'Unknown operation.' end
  local tree,why=M.compilePrice(expr,M.account().namedFormulas)
  if not tree then return why end
  local group=M.group(id) or {margin=0,stock=0,cap=0}
  group.sourceRules=group.sourceRules or {};group.sourceRules[key]=tree
  M.account().desk.groups[id]=group;M.invalidate();return 'Saved '..operations[key]
end
local ledgerKeys={avgbuy=true,avgsell=true,smartavgbuy=true,numexpires=true,salerate=true,numinventory=true}
local cache={}
function M.personalPrice(id,key)
  if key=='vendorbuy' then
    local a=(ForeverMarketDB.operations or {})[M.inventoryScope()];local v=a and a.vendors[id]
    if v and (v.bundle or 0)>0 then return v.price/v.bundle,nil,'Observed vendor / '..date('%b %d',v.at) end
    return nil,'Visit a vendor selling this item'
  elseif key=='destroy' then
    local n,s=M.disenchantValue(id);if n then return n,nil,s..' observed disenchant samples, net value' end
    return nil,'Missing local conversion yields or material prices'
  elseif key=='matprice' then
    for _,r in pairs(M.account().recipes or {}) do
      if (r.materials or {})[id] then local price=M.prices(id);if price then return price,nil,'Known reagent / local price' end end
    end
    return nil,'Missing known reagent or material price'
  end
  if not ledgerKeys[key] then return end
  local inventory=C_Item.GetItemCount or GetItemCount
  if key=='numinventory' then
    if inventory then return inventory(id,true),nil,'Personal bags and bank' end
    return nil,'Inventory unavailable'
  end
  local events=ForeverMarketActivity and ForeverMarketActivity.events or {}
  local realm,character,faction=ForeverMarketVenueRealm(),UnitName('player'),UnitFactionGroup('player')
  local scope=table.concat({GetCurrentRegion(),realm,character,faction},'|')
  if cache.events~=events or cache.scope~=scope or cache.last~=events[#events] or cache.count~=#events then
    cache={events=events,scope=scope,count=#events,last=events[#events],rows={}}
    for _,e in ipairs(events) do
      if e.character==character and e.region==GetCurrentRegion() and e.faction==faction and ForeverMarketEventRealm(e)==realm then
        local k=e.itemId or e.name
        if k then
          local rows=cache.rows;rows[k]=rows[k] or {};table.insert(rows[k],e)
        end
      end
    end
  end
  local rows={};local name=C_Item.GetItemNameByID(id)
  for _,k in ipairs({id,name}) do for _,e in ipairs(cache.rows[k] or {}) do rows[#rows+1]=e end end
  table.sort(rows,function(a,b)return a.at>b.at end)
  local cost,bought,gross,sold,posts,sales,expires=0,0,0,0,0,0,0
  local need=key=='smartavgbuy' and inventory and inventory(id,true) or 0
  local sum,taken,seenSale=0,0,false
  for _,e in ipairs(rows) do
    local n=e.quantity or 0
    if e.kind=='purchase' and n>0 and (e.total or 0)>0 then
      bought=bought+n;cost=cost+e.total;local q=math.min(need-taken,n);sum=sum+q*e.total/n;taken=taken+q
    elseif e.kind=='proceeds_collected' and e.invoiceType=='seller' and e.amount and e.fee and e.deposit and n>0 then
      sold=sold+n;gross=gross+e.amount+e.fee-e.deposit;sales=sales+1;seenSale=true
    elseif e.kind=='posted' then posts=posts+1
    elseif (e.kind=='auction_expired' or e.kind=='auction_cancelled') and not seenSale then expires=expires+1 end
  end
  if key=='avgbuy' and bought>0 then return cost/bought,nil,bought..' purchased units' end
  if key=='smartavgbuy' and need>0 and taken==need then return sum/taken,nil,taken..' recent purchased units' end
  if key=='avgsell' and sold>0 then return gross/sold,nil,sold..' invoiced units' end
  if key=='salerate' and posts>0 and sales<=posts then return sales/posts,nil,sales..' collected sales / '..posts..' posts' end
  if key=='numexpires' and #rows>0 then return expires,nil,'Recorded returns since last collected sale' end
  return nil,key=='avgbuy' and 'No recorded purchases' or 'Insufficient personal history for '..key
end
