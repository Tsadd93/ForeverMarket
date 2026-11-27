local M=ForeverMarketTools
local function pathOf(value)
  return type(value)=='string' and value:gsub('^%s+',''):gsub('%s+$','')
end
local function whole(value,max)
  local n=tonumber(value)
  if n and n>=0 and n<=max and n==math.floor(n) then return n end
end
-- Only translate expressions with the same meaning on this client.
local function convert(kind,key,v,r)
  if kind=='Auctioning' and key=='minPrice' and type(v)=='string' then
    local args=v:lower():match('^max%(([^()]+)%)$')
    if args then
      local maxRule={}
      for expr in (args..','):gmatch('(.-),') do
        local part={}
        if not convert(kind,key,expr:match('^%s*(.-)%s*$'),part) then return end
        for k,n in pairs(part) do maxRule[k]=math.max(maxRule[k] or 0,n) end
      end
      for k,n in pairs(maxRule) do r[k]=n end
      return true
    end
    local realm=v:lower()=='dbmarket' and 100 or tonumber(v:lower():match('^(%d+)%%%s*dbmarket$'))
    if realm and realm>0 and whole(realm,1000) then r.realmPct=realm;return true end
    local percent=v:lower()=='crafting' and '100' or v:lower():match('^(%d+)%%%s*crafting$')
    if percent and whole(percent,1000) then r.craftPct=tonumber(percent);return true end
    if v:lower():match('^[%d%s gsc]+$') and v:match('[gsc]') then local n=M.goldInput(v);if n then r.fixedFloor=n;return true end end
  elseif kind=='Auctioning' and key=='keepQuantity' and whole(v,9999) then r.reserve=tonumber(v);return true
  elseif kind=='Auctioning' and key=='duration' and ({[12]=1,[24]=2,[48]=3})[tonumber(v) or 0] then r.duration=({[12]=1,[24]=2,[48]=3})[tonumber(v)];return true
  elseif kind=='Auctioning' and key=='stackSize' and whole(v,9999) and tonumber(v)>0 then r.size=tonumber(v);return true
  elseif kind=='Sniper' and key=='belowPrice' and type(v)=='string' and v:match('[gsc]') and M.goldInput(v) then r.watchCap=M.goldInput(v);return true
  elseif kind=='Crafting' and key=='maxRestock' and whole(v,9999) then r.craftStock=tonumber(v);return true
  elseif kind=='Crafting' and key=='minRestock' and whole(v,9999) then r.minBatch=tonumber(v);return true
  elseif kind=='Warehousing' and key=='restockQuantity' and whole(v,9999) then r.bankTarget=tonumber(v);return true
  elseif kind=='Mailing' and key=='target' and type(v)=='string' then
    for _,to in ipairs(M.destinations()) do if to==v then r.mailTo=to;return true end end
  elseif kind=='Mailing' and (key=='keepQuantity' or key=='keepQty') and whole(v,9999) then r.mailKeep=tonumber(v);return true
  elseif kind=='Shopping' and key=='restockQuantity' and whole(v,9999) and tonumber(v)>0 then r.shopTarget=tonumber(v);return true
  elseif kind=='Shopping' and key=='maxPrice' and type(v)=='string' then
    local realm=v:lower()=='dbmarket' and 100 or tonumber(v:lower():match('^(%d+)%%%s*dbmarket$'))
    if realm and realm>0 and whole(realm,1000) then r.buyRealmPct=realm;return true end
    if not v:match('[gsc]') then return end
    local n=M.goldInput(v);if n and n>0 then r.cap=n;return true end
  end
end
local caps={}
function M.groupPurchaseAllowed(id,group,unit,force)
  if not group then return true end
  if (group.cap or 0)>0 and unit>group.cap then return false end
  if not group.buyRealmPct then return true end
  local cached=caps[id];local scope=M.scope()
  if force or not cached or cached.scope~=scope or cached.pct~=group.buyRealmPct or GetTime()-cached.at>=3 then
    local cap,why=M.policyFloor(id,true,{realmPct=group.buyRealmPct})
    cached={pct=group.buyRealmPct,scope=scope,at=GetTime(),cap=not why and cap or 0};caps[id]=cached
  end
  return unit<=cached.cap
end
local function count(t)local n=0;for _ in pairs(t)do n=n+1 end;return n end
local function previewProfile(profile,db)
  local prefix='p@'..profile..'@userData@'
  db=db or {}
  local items=db[prefix..'items']
  if type(items)~='table' then return nil,'Load TSM once alongside Forever Market and enter the exact TSM profile name.' end
  local groups=db[prefix..'groups'] or {}
  local assignments=db[prefix..'groupOperations'] or groups
  local operations=db[prefix..'operations'] or {}
  local result={list=profile,kind='TSM profile',items={},paths={},rules={},skipped={},migration=true}
  for item,path in pairs(items) do
    local id=type(item)=='string' and tonumber(item:match('^i:(%d+)$'));path=pathOf(path)
    if id and path then
      result.paths[id]=path;result.items[id]=1
    else result.skipped[#result.skipped+1]='Unsupported item '..tostring(item) end
  end
  local seen={}
  for _,path in pairs(result.paths) do
    if not seen[path] then
      seen[path]=true
      local lineage,cur={},path
      while cur do table.insert(lineage,1,cur);cur=cur:match('^(.*)%`[^`]+$') end
      local active={}
      for _,p in ipairs(lineage) do
        local a=assignments[p]
        if type(a)=='table' then for kind,ops in pairs(a) do
          if type(ops)=='table' and ops.override~=false and (#ops>0 or ops.override==true) then active[kind]=ops end
        end end
      end
      local policy={};result.rules[path]=policy
      for kind,names in pairs(active) do
        if #names~=1 then result.skipped[#result.skipped+1]=path..' / '..kind..' / multiple operations'
        else
          local name=names[1];local op=operations[kind] and operations[kind][name]
          if type(op)=='table' then
            for k,v in pairs(op) do
              if kind=='Auctioning' and k=='postCap' and whole(op.stackSize,9999) and whole(v,9999) and tonumber(op.stackSize)*tonumber(v)<=9999 then
                policy.postCap=tonumber(op.stackSize)*tonumber(v)
              elseif kind=='Mailing' and (op.maxQtyEnabled or op.restock) and k=='target' then
                result.skipped[#result.skipped+1]=path..' / conditional mail route '..tostring(v)
              elseif not convert(kind,k,v,policy) then
                result.skipped[#result.skipped+1]=path..' / '..name..' / '..k..' = '..(type(v)=='table' and '(linked settings)' or tostring(v))
              end
            end
          else result.skipped[#result.skipped+1]=path..' / unresolved '..tostring(name) end
        end
      end
    end
  end
  if not next(result.items) then return nil,'No supported base items in this profile.' end
  if next(operations) and not next(assignments) then result.skipped[#result.skipped+1]='Operation assignments unavailable. Item groups only.' end
  table.sort(result.skipped);return result
end
function M.previewTSM(profile)return previewProfile(profile,TradeSkillMasterDB) end
function M.decodeGroup(raw,destination)
  local trimmed=raw:match('^%s*(.-)%s*$')
  if #trimmed<=180000 and (trimmed:sub(1,2)=='^1' or trimmed:match('^group:')) then
    local data={groupExport=trimmed}
    if trimmed:sub(1,2)=='^1' then
      local ok,value=ForeverMarketAceSerializer:Deserialize(trimmed)
      if not ok or type(value)~='table' or type(value.groupExport)~='string' then return end
      data=value
    end
    local prefix='p@'..destination..'@userData@'
    local path,items='',{}
    for token in data.groupExport:gmatch('[^,]+') do
      local group=token:match('^group:(.*)$')
      if group then path=group else items[token]=path end
    end
    return previewProfile(destination,{[prefix..'items']=items,[prefix..'groupOperations']=data.groupOperations,[prefix..'operations']=data.operations})
  end
  if #trimmed<24 or #trimmed>32000 or not trimmed:match('^[a-zA-Z0-9()]+$') then return end
  local packed=ForeverMarketLibDeflate:DecodeForPrint(trimmed)
  local bytes=packed and ForeverMarketLibDeflate:DecompressDeflate(packed)
  if not bytes or #bytes>1500000 then return end
  local ok,magic,ver,root,items,groups,links,ops,custom=ForeverMarketLibSerialize:Deserialize(bytes)
  if not ok or magic~='TSM_EXPORT' or ver~=2 or type(root)~='string' or type(items)~='table' or type(groups)~='table' or type(links)~='table' or type(ops)~='table' then return end
  local prefix='p@'..destination..'@userData@'
  local p=previewProfile(destination,{[prefix..'items']=items,[prefix..'groups']=groups,[prefix..'groupOperations']=links,[prefix..'operations']=ops})
  if p then
    p.root=root
    for k in pairs(type(custom)=='table' and custom or {}) do p.skipped[#p.skipped+1]='Custom price source '..tostring(k) end
  end
  return p
end
function M.applyMigration(p)
  local s=M.session();s.groupPaths=s.groupPaths or {}
  for id,path in pairs(p.paths) do
    s.groupPaths[id]=path~='' and path or p.root or p.list
    local rule=p.rules[path]
    if next(rule) then
      M.group(id) -- initialize the desk
      local groups=M.account().desk.groups
      local g=groups[id] or {margin=0,stock=0,cap=0};groups[id]=g
      for k,v in pairs(rule) do g[k]=v end
      if rule.size or rule.duration then
        local opt=M.postOptions(id);M.setPosting(id,rule.size or opt.size,rule.duration or opt.duration or 1)
      end
      if rule.shopTarget then
        local list=M.restockList();list[id]={keep=rule.shopTarget,cap=rule.cap or list[id] and list[id].cap or 0}
      end
      if rule.watchCap then M.setPriceWatch(id,rule.watchCap) end
      if rule.mailTo then M.setRoute(id,rule.mailTo,rule.mailKeep or 0) end
    end
  end
  M.invalidate()
  return ('Imported %d items. %d settings need separate review.'):format(count(p.paths),#p.skipped)
end
