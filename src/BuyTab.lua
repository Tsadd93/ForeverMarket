local GetRealmName=ForeverMarketVenueRealm or function() return _G.GetRealmName and _G.GetRealmName() or '' end
local api=C_AuctionHouse
if not api then return end
local panel,status,balance,content,scroll
local fundButtons={}
local rows,leads,verified={},{},{}
local cursor,search,lastSearch=1,nil,-100
local checked,unanswered,totalLeads,missingScan=0,0,0,false
local remembered,displayOrder={},{}
local snapshotMode,waitingSince,startedAt,firstResult,requests
local report
local awaitingBulk,nextBulkCheck
local running=false
local completed=false
local detail
local quote,posting
local function fund()
  ForeverMarketDB=ForeverMarketDB or {}
  local funds=ForeverMarketDB.__funds or {};ForeverMarketDB.__funds=funds
  local key=UnitGUID('player')
  funds[key]=funds[key] or {seed=10000,cash=10000,held={},lots={}}
  return funds[key]
end
ForeverMarketTradingFund=fund
function ForeverMarketChangeCash(f,delta,kind,name)
  if delta==0 then return end
  f.cashLog=f.cashLog or {}
  f.cashOpening=f.cashOpening or f.cash
  f.cash=f.cash+delta
  table.insert(f.cashLog,{at=time(),delta=delta,kind=kind,name=name})
  if #f.cashLog>500 then local e=table.remove(f.cashLog,1);f.cashOpening=f.cashOpening+e.delta end
end
local function available(forCraft)
  local f=fund();local reserve=0
  for _,h in pairs(f.held) do reserve=reserve+(h.reserve or 0) end
  for _,order in pairs(f.itemOrders or {}) do reserve=reserve+order.total+order.dep end
  if not forCraft and ForeverMarketTools then reserve=reserve+ForeverMarketTools.reserve() end
  return math.max(0,math.min(GetMoney(),f.cash)-reserve)
end
ForeverMarketSpendable=available
local benchmarkCash,benchmarkQueue
local function scanCash()return benchmarkCash or available() end
-- Classic materials and consumables observed in the Forever market.
local staples={
  [2589]=true,[2592]=true,[4306]=true,[4338]=true,[14047]=true, -- cloth
  [2770]=true,[2771]=true,[2772]=true,[3858]=true,[10620]=true, -- ore
  [2318]=true,[2319]=true,[4234]=true,[4304]=true,[8170]=true, -- leather
  [2450]=true,[2452]=true,[10940]=true,[14344]=true, -- herbs and enchanting
  [6889]=true,[12203]=true,[12184]=true,[6471]=true,[5634]=true, -- local leads and potion
}
local stock
local function onHand()
  if stock then return stock end
  local bags,held,mail,orders={},{},{},{}
  local function add(t,id,n) if id and n and n>0 then t[id]=(t[id] or 0)+n end end
  if C_Container and C_Container.GetContainerNumSlots then
    for bag=0,NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
      for slot=1,C_Container.GetContainerNumSlots(bag) do
        local item=C_Container.GetContainerItemInfo(bag,slot)
        if item then add(bags,item.itemID,item.stackCount) end
      end
    end
  end
  local f=fund()
  for key,h in pairs(f.held) do
    local id=h.lead or tonumber(key) or tonumber(tostring(key):match('^(%d+)/'))
    add(held,id,h.n)
    add(mail,id,math.min(h.n or 0,h.inMail or 0))
  end
  for _,o in pairs(f.itemOrders or {}) do add(orders,o.lead or o.id,o.n) end
  local listed={}
  if api.GetNumOwnedAuctions and api.GetOwnedAuctionInfo then
    for i=1,api.GetNumOwnedAuctions() do
      local a=api.GetOwnedAuctionInfo(i)
      if a and a.itemKey and (not a.status or a.status==0) then
        local species=a.itemKey.battlePetSpeciesID or 0
        add(listed,species>0 and -species or a.itemKey.itemID,a.quantity or 1)
      end
    end
  end
  for id,n in pairs(held) do bags[id]=math.max(n,(bags[id] or 0)+(mail[id] or 0)) end
  for id,n in pairs(listed) do add(bags,id,n) end
  for id,n in pairs(orders) do add(bags,id,n) end
  stock=bags
  return bags
end
local function room(id,stack)
  local group=ForeverMarketTools and ForeverMarketTools.group and ForeverMarketTools.group(id)
  local limit=(stack or 1)*(staples[id] and 2 or 1)
  if group and group.stock>0 then limit=group.stock end
  return math.max(0,limit-(onHand()[id] or 0))
end
local investScan=false
local watchScan=false
local watchAgain=0
local watchAlerts={}
local retryPool={}
local function rememberFailure(lead)
  if not lead or not lead.id then return end
  retryPool[lead.id]=lead
end
local itemConfirmation=false
local scanWait
local scanWake=false
local fundMessageUntil=0
local function note(s) if status then status:SetText(s) end end
local function clearQuote()
  if quote then quote=nil;api.CancelCommoditiesPurchase() end
end
-- Browse summaries select candidates. Only the existing detailed lookup may create a Buy row.
local categories,categoryIndex,browse={},1,nil
local screened,browseFallback=0,0
local rechecked={}
local pausedMarket
local function nearMiss(id,gap,reason)
  if not report or gap<=0 then return end
  local misses=report.misses or {};report.misses=misses
  for i,miss in ipairs(misses) do
    if miss.id==id then if miss.gap<=gap then return end;table.remove(misses,i);break end
  end
  misses[#misses+1]={id=id,gap=gap,reason=reason}
  table.sort(misses,function(a,b)return a.gap<b.gap end)
  misses[4]=nil
end
local function screenOffer(id,cost,net,cash,deposit)
  if cost<=0 then return end
  if cost+deposit>cash then
    local short=cost+deposit-cash
    nearMiss(id,short/(cost+deposit),'needs '..ForeverMarketCoins(short)..' more')
  elseif net*10000<cost*(10000+ForeverMarketMarginBP()) then
    local margin=(net/cost-1)*100
    nearMiss(id,(ForeverMarketMarginBP()/100-margin)/100,('estimated %.1f%% return'):format(margin))
  end
end
local function supportsBrowse()
  return api.SendBrowseQuery and api.GetBrowseResults and api.RequestMoreBrowseResults
    and api.HasFullBrowseResults and C_Item.GetItemInfoInstant
end
local function groupCandidates(batchKeys)
  local groups,unknown={},{}
  local batch
  for _,lead in ipairs(leads) do
    local _,_,_,slot,_,class,sub=C_Item.GetItemInfoInstant(lead.id<0 and 82800 or lead.id)
    local key=batchKeys and api.SearchForItemKeys and lead.id>0 and api.MakeItemKey(lead.id)
    local info=key and api.GetItemKeyInfo and api.GetItemKeyInfo(key)
    if info and info.isCommodity then
      if not batch or #batch.keys>=100 then
        batch={keys={},items={},byId={}}
        categories[#categories+1]=batch
      end
      batch.keys[#batch.keys+1]=key
      batch.items[#batch.items+1]=lead
      batch.byId[lead.id]=lead
    elseif type(class)=='number' and lead.id>0 then
      if class~=2 and class~=4 then sub=nil end
      local head=class==4 and slot=='INVTYPE_HEAD'
      local groupKey=class..'/'..tostring(sub)..(head and '/head' or '')
      local group=groups[groupKey]
      if not group then
        group={filter={classID=class,subClassID=sub,inventoryType=head and 1 or nil},items={},byId={}}
        groups[groupKey]=group
        categories[#categories+1]=group
      end
      group.items[#group.items+1]=lead
      group.byId[lead.id]=lead
    else
      unknown[#unknown+1]=lead
    end
  end
  if #unknown>0 then categories[#categories+1]={items=unknown} end
  leads={}
end
local function finishCategory(fallback)
  local group=browse
  browse=nil
  if fallback and #group.items>4 then
    if not group.retried then
      group.retried=true;group.count=nil;group.processed=nil;group.more=nil
      categories[#categories+1]=group
    else
      for _,lead in ipairs(group.items) do rememberFailure(lead) end
      unanswered=unanswered+#group.items
    end
    browseFallback=browseFallback+1;scanWake=true;return
  end
  local picks={}
  local cash=scanCash()
  for _,lead in ipairs(group.items) do
    local price=group.prices[lead.id]
    if fallback or price==0 then
      picks[#picks+1]=lead
    elseif price and price<=cash and (math.floor(lead.ref*.9)-2)*ForeverMarketKeepBP()>=price*(10000+ForeverMarketMarginBP()) then
      lead.browseRank=lead.ref/price
      picks[#picks+1]=lead
    else
      if not price then report.noSupply=(report.noSupply or 0)+1
      elseif price>cash then report.overBudget=(report.overBudget or 0)+1
      else report.weakSpread=(report.weakSpread or 0)+1 end
      if price and price>0 then screenOffer(lead.id,price,ForeverMarketSaleNet(math.max(0,math.floor(lead.ref*.9)-2)),cash,0) end
      screened=screened+1
    end
  end
  if fallback then browseFallback=browseFallback+1 else
    table.sort(picks,function(a,b)
      if a.potential~=b.potential then return a.potential>b.potential end
      local ar,br=a.browseRank or 0,b.browseRank or 0
      if ar~=br then return ar>br end
      if a.researchRank~=b.researchRank then return a.researchRank<b.researchRank end
      return a.id<b.id
    end)
  end
  for _,lead in ipairs(picks) do leads[#leads+1]=lead end
  scanWake=true
end
local function browseResults(added,page)
  if not browse then return end
  local results=api.GetBrowseResults()
  if type(results)~='table' then finishCategory(true);return end
  local first=1
  local rows=results
  if added and type(page)=='table' then
    rows=page
  elseif added and browse.processed and browse.processed<=#results then
    first=browse.processed+1
  elseif not added then
    browse.prices={}
  end
  for i=first,#rows do
    local r=rows[i]
    local id=r.itemKey and r.itemKey.itemID
    if id and (r.minPrice or 0)>0 and (r.totalQuantity or 0)>0 then ForeverMarketObserve(ForeverMarketHistoryKey(r.itemKey),r.minPrice,r.totalQuantity) end
    if id and browse.byId[id] then
      local price=r.minPrice or 0
      browse.prices[id]=math.min(browse.prices[id] or price,price)
    end
  end
  browse.processed=#results
  if api.HasFullBrowseResults() then finishCategory(false)
  elseif #results>(browse.count or -1) then
    browse.count=#results;browse.more=true;scanWake=true
  end
end
local function advanceCategory()
  if browse then
    scanWait='Waiting for category results'
    if GetTime()-browse.sent>8 then finishCategory(true)
    elseif browse.more and api.IsThrottledMessageSystemReady() then
      browse.more=false;browse.sent=GetTime()
      if not pcall(api.RequestMoreBrowseResults) then finishCategory(true) end
    end
  elseif categoryIndex<=#categories and api.IsThrottledMessageSystemReady() then
    local group=categories[categoryIndex]
    categoryIndex=categoryIndex+1
    if not group.filter and not group.keys then
      for _,lead in ipairs(group.items) do leads[#leads+1]=lead end
      return
    end
    browse=group;group.prices={};group.sent=GetTime()
    if group.keys then
      if not pcall(api.SearchForItemKeys,group.keys,{}) then finishCategory(true) end
      return
    end
    group.query={searchString='',sorts={},filters={},itemClassFilters={group.filter}}
    if not pcall(api.SendBrowseQuery,group.query) and browse then finishCategory(true) end
  elseif categoryIndex<=#categories then
    scanWait='Waiting for the auction house throttle'
  end
end
-- Browse results belong to the shared AH window. Discard our batch if another
-- tab or addon replaces its query before the final page arrives.
if hooksecurefunc and api.SendBrowseQuery then
  hooksecurefunc(api,'SendBrowseQuery',function(query)
    if browse and query~=browse.query then finishCategory(true) end
  end)
end
-- IDs are stable across item locales. These are ordinary vendor supplies.
local vendorStock={
  [4471]=true,[2901]=true,[7005]=true,[5956]=true,[6256]=true,[4470]=true,
  [2320]=true,[2321]=true,[4291]=true,[8343]=true,[14341]=true,
  [3371]=true,[2880]=true,[3466]=true,
}
local junkCount,unknownCount=0,0
local pendingFilter
local function buyEligible(lead)
  if lead.id<0 then return true end
  if vendorStock[lead.id] then return false end
  local _,_,quality,_,_,_,_,stack,_,_,vendor,class=C_Item.GetItemInfo(lead.id)
  if quality==nil then return nil end
  lead.maxStack=stack
  if quality>=2 then return true end
  if class==nil and C_Item.GetItemInfoInstant then class=select(6,C_Item.GetItemInfoInstant(lead.id)) end
  if quality==1 and (class==3 or class==5 or class==7 or class==9) then return true end
  if quality==1 and class==nil then return nil end
  if vendor==nil then return nil end
  return lead.scarceDays>=5 and lead.ref>=math.max(10000,vendor*10)
end
-- A buyer who clears the cheapest tier can list against the immediate next
-- tier. The sell tab's outlier test serves a different purpose.
local function commodityResaleAsk(depth)
  if depth.nextPrice and depth.nextQty and depth.nextQty>=math.max(2,depth.lowQty) then
    return depth.nextPrice
  end
  return depth.low
end
local function rankCandidates(snapshot,grouped,cash)
  local eligible={}
  report.stockSkipped=0
  for _,lead in ipairs(leads) do
    if room(lead.id,lead.maxStack)>0 then eligible[#eligible+1]=lead
    else report.stockSkipped=report.stockSkipped+1 end
  end
  if watchScan=='bench' then
    local key=GetRealmName()..'|'..UnitFactionGroup('player')
    local sets=ForeverMarketDB.benchSets or {};ForeverMarketDB.benchSets=sets
    local fixed=ForeverMarketDB.trialSets or {};ForeverMarketDB.trialSets=fixed
    local ids=benchmarkCash and fixed[key] or sets[key]
    if not ids then
      table.sort(eligible,function(a,b)return a.id<b.id end);ids={}
      for _,l in ipairs(eligible) do if l.id>0 then ids[#ids+1]=l.id;if #ids==50 then break end end end
      if #ids==50 then sets[key]=ids end
    end
    if benchmarkCash and #ids>0 and not fixed[key] then fixed[key]=ids end
    local selected,byID={},{}
    for _,l in ipairs(eligible) do byID[l.id]=l end
    for _,id in ipairs(ids) do if byID[id] then selected[#selected+1]=byID[id] end end
    eligible=selected;report.benchSize=#ids;report.benchIDs=ids
  end
  leads=eligible;totalLeads=#leads
  local deferred={}
  local fresh=snapshot and GetTime()-snapshot.at<60
  if watchScan then snapshot=nil end
  if snapshot then
    local picks={}
    for _,lead in ipairs(leads) do
      local d=snapshot.books[lead.id]
      local cap=lead.model and lead.model.exit or math.floor(lead.ref*.9)-2
      local pick=false
      if d and d.low<=cash and cap*ForeverMarketKeepBP()>=d.low*(10000+ForeverMarketMarginBP()) then
        local info=api.GetItemKeyInfo and api.GetItemKeyInfo(api.MakeItemKey(lead.id))
        local commodity=info and info.isCommodity
        local exit=cap
        if commodity and lead.model then exit=d.floorPrice<=lead.model.entry and cap or 0
        elseif commodity then exit=math.min(exit,ForeverMarketPostPrice(commodityResaleAsk(d)))
        elseif d.nextPrice then exit=math.min(exit,ForeverMarketPostPrice(d.nextPrice)) end
        local qty=commodity and math.min(d.lowQty,math.floor(cash*(lead.model and .20 or 1)/d.low)) or 1
        local dep=0
        if commodity and qty>0 and api.CalculateCommodityDeposit then dep=api.CalculateCommodityDeposit(lead.id,1,qty) or 0
        elseif C_Item.GetItemInfo then dep=math.max(100,select(11,C_Item.GetItemInfo(lead.id)) or 0) end
        lead.potential=math.max(0,ForeverMarketSaleNet(exit*qty)-d.low*qty-ForeverMarketDepositLoss(qty))
        if commodity and qty>0 then screenOffer(lead.id,qty*d.low,ForeverMarketSaleNet(exit*qty)-ForeverMarketDepositLoss(qty),cash,dep) end
        -- Mixed equipment variants can hide a better comparable listing.
        if commodity then
          pick=(lead.model or qty==d.lowQty and qty*d.low+dep<=cash) and lead.potential>0 and lead.potential*10000>=qty*d.low*ForeverMarketMarginBP()
        elseif not info or info.isCommodity==nil then
          pick=d.nextPrice~=nil
        else
          -- A variant cannot resell above the highest buyout in the base-item book.
          local upper=math.min(cap,ForeverMarketPostPrice(d.high or d.nextPrice or d.low))
          pick=ForeverMarketSaleNet(upper)-ForeverMarketDepositLoss(1)>=d.low*(1+ForeverMarketMarginBP()/10000)
        end
      end
      if d and d.low>cash then screenOffer(lead.id,d.low,0,cash,0) end
      if pick then picks[#picks+1]=lead
      elseif not fresh or lead.id<0 then deferred[#deferred+1]=lead
      else screened=screened+1
        local reason=not d and "noSupply" or d.low>cash and "overBudget" or "weakSpread"
        report[reason]=(report[reason] or 0)+1
      end
    end
    leads=picks
  end
  if ForeverMarketTools and ForeverMarketTools.salesWeight then
    for _,lead in ipairs(leads) do
      local name=C_Item.GetItemNameByID(lead.id)
      if name then lead.potential=lead.potential*ForeverMarketTools.salesWeight(name) end
    end
  end
  table.sort(leads,function(a,b)
    if (a.potential>0 or staples[a.id]==true)~=(b.potential>0 or staples[b.id]==true) then return a.potential>0 or staples[a.id]==true end
    if a.potential~=b.potential then return a.potential>b.potential end
    if a.affordable~=b.affordable then return a.affordable end
    if a.researchRank~=b.researchRank then return a.researchRank<b.researchRank end
    if a.rank~=b.rank then return a.rank>b.rank end
    return a.id<b.id
  end)
  if snapshot then
    -- Search the snapshot leaders immediately. Refresh the remaining market
    -- after them so a new undercut during the snapshot cooldown is discoverable.
    local picks=leads
    leads=deferred
    if grouped then groupCandidates(true) else categories={{items=deferred}} end
    leads=picks
  elseif grouped then
    -- Detail-check recent discounts first, before an expensive category sweep.
    -- Other items still receive the normal batched search.
    local live=ForeverMarketDB[(GetRealmName and GetRealmName() or '')..'|'..(UnitFactionGroup and UnitFactionGroup('player') or '')] or {}
    local early,remaining={},{}
    for _,lead in ipairs(leads) do
      local q=live[tostring(lead.id)]
      if staples[lead.id] or lead.potential>0 then
        lead.preview=lead.rank;early[#early+1]=lead
      elseif q and q.at<=time() and time()-q.at<=900 and q.price>0 and q.price<=cash
        and ForeverMarketSaleNet(math.floor(lead.ref*.9)-2)>=q.price*(1+ForeverMarketMarginBP()/10000) then
        lead.preview=lead.ref/q.price;early[#early+1]=lead
      else remaining[#remaining+1]=lead end
    end
    table.sort(early,function(a,b)
      if a.potential~=b.potential then return a.potential>b.potential end
      if a.preview~=b.preview then return a.preview>b.preview end
      return a.id<b.id
    end)
    -- Give a few promising items a head start without delaying broader coverage.
    for i=#early,25,-1 do remaining[#remaining+1]=early[i];early[i]=nil end
    leads=remaining;groupCandidates(true);leads=early;report.early=#early
  end
end
local function candidates(keepVerified,snapshot)
  leads={};cursor=1;search=nil
  categories,categoryIndex,browse={},1,nil
  screened,browseFallback=0,0
  rechecked={}
  junkCount,unknownCount,pendingFilter=0,0,nil
  local grouped=not investScan and (not watchScan or watchScan=='market') and supportsBrowse()
  if not keepVerified then verified={} end
  if ForeverMarketRepairHistory then report.merged=ForeverMarketRepairHistory() end
  if investScan and ForeverMarketSeedFloors then ForeverMarketSeedFloors() end
  local db=ForeverMarketHistory()
  checked,unanswered,totalLeads=0,0,0
  missingScan=not db or not next(db)
  local seed=not investScan and (not watchScan or watchScan=='market' or watchScan=='bench') and ForeverMarketStarter
  local realmID=GetRealmID and GetRealmID()
  if not realmID or realmID==0 then realmID=tonumber((UnitGUID('player') or ''):match('^Player%-(%d+)%-')) end
  if seed and (seed.realmID~=realmID or seed.region~=GetCurrentRegion() or seed.faction~=UnitFactionGroup('player') or GetRealmName():find('Neutral AH',1,true) or time()<seed.at or time()-seed.at>21*86400) then seed=nil end
  if missingScan and not seed then return end
  db=db or {}
  local cash=scanCash()
  local books=ForeverMarketDB.__depth
  local book=books and books[GetRealmName()..'|'..UnitFactionGroup('player')]
  local now=time()
  local research=ForeverMarketResearch
  if research then
    local realm=GetRealmName() or ''
    if research.region~=GetCurrentRegion() or research.faction~=UnitFactionGroup('player') or
       not (realm==research.realm or realm=='' and research.allowBlank or ForeverMarketDesktopRealm and ForeverMarketDesktopRealm(realm,GetCurrentRegion(),UnitFactionGroup('player'))==research.realm) or now<research.at or now-research.at>86400 then research=nil end
  end
  local today=math.floor(time()/86400)
  local byId={}
  report.thinHistory=0;report.overBudget=0;report.weakSpread=0;report.noSupply=0;report.bestDays=0;report.bestItem=nil
  for key,r in pairs(db) do
    local raw=tostring(key)
    local species=tonumber(raw:match('^p:(%d+)$'))
    local id=species and -species or tonumber(raw) or tonumber(raw:match('^gr?:(%d+):'))
    if investScan then
      local model=tonumber(raw) and ForeverMarketRecovery and ForeverMarketRecovery(r.floors,today,r.bulkHigh)
      if tonumber(raw) and r.floors then
        local days=0;for day in pairs(r.floors) do if day<today and day>=today-60 then days=days+1 end end
        if days>(report.bestDays or 0) then report.bestDays=days;report.bestItem=id end
      end
      local info=model and api.GetItemKeyInfo(api.MakeItemKey(id))
      if info and info.isCommodity then
        leads[#leads+1]={id=id,ref=model.exit/.9+3,model=model,scarceDays=0,affordable=true,potential=0,researchRank=0,rank=model.wins/model.trials}
      else report.thinHistory=report.thinHistory+1 end
    elseif id and (not watchScan or watchScan=='market' or watchScan=='bench' or ForeverMarketTools.favorite(id)) and type(r)=='table' and type(r.m)=='number' and r.m>0 and r.h then
      local prices,recentPrices={},{}
      local scarceDays=0
      for day,hi in pairs(r.h) do
        local d=tonumber(day)
        if d and d<today and d>=today-14 then
          local price=(r.l and r.l[day]) or hi
          prices[#prices+1]=price
          if d>=today-3 then recentPrices[#recentPrices+1]=price end
          local qty=r.a and r.a[day]
          if qty and qty>0 and qty<=3 then scarceDays=scarceDays+1 end
        end
      end
      if #prices<3 then report.thinHistory=report.thinHistory+1 end
      if #prices>=3 then
        table.sort(prices)
        local ref=prices[math.ceil(#prices/2)]
        if #recentPrices==3 then
          table.sort(recentPrices);ref=math.min(ref,recentPrices[2])
        end
        local studied=research and research.items[id]
        if studied then ref=math.min(ref,studied.ceiling) end
        -- With a week of history, tolerate one extreme observation at each end.
        local trim=#prices>=7 and 1 or 0
        if prices[#prices-trim]<=prices[1+trim]*2 then
          -- A scan can miss a new undercut. Check stable, affordable candidates
          -- even when the last scan's minimum was close to the usual price.
          local discounted=ref*ForeverMarketKeepBP()>=r.m*(10000+ForeverMarketMarginBP())
          local recent=book and book[id]
          if watchScan or snapshot or grouped or discounted or r.m<=cash or (recent and recent.low and recent.low<=cash and recent.at and now-recent.at<300) then
            local potential=0
            if recent and recent.low and recent.low>0 and recent.lowQty and recent.floorPrice and recent.at and now>=recent.at and now-recent.at<300 then
              local ask=recent.nextPrice and commodityResaleAsk(recent) or recent.floorPrice
              local exit=math.min(ForeverMarketPostPrice(ask),math.floor(ref*.9)-2)
              local cost=recent.low*recent.lowQty
              local profit=ForeverMarketSaleNet(exit*recent.lowQty)-cost-ForeverMarketDepositLoss(recent.lowQty)
              if cost<=cash and profit>0 and profit*10000>=cost*ForeverMarketMarginBP() then
                potential=profit
              end
            end
            local previous=byId[id]
            if previous then
              previous.ref=math.min(previous.ref,ref)
              previous.scarceDays=math.min(previous.scarceDays,scarceDays)
              previous.affordable=previous.affordable or r.m<=cash
            else
              local lead={id=id,ref=ref,scarceDays=scarceDays,rank=ref/r.m,affordable=r.m<=cash,potential=potential,researchRank=studied and studied.rank or math.huge}
              byId[id]=lead
              leads[#leads+1]=lead
            end
          end
        end
      end
    end
  end
  if seed then
    for id,ref in pairs(seed.items) do
      local h=db[tostring(id)]
      local days=0
      for d in pairs(h and h.h or {}) do if tonumber(d)<today and tonumber(d)>=today-14 then days=days+1 end end
      if not byId[id] and days<3 then
        leads[#leads+1]={id=id,ref=ref,scarceDays=0,rank=1,affordable=ref<=cash,potential=0,researchRank=math.huge,starter=true}
      end
    end
    missingScan=#leads==0
  end
  local eligible,pending={},{}
  for _,lead in ipairs(leads) do
    local allow=buyEligible(lead)
    if allow then eligible[#eligible+1]=lead
    elseif allow==false then junkCount=junkCount+1
    else pending[#pending+1]=lead end
  end
  leads=eligible
  if #pending>0 then
    pendingFilter={items=pending,at=GetTime(),next=GetTime()+.25,snapshot=snapshot,grouped=grouped}
  else rankCandidates(snapshot,grouped,cash) end
end
local function resaleDeposit(v,n)
  if v.auctionID then return v.dep end
  local options=ForeverMarketTools and ForeverMarketTools.postOptions and ForeverMarketTools.postOptions(v.id) or {}
  local stack=math.min(v.stack,options.size or v.stack)
  local duration=options.duration or 1
  local full=math.floor(n/stack)
  local rest=n%stack
  local standard=0
  if full>0 then standard=api.CalculateCommodityDeposit(v.id,duration,stack) end
  local remainder=0
  if full>0 and not standard then return end
  if rest>0 then remainder=api.CalculateCommodityDeposit(v.id,duration,rest) end
  if remainder then return full*standard+remainder end
end
local function netResale(v,n)
  local options=ForeverMarketTools and ForeverMarketTools.postOptions and ForeverMarketTools.postOptions(v.itemID or v.id) or {}
  local stack=math.min(v.stack,options.size or v.stack)
  local full=math.floor(n/stack)
  local remainder=n%stack
  return full*ForeverMarketSaleNet(v.exit*stack)+ForeverMarketSaleNet(v.exit*remainder)
end
local function demand(v)
  local m=ForeverMarketTools
  if v.model or not m or not m.saleCount or not m.marketOutcomes then return math.huge end
  local name=C_Item.GetItemNameByID(v.itemID or v.id)
  local observed=name and m.marketOutcomes(name)
  local sold=observed and observed.paidWeek or 0
  local held=onHand()[v.id] or 0
  local probe=math.min(v.stack,5)
  local limit=sold>0 and sold or probe
  local repeatSales=observed and (observed.receiptsWeek or 0)>=2 and observed.returns==0 and (observed.linked or 0)>=2 and observed.hours/observed.linked<=24
  if repeatSales and sold>0 then limit=limit+math.min(probe,math.ceil(sold*.25)) end
  if observed and observed.returns>0 and sold==0 then limit=1 end
  if observed and (observed.linked or 0)>0 and observed.hours/observed.linked>72 then limit=math.max(1,math.ceil(limit/2)) end
  local evidence=sold>0 and (sold..' paid units in 7 days') or observed and observed.returns>0 and 'Recent expiry without a paid sale' or 'Trial quantity / no recent paid sales'
  if repeatSales then evidence=evidence..' / trial increased after repeat sales' end
  return math.max(0,limit-held),evidence..' / '..held..' already owned or ordered'
end
local function repostOK(v,n,dep,force)
  local m=ForeverMarketTools
  if v.model or not m or not m.stockPostRestriction then return true end
  local id=v.itemID or v.id
  local pin=ForeverMarketPinnedExit and ForeverMarketPinnedExit(id,v.variant)
  if pin and pin<v.exit then return false,'Saved Sell quote below expected exit' end
  local restriction=m.stockPostRestriction(id,n,v.exit,force,n)
  if restriction then return false,restriction end
  local h=fund().held[v.variant or id] or fund().held[id] or {}
  local floor=ForeverMarketFundMinimum((h.cost or 0)+n*v.low,(h.n or 0)+n,dep,n)
  if m.rule(id)=='Margin' then floor=math.ceil(floor*(10000+ForeverMarketMarginBP())/10000) end
  if v.exit<math.max(floor,ForeverMarketInvestmentTarget(id) or 0) then return false,'Below fund resale minimum' end
  return true
end
local function allocation(v,cash)
  local cap,reason=demand(v);v.demandReason=reason
  local n=math.min(v.qty,room(v.id,v.stack),math.floor(cash/v.low),cap)
  local lo,hi=0,n
  local blocked
  while lo<hi do
    local mid=math.ceil((lo+hi)/2)
    local dep=resaleDeposit(v,mid)
    local ok,why=repostOK(v,mid,dep,false)
    if dep and mid*v.low+dep<=cash and ok then lo=mid else hi=mid-1;blocked=why or blocked end
  end
  if lo==0 or v.clearTier and lo<v.qty then
    if report and (blocked or cap<v.qty) then
      report.repostExample={id=v.itemID or v.id,reason=blocked or ('Demand allows '..cap..' / cheap tier '..v.qty)}
    end
    return 0,0
  end
  return lo,resaleDeposit(v,lo)
end
local function investmentBudget(cash)
  local f=fund();local committed=0
  for _,h in pairs(f.held) do if (h.invested or 0)>0 and h.n>0 then committed=committed+math.ceil(h.cost*h.invested/h.n) end end
  for _,lot in ipairs(f.lots) do if lot.target and lot.n>0 then committed=committed+math.ceil((lot.basis or 0)*math.min(lot.invested or 0,lot.n)/lot.n) end end
  return math.max(0,math.floor((cash+committed)*.20)-committed)
end
local function plan()
  local choices={}
  for _,v in pairs(verified) do if GetTime()-v.at<60 then choices[#choices+1]=v end end
  local scores,weights={},{}
  for _,v in ipairs(choices) do
    local weight=1
    if ForeverMarketTools and ForeverMarketTools.salesWeight then
      local name=C_Item.GetItemNameByID(v.itemID or v.id)
      if name then weight=ForeverMarketTools.salesWeight(name) end
    end
    weights[v]=weight; scores[v]=weight*v.edge/v.low
  end
  table.sort(choices,function(a,b)if scores[a]==scores[b] then return a.id<b.id end return scores[a]>scores[b] end)
  local start=scanCash()
  if investScan then start=investmentBudget(start) end
  local full={}
  for _,v in ipairs(choices) do
    local n,dep=allocation(v,start)
    full[v]={n=n,dep=dep,cost=n*v.low+dep}
  end
  local function fill(order,first)
    local list,cash,gain={},start,0
    local function take(v)
      local size=full[v]
      local n,dep=size.n,size.dep
      if cash<size.cost then
        if v.clearTier or v.auctionID then return end
        n,dep=allocation(v,cash)
      end
      local net=netResale(v,n)
      local expectedNet=net-ForeverMarketDepositLoss(n)
      local profit=expectedNet-n*v.low
      local group=ForeverMarketTools and ForeverMarketTools.group and ForeverMarketTools.group(v.itemID or v.id)
      local allowed=not group or not group.cap or group.cap==0 or v.low<=group.cap
      if group and ForeverMarketTools.groupPurchaseAllowed then allowed=ForeverMarketTools.groupPurchaseAllowed(v.itemID or v.id,group,v.low) end
      if n>0 and allowed and profit>0 and profit*10000>=n*v.low*math.max(ForeverMarketMarginBP(),group and group.margin*100 or 0) and expectedNet>n*v.vendor and v.exit>=ForeverMarketFundHoldPrice(v.variant or v.id,n,dep) then
        list[#list+1]={v=v,n=n,dep=dep};cash=cash-n*v.low-dep;gain=gain+profit*weights[v]
      end
    end
    if first then take(first) end
    for _,v in ipairs(order) do if v~=first and cash>0 then take(v) end end
    return list,gain
  end
  local best,gain=fill(choices)
  for _,v in ipairs(choices) do local single,g=fill({v});if g>gain then best,gain=single,g end end
  -- Explore alternative baskets while bounding work in the live AH frame.
  if #choices>1 then
    for i=2,math.min(12,#choices) do
      local basket,g=fill(choices,choices[i])
      if g>gain then best,gain=basket,g end
    end
  end
  return best
end
local function retire(id,reason)
  verified[id]=nil
  if remembered[id] then remembered[id].reason=reason end
end
local function prepare(row)
  if fund().pending or not row.pick or row.pick.inactive or verified[row.pick.v.id]~=row.pick.v or GetTime()-row.pick.v.at>=60 then return end
  local p=row.pick
  if p.v.auctionID then return end
  if quote and quote.id==p.v.id and quote.n==p.n and GetTime()-quote.at<8 then return end
  clearQuote()
  quote={id=p.v.id,n=p.n,max=p.v.low*p.n,at=GetTime(),dep=p.dep}
  api.StartCommoditiesPurchase(quote.id,quote.n)
end
local function buy(row)
  if benchmarkCash then return end
  if not row.pick or row.pick.inactive or fund().pending or verified[row.pick.v.id]~=row.pick.v or GetTime()-row.pick.v.at>=60 then return end
  local p=row.pick
  stock=nil
  if p.n>room(p.v.id,p.v.stack) then clearQuote();note('Stock limit reached.');return end
  if p.n>demand(p.v) or not repostOK(p.v,p.n,p.dep,true) then clearQuote();note('Demand or posting rules changed. Review the shopping list.');return end
  local m=ForeverMarketTools
  local group=m and m.group and m.group(p.v.itemID or p.v.id)
  local cost=p.n*p.v.low
  local after=netResale(p.v,p.n)-ForeverMarketDepositLoss(p.n)
  if group and ((group.cap or 0)>0 and p.v.low>group.cap or m.groupPurchaseAllowed and not m.groupPurchaseAllowed(p.v.itemID or p.v.id,group,p.v.low,true)) or after<=p.n*p.v.vendor or (after-cost)*10000<cost*math.max(ForeverMarketMarginBP(),group and group.margin*100 or 0) then
    clearQuote();note('Resale margin changed. Review the shopping list.');return
  end
  local pressed=row.pressed
  row.pressed=nil
  if pressed and (pressed.id~=p.v.id or pressed.n~=p.n or pressed.total~=row.buyTotal or pressed.auctionID~=p.v.auctionID) then
    note('The offer changed. Review the row and click Buy again.');return
  end
  if p.v.model and p.n*p.v.low+p.dep>investmentBudget(available()) then clearQuote();note("Investment budget changed. Review the updated quantity.");return end
  if p.v.auctionID then
    local v=p.v
    if not itemConfirmation or p.n~=1 or p.dep+v.low>available() then return end
    local current
    for i=1,api.GetNumItemSearchResults(v.searchKey) do
      local r=api.GetItemSearchResultInfo(v.searchKey,i)
      if r and r.auctionID==v.auctionID then current=r;break end
    end
    if not current or current.containsOwnerItem or current.containsAccountItem or current.buyoutAmount~=v.low or
       ForeverMarketVariant(current.itemKey,current.itemLink)~=v.variant then
      retire(v.id,'Offer changed');note('Auction changed. Check the next live offer.');return
    end
    clearQuote()
    local f=fund();f.itemOrders=f.itemOrders or {}
    if f.itemOrders[v.auctionID] then return end
    f.itemOrders[v.auctionID]={run=report and report.run,id=v.itemID,holding=v.variant,lead=v.id,name=v.name,n=1,forecast=netResale(v,1)-ForeverMarketDepositLoss(1)-v.low,total=v.low,dep=p.dep,auctionID=v.auctionID,at=time()}
    local ok,err=pcall(api.PlaceBid,v.auctionID,v.low)
    if not ok then f.itemOrders[v.auctionID]=nil;note(tostring(err))
    else retire(v.id,'Awaiting confirmation') end
    return
  end
  if not quote or quote.id~=p.v.id or quote.n~=p.n or GetTime()-quote.at>=8 or not quote.total then
    prepare(row);note('Checking the live offer. Click Buy when ready.');return
  end
  if quote.total>p.v.low*p.n or quote.total+p.dep>available() then
    clearQuote();retire(p.v.id,'Offer changed');note('Offer changed. Shopping list updated.');return
  end
  if row.buyTotal~=quote.total then note('Review the updated buy total and click again.');return end
  fund().pending={run=report and report.run,forecast=netResale(p.v,p.n)-ForeverMarketDepositLoss(p.n)-quote.total,target=p.v.model and p.v.exit,id=quote.id,n=quote.n,total=quote.total,dep=p.dep,at=time()}
  quote=nil
  local ok,err=pcall(api.ConfirmCommoditiesPurchase,p.v.id,p.n)
  if not ok then fund().pending=nil;note(tostring(err)) end
end
local function label(parent,x,y)
  local t=parent:CreateFontString(nil,'OVERLAY','GameFontHighlight');t:SetPoint('TOPLEFT',x,y);return t
end
local function updateReport(state)
  if not report or report.finished then return end
  report.state=state
  report.elapsed=math.floor(GetTime()-startedAt)
  report.candidates=totalLeads;report.checked=checked;report.screened=screened
  report.unanswered=unanswered;report.detailRequests=requests;report.junk=junkCount
  report.batch=math.min(categoryIndex-1,#categories);report.batches=#categories
  report.item=search and search.id or nil;report.firstBuy=firstResult
  if state=='complete' and watchScan then
    local db=ForeverMarketDB;db.watchRuns=db.watchRuns or {}
    table.insert(db.watchRuns,{at=time(),scope=GetRealmName(),mode=watchScan=='market' and 'Radar' or watchScan=='bench' and 'Benchmark' or 'Watch',size=report.benchSize,ids=report.benchIDs,hits=report.benchHits,elapsed=report.elapsed,first=firstResult,checked=checked,unanswered=unanswered,requests=requests})
    if #db.watchRuns>20 then table.remove(db.watchRuns,1) end
  end
  if state=='complete' or state=='stopped' or state=='closed' then
    report.finished=true
    local f=fund();f.sessions=f.sessions or {}
    if report.run then
      local hits=0;for _ in pairs(report.hitIDs or {}) do hits=hits+1 end
      f.sessions[report.run]={at=report.at,cash=report.cash,target=report.target,mode=report.mode,state=state,ids=report.benchIDs,found=report.benchHits,
        checked=checked,missed=unanswered,hits=hits,elapsed=report.elapsed,first=firstResult}
      f.sessions[report.run-500]=nil
    end
  end
end
local function render()
  if not panel or not panel:IsVisible() then return end
  local list=plan()
  local active={}
  for _,p in ipairs(list) do
    local id=p.v.id
    active[id]=true
    if report then report.hitIDs=report.hitIDs or {};report.hitIDs[id]=true end
    if watchScan=='bench' then report.benchHits=report.benchHits or {};report.benchHits[id]=true end
    local alerted=watchAlerts[id]
    if watchScan and (not alerted or p.v.low<alerted.price or p.n>alerted.n) then
      watchAlerts[id]={price=p.v.low,n=p.n}
      print('Forever Market deal: '..(C_Item.GetItemNameByID(p.v.itemID or id) or tostring(id))..' x '..p.n..' at '..ForeverMarketCoins(p.v.low)..' each.')
    end
    for j=#(report and report.misses or {}),1,-1 do if report.misses[j].id==id then table.remove(report.misses,j) end end
    if not remembered[id] then displayOrder[#displayOrder+1]=id end
    remembered[id]={pick=p}
  end
  local buyCount=#list
  if ForeverMarketTools then ForeverMarketTools.visibleDeals={at=GetTime(),scope=GetRealmName(),count=buyCount} end
  if buyCount>0 and not firstResult and startedAt then firstResult=GetTime()-startedAt end
  updateReport(completed and "complete" or running and (search and "checking" or browse and "browsing" or scanWait or "scanning") or "stopped")
  for _,id in ipairs(displayOrder) do
    if not active[id] then
      local saved=remembered[id]
      local v=verified[id]
      local reason=saved.reason or (v and GetTime()-v.at<60 and 'Outside current plan' or 'Rechecking price')
      list[#list+1]={v=saved.pick.v,n=saved.pick.n,inactive=reason}
    end
  end
  balance:SetText(benchmarkCash and ('Test fund '..ForeverMarketCoins(benchmarkCash)) or ('Fund cash  '..ForeverMarketCoins(fund().cash)))
  if #fundButtons>0 and (not fundButtons.updated or GetTime()-fundButtons.updated>=.5) then
    fundButtons.updated=GetTime()
    local sums=ForeverMarketTools.fundSummary()
    for _,b in ipairs(fundButtons) do b:SetText(b.caption..' '..ForeverMarketCoins(sums[b.section])) end
  end
  content:SetHeight(math.max(1,#list*26))
  for i=1,math.max(#rows,#list) do
    local row=rows[i]
    if not row then
      local y=-(i-1)*26-6
      row={name=label(content,8,y),qty=label(content,221,y),cost=label(content,269,y),profit=label(content,434,y)}
      ForeverMarketRowArt(content,y+5,672,i)
      row.qty:SetWidth(42);row.cost:SetWidth(156);row.profit:SetWidth(154)
      for _,t in ipairs({row.qty,row.cost,row.profit}) do t:SetJustifyH('LEFT');t:SetWordWrap(false) end
      row.name:SetWidth(205);row.name:SetJustifyH('LEFT');row.name:SetWordWrap(false)
      row.hover=ForeverMarketHover(content,-(i-1)*26,590,row)
      row.btn=CreateFrame('Button',nil,content,'UIPanelButtonTemplate');row.btn:SetSize(72,21);row.btn:SetPoint('TOPLEFT',600,-(i-1)*26)
      row.btn:SetScript('OnMouseDown',function()
        row.pressed=row.pick and {id=row.pick.v.id,n=row.pick.n,total=row.buyTotal,auctionID=row.pick.v.auctionID}
      end)
      row.btn:SetText('Buy');row.btn:SetScript('OnEnter',function()if not benchmarkCash then prepare(row) end end);row.btn:SetScript('OnClick',function()buy(row)end);rows[i]=row
    end
    row.pick=list[i];row.itemRef=row.pick and (row.pick.v.link or "item:"..row.pick.v.id);row.hover:SetShown(row.pick~=nil);row.btn:SetShown(row.pick~=nil);row.btn:SetEnabled(not benchmarkCash and row.pick~=nil and not row.pick.inactive and not fund().pending)
    row.name:SetText(row.pick and ForeverMarketRowIcon(row.pick.v.itemID or row.pick.v.id,row.pick.v.link or C_Item.GetItemNameByID(row.pick.v.id) or 'Item '..row.pick.v.id) or '')
    local p=row.pick
    local live=p and quote and quote.id==p.v.id and quote.n==p.n and GetTime()-quote.at<8 and quote.total
    row.buyTotal=p and not p.inactive and (live or p.n*p.v.low)
    local itemName=p and C_Item.GetItemNameByID(p.v.itemID or p.v.id)
    row.marketId=p and (p.v.itemID or p.v.id)
    row.priceReason=p and not p.inactive and ("Buy "..p.n.." x "..ForeverMarketCoins(p.v.low).." / exit per item "..ForeverMarketCoins(p.v.exit).." / deposit reserved "..ForeverMarketCoins(p.dep or 0)) or nil

    if row.priceReason and p.v.starter then row.priceReason='Starter estimate '..date('%b %d',ForeverMarketStarter.at)..' / live offer checked. '..row.priceReason end
    if row.priceReason and itemName and ForeverMarketTools and ForeverMarketTools.marketOutcomes then
      local outcomes=ForeverMarketTools.marketOutcomes(itemName)
      if outcomes then
        row.priceReason=row.priceReason..(' / 14 days: %d sale notices, %d expired'):format(outcomes.sales,outcomes.returns)
        if outcomes.linked>0 then row.priceReason=row.priceReason..(' / mean time to sale %.1fh'):format(outcomes.hours/outcomes.linked) end
      end
    end
    if p and p.v.model and not p.inactive then
      local paper=ForeverMarketPaperDip and ForeverMarketPaperDip(p.v.id,p.v.exit)
      row.priceReason=("Historical replay: %d/%d dips recovered. "):format(p.v.model.wins,p.v.model.trials)..(paper or '')..row.priceReason
    end
    row.saleText=itemName and ForeverMarketTools and ForeverMarketTools.saleLabel and ForeverMarketTools.saleLabel(itemName)
    row.qty:SetText(p and p.n or '');if p and row.priceReason then row.priceReason='Quantity '..p.n..': '..(p.v.demandReason or 'Sized to available supply and cash')..'. '..row.priceReason end
    row.cost:SetText(row.buyTotal and ForeverMarketCoins(row.buyTotal) or '')
    local resale=row.buyTotal and netResale(p.v,p.n)
    row.profit:SetText(p and (p.inactive or ForeverMarketCoins(resale-row.buyTotal-ForeverMarketDepositLoss(p.n))) or '')
    local shade=p and p.inactive and .55 or 1
    for _,field in ipairs({row.name,row.qty,row.cost,row.profit}) do field:SetTextColor(shade,shade,shade) end
  end
  if GetTime()<fundMessageUntil then return end
  detail:SetText('')
  if not running and not completed then
    note(pausedMarket and 'Paused. Resume to continue checking remaining offers.' or 'Set your fund and minimum profit, then choose Find flips.')
    return
  end
  if fund().pending then note('Waiting for purchase confirmation.')
  elseif quote then return
  elseif scanCash()==0 then note('No trading cash available for a purchase.')
  elseif missingScan then note('Building local history.');detail:SetText('Browse > Below vendor works after a Market Scan.')
  elseif investScan and totalLeads==0 then note('Invest: no qualifying recovery patterns');detail:SetText(('Best coverage: %s, %d days / 14 minimum; repeated rebounds required.'):format(report.bestItem and C_Item.GetItemNameByID(report.bestItem) or 'none',report.bestDays or 0))
  elseif totalLeads==0 then detail:SetText(("Insufficient history: %d item records"):format(report and report.thinHistory or 0));note(('No eligible candidates Â· %d junk filtered Â· %d uncached'):format(junkCount,unknownCount))
  else
    local progress=('%g%% | %d/%d resolved | %d unanswered'):format(ForeverMarketMarginBP()/100,math.min(totalLeads,screened+checked+unanswered),totalLeads,unanswered)
    if #categories>0 then
      progress=progress..(' | %d screened out | batch %d/%d'):format(screened,math.min(categoryIndex,#categories+1)-1,#categories)
      if browseFallback>0 then progress=progress..(' | %d batch failures'):format(browseFallback) end
    end
    if search then detail:SetText('Looking up '..((search.id>0 and C_Item.GetItemNameByID(search.id)) or ('item '..search.id)))
    elseif browse then detail:SetText('Browsing category')
    else detail:SetText(scanWait or '') end
    if snapshotMode then
      progress=('Bulk Â· %d/%d resolved Â· %d unanswered'):format(math.min(totalLeads,screened+checked+unanswered),totalLeads,unanswered)
      if firstResult then progress=progress..(' Â· first buy %.1fs'):format(firstResult) end
    end
    progress=progress..(' | %d junk Â· %d stocked'):format(junkCount,report and report.stockSkipped or 0)
    if unknownCount>0 then progress=progress..(' | %d uncached'):format(unknownCount) end
    if buyCount>0 then note((investScan and 'Invest / ' or '')..progress);if completed then detail:SetText(('Complete Â· %d shopping list items'):format(buyCount)) end
    elseif browse or categoryIndex<=#categories or search or cursor<=#leads then note(progress)
    else note(completed and ('Complete / no qualifying buys / '..unanswered..' unanswered') or progress);local reason,most='No eligible live offers',0
      for _,pair in ipairs({{'Too little history',report.thinHistory},{'Over budget',report.overBudget},{'Margin too small',report.weakSpread},{'No supply',report.noSupply},{'Already stocked',report.stockSkipped}}) do
        if (pair[2] or 0)>most then reason,most=pair[1],pair[2] end
      end
      local ex=report.repostExample or report.misses and report.misses[1]
      detail:SetText(reason..' ('..most..')'..(ex and (' / '..(C_Item.GetItemNameByID(ex.id) or ex.id)..': '..ex.reason) or '')) end
  end
end
local function inspect(id)
  if not search or search.id~=id then return end
  local count=api.GetNumCommoditySearchResults(id)
  if api.HasFullCommoditySearchResults and not api.HasFullCommoditySearchResults(id) then
    if count>0 and api.RequestMoreCommoditySearchResults and count>(search.pageCount or 0) then
      search.pageCount=count
      lastSearch=GetTime()
      api.RequestMoreCommoditySearchResults(id)
    end
    return
  end
  local v=search
  local levels,owned={},{}
  for i=1,count do
    local r=api.GetCommoditySearchResultInfo(id,i)
    if r and r.unitPrice and r.quantity>0 then
      levels[r.unitPrice]=(levels[r.unitPrice] or 0)+r.quantity
      if r.containsOwnerItem then owned[r.unitPrice]=true end
    end
  end
  local d=ForeverMarketPriceDepth(levels)
  retire(id,d and 'Margin too low' or 'No live offer')
  if d and not owned[d.low] and (v.model and d.floorPrice<=v.model.entry or not v.model and not owned[d.nextPrice]) then
    local get=C_Item.GetItemInfo or GetItemInfo
    local stack,vendor
    if get then
      local _,_,_,_,_,_,_,size,_,_,value=get(id)
      stack,vendor=size,value
    end
    if type(vendor)~='number' or not stack or stack<1 then
      if not v.waitItem and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
      v.waitItem=true
      return
    end
    v.stack=stack;v.vendor=vendor
    v.exit=v.model and v.model.exit or math.min(ForeverMarketPostPrice(commodityResaleAsk(d)),math.floor(v.ref*.9)-2)
    if not v.model and ForeverMarketPinnedExit then v.exit=math.min(v.exit,ForeverMarketPinnedExit(id) or v.exit) end
    -- Fee rounding and deposit depend on stack quantity. Screen on the
    -- unrounded ceiling here; plan() checks actual stack proceeds in copper.
    v.edge=v.exit*ForeverMarketKeepBP()/10000-d.low
    local checkedQty=v.model and 1 or d.lowQty
    local deposit=resaleDeposit(v,checkedQty) or 0
    screenOffer(id,d.low*checkedQty,netResale(v,checkedQty)-ForeverMarketDepositLoss(checkedQty),scanCash(),deposit)
    if v.exit*ForeverMarketKeepBP()>=d.low*(10000+ForeverMarketMarginBP()) then
      v.low=d.low;v.qty=d.lowQty;v.clearTier=not v.model;v.at=GetTime();verified[id]=v
      if remembered[id] then remembered[id].reason=nil end
    end
  end
  if watchScan and not verified[id] then watchAlerts[id]=nil end
  retryPool[id]=nil
  if not search.recheck then checked=checked+1 end;search=nil;scanWake=true
  render()
end
local function inspectItems(key)
  local lead=search
  if not lead or not key or not lead.searchKey or key.itemID~=lead.searchKey.itemID or
     (key.battlePetSpeciesID or 0)~=(lead.searchKey.battlePetSpeciesID or 0) then return end
  local count=api.GetNumItemSearchResults(key)
  if api.HasFullItemSearchResults and not api.HasFullItemSearchResults(key) then
    if api.RequestMoreItemSearchResults and count>(lead.pageCount or 0) then
      lead.pageCount=count;lastSearch=GetTime();api.RequestMoreItemSearchResults(key)
    end
    return
  end
  if ForeverMarketTools and ForeverMarketTools.recordGearBook then ForeverMarketTools.recordGearBook(key,count) end
  local groups={}
  for i=1,count do
    local r=api.GetItemSearchResultInfo(key,i)
    local variant=r and r.itemKey and r.itemKey.itemID==key.itemID and ForeverMarketVariant(r.itemKey,r.itemLink)
    if variant and r.auctionID and (r.buyoutAmount or 0)>0 then
      local orders=fund().itemOrders
      -- A fresh server reply still listing this exact auction resolves a failed attempt.
      if orders and orders[r.auctionID] and time()-orders[r.auctionID].at>30 then orders[r.auctionID]=nil end
      local group=groups[variant] or {};groups[variant]=group
      group[#group+1]=r
    end
  end
  local best,waiting
  for variant,g in pairs(groups) do
    if #g>=2 then
      table.sort(g,function(a,b)return a.buyoutAmount<b.buyoutAmount end)
      local r=g[1]
      local exit=math.min(ForeverMarketPostPrice(g[2].buyoutAmount),math.floor(lead.ref*.9)-2)
      if ForeverMarketPinnedExit then exit=math.min(exit,ForeverMarketPinnedExit(key.itemID,variant) or exit) end
      local name,_,_,_,_,_,_,_,_,_,vendor=C_Item.GetItemInfo(r.itemLink)
      if not vendor and lead.id<0 then vendor=0 end
      if not vendor then waiting=true
      elseif not r.containsOwnerItem and not r.containsAccountItem and not (fund().itemOrders or {})[r.auctionID]
          and not g[2].containsOwnerItem and not g[2].containsAccountItem then
        -- Before delivery Blizzard cannot quote an inventory-item deposit.
        -- Reserve one full vendor value, with a one-silver minimum.
        local dep=math.max(100,vendor)
        local profit=ForeverMarketSaleNet(exit)-r.buyoutAmount-ForeverMarketDepositLoss(1)
        screenOffer(lead.id,r.buyoutAmount,r.buyoutAmount+profit,scanCash(),dep)
        if profit>0 and profit*10000>=r.buyoutAmount*ForeverMarketMarginBP() and
           r.buyoutAmount+dep<=scanCash() and ForeverMarketSaleNet(exit)-ForeverMarketDepositLoss(1)>vendor and
           exit>=ForeverMarketFundHoldPrice(variant,1,dep) and (not best or profit>best.edge) then
          best={id=lead.id,itemID=r.itemKey.itemID,ref=lead.ref,auctionID=r.auctionID,searchKey=key,
            link=r.itemLink,name=name or r.itemLink:match('%[(.-)%]'),variant=variant,dep=dep,exit=exit,low=r.buyoutAmount,
            stack=1,qty=1,vendor=vendor,at=GetTime(),edge=profit}
        end
      end
    end
  end
  if waiting and not best then lead.waitKey=key;return end
  retire(lead.id,'No qualifying buyout')
  if best and itemConfirmation then verified[lead.id]=best elseif watchScan then watchAlerts[lead.id]=nil end
  retryPool[lead.id]=nil
  if not search.recheck then checked=checked+1 end;search=nil;scanWake=true;render()
end
local recheckedLast=false
local function tick(refreshUI)
  if waitingSince then
    local data,state=ForeverMarketSnapshot()
    if not data and (state=='pending' or state=='throttled') and GetTime()-waitingSince<3 then
      updateReport(state);note('Receiving market snapshotÂ…');detail:SetText('');return
    end
    awaitingBulk=not data and state=='pending';nextBulkCheck=GetTime()+1
    waitingSince=nil;snapshotMode=data~=nil;report.source=data and "bulk" or "browse";report.snapshotStatus=state or (data and "ready" or "unavailable");candidates(false,data)
  end
  if awaitingBulk and not search and not browse and not quote and not fund().pending and GetTime()>=nextBulkCheck then
    nextBulkCheck=GetTime()+1
    local data=ForeverMarketReadySnapshot and ForeverMarketReadySnapshot()
    if data then
      awaitingBulk=false;snapshotMode=true;report.source='bulk';report.snapshotStatus='ready after browse'
      candidates(true,data)
    end
  end
  if pendingFilter then
    local f=pendingFilter
    if GetTime()<f.next then return end
    local unresolved={}
    for _,lead in ipairs(f.items) do
      local allow=buyEligible(lead)
      if allow then leads[#leads+1]=lead
      elseif allow==false then junkCount=junkCount+1
      else unresolved[#unresolved+1]=lead end
    end
    if #unresolved>0 and GetTime()-f.at<4 then
      f.items=unresolved;f.next=GetTime()+.5
      note('Checking item quality Â· '..#unresolved..' pending');detail:SetText('');return
    end
    unknownCount=#unresolved;pendingFilter=nil
    rankCandidates(f.snapshot,f.grouped,scanCash())
  end
  if not browse and not search and not quote and not fund().pending and (not recheckedLast or cursor>#leads) then
    for _,id in ipairs(displayOrder) do
      local v=verified[id]
      if v and not rechecked[id] and GetTime()-v.at>=60 then
        rechecked[id]=true
        retire(id,'Rechecking price')
        table.insert(leads,cursor,{id=id,ref=v.ref,model=v.model,recheck=true})
        break
      end
    end
  end
  if search and search.waitKey and refreshUI then inspectItems(search.waitKey) end
  if search and search.waitItem and refreshUI then inspect(search.id) end
  if search and GetTime()-lastSearch>8 then
    if search.retried then rememberFailure(search);retire(search.id,'No live response');if not search.recheck then unanswered=unanswered+1 end
    else search.retried=true;leads[#leads+1]=search end
    search=nil
  end
  scanWait=nil
  if not search and not quote and not fund().pending and scanCash()>0 and cursor>#leads then advanceCategory() end
  if not browse and not search and not quote and not fund().pending and scanCash()>0 and cursor<=#leads then
    if not api.IsThrottledMessageSystemReady() then
      scanWait='Waiting for the auction house'
      if refreshUI then render() end
      return
    end
    local lead=leads[cursor]
    cursor=cursor+1
    local key=lead.id<0 and api.MakeItemKey(82800,nil,nil,-lead.id) or api.MakeItemKey(lead.id)
    local info=api.GetItemKeyInfo and api.GetItemKeyInfo(key)
    if api.GetItemKeyInfo and not info then
      scanWait='Loading item '..lead.id
      if not lead.warmAt then lead.warmAt=GetTime() end
      if GetTime()-lead.warmAt<15 then leads[#leads+1]=lead else rememberFailure(lead);retire(lead.id,'Item data unavailable');unanswered=unanswered+1 end
    else
      recheckedLast=lead.recheck
      lead.pageCount=nil;lead.waitItem=nil
      search=lead;lastSearch=GetTime()
      lead.searchKey=key;lead.waitKey=nil
      local single=info and info.isCommodity==false
      local send=single and api.SendSellSearchQuery or api.SendSearchQuery
      requests=(requests or 0)+1
      send(key,{{sortOrder=single and 4 or 0,reverseSort=false}},true)
    end
  end
  if quote and GetTime()-quote.at>9 then clearQuote() end

  if not search and not quote and not fund().pending and (scanCash()==0 or not browse and categoryIndex>#categories and cursor>#leads) then
    running=false;completed=true
  end
  if refreshUI then render() end
end
local function create()
  if panel then return end
  if not AuctionHouseFrame then return end
  panel=CreateFrame('Frame',nil,AuctionHouseFrame);panel:SetPoint('TOPLEFT',20,-60);panel:SetPoint('BOTTOMRIGHT',-30,45);panel:Hide()
  balance=label(panel,4,-4);balance:SetWidth(160);balance:SetJustifyH('LEFT');balance:SetWordWrap(false)
  status=label(panel,4,-37);detail=label(panel,4,-57)
  for _,line in ipairs({status,detail}) do
    line:SetPoint('TOPRIGHT',panel,'TOPRIGHT',-8,line==status and -37 or -57)
    line:SetJustifyH('LEFT');line:SetWordWrap(false)
  end
  if ForeverMarketTools and ForeverMarketTools.fundSummary then
    for i,s in ipairs({{'Spendable','cash'},{'Stock cost','inventory'},{'Due est.','pending'},{'Realized','profit'}}) do
      local b=CreateFrame('Button',nil,panel)
      b:SetNormalFontObject('GameFontNormalSmall')
      b:SetHighlightFontObject('GameFontHighlightSmall')
      b:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight')
      b:SetSize(172,20);b:SetPoint('TOPLEFT',(i-1)*175,-82);b.caption=s[1];b.section=s[2]
      b:SetScript('OnClick',function()ForeverMarketTools.openFundSection(s[2])end)
      local hints={cash='Cash available for new purchases.',inventory='Purchase cost of stock still held.',pending='Estimated proceeds awaiting collection.',profit='Realized profit from matched fund sales.'}
      b:SetScript('OnEnter',function(self)
        GameTooltip:SetOwner(self,'ANCHOR_TOP');GameTooltip:AddLine(self:GetText());GameTooltip:AddLine(hints[self.section]..' Click for details.',1,1,1,true);GameTooltip:Show()
      end)
      b:SetScript('OnLeave',function()GameTooltip:Hide()end)
      fundButtons[i]=b
    end
  end
  ForeverMarketResults(panel,107,{{'Name',0},{'Qty',213},{'Buy total',261},{'Est. profit',426},{'Action',592}})
  local edit=CreateFrame('EditBox',nil,panel,'InputBoxTemplate');edit:SetSize(45,24);edit:SetPoint('TOPLEFT',178,0);edit:SetAutoFocus(false)
  local set=CreateFrame('Button',nil,panel,'UIPanelButtonTemplate');set:SetSize(92,24);set:SetPoint('TOPLEFT',230,0);set:SetText('Set fund (gold)')
  set:SetScript('OnClick',function()
    local gold=tonumber(edit:GetText());local f=fund()
    fundMessageUntil=GetTime()+8
    if f.pending then note('Wait for purchase confirmation before changing the fund.');return end
    if not gold or gold~=gold or gold<=0 or gold>10000000 then note('Enter a positive cash amount in gold.');return end
    local cash=math.floor(gold*10000+.5)
    if cash<1 then note('Enter at least one copper (0.0001 gold).');return end
    local reserved=0
    for _,h in pairs(f.held) do reserved=reserved+(h.reserve or 0) end
    if cash<reserved then note('Reserved for posting deposits: '..ForeverMarketCoins(reserved));return end
    f.seed=f.seed+(cash-f.cash)
    ForeverMarketChangeCash(f,cash-f.cash,'Fund adjustment')
    edit:SetText(cash/10000);edit:ClearFocus()
    clearQuote();render();note('Fund saved.')
  end)
  label(panel,332,-4):SetText('Min. profit %')
  local target=CreateFrame('EditBox',nil,panel,'InputBoxTemplate')
  target:SetSize(38,24);target:SetPoint('TOPLEFT',413,0);target:SetAutoFocus(false)
  local function start()
    if watchScan~="bench" then benchmarkCash=nil;benchmarkQueue=nil end
    local pct=tonumber(target:GetText())
    if not pct or pct~=pct or pct<0 or pct>1000 then
      fundMessageUntil=GetTime()+5;note('Enter a target between 0 and 1000%.');return
    end
    if fund().pending then fundMessageUntil=GetTime()+5;note('Waiting for purchase confirmation.');return end
    target:ClearFocus();ForeverMarketDB.buyTargetBP=math.floor(pct*100+.5)
    retryPool={}
    pausedMarket=nil;clearQuote();remembered,displayOrder={},{};running=true;completed=false;fundMessageUntil=0
    verified={};search=nil;browse=nil;quote=nil
    startedAt=GetTime();firstResult=nil;requests=0;snapshotMode=false
    stock=nil
    local f=fund();f.runSequence=(f.runSequence or 0)+1
    report={run=f.runSequence,at=time(),target=ForeverMarketMarginBP(),cash=scanCash(),source='browse',mode=watchScan or (investScan and 'Invest' or 'Buy')}
    ForeverMarketDB.lastBuyScan=report
    awaitingBulk=false
    waitingSince=not watchScan and ForeverMarketSnapshot and startedAt or nil
    if not waitingSince then candidates() end
    tick(true)
  end
  function ForeverMarketBenchmark(gold)
    if not panel:IsVisible() or running or fund().pending or quote then print('Forever Market: open Market Buy and stop any current scan before benchmarking.');return end
    benchmarkQueue=nil
    if gold=='all' then benchmarkQueue={5,50,target=tonumber(target:GetText())};gold=1 end
    if gold and gold~=1 and gold~=5 and gold~=50 then return end
    benchmarkCash=gold and gold*10000
    investScan=false;watchScan='bench';watchAlerts={};start()
  end
  local function control(text,x,fn)
    local b=CreateFrame('Button',nil,panel,'UIPanelButtonTemplate')
    b:SetSize(65,24);b:SetPoint('TOPLEFT',x,0);b:SetText(text);b:SetScript('OnClick',fn)
    return b
  end
  local startButton=control('Find flips',466,function()investScan=false;watchScan=false;start() end)
  local resume=control('Resume',0,function()
    if not pausedMarket and completed and next(retryPool) then
      if fund().pending or quote then return end
      leads={};for _,lead in pairs(retryPool) do
        lead.retried=nil;lead.warmAt=nil;lead.waitKey=nil;lead.waitItem=nil;lead.pageCount=nil
        leads[#leads+1]=lead
      end
      table.sort(leads,function(a,b)if (a.potential or 0)==(b.potential or 0) then return a.id<b.id end return (a.potential or 0)>(b.potential or 0) end)
      retryPool={};cursor=1;unanswered=0;completed=false;running=true;scanWake=true;report.finished=nil;return
    end
    if pausedMarket~=GetRealmName() then return end
    if tonumber(target:GetText())~=report.target/100 then
      fundMessageUntil=GetTime()+5;note('Target changed. Press Start for a new scan.');return
    end
    for _,v in pairs(verified) do
      table.insert(leads,cursor,{id=v.id,ref=v.ref,model=v.model,recheck=true})
    end
    verified={};stock=nil;pausedMarket=nil;running=true;report.finished=nil;report.cash=available()
    fundMessageUntil=0;scanWake=true;render()
  end)
  resume:ClearAllPoints();resume:SetPoint('TOPRIGHT',panel,'TOPRIGHT',-6,-54)
  detail:ClearAllPoints();detail:SetPoint('TOPLEFT',4,-57);detail:SetPoint('TOPRIGHT',panel,'TOPRIGHT',-80,-57)
  local stopButton=control('Stop',536,function()
    benchmarkQueue=nil
    pausedMarket=nil;watchScan=false;running=false;completed=false;search=nil;browse=nil;clearQuote();fundMessageUntil=0;render()
  end)
  local menu=CreateFrame('Frame',nil,panel,'BackdropTemplate')
  menu:SetSize(382,207);menu:SetPoint('TOPRIGHT',panel,'TOPRIGHT',-4,-26)
  menu:SetFrameLevel(panel:GetFrameLevel()+25);menu:EnableMouse(true)
  menu:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=12})
  menu:SetBackdropColor(.10,.08,.06,.99);menu:SetBackdropBorderColor(.67,.55,.34,1);menu:Hide()
  local more=control('Scan tools',610,function()if menu:IsShown() then menu:Hide() else menu:Show() end end)
  more:SetWidth(96)
  local function option(i,title,help,fn)
    local y=-10-(i-1)*32
    local b=CreateFrame('Button',nil,menu,'UIPanelButtonTemplate')
    b:SetPoint('TOPLEFT',9,y);b:SetSize(125,24);b:SetText(title)
    b:SetScript('OnClick',function()menu:Hide();fn()end)
    local t=label(menu,141,y-3);t:SetWidth(231);t:SetJustifyH('LEFT');t:SetText(help)
  end
  option(1,'Restart scan','Start this scan again with your current settings.',start)
  option(2,'Buy price dips','Find items with a history of price recovery.',function()investScan=true;watchScan=false;start()end)
  if ForeverMarketTools then
    option(3,'Watch favorites','Repeat deal checks on your favorite items.',function()
      investScan=false;watchScan=true;watchAgain=GetTime()+60;start()
    end)
    option(4,'Watch market','Repeat deal checks across the market.',function()
      investScan=false;watchScan='market';watchAlerts={};watchAgain=GetTime()+60;start()
    end)
    option(5,'Craft materials','Open the shopping list for your crafts.',ForeverMarketTools.openMaterials)
    option(6,'Scan report','Print the latest scan details in chat.',function()SlashCmdList.FOREVERMARKET('scanstatus')end)
  end
  scroll=CreateFrame('ScrollFrame','ForeverMarketBuyScroll',panel,'UIPanelScrollFrameTemplate');scroll:SetPoint('TOPLEFT',0,-135);scroll:SetPoint('BOTTOMRIGHT',-26,4)
  content=CreateFrame('Frame',nil,scroll);content:SetSize(678,1);scroll:SetScrollChild(content)
  panel:SetScript('OnShow',function()
    if pausedMarket~=GetRealmName() then pausedMarket=nil;remembered,displayOrder,verified={},{},{} end
    running=false;completed=false;fundMessageUntil=0;resume:SetShown(pausedMarket~=nil)
    edit:SetText(fund().cash/10000);target:SetText(ForeverMarketMarginBP()/100);render()
  end)
  panel:SetScript('OnHide',function()
    menu:Hide()
    benchmarkQueue=nil
    if running and not watchScan then
      pausedMarket=GetRealmName()
      if search then search.retried=nil;search.pageCount=nil;search.waitKey=nil;table.insert(leads,cursor,search) end
      if browse then categoryIndex=math.max(1,categoryIndex-1);browse.more=nil;browse.count=nil;browse.processed=nil end
    end
    watchScan=false;updateReport('closed');running=false;clearQuote();search=nil;browse=nil
  end)
  local scanElapsed,uiElapsed=0,0
  panel:SetScript('OnUpdate',function(_,dt)
    scanElapsed=scanElapsed+dt
    uiElapsed=uiElapsed+dt
    if scanElapsed<.1 and not scanWake then return end
    scanWake=false
    scanElapsed=0
    local refreshUI=uiElapsed>=.5
    if refreshUI then uiElapsed=0 end
    local retry=completed and next(retryPool)~=nil
    resume:SetText(retry and 'Retry' or 'Resume');resume:SetShown(pausedMarket~=nil or retry);startButton:SetEnabled(not running);stopButton:SetEnabled(running or watchScan)
    if benchmarkQueue and watchScan=='bench' and completed and report.finished and not running then
      local gold=table.remove(benchmarkQueue,1)
      if gold and benchmarkQueue.target==tonumber(target:GetText()) then benchmarkCash=gold*10000;start();return end
      benchmarkQueue=nil
    end
    if watchScan and watchScan~='bench' and completed and not running and not fund().pending and not quote and GetTime()>=watchAgain then watchAgain=GetTime()+60;start();return end
    if running then tick(refreshUI) elseif refreshUI then
      if quote and GetTime()-quote.at>9 then clearQuote() end
      render()
    end
  end)
  ForeverMarketTab('ForeverMarketBuy',panel,'Market Buy','Market Buy')
end
function ForeverMarketFundHolding(id)
  local h=fund().held[id];return h and h.n or 0
end
function ForeverMarketFundHoldPrice(id,qty,deposit)
  local h=fund().held[id]
  if (not h or h.n==0) and type(id)=="string" then h=fund().held[tonumber(id:match("^(%d+)/"))] end
  return h and ForeverMarketFundMinimum(h.cost or 0,h.n,deposit or 0,qty or 1) or 0
end
function ForeverMarketInvestmentTarget(id)
  local h=fund().held[id];return h and (h.invested or 0)>0 and h.target or nil
end
function ForeverMarketFundPost(id,n,price,deposit,itemID)
  local h=fund().held[id];posting=nil
  if (not h or h.n<=0) and itemID and fund().held[itemID] then id=itemID;h=fund().held[id] end
  if h and h.n>0 then posting={id=id,itemID=itemID or id,dep=deposit,n=n,tracked=math.min(n,h.n),price=price,at=time()} end
end
function ForeverMarketFundActivity(kind,e)
  stock=nil
  local f=fund();local p=e.auctionId and f.itemOrders and f.itemOrders[e.auctionId] or f.pending
  if kind=='purchase' and p and (not p.auctionID or p.auctionID==e.auctionId) and e.itemId==p.id and e.quantity==p.n and e.total and e.total<=p.total then
    if p.auctionID then f.itemOrders[p.auctionID]=nil else f.pending=nil end
    ForeverMarketChangeCash(f,-e.total,'Purchased',e.name)
    if p.craft and ForeverMarketTools then
      local a=ForeverMarketTools.account();a.transit[p.id]=(a.transit[p.id] or 0)+p.n
      a.materialCosts=a.materialCosts or {}
      local bought=a.materialCosts[p.id] or {n=0,cost=0};a.materialCosts[p.id]=bought
      bought.n=bought.n+p.n;bought.cost=bought.cost+e.total
      ForeverMarketTools.invalidate();return
    end
    if ForeverMarketTools and ForeverMarketTools.trackAcquisition then ForeverMarketTools.trackAcquisition(e.name,p.n) end
    local holding=p.holding or p.id
    local h=f.held[holding] or {n=0,reserve=0};f.held[holding]=h
    if p.target then h.target=math.max(h.target or 0,p.target);h.invested=(h.invested or 0)+p.n end
    if ForeverMarketTools and ForeverMarketTools.beginFlip then ForeverMarketTools.beginFlip(f,h,p,e) end
    h.itemID=p.id;h.lead=p.lead or p.id;h.inMail=(h.inMail or 0)+p.n
    h.cost=(h.cost or 0)+e.total;h.n=h.n+p.n;h.reserve=h.reserve+p.dep;retire(p.lead or p.id,'Purchased')
  elseif kind=='purchased_item_received' and e.itemId and e.quantity then
    local left=e.quantity
    for key,h in pairs(f.held) do
      if (h.itemID or key)==e.itemId and left>0 then
        local n=math.min(h.inMail or 0,left);h.inMail=(h.inMail or 0)-n;left=left-n
      end
    end
  elseif kind=='posted' and posting and time()-posting.at<30 and e.itemId==posting.itemID and e.quantity==posting.n and e.total==posting.n*posting.price then
    local t=posting;posting=nil;local h=f.held[t.id]
    local dep=t.dep or api.CalculateCommodityDeposit(t.itemID,1,t.n)
    if dep then
      local basis=math.floor((h.cost or 0)*t.tracked/h.n)
      local investmentQty=math.min(h.invested or 0,t.tracked);local investmentTarget=h.target
      h.invested=math.max(0,(h.invested or 0)-t.tracked);if h.invested==0 then h.target=nil end
      h.cost=math.ceil((h.cost or 0)*(h.n-t.tracked)/h.n);ForeverMarketChangeCash(f,-math.ceil(dep*t.tracked/t.n),'Posting deposit',e.name);h.reserve=math.floor(h.reserve*(h.n-t.tracked)/h.n);h.n=h.n-t.tracked
      f.lots[#f.lots+1]={name=e.name,n=t.tracked,invested=investmentQty,target=investmentTarget,posted=t.n,unpaid=t.n,basis=basis,holding=t.id,itemID=t.itemID,deposit=math.ceil(dep*t.tracked/t.n),price=t.price,auctionId=e.auctionId}
      if ForeverMarketTools and ForeverMarketTools.listFlip then ForeverMarketTools.listFlip(h,f.lots[#f.lots],h.n+t.tracked) end
    end
  elseif kind=='proceeds_collected' and e.invoiceType=='seller' and e.quantity and e.quantity>0 and e.amount and e.fee and e.deposit then
    local gross=e.amount+e.fee-e.deposit
    local remain=e.quantity
    local credit=0
    for _,lot in ipairs(f.lots) do
      if lot.sold and lot.name==e.name and lot.price*e.quantity==gross and remain>0 then
        local units=math.min(remain,lot.unpaid or lot.n)
        local n=math.min(units,lot.n)
        local offset=e.quantity-remain
        credit=credit+math.floor(e.amount*(offset+n)/e.quantity)-math.floor(e.amount*offset/e.quantity)
        if n>0 and lot.basis and ForeverMarketTools and ForeverMarketTools.settleLot then
          local basis=math.floor(lot.basis*n/lot.n)
          if ForeverMarketTools.payFlip then ForeverMarketTools.payFlip(lot,e,n,offset) end
          ForeverMarketTools.settleLot(lot,e,n,basis,math.floor(e.amount*(offset+n)/e.quantity)-math.floor(e.amount*offset/e.quantity),math.floor(lot.deposit*n/lot.n))
          lot.basis=lot.basis-basis
          lot.deposit=lot.deposit-math.floor(lot.deposit*n/lot.n)
        end
        lot.unpaid=(lot.unpaid or lot.n)-units
        lot.n=lot.n-n;remain=remain-units
      end
    end
    ForeverMarketChangeCash(f,credit,'Collected sale',e.name)
  elseif kind=='sale_notice' and e.auctionId then
    for _,lot in ipairs(f.lots) do
      if lot.auctionId==e.auctionId then lot.sold=true;return end
    end
    -- The mailbox omits auction IDs. Include outside-fund sales in matching
    -- so their units cannot be credited again to a later identical fund sale.
    local sale=ForeverMarketTools and ForeverMarketTools.account and ForeverMarketTools.account().sales[e.auctionId]
    if sale and sale.qty and sale.qty>0 and sale.amount and sale.name then
      f.lots[#f.lots+1]={name=sale.name,n=0,unpaid=sale.qty,price=sale.amount/sale.qty,auctionId=e.auctionId,sold=true}
    end
  end
end
function ForeverMarketFundCash() return fund().cash end
local f=CreateFrame('Frame')
for _,ev in ipairs({'AUCTION_HOUSE_SHOW','ITEM_SEARCH_RESULTS_UPDATED','COMMODITY_SEARCH_RESULTS_UPDATED','COMMODITY_PRICE_UPDATED','COMMODITY_PURCHASE_FAILED','COMMODITY_PRICE_UNAVAILABLE'}) do f:RegisterEvent(ev) end
for _,ev in ipairs({'AUCTION_HOUSE_BROWSE_RESULTS_UPDATED','AUCTION_HOUSE_BROWSE_RESULTS_ADDED','AUCTION_HOUSE_BROWSE_FAILURE'}) do pcall(f.RegisterEvent,f,ev) end
pcall(f.RegisterEvent,f,'BAG_UPDATE_DELAYED')
pcall(f.RegisterEvent,f,'OWNED_AUCTIONS_UPDATED')
pcall(f.RegisterEvent,f,'AUCTION_HOUSE_THROTTLED_SYSTEM_READY')
if api.RequestMoreCommoditySearchResults then pcall(f.RegisterEvent,f,'COMMODITY_SEARCH_RESULTS_ADDED') end
itemConfirmation=pcall(f.RegisterEvent,f,'AUCTION_HOUSE_PURCHASE_COMPLETED')
if api.RequestMoreItemSearchResults then pcall(f.RegisterEvent,f,'ITEM_SEARCH_RESULTS_ADDED') end
f:SetScript('OnEvent',function(_,ev,id,total)
  if ev=='BAG_UPDATE_DELAYED' or ev=='OWNED_AUCTIONS_UPDATED' then stock=nil
  elseif ev=='AUCTION_HOUSE_SHOW' then stock=nil;create()
  elseif ev=='AUCTION_HOUSE_BROWSE_RESULTS_UPDATED' or ev=='AUCTION_HOUSE_BROWSE_RESULTS_ADDED' then
    if panel and panel:IsVisible() then browseResults(ev=='AUCTION_HOUSE_BROWSE_RESULTS_ADDED',id) end
  elseif ev=='AUCTION_HOUSE_BROWSE_FAILURE' and browse then finishCategory(true)
  elseif ev=='AUCTION_HOUSE_THROTTLED_SYSTEM_READY' then
    if panel and panel:IsVisible() and not search then scanWake=true end
  elseif ev=='AUCTION_HOUSE_PURCHASE_COMPLETED' then
    local p=(fund().itemOrders or {})[id]
    if p then ForeverMarketItemBought(p) end
  elseif ev=='COMMODITY_PURCHASE_FAILED' then
    if fund().pending and not fund().pending.auctionID then fund().pending=nil end
    quote=nil
  elseif ev=='COMMODITY_PRICE_UNAVAILABLE' then if quote then retire(quote.id,'Offer unavailable') end;quote=nil;render()
  elseif ev=='COMMODITY_PRICE_UPDATED' and quote then
    if GetTime()-quote.at<8 and total and total>0 and total<=quote.max then quote.total=total;render();note('Ready to buy.')
    else retire(quote.id,'Offer changed');clearQuote();render();note('Offer changed.') end
  elseif (ev=='ITEM_SEARCH_RESULTS_UPDATED' or ev=='ITEM_SEARCH_RESULTS_ADDED') and panel and panel:IsVisible() then inspectItems(id)
  elseif (ev=='COMMODITY_SEARCH_RESULTS_UPDATED' or ev=='COMMODITY_SEARCH_RESULTS_ADDED') and panel and panel:IsVisible() then inspect(id) end
end)
