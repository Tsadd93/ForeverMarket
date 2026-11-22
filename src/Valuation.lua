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
  if a.collectedInitialized then return end
  local name=UnitName('player')
  local source=ForeverMarketActivity or ForeverMarketDB.__activity
  for _,e in ipairs(source and source.events or {}) do
    if e.kind=='proceeds_collected' and e.invoiceType=='seller' and e.amount and e.at and e.character==name
      and e.realm==GetRealmName() and e.region==GetCurrentRegion() and e.faction==UnitFactionGroup('player') then
      local day=date('%Y-%m-%d',e.at);a.collected[day]=(a.collected[day] or 0)+e.amount
    end
  end
  a.collectedInitialized=true
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
  local q=M.quotes()[variant or id]
  local hist=ForeverMarketHistory()[key or tostring(id)]
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
    return ForeverMarketPostPrice(q.price),q.at,time()-q.at<60 and 'Live check' or 'Last scan'
  end
  local avg,at=M.history(key or tostring(id))
  return avg,at,'Historical estimate'
end
function M.bagCount(id)
  local count=C_Item and C_Item.GetItemCount or GetItemCount
  return count and count(id,false,false,false) or 0
end
function M.levels(levels)
  local prices={}
  for price in pairs(levels) do prices[#prices+1]=price end
  table.sort(prices)
  local out={}
  for i=1,math.min(32,#prices) do out[i]={prices[i],levels[prices[i]]} end
  return out
end
function M.cost(id,n)
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
        if n==0 then return total end
      end
    end
  end
end
function M.saleTotals()
  local a=M.account()
  local api=C_AuctionHouse
  local listed=0
  for i=1,api.GetNumOwnedAuctions() do
    local r=api.GetOwnedAuctionInfo(i)
    if r and r.status==0 then listed=listed+(r.buyoutAmount or r.bidAmount or 0) end
  end
  local amount=0
  for _,m in ipairs(a.mail) do amount=amount+m.amount end
  local count=0;for _ in pairs(a.notice) do count=count+1 end
  return listed,amount,a.collected[date('%Y-%m-%d')] or 0,count
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
  a.mail=list
end
function M.onActivity(kind,e)
  local a=M.account()
  if M.recordMarket then M.recordMarket(kind,e) end
  if kind=='posted' and e.auctionId then a.sales[e.auctionId]={name=e.name,id=e.itemId,qty=e.quantity,amount=e.total,at=e.at,deposit=e.deposit}
  elseif kind=='sale_notice' and e.auctionId then
    local s=a.sales[e.auctionId]
    if s then s.soldAt=e.at end
    a.notice[e.auctionId]={name=s and s.name,text=e.name}
  elseif kind=='proceeds_collected' and e.invoiceType=='seller' then
    local day=date('%Y-%m-%d',e.at);a.collected[day]=(a.collected[day] or 0)+e.amount
    for i,m in ipairs(a.mail) do if e.mailRevision==a.mailRevision and m.name==e.name and m.amount==e.amount and m.qty==e.quantity then table.remove(a.mail,i);break end end
  elseif kind=='purchased_item_received' and e.itemId then
    a.transit[e.itemId]=math.max(0,(a.transit[e.itemId] or 0)-(e.quantity or 0))
    if M.invalidate then M.invalidate() end
  end
end
