local M=ForeverMarketTools
local function settings()
  local a=M.account()
  a.marketSession=a.marketSession or {}
  local key=GetCurrentRegion()..'|'..M.scope()
  a.marketSession[key]=a.marketSession[key] or {watches={},stage=1}
  return a.marketSession[key]
end
M.session=settings
local timed
local timerFrame=CreateFrame('Frame')
local canCount=pcall(timerFrame.RegisterEvent,timerFrame,'GLOBAL_MOUSE_DOWN')
timerFrame:SetScript('OnEvent',function()
  if timed and (AuctionHouseFrame and AuctionHouseFrame:IsShown() or MailFrame and MailFrame:IsShown()) then timed.clicks=timed.clicks+1 end
end)
function M.timeSelling()
  local s=settings()
  if not timed then timed={started=GetTime(),clicks=0,posts=0,counted=canCount};M.sellingTimer=timed;return 'Timer started. Use any auction interface for this pass.' end
  timed.elapsed=math.floor(GetTime()-timed.started)
  s.sellTrials=s.sellTrials or {};table.insert(s.sellTrials,1,timed);s.sellTrials[11]=nil;timed=nil;M.sellingTimer=nil
  return 'Selling trial saved.'
end
function M.setPriceWatch(id,cap)
  if not id or id<=0 or id~=math.floor(id) or not cap or cap<0 or cap>1e10 or cap~=math.floor(cap) then return 'Enter an item and a valid maximum unit price.' end
  local list=settings().watches
  if cap==0 then list[id]=nil;return 'Price watch removed.' end
  list[id]={cap=cap}
  return 'Watching '..(C_Item.GetItemNameByID(id) or id)..' up to '..ForeverMarketCoins(cap)..' each.'
end
function M.watchRecipe(recipe)
  local inputs=M.inputs(recipe,1)
  if not inputs then return 'Choose reagents for this recipe first.' end
  local count,missing,kept=0,0,0
  local snap=ForeverMarketReadySnapshot()
  for id in pairs(inputs) do
    local b=snap and snap.books[id]
    if settings().watches[id] then kept=kept+1
    elseif b and b.low and b.low>0 then M.setPriceWatch(id,b.low);count=count+1
    else missing=missing+1 end
  end
  return ('%d new ceilings at scanned asks / %d existing / %d without a price.'):format(count,kept,missing)
end
local poll,waiting,nextAt,index=false,nil,0,0
local api=C_AuctionHouse
function M.monitorPrices(enable)
  poll=enable;waiting=nil;index=0;nextAt=0
end
function M.priceMonitorActive()return poll end
function M.watchTick()
  if not poll then return end
  if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then M.monitorPrices(false);return end
  if waiting and GetTime()-waiting.at>10 then waiting=nil end
  if waiting or GetTime()<nextAt or not api.IsThrottledMessageSystemReady() then return end
  local ids={}
  for id in pairs(settings().watches) do ids[#ids+1]=id end
  if #ids==0 then M.monitorPrices(false);return end
  table.sort(ids);index=index%#ids+1
  local id=ids[index];local name=C_Item.GetItemNameByID(id)
  nextAt=GetTime()+math.max(2,15/#ids)
  if not name then return end
  local query={searchString=name,sorts={},filters={}}
  waiting={id=id,query=query,at=GetTime()}
  if not pcall(api.SendBrowseQuery,query) then waiting=nil end
end
local listener=CreateFrame('Frame')
listener:RegisterEvent('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
listener:RegisterEvent('AUCTION_HOUSE_CLOSED')
listener:SetScript('OnEvent',function(_,event)
  if event=='AUCTION_HOUSE_CLOSED' then M.monitorPrices(false);return end
  if not waiting then return end
  local id=waiting.id
  local rule=settings().watches[id]
  if not rule then waiting=nil;return end
  local lowest,bestKey
  for _,row in ipairs(api.GetBrowseResults() or {}) do
    if row.itemKey and row.itemKey.itemID==id and (row.totalQuantity or 0)>0 and (row.minPrice or 0)>0 and (not lowest or row.minPrice<lowest) then lowest=row.minPrice;bestKey=row.itemKey end
  end
  if lowest or api.HasFullBrowseResults() then
    if lowest and lowest<=rule.cap and (not rule.ask or lowest<rule.ask or rule.ask>rule.cap) then
      print('Forever Market: '..(C_Item.GetItemNameByID(id) or id)..' listed at '..ForeverMarketCoins(lowest)..' each.')
    end
    rule.ask=lowest;rule.key=bestKey;rule.at=time();waiting=nil;M.watchChanged=true
  end
end)
if hooksecurefunc and api.SendBrowseQuery then
  hooksecurefunc(api,'SendBrowseQuery',function(query)if poll and (not waiting or query~=waiting.query) then M.monitorPrices(false) end end)
end
if hooksecurefunc and api.SendSearchQuery then
  hooksecurefunc(api,'SendSearchQuery',function()if poll then M.monitorPrices(false) end end)
end
if hooksecurefunc and api.SearchForItemKeys then
  hooksecurefunc(api,'SearchForItemKeys',function()if poll then M.monitorPrices(false) end end)
end

function M.disenchantValue(id)
  local manager=M.account().manager
  local s=manager and manager.samples and manager.samples[id]
  if not s or s.count<1 then return end
  local sum,parts=0,{}
  for mat,n in pairs(s.outputs) do
    local price=M.prices(mat)
    if not price then return end
    sum=sum+ForeverMarketSaleNet(n*price)-(ForeverMarketDepositLoss and ForeverMarketDepositLoss(n) or 0)
    parts[#parts+1]=('%.2f x %s at %s'):format(n/s.count,C_Item.GetItemNameByID(mat) or mat,ForeverMarketCoins(price))
  end
  if #parts==0 then return end
  table.sort(parts)
  return math.floor(sum/s.count),s.count,table.concat(parts,', ')
end

local mailPending
local mailEvents=CreateFrame('Frame')
for _,ev in ipairs({'MAIL_SHOW','MAIL_CLOSED','MAIL_INBOX_UPDATE','MAIL_FAILED'}) do pcall(mailEvents.RegisterEvent,mailEvents,ev) end
mailEvents:SetScript('OnEvent',function()mailPending=nil;M.mailChanged=true end)
function M.returnLetters()
  local rows={}
  if not MailFrame or not MailFrame:IsShown() or not GetInboxNumItems then return rows end
  for i=1,GetInboxNumItems() do
    local _,_,sender,subject,_,cod=GetInboxHeaderInfo(i)
    local name,id,_,n=GetInboxItem(i,1)
    if name and id and n and n>0 and (cod or 0)==0 then
      local expired=AUCTION_EXPIRED_MAIL_SUBJECT and subject==AUCTION_EXPIRED_MAIL_SUBJECT:format(name)
      local cancelled=AUCTION_REMOVED_MAIL_SUBJECT and subject==AUCTION_REMOVED_MAIL_SUBJECT:format(name)
      if expired or cancelled then rows[#rows+1]={index=i,id=id,n=n,name=name,subject=subject,sender=sender} end
    end
  end
  return rows
end
function M.collectReturn(row)
  if mailPending and GetTime()-mailPending<4 then return 'Waiting for the mailbox.' end
  for _,live in ipairs(M.returnLetters()) do
    if live.index==row.index and live.id==row.id and live.n==row.n and live.subject==row.subject and live.sender==row.sender then
      mailPending=GetTime();TakeInboxItem(row.index,1);return 'Collection requested.'
    end
  end
  return 'Mail changed. Review the refreshed list.'
end

local coverage
local function daysSeen(values,today)
  local n=0
  for day in pairs(values or {}) do
    day=tonumber(day)
    if day and day<=today and day>today-14 then n=n+1 end
  end
  return n
end
function M.marketCoverage()
  local snap=ForeverMarketReadySnapshot and ForeverMarketReadySnapshot()
  local scope=M.scope()
  if not coverage or coverage.scope~=scope or coverage.snapshotRef~=snap or (coverage.done and GetTime()-coverage.at>=30) then
    local history=ForeverMarketHistory()
    coverage={scope=scope,snapshotRef=snap,snapshot=snap~=nil,source=snap and snap.books or history,
      history=history,items=0,categories={},seen={},today=math.floor(time()/86400)}
    M.coverageTick()
  end
  return (not coverage.done or coverage.items>0) and coverage or nil
end
function M.coverageTick()
  local c=coverage;if not c or c.done then return end
  for i=1,120 do
    if c.cursor and not c.source[c.cursor] then coverage=nil;return true end
    local key,value=next(c.source,c.cursor);c.cursor=key
    if not key then c.done=true;c.at=GetTime();c.seen=nil;return true end
    local id=tonumber(key) or type(key)=='string' and tonumber(key:match('^g:(%d+):'))
    if id and not c.seen[id] and (c.snapshot or type(value)=='table' and daysSeen(value.l,c.today)>0) then
      c.seen[id]=true;c.items=c.items+1
      local class=C_Item.GetItemInfoInstant and select(6,C_Item.GetItemInfoInstant(id))
      local className=GetItemClassInfo or C_Item.GetItemClassInfo
      local label=class and className and className(class) or class and ('Class '..class) or 'Other'
      local cat=c.categories[label] or {all=0,repeatDays=0};c.categories[label]=cat;cat.all=cat.all+1
      local entry=c.history[tostring(id)]
      if daysSeen(entry and entry.floors,c.today)>=3 then cat.repeatDays=cat.repeatDays+1 end
    end
  end
end
