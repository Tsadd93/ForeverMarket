local M=ForeverMarketTools

-- Each observed UTC day contributes one bulk floor, regardless of scan frequency.
function M.priceStatistics(id,days,history)
  local h=(history or ForeverMarketHistory())[tostring(id)] or {}
  local today=math.floor(time()/86400)
  local samples={}
  local sum,ema=0,nil
  for day=today-days+1,today do
    local ask=h.floors and (h.floors[day] or h.floors[tostring(day)])
    if ask and ask>0 then
      samples[#samples+1]=ask;sum=sum+ask
      ema=ema and ema+(ask-ema)*.25 or ask
    end
  end
  local n=#samples
  if n==0 then return end
  table.sort(samples)
  local function percentile(p)
    local pos=1+(n-1)*p
    local lo,hi=math.floor(pos),math.ceil(pos)
    return samples[lo]+(samples[hi]-samples[lo])*(pos-lo)
  end
  local q1,q3=percentile(.25),percentile(.75)
  local spread=q3-q1
  local low,high=samples[1],samples[n]
  local bins,trimmed,used={0,0,0,0,0},0,0
  local width=math.max(1,math.ceil((high-low+1)/5))
  for _,v in ipairs(samples) do
    local i=math.floor((v-low)/width)+1;bins[i]=bins[i]+1
    if v>=q1-1.5*spread and v<=q3+1.5*spread then trimmed=trimmed+v;used=used+1 end
  end
  return {n=n,low=low,high=high,q1=q1,q3=q3,median=percentile(.5),mean=sum/n,
    ema=ema,filtered=trimmed/used,excluded=n-used,bins=bins,width=width}
end

-- Shared packs contain prices only and never enter the executable pricing path.
local function venue()
  local guid=UnitGUID('player') or ''
  local realm=GetRealmID and GetRealmID()
  if not realm or realm<=0 then realm=tonumber(guid:match('^Player%-(%d+)%-')) end
  local faction=UnitFactionGroup('player')
  if not realm or not faction then return end
  return table.concat({GetCurrentRegion(),realm,faction,ForeverMarketVenueRealm():find('Neutral AH',1,true) and 'N' or 'F'},'/')
end
function M.referencePack(raw)
  local key=venue()
  if not key then return nil,'Market identity unavailable.' end
  if type(raw)~='string' or #raw>150000 then return nil,'Paste a Forever Market reference pack.' end
  local header,body=raw:match('^([^\r\n]+)\r?\n(.+)$')
  if not header or header~='FMREF1 '..key then return nil,'This pack must match your region, realm, faction and auction house.' end
  local rows,count={},0
  local now=time()
  for line in body:gmatch('[^\r\n]+') do
    local id,price,stamp=line:match('^(%d+),(%d+),(%d+)$')
    id,price,stamp=tonumber(id),tonumber(price),tonumber(stamp)
    if not id or id<1 or id>2147483647 or price<1 or price>1e12 or stamp>now or now-stamp>7*86400 or rows[id] or count>=2000 then
      return nil,'Invalid, duplicate or expired entry. Ask for a fresh export.'
    end
    rows[id]={price=price,at=stamp};count=count+1
  end
  if count==0 then return nil,'No prices found.' end
  return {scope=key,rows=rows,count=count}
end
function M.importReferencePack(raw)
  local pack,why=M.referencePack(raw)
  if not pack then return why end
  local all=ForeverMarketDB.peerReferences or {};ForeverMarketDB.peerReferences=all
  local rows=all[pack.scope] or {};all[pack.scope]=rows
  for id,v in pairs(rows) do if time()-v.at>7*86400 then rows[id]=nil end end
  for id,v in pairs(pack.rows) do if not rows[id] or v.at>rows[id].at then rows[id]=v end end
  return 'Reviewed '..pack.count..' reference prices. Trading uses local scans.'
end
function M.regionReference(id)
  local full=M.fullRegion and M.fullRegion();local r=full and full.items[id]
  if r and r[1] then return {r[1],r[2],r[3],full.at} end
  local v=ForeverMarketRegionPrices and ForeverMarketRegionPrices[id]
  if v and v[4]<=time() and time()-v[4]<=7*86400 then return v end
end
function M.sharedReferences(filter)
  local all=ForeverMarketDB.peerReferences
  local source=all and all[venue()] or {}
  local rows={}
  local seed=ForeverMarketStarter
  local matching=seed and venue()==table.concat({seed.region,seed.realmID,seed.faction,'F'},'/') and time()>=seed.at and time()-seed.at<=21*86400
  if matching then
    for id,price in pairs(seed.items or {}) do
      local v=source[id]
      if not v or time()-v.at>7*86400 or v.at<seed.at then rows[#rows+1]={id=id,at=seed.at,price=price,starter=true} end
    end
  end
  for id,v in pairs(source) do
    if v.at<=time() and time()-v.at<=7*86400 and not (matching and seed.items[id] and seed.at>v.at) then rows[#rows+1]={id=id,at=v.at,price=v.price} end
  end
  local full=M.fullRegion and M.fullRegion()
  local indexed=filter and {[filter]=true} or full and full.items or ForeverMarketRegionPrices or {}
  for id in pairs(indexed) do
    if not filter or filter==id then
      local v=M.regionReference(id)
      if v then rows[#rows+1]={id=id,at=v[4],price=v[1],regional=true,rate=v[2],volume=v[3]} end
    end
  end
  if filter then
    local matches={}
    for _,r in ipairs(rows) do if r.id==filter then matches[#matches+1]=r end end
    rows=matches
  end
  table.sort(rows,function(a,b)
    if a.regional~=b.regional then return not a.regional end
    if a.regional and (a.volume or 0)~=(b.volume or 0) then return (a.volume or 0)>(b.volume or 0) end
    return a.id<b.id
  end)
  return rows
end
function M.exportReferencePack()
  local key=venue()
  if not key or not ForeverMarketHasScan() then return nil,'Complete a local Market Scan first.' end
  local rows,now={},time()
  for k,h in pairs(ForeverMarketHistory()) do
    local id=tonumber(k)
    local q=h.bulk
    if id and q and q.price>0 and q.at<=now and now-q.at<=7*86400 then rows[#rows+1]={id=id,q=q} end
  end
  table.sort(rows,function(a,b)if a.q.at~=b.q.at then return a.q.at>b.q.at end return a.id<b.id end)
  if #rows==0 then return nil,'No recent local bulk prices to share.' end
  local lines={'FMREF1 '..key}
  for i=1,math.min(2000,#rows) do
    local v=rows[i];lines[#lines+1]=('%d,%d,%d'):format(v.id,v.q.price,v.q.at)
  end
  return table.concat(lines,'\n')
end

function M.customProgram(expression)
  if type(expression)~='string' or #expression>4096 then return nil,'Formula exceeds 4096 characters.' end
  local seq={}
  for part in (expression..';'):gmatch('(.-);') do
    if #seq>=12 then return nil,'Use at most twelve rules.' end
    local tree,why=M.compilePrice(part,M.account().namedFormulas)
    if not tree then return nil,why end
    seq[#seq+1]={name='Rule '..(#seq+1),source=part,tree=tree}
  end
  return seq
end
function M.setNamedFormula(key,expression)
  if not key:match('^user_[a-z][a-z0-9_]*$') or #key>48 then return 'Use a name such as user_ore.' end
  local names=M.account().namedFormulas or {};local trial={}
  for k,v in pairs(names) do trial[k]=v end;trial[key]=expression
  for k,v in pairs(trial) do
    local tree,why=M.compilePrice(v,trial)
    if not tree then return k..': '..why end
  end
  M.account().namedFormulas=trial
  return 'Saved '..key..'. Reapply dependent rules to use the revised definition.'
end
function M.savePriceProgram(ids,side,expression)
  if side~='buy' and side~='sell' then return 'Choose Buy or Sell.' end
  local seq,why=M.customProgram(expression)
  if not seq then return why end
  for _,id in ipairs(ids) do
    local group=M.group(id) or {margin=0,stock=0,cap=0}
    local old=M.importedRules(group) or {}
    group.program={buy=old.buy,sell=old.sell,sources=old.sources};group.programID=nil
    group.program[side]=seq
    M.account().desk.groups[id]=group
  end
  M.invalidate()
  return 'Saved '..side..' rule for '..#ids..' items.'
end

-- A guild request asks for one item. Replies require opt-in and a recent local scan.
local prefix='FMPRICE1'
local pending,lastReply,lastAsk
local function peerTransport()
  return C_ChatInfo and C_ChatInfo.SendAddonMessage and IsInGuild and IsInGuild()
end
function M.requestGuildPrice(id)
  if not id or id<1 or id>2147483647 or id~=math.floor(id) then return 'Enter an item ID or shift-click a link at right.' end
  local key=venue()
  if not key or not peerTransport() then return 'A guild connection and market identity are required.' end
  if lastAsk and GetTime()-lastAsk<5 then return 'Wait five seconds before another request.' end
  lastAsk=GetTime();pending={id=id,key=key,at=lastAsk}
  C_ChatInfo.SendAddonMessage(prefix,('Q:%s:%d'):format(key,id),'GUILD')
  return 'Requested a guild quote. Replies update the list automatically for 15 seconds.'
end
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  C_ChatInfo.RegisterAddonMessagePrefix(prefix)
  local events=CreateFrame('Frame');events:RegisterEvent('CHAT_MSG_ADDON')
  events:SetScript('OnEvent',function(_,_,tag,payload,channel,sender)
    if tag~=prefix or type(payload)~='string' or #payload>200 or not sender or not ForeverMarketDB then return end
    local key=venue()
    if not key then return end
    if channel=='GUILD' and ForeverMarketDB.shareGuildPrices and ForeverMarketHasScan() then
      local scope,raw=payload:match('^Q:([^:]+):(%d+)$')
      if scope~=key or lastReply and GetTime()-lastReply<3 then return end
      local h=ForeverMarketHistory()[raw];local q=h and h.bulk
      if not q or q.at>time() or time()-q.at>7*86400 then return end
      lastReply=GetTime()
      C_ChatInfo.SendAddonMessage(prefix,('R:%s:%s:%d:%d'):format(key,raw,q.price,q.at),'WHISPER',sender)
    elseif channel=='WHISPER' and pending and pending.key==key and GetTime()-pending.at<=15 then
      local scope,id,price,at=payload:match('^R:([^:]+):(%d+):(%d+):(%d+)$')
      if scope~=key or tonumber(id)~=pending.id then return end
      local raw='FMREF1 '..key..'\n'..id..','..price..','..at
      M.importReferencePack(raw);M.peerPricesChanged=true
    end
  end)
end
