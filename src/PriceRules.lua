local M=ForeverMarketTools
local functions={min={1,32},max={1,32},avg={1,32},first={1,32},ifgt={3,4},ifgte={3,4},iflt={3,4},iflte={3,4},ifeq={3,4}}
local market={dbmarket=true,dbhistorical=true,dbregionmarketavg=true,dbregionhistorical=true,dbminbuyout=true}
local tsmOnly={dbregionsaleavg=true,avgbuy=true,avgsell=true,smartavgbuy=true,vendorbuy=true,destroy=true,matprice=true,
  auctioningopmin=true,auctioningopnormal=true,auctioningopmax=true,shoppingopmax=true,sniperopmax=true}
local native={fmrealm=true,crafting=true,vendorsell=true,itemlevel=true}
local units={g=10000,s=100,c=1}
-- Parse a bounded expression language. Imported text is never evaluated as Lua.
function M.compilePrice(source,aliases)
  local seen,count,refs={},0,{}
  local parse
  parse=function(raw,depth)
    if type(raw)~='string' or #raw>1024 or depth>24 then error('Invalid or oversized formula',0) end
    local str=raw:lower();local pos=1
    local function space()pos=str:find('%S',pos) or #str+1 end
    local function char()space();return str:sub(pos,pos) end
    local function take(c)if char()==c then pos=pos+1;return true end end
    local expr
    local function atom(level)
      count=count+1;if count>256 or level>32 then error('Formula too complex',0) end
      if take('-') then return {'*',-1,atom(level+1)} end
      if take('(') then local n=expr(1,level+1);if not take(')') then error('Missing closing parenthesis',0) end;return n end
      local token=str:match('^(%d+%.?%d*)',pos) or str:match('^(%.%d+)',pos)
      if token then
        pos=pos+#token;local value=tonumber(token);local unit=char()
        if units[unit] then
          value=value*units[unit];pos=pos+1
          while true do space();local n,u=str:match('^(%d+)%s*([gsc])',pos);if not n then break end
            local _,endpos=str:find('^%d+%s*[gsc]',pos);pos=endpos+1;value=value+tonumber(n)*units[u]
          end
        end
        if not value or value>1e14 then error('Value out of range',0) end
        if take('%') then return {'*',value/100,atom(level+1)} end
        return value
      end
      local id=str:match('^([%a_][%w_]*)',pos)
      if not id then error('Expected a number or price source',0) end
      pos=pos+#id
      if take('(') then
        local spec=functions[id];if not spec then error('Unsupported function '..id,0) end
        local n={id}
        repeat n[#n+1]=expr(1,level+1) until not take(',')
        if not take(')') or #n-1<spec[1] or #n-1>spec[2] then error('Invalid arguments for '..id,0) end
        return n
      end
      if aliases and aliases[id] then
        if seen[id] then error('Circular custom source '..id,0) end
        seen[id]=true;local n=parse(aliases[id],depth+1);seen[id]=nil;return n
      end
      if not market[id] and not tsmOnly[id] and not native[id] then error('Unknown price source '..id,0) end
      refs[id]=true;return id
    end
    local precedence={['+']=1,['-']=1,['*']=2,['/']=2}
    expr=function(minimum,level)
      local n=atom(level);local op=char()
      while (precedence[op] or 0)>=minimum do
        pos=pos+1;n={op,n,expr(precedence[op]+1,level+1)};op=char()
      end
      return n
    end
    local tree=expr(1,depth);if char()~='' then error('Unexpected text at '..pos,0) end
    return tree
  end
  local ok,tree=pcall(parse,source,1);if not ok then return nil,tree end
  return tree,refs
end
function M.evaluatePrice(tree,read)
  if type(tree)=='number' then return tree end
  if type(tree)=='string' then return read(tree) end
  local op=tree[1]
  if op=='first' or op=='min' or op=='max' or op=='avg' then
    local result,count=nil,0;local why
    for i=2,#tree do local n,err=M.evaluatePrice(tree[i],read);why=why or err
      if n~=nil then
        if op=='first' then return n end
        result=op=='avg' and ((result or 0)+n) or op=='max' and math.max(result or n,n) or math.min(result or n,n);count=count+1
      end
    end
    if not result then return nil,why or 'No usable price' end
    return op=='avg' and result/count or result
  end
  local a,ea=M.evaluatePrice(tree[2],read);local b,eb=M.evaluatePrice(tree[3],read)
  if a==nil or b==nil then return nil,ea or eb or 'Missing price' end
  if op:sub(1,2)=='if' then
    local yes=op=='ifgt' and a>b or op=='ifgte' and a>=b or op=='iflt' and a<b or op=='iflte' and a<=b or op=='ifeq' and a==b
    if yes then return M.evaluatePrice(tree[4],read) end
    if tree[5] then return M.evaluatePrice(tree[5],read) end
    return nil,'Condition false'
  end
  if op=='/' and b==0 then return nil,'Division by zero' end
  local v=op=='+' and a+b or op=='-' and a-b or op=='*' and a*b or a/b
  if v~=v or math.abs(v)>1e14 then return nil,'Value out of range' end
  return v
end
function M.ruleSource(id,key,useLocal)
  if key=='fmrealm' then
    local n,why=M.policyFloor(id,true,{realmPct=100});if not why and n>0 then return n end
  elseif key=='crafting' then
    local n,why=M.policyFloor(id,true,{craftPct=100});if not why and n>0 then return n end
  elseif key=='vendorsell' or key=='itemlevel' then
    local _,_,_,level,_,_,_,_,_,_,vendor=C_Item.GetItemInfo(id)
    local n=key=='vendorsell' and vendor or key=='itemlevel' and level
    if type(n)=='number' and n>0 then return n end
  elseif market[key] or tsmOnly[key] then
    if useLocal and market[key] then
      local n,why=M.policyFloor(id,true,{realmPct=100});if not why and n>0 then return n end
    elseif TSM_API and TSM_API.GetCustomPriceValue then
      local ok,n=pcall(TSM_API.GetCustomPriceValue,key,'i:'..id)
      if ok and type(n)=='number' and n>0 then return n end
    end
  end
  return nil,'Missing '..key
end
function M.importPrice(id,program,useLocal,evidence)
  local values={}
  for _,op in ipairs(program) do
    if not op.tree then return nil,op.error or 'Unresolved operation' end
    local n,why=M.evaluatePrice(op.tree,function(key)
      if not values[key] then values[key]={M.ruleSource(id,key,useLocal)} end
      if evidence then evidence[key]=values[key][1] end
      return values[key][1],values[key][2]
    end)
    if n and n>0 then return n,nil,op.name,op.settings end
    if why~='Condition false' then return nil,why or 'Price must be positive',op.name end
  end
  return nil,'No operation applies'
end
M.marketRuleSources=market
