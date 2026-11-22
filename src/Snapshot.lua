local GetRealmName=ForeverMarketVenueRealm or function() return _G.GetRealmName and _G.GetRealmName() or '' end
-- One session snapshot is shared by Market Scan and Market Buy. A second
-- consumer may join a request already in flight without sending another.
local api=C_AuctionHouse
if not api or not api.ReplicateItems or not api.GetNumReplicateItems or not api.GetReplicateItemInfo then return end
local frame=CreateFrame('Frame')
if not pcall(frame.RegisterEvent,frame,'REPLICATE_ITEM_LIST_UPDATE') then return end
frame:RegisterEvent('AUCTION_HOUSE_CLOSED')
local cached,job
local retryAt,failures=0,0
local lastFailure
local function fail(reason)
  job=nil;failures=failures+1;lastFailure=reason
  retryAt=GetTime()+(failures==1 and 60 or 900)
end
local function scope()
  return table.concat({GetCurrentRegion(),GetRealmID and GetRealmID() or '',GetRealmName(),UnitFactionGroup('player')},'|')
end
function ForeverMarketReadySnapshot()
  if cached and cached.scope==scope() and GetTime()-cached.at<900 then return cached end
end
function ForeverMarketSnapshot()
  local now=GetTime()
  if not cached then
    local saved=ForeverMarketDB and ForeverMarketDB.bulkSnapshot
    if saved and saved.scope==scope() and saved.observed and saved.books then
      local age=time()-saved.observed
      if age>=0 and age<900 then
        cached={scope=saved.scope,books=saved.books,at=now-age,rows=saved.rows}
        retryAt=cached.at+900
      end
    end
  end
  if cached and cached.scope==scope() and now-cached.at<900 then return cached end
  if job then return nil,'pending' end
  if now<retryAt then return nil,lastFailure or 'cooldown' end
  if api.IsThrottledMessageSystemReady and not api.IsThrottledMessageSystemReady() then return nil,'throttled' end
  job={scope=scope(),at=now,levels={},rows=0,index=0}
  retryAt=now+900
  if not pcall(api.ReplicateItems) then fail("request failed");return nil,lastFailure end
  return nil,'pending'
end
frame:SetScript('OnEvent',function(_,event)
  if event=='AUCTION_HOUSE_CLOSED' then job=nil;return end
  if job and not job.total then
    local count=api.GetNumReplicateItems()
    if count and count>0 then job.total=count end
  end
end)
frame:SetScript('OnUpdate',function()
  if not job then return end
  if not job.total then
    if GetTime()-job.at>60 then fail("snapshot timed out") end
    return
  end
  -- Spread row decoding and history writes across frames on busy realms.
  if job.index<job.total then
    for i=job.index,math.min(job.index+299,job.total-1) do
      local _,_,qty,_,_,_,_,_,_,total,_,_,_,_,_,_,id=api.GetReplicateItemInfo(i)
      if id and id>0 and qty and qty>0 and total and total>0 then
        local p=math.ceil(total/qty)
        local levels=job.levels[id] or {};job.levels[id]=levels
        levels[p]=(levels[p] or 0)+qty
        job.rows=job.rows+1
      end
      job.index=i+1
    end
    return
  end
  job.books=job.books or {}
  for i=1,100 do
    local id,levels=next(job.levels,job.lastID)
    if not id then
      if job.rows==0 then fail("no priced rows");return end
      if job.rows>0 then
        failures=0;lastFailure=nil
        cached={scope=job.scope,at=job.at,books=job.books,rows=job.rows}
        ForeverMarketDB=ForeverMarketDB or {}
        ForeverMarketDB.bulkSnapshot={scope=job.scope,observed=time()-math.ceil(GetTime()-job.at),books=job.books,rows=job.rows}
      end
      job=nil;return
    end
    local d=ForeverMarketPriceDepth(levels)
    if ForeverMarketTools then d.levels=ForeverMarketTools.levels(levels) end
    local qty=0
    for p,n in pairs(levels) do
      d.high=math.max(d.high or 0,p)
      qty=qty+n
    end
    job.books[id]=d
    -- Replication identifies the base item; variant-specific prices still
    -- come from keyed browse and live item searches.
    if id~=82800 then ForeverMarketObserve(tostring(id),d.low,qty) end
    job.lastID=id
  end
end)
