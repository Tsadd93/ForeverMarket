-- Venue is set on AH open before a scan. Keep the last venue for offline review/export.
local neutral=false
function ForeverMarketSetVenue(isNeutral) neutral=isNeutral==true end
local clientRealm=GetRealmName
function ForeverMarketVenueRealm()
  local realm=clientRealm() or ''
  return neutral and (realm..' [Neutral AH]') or realm
end
local GetRealmName=ForeverMarketVenueRealm
-- Price history is indexed by market and UTC day; the desktop export keeps original observation timestamps.
local function scope(realm,faction,region)
  return tostring(region)..'|'..realm..'|'..faction
end
function ForeverMarketHistory()
  ForeverMarketDB=ForeverMarketDB or {}
  local all=ForeverMarketDB.history or {};ForeverMarketDB.history=all
  local key=scope(GetRealmName(),UnitFactionGroup('player'),GetCurrentRegion())
  all[key]=all[key] or {}
  return all[key]
end
local commodityByID={}
local function commodity(key)
  local id=key.itemID
  if commodityByID[id]~=nil then return commodityByID[id] end
  local api=C_AuctionHouse
  local info=api and api.GetItemKeyInfo and api.GetItemKeyInfo(key)
  if info and type(info.isCommodity)=='boolean' then commodityByID[id]=info.isCommodity end
  return commodityByID[id]
end
function ForeverMarketHistoryKey(k)
  if (k.battlePetSpeciesID or 0)>0 then return 'p:'..k.battlePetSpeciesID end
  if (k.itemLevel or 0)>0 and not commodity(k) then return 'g:'..k.itemID..':'..k.itemLevel end
  return tostring(k.itemID)
end
-- Older versions stored commodity browse results under equipment-style keys.
-- Merge only confirmed commodities; overlapping observations represent one day.
function ForeverMarketRepairHistory()
  local db=ForeverMarketHistory()
  local market=GetRealmName()..'|'..UnitFactionGroup('player')
  local live=ForeverMarketDB[market] or {}
  ForeverMarketDB[market]=live
  local aliases={}
  for key in pairs(db) do
    local id,level=tostring(key):match('^g:(%d+):(%d+)$')
    if id and commodity({itemID=tonumber(id),itemLevel=tonumber(level),itemSuffix=0,battlePetSpeciesID=0}) then
      aliases[#aliases+1]={key,id}
    end
  end
  for _,pair in ipairs(aliases) do
    local key,id=pair[1],pair[2]
    local src,dst=db[key],db[id]
    if not dst then db[id]=src
    else
      for day,high in pairs(src.h) do
        local previousLow=dst.l[day] or dst.h[day]
        dst.h[day]=math.max(dst.h[day] or high,high)
        local low=src.l[day] or high
        dst.l[day]=math.min(previousLow or low,low)
        if src.a[day] then dst.a[day]=math.max(dst.a[day] or 0,src.a[day]) end
        dst.stamp[day]=dst.stamp[day] or src.stamp[day]
      end
      if (src.day or 0)>(dst.day or 0) then dst.day=src.day;dst.m=src.m end
      if src.bulk and (not dst.bulk or src.bulk.at>dst.bulk.at) then dst.bulk=src.bulk end
    end
    if live[key] and (not live[id] or live[key].at>live[id].at) then live[id]=live[key] end
    if live[id] and (not db[id].day or math.floor(live[id].at/86400)>=db[id].day) then db[id].m=live[id].price end
    live[key]=nil;db[key]=nil
  end
  return #aliases
end
-- Freeze a displayed investment's exit for three days. Only later full bulk
-- observations can resolve it. Missing coverage stays separate from misses.
local function closePaperWindow(p,now)
  if p.at and now>p.at+3*86400 then
    if not p.hit then
      if p.d1 and p.d2 and p.d3 then p.misses=p.misses+1 else p.gaps=p.gaps+1 end
    end
    p.at=nil
  end
end
function ForeverMarketPaperDip(id,exit)
  local r=ForeverMarketHistory()[tostring(id)]
  if not r then return end
  local p=r.paper or {hits=0,misses=0,gaps=0};r.paper=p
  local now=time()
  closePaperWindow(p,now)
  if not p.at then p.at=now;p.exit=exit;p.hit=nil;p.d1=nil;p.d2=nil;p.d3=nil end
  return ('Forward quotes: %d hit / %d missed / %d incomplete. '):format(p.hits,p.misses,p.gaps)
end
function ForeverMarketPaperResults()
  local results={}
  for key,r in pairs(ForeverMarketHistory()) do
    if r.paper then
      closePaperWindow(r.paper,time())
      results[#results+1]={id=tonumber(key),paper=r.paper}
    end
  end
  table.sort(results,function(a,b)return a.id<b.id end)
  return results
end
function ForeverMarketObserve(key,price,quantity,bulk)
  if not price or price<=0 then return end
  local db=ForeverMarketHistory()
  local r=db[key] or {h={},l={},a={},stamp={}};db[key]=r
  local now=time();local day=math.floor(now/86400)
  if r.day~=day then
    for old in pairs(r.h) do
      if old<day-60 then if r.floors then r.floors[old]=nil end;r.h[old]=nil;r.l[old]=nil;r.a[old]=nil;r.stamp[old]=nil end
    end
  end
  r.day=day;r.m=price
  r.h[day]=math.max(r.h[day] or price,price);r.l[day]=math.min(r.l[day] or price,price)
  r.a[day]=quantity;r.stamp[day]=r.stamp[day] or day*86400
  local market=GetRealmName()..'|'..UnitFactionGroup('player')
  ForeverMarketDB[market]=ForeverMarketDB[market] or {}
  ForeverMarketDB[market][key]={price=price,quantity=quantity,at=now}
  if ForeverMarketTools and ForeverMarketTools.checkAlert then ForeverMarketTools.checkAlert(key,price) end
  local trial=r.paper
  if trial then closePaperWindow(trial,now) end
  if bulk and trial and trial.at and not trial.hit and now>trial.at and now<=trial.at+3*86400 then
    local window=math.ceil((now-trial.at)/86400)
    trial['d'..window]=true
    if bulk>=trial.exit then trial.hit=true;trial.hits=trial.hits+1 end
  end
  if bulk then r.bulk={price=bulk,at=now};r.floors=r.floors or {};r.floors[day]=math.min(bulk,r.floors[day] or bulk) end
end

-- Read the JSON written by earlier versions without executing saved data.
local function decode(s)
  local i=1
  local escapes={n='\n',r='\r',t='\t',['"']='"',['\\']='\\',['/']='/'}
  local function str()
    local start=i+1;i=start
    local parts={}
    while true do
      local j=assert(s:find('["\\]',i));parts[#parts+1]=s:sub(start,j-1)
      if s:sub(j,j)=='"' then i=j+1;return table.concat(parts) end
      local e=s:sub(j+1,j+1);i=j+2
      if e=='u' then parts[#parts+1]=string.char(assert(tonumber(s:sub(i,i+3),16)));i=i+4
      else parts[#parts+1]=assert(escapes[e]) end
      start=i
    end
  end
  local function value()
    local c=s:sub(i,i)
    if c=='"' then return str() end
    if c=='{' or c=='[' then
      i=i+1;local t={};local closing=c=='{' and '}' or ']'
      while s:sub(i,i)~=closing do
        local k=#t+1
        if c=='{' then assert(s:sub(i,i)=='"');k=str();assert(s:sub(i,i)==':');i=i+1 end
        t[k]=value()
        if s:sub(i,i)==closing then break end
        assert(s:sub(i,i)==',');i=i+1
      end
      i=i+1;return t
    end
    local j=s:find('[,}%]]',i) or #s+1
    local word=s:sub(i,j-1);i=j
    if word=='true' then return true elseif word=='false' then return false elseif word=='null' then return nil end
    return assert(tonumber(word))
  end
  return value()
end
function ForeverMarketMigrate()
  ForeverMarketHistory()
  if ForeverMarketDB.historyImported or not ForeverMarketExport then return true end
  local ok,old=pcall(decode,ForeverMarketExport)
  if not ok or type(old)~='table' or not old.rows then
    print('Forever Market: could not import the previous export. It has been preserved.');return false
  end
  local k=scope(old.realm,old.faction,old.region)
  local db=ForeverMarketDB.history[k] or {};ForeverMarketDB.history[k]=db
  for _,row in ipairs(old.rows) do
    if not db[row.key] then
      local r={h={},l={},a={},stamp={}}
      for _,p in ipairs(row.history or {}) do
        local day=math.floor(p.at/86400)
        r.h[day]=p.high;r.l[day]=p.low;r.a[day]=p.quantity;r.stamp[day]=p.at
        if not r.day or day>r.day then r.day=day;r.m=p.low end
      end
      if row.live and row.live.price then r.m=row.live.price end
      if r.m then db[row.key]=r end
    end
  end
  ForeverMarketDB.historyImported=true
  return true
end

local tabs={}
function ForeverMarketTab(id,panel,text,title)
  local ah=AuctionHouseFrame
  local prev=#tabs>0 and tabs[#tabs].button or ah.Tabs[#ah.Tabs]
  local b=CreateFrame('Button',id..'TabButton',ah,'AuctionHouseFrameDisplayModeTabTemplate')
  b:SetText(text);PanelTemplates_TabResize(b,16,nil,65)
  b:SetPoint('TOPLEFT',prev,'TOPRIGHT',2,0)
  PanelTemplates_DeselectTab(b)
  tabs[#tabs+1]={panel=panel,button=b}
  if #tabs==1 then
    hooksecurefunc(ah,'SetDisplayMode',function()
      for _,t in ipairs(tabs) do t.panel:Hide();PanelTemplates_DeselectTab(t.button) end
    end)
  end
  panel.selectTab=function()
    ah:SetDisplayMode({});ah.displayMode=nil
    for _,t in ipairs(ah.Tabs) do PanelTemplates_DeselectTab(t) end
    PanelTemplates_SelectTab(b);ah:SetTitle(title);panel:Show()
  end
  b:SetScript('OnClick',panel.selectTab)
end

-- Use only observed daily bulk prices. Today's quote is checked separately.
function ForeverMarketRecovery(floors,today)
  if not floors then return end
  local days={}
  for day,p in pairs(floors) do
    if type(day)=='number' and day<today and day>=today-60 and p>0 then days[#days+1]=day end
  end
  if #days<14 then return end
  table.sort(days)
  if days[#days]<today-2 then return end
  local function median(i,n)
    local prices={}
    for j=i-n+1,i do prices[#prices+1]=floors[days[j]] end
    table.sort(prices);return prices[math.ceil(n/2)]
  end
  local wins,trials,nextDay=0,0,0
  for i=6,#days do
    local day=days[i]
    if day>=nextDay and day+3<today and days[i-5]>=day-8 then
      local baseline=median(i-1,5)
      if floors[day]<=baseline*.85 then
        trials=trials+1;nextDay=day+4
        for future=day+1,day+3 do
          if floors[future] and floors[future]>=baseline*.95 then wins=wins+1;break end
        end
      end
    end
  end
  if wins<3 or wins/trials<.8 then return end
  local normal=median(#days,#days)
  local recent=median(#days,5)
  if recent<normal*.9 or days[#days-4]<today-8 then return end
  local baseline=math.min(normal,recent)
  return {entry=math.floor(baseline*.85),exit=math.floor(baseline*.95)-2,wins=wins,trials=trials}
end
function ForeverMarketSeedFloors()
  local source=ForeverMarketActivity or ForeverMarketDB.__activity
  if not source then return end
  local realm,faction,region=GetRealmName(),UnitFactionGroup('player'),GetCurrentRegion()
  local key=scope(realm,faction,region)
  local seeded=ForeverMarketDB.floorMigration or {};ForeverMarketDB.floorMigration=seeded
  if seeded[key] then return end
  local db=ForeverMarketHistory();local oldest=math.floor(time()/86400)-60
  for _,e in ipairs(source.events or {}) do
    if e.kind=='price_depth' and e.realm==realm and e.faction==faction and e.region==region and e.floorPrice and e.floorPrice>0 and e.itemId then
      local r=db[tostring(e.itemId)];local day=math.floor(e.at/86400)
      if r and day>=oldest then r.floors=r.floors or {};r.floors[day]=math.min(r.floors[day] or e.floorPrice,e.floorPrice) end
    end
  end
  seeded[key]=true
end
