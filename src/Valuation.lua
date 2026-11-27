local GetRealmName=ForeverMarketVenueRealm or function() return _G.GetRealmName and _G.GetRealmName() or '' end
-- Shared market values. All money is integer copper.
ForeverMarketTools={}
local M=ForeverMarketTools
function M.settings()
  ForeverMarketDB=ForeverMarketDB or {}
  if not ForeverMarketDB.pricing then
    local prior=ForeverMarketRisk or {}
    ForeverMarketDB.pricing={cutBP=prior.cutBP or 500,lostDepositPerUnit=prior.lostDepositPerUnit or 0}
    ForeverMarketDB.buyTargetBP=ForeverMarketDB.buyTargetBP or prior.marginBP or 2000
  end
  return ForeverMarketDB.pricing
end
function M.account()
  ForeverMarketDB=ForeverMarketDB or {}
  local all=ForeverMarketDB.characters or {};ForeverMarketDB.characters=all
  local key=UnitGUID('player')
  if not all[key] then all[key]={recipes={},build={},transit={},sales={},notice={},mail={},collected={}} end
  return all[key]
end
function M.restoreCollected()
  local a=M.account()
  if a.receiptsRebuilt then return end
  local name=UnitName('player')
  local source=ForeverMarketActivity or ForeverMarketDB.__activity
  if not source or not source.events then return end
  local days,queue,confirmed={}, {}, {}
  local before,last
  for _,e in ipairs(source.events) do
    if e.character==name and e.region==GetCurrentRegion() and e.faction==UnitFactionGroup('player')
      and ((ForeverMarketEventRealm and ForeverMarketEventRealm(e) or e.realm)==GetRealmName() or (ForeverMarketEventRealm and ForeverMarketEventRealm(e) or e.realm)==GetRealmName()..' [Neutral AH]') then
      local day=date('%Y-%m-%d',e.at)
      if e.kind=='sale_notice' and e.auctionId and a.notice[e.auctionId] then a.notice[e.auctionId].at=e.at end
      if not last or e.at-last>10 or e.kind=='session' then queue={};before=nil;confirmed={} end
      last=e.at
      if e.kind=='collection_requested' and e.invoiceType=='seller' and (e.amount or 0)>0 then
        if before~=e.gold then before=e.gold;queue={};confirmed={} end
        queue[#queue+1]=e
      elseif e.kind=='proceeds_collected' and e.invoiceType=='seller' and e.amount then
        days[day]=(days[day] or 0)+e.amount
        local k=(e.name or '')..'/'..e.amount
        confirmed[k]=(confirmed[k] or 0)+1
      elseif e.kind=='wallet' and before and e.gold~=before then
        local sum=0;local matched
        for i,q in ipairs(queue) do
          if e.at-q.at>10 then break end
          sum=sum+q.amount
          if sum==e.gold-before then matched=i;break end
          if sum>e.gold-before then break end
        end
        if matched then
          for i=1,matched do
            local q=table.remove(queue,1);local k=(q.name or '')..'/'..q.amount
            if (confirmed[k] or 0)>0 then confirmed[k]=confirmed[k]-1
            else days[day]=(days[day] or 0)+q.amount end
          end
        else queue={} end
        before=e.gold;confirmed={}
      end
    end
  end
  for day,n in pairs(days) do a.collected[day]=math.max(a.collected[day] or 0,n) end
  a.receiptsRebuilt=true;a.collectedInitialized=true
end
function M.scope() return GetRealmName()..'|'..UnitFactionGroup('player') end
function M.history(key)
  local r=ForeverMarketHistory()[key]
  if not r then return end
  local sum,n,last=0,0,0
  local today=math.floor(time()/86400)
  for day,value in pairs(r.l or {}) do
    local d=tonumber(day)
    if d and d<=today and d>today-15 then sum=sum+value;n=n+1;last=math.max(last,d*86400) end
  end
  if n>0 then return math.floor(sum/n+.5),last end
end
function M.quotes()
  local all=ForeverMarketDB.sellQuotes or {};ForeverMarketDB.sellQuotes=all
  all[M.scope()]=all[M.scope()] or {}
  return all[M.scope()]
end
function M.prices(id,key,variant)
  if ForeverMarketHasScan and not ForeverMarketHasScan() then return end
  local hist=ForeverMarketHistory()[key or tostring(id)]
  local q=M.quotes()[variant or id]
  local depths=ForeverMarketDB.__depth
  local d=not variant and depths and depths[M.scope()] and depths[M.scope()][id]
  if d and (not q or d.at>q.at) then q={price=d.floorPrice,at=d.at} end
  local snap=ForeverMarketDB.bulkSnapshot
  if not variant and snap and snap.scope==table.concat({GetCurrentRegion(),GetRealmID and GetRealmID() or '',GetRealmName(),UnitFactionGroup('player')},'|') then
    local book=snap.books[id]
    if book and (not q or snap.observed>q.at) then q={price=book.floorPrice,at=snap.observed} end
  end
  if hist and hist.bulk and not variant and (not q or hist.bulk.at>q.at) then q=hist.bulk end
  if q and q.price and time()>=q.at and time()-q.at<=86400 then
    local match=ForeverMarketDB.matchBulk or M.rule and M.rule(id)=='Margin'
    return match and q.price or ForeverMarketPostPrice(q.price),q.at,(variant and 'Exact variant / ' or '')..(time()-q.at<60 and 'Live check' or 'Last scan'),q.price
  end
  local avg,at=M.history(key or tostring(id))
  return avg,at,variant and 'Base item / historical estimate' or 'Historical estimate'
end
function M.starterReference(id)
  if ForeverMarketHasScan and not ForeverMarketHasScan() then return end
    local s=ForeverMarketStarter
    local realm=GetRealmID and GetRealmID()
    if not realm or realm==0 then realm=tonumber((UnitGUID('player') or ''):match('^Player%-(%d+)%-')) end
    local reference=s and s.reference and s.reference[id]
    local stamped=s and (reference and s.referenceAt or s.at)
    if s and (reference or s.items[id]) and realm==s.realmID and GetCurrentRegion()==s.region and UnitFactionGroup('player')==s.faction and not GetRealmName():find('Neutral AH',1,true) and time()>=stamped and time()-stamped<=21*86400 then
      return reference or s.items[id],stamped,'Starter reference / historical estimate'
    end
end
function M.bagCount(id)
  local count=C_Item and C_Item.GetItemCount or GetItemCount
  return count and count(id,false,false,false) or 0
end
function M.cost(id,n,tiers)
  if n<=0 then return 0 end
  local depth=ForeverMarketDB.__depth
  local book=depth and depth[M.scope()] and depth[M.scope()][id]
  local snap=ForeverMarketReadySnapshot and ForeverMarketReadySnapshot()
  local snapBook=snap and snap.books[id]
  if snapBook and (not book or GetTime()-snap.at<time()-book.at) then book=snapBook
  elseif book and (time()-book.at>900 or time()<book.at) then book=nil end
  if book then
    local levels=book.levels or {{book.low,book.lowQty},{book.nextPrice,book.nextQty}}
    local total=0
    for _,tier in ipairs(levels) do
      if tier[1] and tier[2] then
        local take=math.min(n,tier[2]);total=total+tier[1]*take;n=n-take
        if tiers and take>0 then tiers[#tiers+1]=take..' x '..ForeverMarketCoins(tier[1]) end
        if n==0 then return total end
      end
    end
  end
end
function M.listingGross(r)
  local q=r.quantity or 0
  if r.status==1 and r.bidder and (r.bidAmount or 0)>0 then return r.bidAmount end
  if r.unitPrice and r.unitPrice>0 then return r.unitPrice*q end
  local s=r.auctionID and M.account().sales[r.auctionID]
  if s and s.amount and s.amount>0 and s.qty and s.qty>=q and q>0 and (r.status==0 or not r.bidder) then return math.floor(s.amount*q/s.qty) end
  return (r.buyoutAmount and r.buyoutAmount>0 and r.buyoutAmount) or r.bidAmount or 0
end
function M.saleTotals()
  local a=M.account()
  local api=C_AuctionHouse
  local listed,sold=0,0
  local pending,seen={},{}
  for i=1,api.GetNumOwnedAuctions() do
    local r=api.GetOwnedAuctionInfo(i)
    if r and r.status==0 then listed=listed+M.listingGross(r) elseif r and r.status==1 then
      local gross=M.listingGross(r);sold=sold+gross
      if r.auctionID then
        seen[r.auctionID]=true
        local s=a.sales[r.auctionID];local n=a.notice[r.auctionID]
        if n and n.at and n.at>(a.mailAsOf or 0) then
          pending[#pending+1]=ForeverMarketSaleNet(gross)+(s and s.qty==r.quantity and s.deposit or 0)
        end
      end
    end
  end
  local amount=0
  for _,m in ipairs(a.mail) do amount=amount+m.amount end
  local count=0
  for id,n in pairs(a.notice) do
    local s=a.sales[id]
    if not seen[id] and n.at and n.at>(a.mailAsOf or 0) and s and s.qty==1 and s.amount then
      pending[#pending+1]=ForeverMarketSaleNet(s.amount)+(s.deposit or 0)
    elseif not seen[id] and n.at and n.at>(a.mailAsOf or 0) then count=count+1 end
  end
  local estimate=0;for _,value in ipairs(pending) do estimate=estimate+value end
  return listed,amount,a.collected[date('%Y-%m-%d')] or 0,count,sold,estimate
end
function M.mailSnapshot(list)
  local a=M.account()
  -- Only newly visible invoices can settle a previously unseen notification.
  a.mailRevision=(a.mailRevision or 0)+1
  local old={}
  for _,m in ipairs(a.mail) do old[m.key]=(old[m.key] or 0)+1 end
  for _,m in ipairs(list) do
    if (old[m.key] or 0)>0 then old[m.key]=old[m.key]-1
    else
      for id,s in pairs(a.notice) do
        if s.name==m.name or (s.text and m.name and s.text:find(m.name,1,true)) then a.notice[id]=nil;break end
      end
    end
  end
  a.mail=list;a.mailAsOf=time()
end
function M.onActivity(kind,e)
  if M.farmActivity then M.farmActivity(kind,e) end
  if kind=='purchase' or kind=='purchased_item_received' then M.tripDirty=true end
  local a=M.account()
  if M.recordMarket then M.recordMarket(kind,e) end
  if kind=='posted' and e.auctionId then a.sales[e.auctionId]={name=e.name,id=e.itemId,qty=e.quantity,amount=e.total,at=e.at,deposit=e.deposit}
    local intent=M.sellIntent
    if intent and e.quantity==intent.n and e.itemId==intent.id and e.total==intent.price*intent.n and e.at and e.at-intent.at<=60 then
      local styles=a.styleStats or {};a.styleStats=styles
      local byItem=styles[e.itemId] or {};styles[e.itemId]=byItem
      local stat=byItem[intent.style] or {posts=0,sold=0,seconds=0};byItem[intent.style]=stat
      stat.posts=stat.posts+1;a.sales[e.auctionId].style=intent.style;M.sellIntent=nil
    end
  elseif kind=='sale_notice' and e.auctionId then
    local s=a.sales[e.auctionId]
    if s and s.style and not s.soldAt and e.at then
      local stat=a.styleStats[s.id][s.style];stat.sold=stat.sold+1;stat.seconds=stat.seconds+math.max(0,e.at-s.at)
    end
    if s then s.soldAt=e.at end
    a.notice[e.auctionId]={name=s and s.name,text=e.name,at=e.at}
  elseif kind=='proceeds_collected' and e.invoiceType=='seller' then
    local day=date('%Y-%m-%d',e.at);a.collected[day]=(a.collected[day] or 0)+e.amount
    for i,m in ipairs(a.mail) do if e.mailRevision==a.mailRevision and m.name==e.name and m.amount==e.amount and m.qty==e.quantity then table.remove(a.mail,i);break end end
  elseif kind=='purchased_item_received' and e.itemId then
    a.transit[e.itemId]=math.max(0,(a.transit[e.itemId] or 0)-(e.quantity or 0))
    if M.invalidate then M.invalidate() end
  end
end
