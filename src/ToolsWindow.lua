local M=ForeverMarketTools
local f,field,second,hint,summary,message,pager,viewport,heading,emblem
local rows,actions,chart,nav,cards={}, {}, {},{},{}
local resultDays,invest=7,false
local mode,page,days='Basket',1,7
local preview,chain,lastQuote,compareID
local formulaSide,historyModel,historyStats="buy","median",false
local content={}
local function coins(n) return n and ForeverMarketCoins(math.floor(n)) or 'unknown' end
local function itemName(id) return C_Item.GetItemNameByID(id) or ('Item '..id) end
local function itemID(text)
  return tonumber(text:match('item:(%d+)') or text:match('^(%d+)$')) or tonumber((select(2,C_Item.GetItemInfo(text)) or ''):match('item:(%d+)'))
end
local function font(x,y,w)
  local t=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');t:SetPoint('TOPLEFT',x,y);t:SetWidth(w);t:SetJustifyH('LEFT');t:SetWordWrap(false);if t.SetHeight then t:SetHeight(18) end;if ForeverMarketTextHint then ForeverMarketTextHint(f,t) end;return t
end
local function button(x,y,w,text,fn)
  local b=CreateFrame('Button',nil,f,'UIPanelButtonTemplate');b:SetSize(w,22);b:SetPoint('TOPLEFT',x,y);b:SetText(text);b:SetScript('OnClick',fn);return b
end
local function input(x,y,w)
  local b=CreateFrame('EditBox',nil,f,'InputBoxTemplate');b:SetSize(w,22);b:SetPoint('TOPLEFT',x,y);b:SetAutoFocus(false);return b
end
local refresh,selectTab
local function add(a,b,label,fn) content[#content+1]={a=a,b=b,label=label,fn=fn} end
local function action(i,label,fn,offer)
  local button=actions[i]
  button:SetText(label);button:Show()
  button:SetScript('OnMouseDown',function(self)self.pressedOffer=offer or false end)
  button:SetScript('OnClick',function(self)
    local changed=self.pressedOffer~=nil and self.pressedOffer~=(offer or false)
    self.pressedOffer=nil
    if changed then message:SetText('Offer changed. Review the current total.');return end
    local msg=fn();refresh();if msg then ForeverMarketSetItemText(message,msg) end
  end)
end
local function plot(id)
  local series=M.historySeries(id,days);local peak,supply=1,1
  local first,last,sold
  for _,v in ipairs(series) do
    peak=math.max(peak,v.high or 0,v.ask or 0,v.sale or 0);supply=math.max(supply,v.units or 0)
    if v.ask then first=first or v;last=v end;sold=(sold or 0)+(v.sold or 0)
  end
  ForeverMarketSetItemText(summary,itemName(id)..' / green: bulk ask range   gold: paid sales   blue: units (separate scale)')
  for i,v in ipairs(series) do
    local x=27+(i-1)*560/#series
    local function bar(index,value,cap,y,height,r,g,b,base)
      if not value then return end
      local t=chart[index]
      if not t then t=f:CreateTexture(nil,'ARTWORK');chart[index]=t end
      t:ClearAllPoints();t:SetPoint('TOPLEFT',f,'TOPLEFT',x,y+math.max(3,height*value/cap))
      t:SetSize(math.max(3,490/#series),math.max(3,height*(value-(base or value))/cap))
      t:SetColorTexture(r,g,b,1);t:Show()
    end
    bar(i,v.high or v.ask,peak,-292,64,.15,.8,.5,v.ask)
    bar(30+i,v.sale,peak,-292,64,1,.8,.1)
    bar(60+i,v.units,supply,-334,42,.3,.55,.9,0)
    add(date('%b %d',v.day*86400+43200),'Bulk '..coins(v.ask)..' / paid '..coins(v.sale)..' / '..(v.units or '?')..' listed')
  end
  local change=first and last and first~=last and first.ask>0 and math.floor((last.ask/first.ask-1)*100+.5)
  local depth=first and last and first.units and last.units and first.units>0 and last.units/first.units
  message:SetText((change and ('Price '..(change>=0 and '+' or '')..change..'% / ') or '')..(depth and ('supply '..string.format('%.1fx',depth)..' / ') or '')..(first and ('First ask '..coins(first.ask)..' / latest '..coins(last.ask)) or 'No bulk quotes observed')..' / '..(sold or 0)..' units with paid invoices.')
end
local function basket()
  hint:SetText('List name at left. At right, enter an item ID and keep quantity, e.g. 2589 20.')
  M.restockList();local m=M.account().manager
  action(1,'Use list',function()
    local list=field:GetText();if list=='' or #list>48 then return 'Enter a list name.' end
    m.lists[list]=m.lists[list] or {};m.active=list;M.cancelMaterial();M.invalidate();page=1
  end)
  action(2,'Save target',function()
    local id,n=second:GetText():match('^(%d+)%s+(%d+)$');id,n=tonumber(id),tonumber(n)
    if not id or id<1 or not n or n>9999 then return 'Enter item ID and quantity (0 removes).' end
    local list=M.restockList();list[id]=n>0 and {keep=n,cap=list[id] and list[id].cap or 0} or nil;M.cancelMaterial();M.invalidate()
  end)
  action(3,'Run shopping list',function() if M.runBasket then return M.runBasket() end end)
  action(4,'Vendor deals',function() if AuctionHouseFrame and AuctionHouseFrame:IsShown() then f:Hide();M.openVendorDeals() else return 'Open the auction house.' end end)
  local trip,total,unknown,remaining=M.shoppingTrip()
  summary:SetText(m.active..' / Buyable now '..coins(total)..' / '..remaining..' units still needed after this pass')
  for i,rule in ipairs(M.basketFilters and M.basketFilters() or {}) do
    add('Search: '..(rule.term~='' and rule.term or rule.category or 'All items'),'Target '..rule.units..' each / max '..(rule.max>0 and coins(rule.max) or 'any price'),'Remove',function()return M.removeBasketFilter(i)end)
  end
  for _,r in ipairs(trip) do
    local q=M.quote;local active=q and q.trip and q.id==r.id
    local displayed=active and q.n==r.n and q.total and q.total<=r.subtotal and q.total
    local detail=active and q.total and not displayed and 'Quote changed / request again' or r.missing==0 and 'Covered' or ('Need '..r.missing..' / buy '..r.n..' / '..coins(displayed or r.subtotal))
    add(r.name,detail,r.n>0 and (displayed and 'Confirm' or active and not q.total and 'Quoting' or 'Quote'),function()
      if displayed and (M.quote~=q or q.total~=displayed) then return 'Quote changed. Review it again.' end
      if not displayed and active then if q.total then M.cancelMaterial() else return 'Waiting for live quote.' end end
      return M.buyTrip(r.id)
    end)
  end
end
local function imports()
  hint:SetText('Paste list or item group at left. Enter destination at right. Preview before applying.')
  action(1,'Preview',function()preview=M.importPreview(field:GetText(),second:GetText());preview.raw=field:GetText();page=1 end)
  action(2,'Apply',function()
    if not preview or preview.raw~=field:GetText() or preview.list~=second:GetText() then return 'Preview the current input first.' end
    local result=preview.migration and M.applyMigration(preview) or M.applyPreview(preview);preview=nil;return result
  end)
  action(3,'Read addon list',function()
    local raw,err=M.readAuctionatorList(second:GetText())
    if not raw then return err end
    field:SetText(raw);preview=M.importPreview(raw,second:GetText());preview.raw=raw;page=1
  end)
  action(4,'Read TSM profile',function()
    local p,err=M.previewTSM(second:GetText());preview=p;if p then p.raw=field:GetText();page=1 end;return err
  end)
  if preview then
    if preview.migration then hint:SetText("Review live rule decisions. Choose a price preset or recipient once for all matching groups.") end
    summary:SetText(preview.kind..' into '..preview.list..' / '..#preview.skipped..' skipped')
    if preview.migration then
      local p=preview
      action(3,'Review choices',function()p.choices=not p.choices;p.showSkipped=false;page=1 end)
      action(4,'Show skipped',function()p.showSkipped=not p.showSkipped;p.choices=false;page=1 end)
      if p.compareItem then
        local id=p.compareItem
        local rule=p.rules[p.paths[id]]
        ForeverMarketSetItemText(summary,itemName(id)..' / original TSM expression vs imported rule')
        action(3,'Back to preview',function()p.compareItem=nil;page=1;message:SetText('') end)
        actions[4]:Hide()
        local snap=ForeverMarketReadySnapshot and ForeverMarketReadySnapshot()
        local book=snap and snap.books[id]
        for _,side in ipairs({'buy','sell'}) do
          local seq=rule.program and rule.program[side]
          if seq then
            local fm,why,chosen,settings=M.importPrice(id,seq,p.localPrices)
            local ask=book and (side=='buy' and book.low or book.floorPrice and (ForeverMarketDB.matchBulk and book.floorPrice or ForeverMarketPostPrice(book.floorPrice)))
            local function decision(price)
              if not price then return 'unresolved' end
              if not ask then return 'no live ask' end
              if side=='buy' and ask>price or side=='sell' and ask<price then return 'hold' end
              return 'price qualifies'
            end
            add(side=='buy' and 'Buy ceiling' or 'Minimum post price','Live comparison price: '..coins(ask))
            for _,step in ipairs(seq) do
              local price
              if TSM_API and TSM_API.GetCustomPriceValue and step.original then
                local ok,value=pcall(TSM_API.GetCustomPriceValue,tostring(step.original),'i:'..id)
                if ok and type(value)=='number' and value>0 then price=value end
              end
              add('TSM: '..step.name,coins(price)..' / '..decision(price)..(step.originalSize and ' / stack '..tostring(step.originalSize) or ''))
            end
            add('Forever Market',coins(fm)..' / '..decision(fm)..' / '..(chosen or why or '')..(side=='sell' and ' / stack '..tostring(settings and settings.size or rule.size or 'default') or ''))
          end
        end
        if not (TSM_API and TSM_API.GetCustomPriceValue) then message:SetText('Load TSM to evaluate its original formulas. FM shows its own decisions independently.') end
        return
      end
      if p.showSkipped then
        for _,v in ipairs(p.skipped) do add('Needs a choice',v) end
        if #p.skipped==0 then add('Ready','All settings recognized.') end
        return
      end
      if next(p.marketSources) then
        add(p.localPrices and 'Local preset selected' or 'Preset suggested',p.localPrices and 'Use local median bulk asks for imported market prices.' or 'Keep original sources. Missing required evidence holds the action.',p.localPrices and 'Use original' or 'Use local',function()
          p.localPrices=not p.localPrices
        end)
      end
      for from,to in pairs(p.recipients) do
        add(to and 'Ready' or 'Needs a choice',from..' → '..(to or 'Hold outgoing mail'),'Choose',function()p.pick=from;p.choices=true;page=1 end)
      end
      if p.choices then
        local function rebuild()
          local updated=p.rebuild();updated.root=p.root;updated.raw=p.raw;updated.localPrices=p.localPrices
          for from in pairs(updated.recipients) do if p.recipients[from]~=nil then updated.recipients[from]=p.recipients[from] end end
          preview=updated;page=1
        end
        if p.formulaPick then
          local key=p.formulaPick;local sell=p.formulaChoices[key]=='sell'
          add('Keep original rule','Hold while this formula cannot be evaluated.','Hold',function()p.replacements[key]=nil;rebuild()end)
          if sell then add('Cover crafting costs','Use 120% of the current known material cost.','Select',function()p.replacements[key]='120% crafting';rebuild()end) end
          add(sell and 'Local posting floor' or 'Local buying ceiling',sell and 'Use the realm median bulk ask.' or 'Pay up to 80% of the realm median bulk ask.','Select',function()
            p.replacements[key]=sell and 'fmrealm' or '80% fmrealm';rebuild()
          end)
        elseif p.operationPick then
          local key=p.operationPick
          local function choose(name)
            p.overrides[key]=name
            rebuild()
          end
          add('Use imported order','Evaluate observable conditions. Hold if ambiguous.','Use order',function()choose(nil)end)
          for _,name in ipairs(p.operationSets[key]) do add(name,'Use only this operation for this assignment.','Select',function()choose(name)end) end
        elseif p.pick then
          for _,to in ipairs(M.destinations()) do add(to,'Use for '..p.pick,'Select',function()p.recipients[p.pick]=to;p.pick=nil;p.choices=false end) end
          add('Hold outgoing mail','Leave this route unresolved.','Hold',function()p.recipients[p.pick]=false;p.pick=nil;p.choices=false end)
        else
          for key in pairs(p.formulaChoices) do add(p.replacements[key] or 'Needs a choice',key,'Preset',function()p.formulaPick=key;page=1 end) end
          for key in pairs(p.operationSets) do add(p.overrides[key] or 'Imported order',key,'Choose',function()p.operationPick=key;page=1 end) end
          add('Review items','See the effect on each item.','Items',function()p.choices=false end)
        end
        return
      end
    elseif #preview.skipped>0 then
      action(3,preview.showSkipped and 'Show items' or 'Show skipped',function()preview.showSkipped=not preview.showSkipped;page=1 end)
      if preview.showSkipped then for _,v in ipairs(preview.skipped) do add('Needs review',v) end;return end
    end
    for _,r in ipairs(preview.filters or {}) do add('Search: '..r.term,'Qty '..r.units..' each / maximum '..coins(r.max)) end
    for id,n in pairs(preview.items) do
      local path=preview.paths and preview.paths[id]
      if path then
        local rule=preview.rules[path];local p=preview
        add(function()return itemName(id)end,function()
          local parts={path};local flags={choice=p.reviewPaths[path]}
          if rule.mailAlias and not p.recipients[rule.mailAlias] or rule.mailHold then flags.choice=true end
          for _,side in ipairs({'sell','buy'}) do
            local seq=rule.program and rule.program[side]
            if seq then
              local evidence={}
              local price,why,op=M.importPrice(id,seq,p.localPrices,evidence)
              if evidence.crafting then parts[#parts+1]='Materials '..coins(evidence.crafting) end
              for _,step in ipairs(seq) do if step.name==op and step.source then parts[#parts+1]=step.source;break end end
              local snap=ForeverMarketReadySnapshot and ForeverMarketReadySnapshot()
              local book=snap and snap.books[id]
              local ask=book and (side=='buy' and book.low or book.floorPrice and (ForeverMarketDB.matchBulk and book.floorPrice or ForeverMarketPostPrice(book.floorPrice)))
              local label=side=='sell' and 'Post floor' or 'Buy ceiling'
              local n=price and (side=='sell' and math.ceil(price) or math.floor(price))
              if not price then
                if why and why:match('^Missing db') and not p.localPrices then flags.preset=true else flags.choice=true end
              end
              local hold=n and ask and (side=='sell' and ask<n or side=='buy' and ask>n)
              parts[#parts+1]=label..' / '..(op or seq[1].name)..' / '..(n and (coins(n)..(ask and (' vs ask '..coins(ask)..(hold and ' / Hold' or ' / Price qualifies')) or ' / no current ask')) or ('Hold: '..tostring(why)))
              if next(p.marketSources) then
                local other=M.importPrice(id,seq,not p.localPrices)
                if price and other and other~=price then parts[#parts+1]=(p.localPrices and 'Original ' or 'Local ')..coins(other) end
              end
            end
          end
          for k,v in pairs(rule) do if k~='program' then parts[#parts+1]=k..' '..tostring(v) end end
          table.insert(parts,1,flags.choice and 'Needs a choice' or flags.preset and 'Preset suggested' or 'Ready')
          return table.concat(parts,' / ')
        end,'Compare',function()p.compareItem=id;page=1 end)
      else add(itemName(id),'Keep '..n) end
    end
    if #preview.skipped>0 then add('Needs review',#preview.skipped..' settings or items. Choose Show skipped for details.') end
  else summary:SetText('For TSM settings, enter the profile name at right and click Read TSM profile.') end
end
local function logistics()
  hint:SetText('Destination character at left. Optional item ID and personal keep quantity at right.')
  action(1,'Set seller',function()return M.setRoute(nil,field:GetText(),0) end)
  action(2,'Assign item',function()
    local id,n=second:GetText():match('^(%d+)%s+(%d+)$')
    if not id then return 'Enter item ID and amount to keep.' end
    return M.setRoute(tonumber(id),field:GetText(),tonumber(n))
  end)
  action(3,'Clear route',function()return M.clearRoute(tonumber(second:GetText():match('^%d+'))) end)
  action(4,'Next character',function()
    local chars=M.destinations()
    for i,to in ipairs(chars) do if to==field:GetText() then field:SetText(chars[i%#chars+1]);return end end
    field:SetText(chars[1] or '')
  end)
  local seller=M.routeSeller()
  summary:SetText('Default seller: '..(seller or 'none')..' / attach at mailbox, inspect draft, then Send.')
  for _,r in ipairs(M.shipments()) do add(itemName(r.id),r.n..' to '..r.to,'Attach',function()return M.attachShipment(r) end) end
  if M.bankQueue then
    for _,r in ipairs(M.bankQueue()) do
      add(itemName(r.id),r.label..' / '..r.n,'Withdraw',function()return M.withdraw(r)end)
    end
  end
  for id,n in pairs(M.materials()) do
    local need=math.max(0,n-M.bagCount(id))
    for _,s in ipairs(M.sources(id)) do if not M.bankOpen and not M.guildOpen and need>0 and s.own and s.place=='bank' then add(itemName(id),'Withdraw '..math.min(s.n,need)..' from bank');break end end
  end
  for id,n in pairs(M.protectedStock()) do add(itemName(id),'Keep '..n..' in bags') end
end
local function chains()
  hint:SetText('Enter finished item ID at left and quantity at right. Prices use observed market depth.')
  action(1,'Compare',function()
    local id,n=itemID(field:GetText()),tonumber(second:GetText())
    if not id or not n or n<1 or n>999 or n~=math.floor(n) then return 'Enter an item and 1–999 units.' end
    local cost,steps,limited=M.supplyPlan(id,n)
    chain={id=id,n=n,cost=cost,steps=steps};page=1
    if limited then return 'Search limit reached. Displaying the available plan.' end
    if not cost then return 'Incomplete prices for this plan.' end
  end)
  action(2,'Save plan',function()
    if not chain or not chain.cost then return 'Compare a priced plan first.' end
    return M.saveSupplyPlan(chain)
  end)
  chain=chain or M.savedSupplyPlan()
  ForeverMarketSetItemText(summary,chain and (itemName(chain.id)..' x '..chain.n..' / planned cash '..coins(chain.cost)..' / buy finished '..coins(M.cost(chain.id,chain.n))) or 'Visit each crafter’s profession window to record learned recipes.')
  for i,s in ipairs(chain and chain.steps or {}) do add(i..'. '..s.action..' '..itemName(s.id),s.n..' / '..(s.detail or '')..(s.cost and (' '..coins(s.cost)) or '')) end
end
local showFarmRoutes=false
local function farming()
  action(2,showFarmRoutes and 'What to farm' or 'Routes by gold/hour',function()
    showFarmRoutes=not showFarmRoutes;page=1
  end)
  if not showFarmRoutes then
    hint:SetText('Ranked by estimated AH return per item. Gathering speed and buyer demand can vary.')
    local targets=M.farmTargets()
    summary:SetText(#targets>0 and 'Item / estimated net per unit / gathering lead' or 'No recent prices for farmable items. Run Market Scan at an auctioneer.')
    for _,target in ipairs(targets) do
      add(itemName(target.id),coins(target.net)..' each / '..target.lead,'History',function()
        selectTab('History',target.id)
      end)
    end
    return
  end
  hint:SetText('Enter a farm or route name at left. Start when you begin looting; stop when done.')
  action(1,M.account().farmActive and 'Stop session' or 'Start session',function()
    return M.account().farmActive and M.farmStop() or M.farmStart(field:GetText())
  end)
  summary:SetText('Routes ranked by current AH value per hour. Incomplete prices reduce the estimate.')
  local ranked=M.farmRouteRanks()
  for _,r in ipairs(ranked) do
    add(r.name,(r.priced>0 and coins(r.hour) or 'Unknown')..' / hour  |  '..math.floor(r.seconds/60)..' min  |  '..r.runs..' runs','Details',function()
      local methods={};for method in pairs(r.methods) do methods[#methods+1]=method end;table.sort(methods)
      return (r.zone or 'Zone unrecorded')..' / '..(#methods>0 and table.concat(methods,', ') or 'Mixed loot')..' / '..r.priced..' of '..r.units..' units priced / paid '..coins(r.paid)..' / vendor '..coins(r.vendor)
    end)
  end
  if #ranked==0 then add('Record your first route','Start a session, gather loot, then stop to see your hourly estimate.') end
end
local function openAH(key)
  if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then return 'Visit an auctioneer first.' end
  if not ForeverMarketPages or not ForeverMarketPages[key] then return 'This page is still loading.' end
  f:Hide();ForeverMarketPages[key]()
end
local function shoppingLists()
  M.restockList()
  local m=M.account().manager
  hint:SetText('Choose a saved list to check its missing items at the auction house.')
  summary:SetText('Shopping lists')
  action(1,'Edit active list',function()selectTab('Basket')end)
  action(2,'Sell from bags',function()return openAH('ForeverMarketSell')end)
  local names={};for name in pairs(m.lists) do names[#names+1]=name end;table.sort(names)
  for _,name in ipairs(names) do
    local n=0;for _ in pairs(m.lists[name]) do n=n+1 end
    add(name,n..' exact item targets','Shop',function()
      m.active=name;M.invalidate();selectTab('Basket');return M.runBasket()
    end)
  end
end
local function references()
  hint:SetText('Paste a price pack at left, or enter an item ID at right and ask your guild.')
  summary:SetText('Reference prices only. Run your own scan for trading advice.')
  action(1,'Copy local prices',function()
    local pack,why=M.exportReferencePack()
    if not pack then return why end
    field:SetText(pack);field:SetFocus();field:HighlightText();return 'Copy the selected pack to share.'
  end)
  action(2,'Import pack',function()
    local msg=M.importReferencePack(field:GetText());page=1;return msg
  end)
  action(3,'Ask guild',function()
    local raw=second:GetText()
    return M.requestGuildPrice(tonumber(raw:match('item:(%d+)') or raw))
  end)
  action(4,ForeverMarketDB.shareGuildPrices and 'Guild replies: on' or 'Guild replies: off',function()
    ForeverMarketDB.shareGuildPrices=not ForeverMarketDB.shareGuildPrices
  end)
  local raw=second:GetText()
  local id=tonumber(raw:match('item:(%d+)') or raw)
  local shared=M.sharedReferences(id)
  for _,r in ipairs(shared) do
    local source=r.regional and 'TSM region' or r.starter and 'bundled realm scan' or 'peer realm scan'
    add(function()return itemName(r.id)end,coins(r.price)..' / '..source..' / '..date('%b %d',r.at),r.regional and 'Sales' or nil,function()
      return ('TradeSkillMaster regional sample / %.1f%% sale rate / %.2f sold per day'):format(r.rate*100,r.volume)
    end)
  end
  if #shared==0 then add('No reference prices','Clear the item filter, ask your guild, paste a pack, or run Market Scan.') end
end
local function formulaEditor()
  hint:SetText('Left: item ID or imported group path. Right: price formula in copper, e.g. 80% fmmedian.')
  local target=field:GetText()
  local ids={}
  local id=tonumber(target:match('item:(%d+)') or target:match('^(%d+)$'))
  if id and id>0 then ids[1]=id elseif target~='' then
    for k,path in pairs(M.session().groupPaths or {}) do
      if path==target or path:sub(1,#target+1)==target..string.char(96) then ids[#ids+1]=k end
    end
    table.sort(ids)
  end
  local source=second:GetText();local tree,err=M.customProgram(source)
  summary:SetText((formulaSide=='buy' and 'Buying ceiling' or 'Posting floor')..' / '..#ids..' items / '..(tree and 'Preview below' or tostring(err)))
  action(1,formulaSide=='buy' and 'Buy (selected)' or 'Buy',function()formulaSide='buy';page=1 end)
  action(2,formulaSide=='sell' and 'Sell (selected)' or 'Sell',function()formulaSide='sell';page=1 end)
  action(3,'Preview',function()page=1 end)
  action(4,'Apply formula',function()
    if field:GetText()~=target or second:GetText()~=source then return 'Preview your edits before applying.' end
    if target:match('^user_') then return M.setNamedFormula(target,source) end
    if #ids==0 then return 'Enter an item ID or an existing group path.' end
    return M.savePriceProgram(ids,formulaSide,source)
  end)
  if tree then for _,k in ipairs(ids) do
    add(function()return itemName(k)end,function()
      local value,why=M.importPrice(k,tree,false)
      return value and value>0 and coins(value) or 'Hold / '..(why or 'nonpositive price')
    end)
  end end
  if #ids==0 then
    add('Named formula','Enter user_name at left and an expression at right, then Apply.')
    add('Ordered rules','Separate alternatives with ;  A false condition tries the next rule.')
    for key,expr in pairs(M.account().namedFormulas or {}) do
      add(key,expr,'Edit',function()field:SetText(key);second:SetText(expr);page=1 end)
    end
    add('Inventory condition','iflt(fmbags, 20, 80% fmmedian, 1c)');add('Common sources','fmrealm, fmmedian, fmema, fmfiltered, fmbags, fmsold, fmexpires') end
end
local function home()
  hint:SetText('Choose what you came to do. Buying and posting always require your click.')
  summary:SetText('At the auction house')
  action(1,'Selling session',function()selectTab('Sell session')end)
  action(2,'Price watches',function()selectTab('Watches')end)
  action(3,'Realm coverage',function()selectTab('Realm coverage')end)
  action(4,'Scan outcomes',function()selectTab('Scan results')end)
  add('Disenchant deals','Compare auction prices with your observed material yields.','Compare',function()selectTab('Conversions')end)
  local s=ForeverMarketPostingPreview and ForeverMarketPostingPreview()
  local deals=M.visibleDeals
  local count=deals and GetTime()-deals.at<60 and deals.scope==ForeverMarketVenueRealm() and deals.count
  add('Saved shopping lists','Choose a list and start checking it in one click.','Shop',function()selectTab('Shopping lists')end)
  add('Shared realm prices','Exchange dated reference prices with other players.','Open',function()selectTab('Shared prices')end)
  add('Custom price rules','Preview a formula for an item or group.','Edit',function()selectTab('Formula editor')end)
  add('Sell from my bags',s and (s.ready..' stacks ready / '..s.checking..' checking prices') or 'Check prices, choose quantities, then post.','Sell',function()return openAH('ForeverMarketSell')end)
  add('Find a deal',count and count>0 and (count..' recently verified deals. Check the current offer.') or 'Set your fund and return target, then start a scan.','Buy',function()return openAH('ForeverMarketBuy')end)
  add('Review my auctions','Check undercuts, returns and expected proceeds.','Review',function()
    if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then return 'Visit an auctioneer first.' end
    f:Hide();if M.openAuctionReview then M.openAuctionReview() else M.openManager() end
  end)
  add('See my results','See what you spent and how much gold came back.','Results',function()selectTab('Results')end)
  if M.saleTotals and AuctionHouseFrame and AuctionHouseFrame:IsShown() then local _,mail,_,_,_,pending=M.saleTotals()
    if (mail or 0)>0 or (pending or 0)>0 then add('Collect sale mail',coins(mail or 0)..' last seen in mail / '..coins(pending or 0)..' estimated pending') end
  end
  add('Group rules','Preview a selling or stocking preset for your items.','Presets',function()selectTab('Rule presets')end)
  add('Buy supplies','Set the quantity you want to keep for each item.','Basket',function()selectTab('Basket')end)
end
local function postingPreview()
  hint:SetText('Review the current sell list. Return to Market Sell to post a stack.')
  action(1,'Back to Sell',function()return openAH('ForeverMarketSell')end)
  local s,why=ForeverMarketPostingPreview()
  if not s then summary:SetText(why);return end
  summary:SetText(('%d ready stacks / %d held / %d checking / gross %s'):format(s.ready,s.hold,s.checking,coins(s.gross)))
  for _,r in ipairs(s.rows) do add(r.name,r.state) end
end
local function results()
  hint:SetText('Choose purchases from the last 7 or 30 days. Figures update when you collect sale mail.')
  action(1,resultDays==7 and '7 days (selected)' or '7 days',function()resultDays=7;page=1 end)
  action(2,resultDays==30 and '30 days (selected)' or '30 days',function()resultDays=30;page=1 end)
  action(3,invest and 'Flips' or 'Flips (selected)',function()invest=false;page=1 end)
  action(4,invest and 'Investments (selected)' or 'Investments',function()invest=true;page=1 end)
  local r=M.tradeResults(resultDays,invest)
  summary:SetText(r.count..' purchases / '..r.paid..' units paid')
  if r.count==0 then
    message:SetText('')
    add('No purchases yet',invest and 'Purchases made through Invest will appear here.' or 'Use Market Buy at an auctioneer to start tracking flips.')
    return
  end
  local values={coins(r.spent),coins(r.profit),coins(r.open),r.delay and (math.floor(r.delay/3600)..'h '..math.floor(r.delay%3600/60)..'m') or 'No payout yet'}
  for i,card in ipairs(cards) do card:Show();card.value:SetText(values[i]) end
  message:SetText('Forecast on paid units '..coins(r.forecast)..' / first payout recorded for '..r.timed..' purchases.')

  local names={};for name in pairs(r.items) do names[#names+1]=name end
  table.sort(names,function(a,b)if r.items[a].profit==r.items[b].profit then return a<b end return r.items[a].profit>r.items[b].profit end)
  for _,name in ipairs(names) do local item=r.items[name];add(name,coins(item.profit)..' profit / '..coins(item.open)..' open') end
end
refresh=function()
  if not f or not f:IsShown() then return end
  content={};for _,c in ipairs(cards) do c:Hide() end;for _,t in pairs(chart) do t:Hide() end;for _,b in ipairs(actions) do b:Hide() end
  local special=mode=='Run detail' or mode=='Conversion detail' or mode=='Comparison' or mode=='Rule presets' or mode=='Watches' or mode=='Conversions' or mode=='Realm coverage' or mode=='Scan results' or mode=='Sell session'
  local inputs=mode~='Shopping lists' and (mode~='Farming' or showFarmRoutes) and mode~='Results' and mode~='Home' and mode~='Preview' and (not special or mode=='Watches' or mode=='Comparison' or mode=='Rule presets')
  field:SetShown(inputs);if viewport then viewport:SetShown(inputs) end;second:SetShown(inputs and mode~='Farming')
  if heading then
    heading:SetShown(not inputs);emblem:SetShown(not inputs)
    heading:SetText(mode=='Shopping lists' and 'Saved shopping lists' or mode=='Farming' and 'What to farm' or special and mode or mode=='Home' and 'Auction house' or mode=='Results' and 'Trading results' or 'Posting preview')
    emblem:SetTexture(mode=='Preview' and 'Interface\\Icons\\INV_Letter_15' or mode=='Home' and 'Interface\\Icons\\INV_Misc_Coin_01' or 'Interface\\Icons\\INV_Misc_Book_09')
  end
  if special then
    M.renderSessionPage(mode,{hint=hint,summary=summary,field=field,second=second,coins=coins,name=itemName,itemID=itemID,add=add,action=action,openAH=openAH,page=selectTab,compareID=compareID,presetInput=field:GetText(),
      offer=function(id,cap)
        if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then return 'Visit an auctioneer first.' end
        f:Hide();M.openOffer(id,cap)
      end,
      review=function()
        if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then return 'Visit an auctioneer first.' end
        f:Hide();M.openAuctionReview()
      end})
  elseif mode=='Formula editor' then formulaEditor() elseif mode=='Shared prices' then references() elseif mode=='Shopping lists' then shoppingLists()
  elseif mode=='Home' then home() elseif mode=='Preview' then postingPreview() elseif mode=='Results' then results() elseif mode=='Basket' then basket() elseif mode=='Import' then imports() elseif mode=='Mail & bank' then logistics()
  elseif mode=='Supply plan' then chains() elseif mode=='Farming' then farming()
  else
    hint:SetText('Item ID or name at left. Daily price and supply use separate scales; empty days have no observation.')
    action(1,'7 days',function()days=7;page=1 end);action(2,'30 days',function()days=30;page=1 end)
    action(3,historyStats and 'Show chart' or 'Price analysis',function()historyStats=not historyStats;page=1 end)
    local id=itemID(field:GetText())
    if not id then summary:SetText('Enter an item to view its market history.')
    elseif not historyStats then plot(id)
    else
      local models={'median','mean','ema','filtered'}
      action(4,'Model: '..historyModel,function()
        for i,key in ipairs(models) do if key==historyModel then historyModel=models[i%#models+1];break end end
      end)
      local s=M.priceStatistics(id,days)
      if not s then summary:SetText('No observed bulk-price days in this period.')
      else
        ForeverMarketSetItemText(summary,itemName(id)..' / '..s.n..' observed days / '..historyModel..' '..coins(s[historyModel]))
        add('Middle 50% of daily asks',coins(s.q1)..' to '..coins(s.q3))
        add('Outlier-filtered mean',coins(s.filtered)..' / '..s.excluded..' days outside IQR fences')
        local maxCount=math.max(unpack(s.bins))
        for i,n in ipairs(s.bins) do
          local low=s.low+(i-1)*s.width
          if low<=s.high then add(coins(low)..' - '..coins(math.min(s.high,low+s.width-1)),string.rep('=',math.floor(n/maxCount*22+.5))..'  '..n..' days') end
        end
      end
    end
  end
  local history=mode=='History' and not historyStats
  local cardView=mode=='Results' and cards[1] and cards[1]:IsShown()
  local per=history and 3 or cardView and 5 or 8
  local pages=math.max(1,math.ceil(#content/per));page=math.max(1,math.min(page,pages));pager:SetText(page..' / '..pages)
  for i,row in ipairs(rows) do
    local y=-(cardView and 236 or 161)-(i-1)*24
    if row.y~=y then
      row.y=y;row.left:ClearAllPoints();row.right:ClearAllPoints();row.btn:ClearAllPoints()
      row.left:SetPoint('TOPLEFT',16,y);row.right:SetPoint('TOPLEFT',210,y);row.btn:SetPoint('TOPLEFT',599,y+5)
      if row.bg then row.bg:ClearAllPoints();row.bg:SetPoint('TOPLEFT',5,y+5) end
    end
    if row.bg then row.bg:SetShown(i<=per) end
    local d=i<=per and content[(page-1)*per+i]
    ForeverMarketSetItemText(row.left,d and (type(d.a)=='function' and d.a() or d.a) or '');ForeverMarketSetItemText(row.right,d and (type(d.b)=='function' and d.b() or d.b) or '')
    row.btn:SetShown(d and d.label and true or false)
    if d and d.label then row.btn:SetText(d.label);row.btn:SetScript('OnClick',function()local msg=d.fn();refresh();if msg then ForeverMarketSetItemText(message,msg) end end) end
  end
end
selectTab=function(tab,value)
  if M.monitorPrices then M.monitorPrices(false) end
  M.cancelMaterial();mode=tab;page=1;
  for key,b in pairs(nav) do if b.SetEnabled then b:SetEnabled(key~=tab) end end
  if tab=='History' then historyStats=false end
  if tab=='Farming' then showFarmRoutes=false end
  preview=nil;chain=nil;field:SetText(value and tostring(value) or '');second:SetText(tab=='Supply plan' and '1' or '')
  if tab=='Comparison' or tab=='Run detail' or tab=='Conversion detail' then compareID=value;field:SetText('') end
  if tab=='Basket' then M.restockList();field:SetText(M.account().manager.active) end
  if tab=='Import' then second:SetText('Imported') end
  field:SetMultiLine(tab=='Shared prices' or tab=='Import' or tab=='Comparison');if viewport then viewport:SetVerticalScroll(0) end;field:ClearFocus();second:ClearFocus()
  message:SetText('');refresh()
  if tab=='Import' and value then field:SetFocus();field:HighlightText() end
end
function M.openTools(tab,value)
  if not f then
    f=CreateFrame('Frame','ForeverMarketToolsWindow',UIParent,'BasicFrameTemplateWithInset')
    f:SetSize(695,398);f:SetPoint('CENTER');f:SetFrameStrata('DIALOG');f:SetClampedToScreen(true);f:EnableMouse(true);f:SetMovable(true);f:RegisterForDrag('LeftButton')
    f:SetScript('OnDragStart',f.StartMoving);f:SetScript('OnDragStop',f.StopMovingOrSizing)
    if f.TitleText then f.TitleText:SetText('Forever Market') end
    if ForeverMarketPanelArt then ForeverMarketPanelArt(f) end
    for i,tabName in ipairs({'Home','Results','Basket','Mail & bank','Supply plan','History','Farming','Import'}) do
      nav[tabName]=button(12+(i-1)*84,-29,82,tabName,function()selectTab(tabName)end)
    end
    hint=font(16,-56,662);field=input(18,-77,334);second=input(367,-77,286)
    if field.SetParent and field.SetTextInsets and f.GetWidth then
      viewport=CreateFrame('ScrollFrame',nil,f)
      viewport:SetPoint('TOPLEFT',18,-76);viewport:SetSize(334,26)
      field:SetParent(viewport);field:ClearAllPoints();field:SetSize(334,22);field:SetTextInsets(6,6,2,2)
      viewport:SetScrollChild(field)
      field:SetScript('OnCursorChanged',function(_,x,y,w,h)
        local bottom=math.max(0,-y+h);local offset=viewport:GetVerticalScroll()
        if bottom>offset+26 then viewport:SetVerticalScroll(bottom-26) elseif -y<offset then viewport:SetVerticalScroll(math.max(0,-y)) end
      end)
      viewport:EnableMouseWheel(true);viewport:SetScript('OnMouseWheel',function(self,d)self:SetVerticalScroll(math.max(0,math.min(self:GetVerticalScrollRange(),self:GetVerticalScroll()-d*18)))end)
    end
    heading=f:CreateFontString(nil,'OVERLAY','GameFontNormalLarge');heading:SetPoint('TOPLEFT',54,-78);heading:SetWidth(610);heading:SetJustifyH('LEFT');heading:SetWordWrap(false)
    emblem=f:CreateTexture(nil,'ARTWORK');emblem:SetPoint('TOPLEFT',16,-75);emblem:SetSize(27,27)
    for i=1,4 do actions[i]=button(12+(i-1)*164,-111,156,'',function()end) end
    summary=font(16,-138,662);message=font(16,-354,664)
    local metrics={{'Purchase cost','INV_Misc_Coin_01'},{'Profit collected','INV_Misc_Coin_02'},{'Stock at cost','INV_Misc_Bag_10'},{'First payout','INV_Misc_PocketWatch_01'}}
    for i,m in ipairs(metrics) do
      local c=CreateFrame('Frame',nil,f,'InsetFrameTemplate')
      c:SetPoint('TOPLEFT',14+(i-1)*167,-159);c:SetSize(163,61)
      local icon=c:CreateTexture(nil,'ARTWORK');icon:SetTexture('Interface\\Icons\\'..m[2]);icon:SetSize(18,18);icon:SetPoint('TOPLEFT',8,-8)
      local title=c:CreateFontString(nil,'OVERLAY','GameFontNormalSmall');title:SetPoint('TOPLEFT',32,-9);title:SetWidth(123);title:SetWordWrap(false);title:SetJustifyH('LEFT');title:SetText(m[1])
      c.value=c:CreateFontString(nil,'OVERLAY','GameFontHighlight');c.value:SetPoint('TOPLEFT',9,-34);c.value:SetWidth(145);c.value:SetJustifyH('LEFT');c.value:SetWordWrap(false)
      if ForeverMarketTextHint then ForeverMarketTextHint(c,c.value) end
      c:Hide();cards[i]=c
    end
    for i=1,8 do local y=-161-(i-1)*24
      local stripe=ForeverMarketRowArt and ForeverMarketRowArt(f,y+5,675,i)
      rows[i]={bg=stripe,left=font(16,y,190),right=font(210,y,388),btn=button(599,y+5,78,'',function()end)}
    end
    button(18,-373,74,'Previous',function()page=page-1;refresh()end);pager=font(99,-378,55)
    button(154,-373,75,'Next',function()page=page+1;refresh()end)
    button(563,-372,100,'Refresh',refresh);field:SetScript('OnEnterPressed',function(self)self:ClearFocus();refresh()end)
    f:SetScript('OnHide',function()if M.monitorPrices then M.monitorPrices(false) end;if M.quote and (M.quote.trip or M.quote.watch) then M.cancelMaterial() end end)
    local t,sellUpdate=0,0
    f:SetScript('OnUpdate',function(_,dt)
      if mode=='Shared prices' and M.peerPricesChanged then M.peerPricesChanged=nil;refresh() end
      if mode=='Realm coverage' and M.coverageTick() then refresh() end
      if mode=='Basket' and M.stepBasket then M.stepBasket() end
      t=t+dt;if t<.4 then return end;t=0
      if mode=='Watches' then
        M.watchTick()
        local q=M.quote and M.quote.watch and M.quote
        if q and GetTime()-q.at>=9 then M.cancelMaterial();q=nil end
        if q and q.total and not q.counted and q.total<=q.max then
          local rule=M.session().watches[q.id]
          if rule then rule.quoted=(rule.quoted or 0)+1 end
          if q.snipe and PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then PlaySound(SOUNDKIT.READY_CHECK) end
          q.counted=true
        end
        local state=q and (q.total or 'checking')
        if M.watchChanged or state~=lastQuote then M.watchChanged=false;lastQuote=state;refresh() end
      end
      if mode=='Sell session' and not (IsMouseButtonDown and IsMouseButtonDown()) and (M.mailChanged or GetTime()>=sellUpdate) then
        M.mailChanged=false;sellUpdate=GetTime()+1;refresh()
      end
      if mode=='Mail & bank' and M.logisticsDirty then M.logisticsDirty=false;refresh() end
      local q=M.quote;local key=q and q.trip and (q.total or 'pending')
      if mode=='Basket' and (key~=lastQuote or M.tripDirty) then lastQuote=key;M.tripDirty=nil;refresh() end
    end)
    if UISpecialFrames then table.insert(UISpecialFrames,'ForeverMarketToolsWindow') end
  end
  if UIParent and UIParent.GetWidth and f.SetScale then
    f:SetScale(math.min(1,(UIParent:GetWidth()-16)/695,(UIParent:GetHeight()-16)/398))
  end
  f:Show();f:Raise();selectTab(tab or 'Basket',value)
end
