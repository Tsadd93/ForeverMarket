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
  if kind=='Auctioning' and key=='keepQuantity' and whole(v,9999) then r.reserve=tonumber(v);return true
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

  end
end
local caps={}
function M.groupPurchaseAllowed(id,group,unit,force)
  if not group then return true end
  local rules=M.importedRules(group)
  if rules and rules.buy then
    local ceiling=M.liveImportPrice(id,rules,'buy',force)
    if not ceiling or unit>math.floor(ceiling) then return false end
  end
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
function M.operationFields(id,group,force)
  local rules=M.importedRules(group)
  if not rules or not rules.sell or #rules.sell<2 then return end
  local _,why,name=M.liveImportPrice(id,rules,'sell',force)
  if not why then for _,op in ipairs(rules.sell) do if op.name==name then return op.settings end end end
end
function M.importedRules(group)
  return group and (group.program or group.programID and (M.account().rulePrograms or {})[group.programID])
end
local recent={}
function M.liveImportPrice(id,rules,side,force)
  local cache=recent[id] or {};recent[id]=cache
  local v=cache[side];local scope=M.scope()
  if not force and v and v.rules==rules and v.scope==scope and GetTime()-v.at<2 then return v.price,v.why,v.name end
  local price,why,name=M.importPrice(id,rules[side],rules[side].localPrices)
  cache[side]={rules=rules,scope=scope,at=GetTime(),price=price,why=why,name=name}
  return price,why,name
end
local function previewProfile(profile,db,custom,overrides,replacements)
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
  result.marketSources={};result.recipients={};result.operationSets={};result.reviewPaths={}
  result.overrides=overrides or {}
  result.replacements={};result.formulaChoices={}
  for k,v in pairs(replacements or (M.session().formulaPresets or {})[profile] or {}) do result.replacements[k]=v end
  result.rebuild=function()return previewProfile(profile,db,custom,result.overrides,result.replacements) end
  result.localPrices=(M.session().sourcePresets or {})[profile]==true
  local aliases={}
  for k,v in pairs(custom or db[prefix..'customPriceSources'] or db['g@ @userData@customPriceSources'] or db['g@ @customPriceSources'] or {}) do
    if type(k)=='string' then aliases[k:lower()]=type(v)=='table' and (v.string or v.value or v.priceString) or v end
  end
  local seen,compiled={},{}
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
      local skipStart=#result.skipped
      local policy={};result.rules[path]=policy
      for kind,names in pairs(active) do
        if #names>1 then
          local key=kind..' / '..table.concat(names,' → ')
          result.operationSets[key]=names
          local chosen=result.overrides[key]
          if chosen then
            for _,name in ipairs(names) do if name==chosen then names={chosen};break end end
          end
        end
        local fields=({Auctioning={minPrice='auctioningopmin',normalPrice='auctioningopnormal',maxPrice='auctioningopmax'},Shopping={maxPrice='shoppingopmax'},Sniper={belowPrice='sniperopmax'}})[kind]
        local first=operations[kind] and operations[kind][names[1]]
        if fields and first then for field,key in pairs(fields) do local tree=M.compilePrice(first[field] and tostring(first[field]),aliases);if tree then policy.program=policy.program or {};policy.program.sources=policy.program.sources or {};policy.program.sources[key]=tree end end end
        local side=kind=='Auctioning' and 'sell' or kind=='Shopping' and 'buy'
        local priceKey=side=='sell' and 'minPrice' or 'maxPrice'
        if side and #names==0 then
          policy.program=policy.program or {};policy.program[side]={{name=kind,error='No assigned operation'}}
        elseif side then
          policy.program=policy.program or {}
          local sequence={};policy.program[side]=sequence
          local baseline=operations[kind] and operations[kind][names[1]] or {}
          local conflict
          for _,name in ipairs(names) do
            local other=operations[kind] and operations[kind][name] or {}
            for _,fields in ipairs({baseline,other}) do
              for k in pairs(fields) do
                local x,y=baseline[k],other[k]
                if type(x)=='table' and not next(x) then x=nil end
                if type(y)=='table' and not next(y) then y=nil end
                if k~=priceKey and x~=y then
                  local adjustable=side=='sell' and (k=='keepQuantity' or k=='duration' or k=='stackSize' or k=='postCap')
                  if not adjustable then conflict=k end
                end
              end
            end
          end
          for _,opName in ipairs(names) do
            local op=operations[kind] and operations[kind][opName]
            local expr=op and op[priceKey]
            local tree,refs
            if type(expr)=='number' then expr=tostring(expr) end
            if type(expr)=='string' and compiled[expr] then tree,refs=unpack(compiled[expr])
            else tree,refs=M.compilePrice(expr,aliases);if tree then compiled[expr]={tree,refs} end end
            local err
            if not tree and type(expr)=='string' then
              local key=kind..' / '..expr;result.formulaChoices[key]=side
              local replacement=result.replacements[key]
              if replacement then expr=replacement;tree,refs=M.compilePrice(expr) end
            end
            if not tree then err=refs else
              for key in pairs(refs) do if M.marketRuleSources[key] then result.marketSources[key]=true end end
            end
            if conflict then err='Conflicting operation settings: '..conflict;tree=nil end
            if op then
              for _,k in ipairs({'ignorePlayer','ignoreFactionrealm','ignoreRealm','relationships'}) do
                local x=op[k]
                if type(x)=='table' and next(x) then err='Review operation restriction '..k;tree=nil end
              end
            end
            if err then result.skipped[#result.skipped+1]=path..' / '..opName..' / '..err end
            local settings={}
            if #names>1 and side=='sell' and op then
              for _,k in ipairs({'keepQuantity','duration','stackSize'}) do
                if op[k]~=nil and not convert(kind,k,op[k],settings) then err='Unsupported '..k;tree=nil end
              end
              if op.postCap~=nil then
                local cap,size=whole(op.postCap,9999),whole(op.stackSize,9999)
                if cap and size and cap*size<=9999 then settings.postCap=cap*size else tree=nil;err='Unsupported posted quantity' end
              end
            end
            if #names>1 and #sequence+1<#names and tree and not (type(tree)=='table' and tree[1]:sub(1,2)=='if' and #tree==4) then
              tree=nil;err='Overlapping operations require a priority choice'
              result.skipped[#result.skipped+1]=path..' / '..opName..' / '..err
            end
            sequence[#sequence+1]={name=opName,original=op and op[priceKey],originalSize=op and op.stackSize,source=expr,tree=tree,error=err,settings=settings}
          end
        end
        if #names~=1 and (not side or #names==0) then
          if not side then result.skipped[#result.skipped+1]=path..' / '..kind..' / multiple operations';if kind=='Mailing' then policy.mailHold=true end end
        else
          local name=names[1];local op=operations[kind] and operations[kind][name]
          if type(op)=='table' then
            for k,v in pairs(op) do
              if #names>1 and side=='sell' and (k=='postCap' or k=='duration' or k=='keepQuantity' or k=='stackSize') then
                -- These settings follow the operation that matched this item.
              elseif side and k==priceKey then
                -- The ordered program owns this price, including invalid or absent prices.
              elseif kind=='Mailing' and k=='target' and type(v)=='string' and not op.maxQtyEnabled and not op.restock then
                policy.mailAlias=v
                local map=M.session().mailMappings or {}
                local found=false
                for _,to in ipairs(M.destinations()) do if to==(map[v] or v) then found=to;break end end
                result.recipients[v]=found
              elseif kind=='Auctioning' and k=='postCap' and whole(op.stackSize,9999) and whole(v,9999) and tonumber(op.stackSize)*tonumber(v)<=9999 then
                policy.postCap=tonumber(op.stackSize)*tonumber(v)
              elseif kind=='Mailing' and (op.maxQtyEnabled or op.restock) and k=='target' then
                policy.mailHold=true;result.skipped[#result.skipped+1]=path..' / conditional mail route '..tostring(v)
              elseif not convert(kind,k,v,policy) then
                result.skipped[#result.skipped+1]=path..' / '..name..' / '..k..' = '..(type(v)=='table' and '(linked settings)' or tostring(v))
              end
            end
          else result.skipped[#result.skipped+1]=path..' / unresolved '..tostring(name);if kind=='Mailing' then policy.mailHold=true end end
        end
      end
      result.reviewPaths[path]=#result.skipped>skipStart
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
    return previewProfile(destination,{[prefix..'items']=items,[prefix..'groupOperations']=data.groupOperations,[prefix..'operations']=data.operations},data.customSources or data.customPriceSources)
  end
  if #trimmed<24 or #trimmed>32000 or not trimmed:match('^[a-zA-Z0-9()]+$') then return end
  local packed=ForeverMarketLibDeflate:DecodeForPrint(trimmed)
  local bytes=packed and ForeverMarketLibDeflate:DecompressDeflate(packed)
  if not bytes or #bytes>1500000 then return end
  local ok,magic,ver,root,items,groups,links,ops,custom=ForeverMarketLibSerialize:Deserialize(bytes)
  if not ok or magic~='TSM_EXPORT' or ver~=2 or type(root)~='string' or type(items)~='table' or type(groups)~='table' or type(links)~='table' or type(ops)~='table' then return end
  local prefix='p@'..destination..'@userData@'
  local p=previewProfile(destination,{[prefix..'items']=items,[prefix..'groups']=groups,[prefix..'groupOperations']=links,[prefix..'operations']=ops},custom)
  if p then
    p.root=root

  end
  return p
end
function M.applyMigration(p)
  local s=M.session();s.groupPaths=s.groupPaths or {}
  local a=M.account()
  a.rulePrograms=a.rulePrograms or {}
  local programs={}
  s.sourcePresets=s.sourcePresets or {};s.sourcePresets[p.list]=p.localPrices==true or nil
  s.formulaPresets=s.formulaPresets or {};s.formulaPresets[p.list]=p.replacements
  s.mailMappings=s.mailMappings or {}
  for key,to in pairs(p.recipients) do s.mailMappings[key]=to or nil end
  for id,path in pairs(p.paths) do
    s.groupPaths[id]=path~='' and path or p.root or p.list
    local rule=p.rules[path]
    if next(rule) then
      M.group(id) -- initialize the desk
      local groups=M.account().desk.groups
      local g=groups[id] or {margin=0,stock=0,cap=0};groups[id]=g
      for k,v in pairs(rule) do if k~='program' then g[k]=v end end
      if rule.program then
        local prior=M.importedRules(g) or {}
        if not programs[path] then programs[path]={} end
        local key=programs[path][prior] or (not next(prior) and programs[path].empty)
        if not key then
          a.ruleSequence=(a.ruleSequence or 0)+1;key=a.ruleSequence
          for _,side in ipairs({'buy','sell'}) do if rule.program[side] then rule.program[side].localPrices=p.localPrices==true end end
          local sources={};for k,v in pairs(prior.sources or {}) do sources[k]=v end;for k,v in pairs(rule.program.sources or {}) do sources[k]=v end
          local combined={sources=sources,buy=rule.program.buy or prior.buy,sell=rule.program.sell or prior.sell}
          a.rulePrograms[key]=combined;programs[path][prior]=key;if not next(prior) then programs[path].empty=key end
        end
        g.program=nil;g.programID=key
        if rule.program.buy then g.cap=0;g.buyRealmPct=nil end
        if rule.program.sell then g.realmPct=nil;g.craftPct=nil;g.fixedFloor=nil end
      end
      if rule.mailAlias then
        local to=p.recipients[rule.mailAlias]
        g.mailHold=not to or M.setRoute(id,to,rule.mailKeep or 0)~='Saved destination '..to
      end
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
  local used={};for _,g in pairs(a.desk and a.desk.groups or {}) do if g.programID then used[g.programID]=true end end
  for k in pairs(a.rulePrograms) do if not used[k] then a.rulePrograms[k]=nil end end
  M.invalidate()
  return ('Imported %d items. %d settings need separate review.'):format(count(p.paths),#p.skipped)
end
