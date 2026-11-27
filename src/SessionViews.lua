local M=ForeverMarketTools
-- The common Tools window owns navigation, input, tooltips and pagination.
function M.renderSessionPage(mode,ui)
  local add,action,coins,name=ui.add,ui.action,ui.coins,ui.name
  local hint,summary=ui.hint,ui.summary
  local field,second=ui.field,ui.second
  if mode=='Watches' then
    hint:SetText('Enter an item name, ID or link at left and the most you will pay per unit at right.')
    action(1,'Save ceiling',function()return M.setPriceWatch(ui.itemID(field:GetText()),M.goldInput(second:GetText()))end)
    action(2,M.priceMonitorActive() and 'Stop watching' or 'Start watching',function()
      if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then return 'Visit an auctioneer first.' end
      M.monitorPrices(not M.priceMonitorActive())
    end)
    summary:SetText(M.priceMonitorActive() and 'Checking listed asks. Close this page to stop.' or 'Select an item below to edit its ceiling. Enter zero to remove it.')
    action(4,M.session().snipe and 'Quick quotes: on' or 'Quick quotes: off',function()
      M.session().snipe=not M.session().snipe
    end)
    local ids={};for id in pairs(M.session().watches) do ids[#ids+1]=id end;table.sort(ids)
    for _,id in ipairs(ids) do
      local rule=M.session().watches[id]
      add(name(id),('Ceiling %s / %s'):format(coins(rule.cap),rule.at and ((rule.ask and coins(rule.ask) or 'No listing')..' at '..date('%H:%M',rule.at)) or 'Awaiting check')..(rule.checks and (' / '..(rule.quoted or 0)..' of '..rule.checks..' checks within ceiling') or ''),'Edit',function()
        field:SetText(tostring(id));second:SetText(rule.cap..'c')
      end)
    end
    local q=M.quote and M.quote.watch and M.quote
    local preview=M.watchPreview
    local auction=q and q.auctionID
    local shown=q and q.total
    if preview then summary:SetText('|cffffd100Commodity found|r / '..name(preview.id)..' / '..coins(preview.price)..' each') end
    if q and shown then summary:SetText('|cffffd100Live quote|r for one '..(q.link or name(q.id))..' / '..coins(shown)..' total') end
    action(3,shown and 'Confirm purchase' or preview and 'Get firm quote' or 'Check live quote',function()
      if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then return 'Visit an auctioneer first.' end
      local id=q and q.snipe and q.id or preview and preview.id or ui.itemID(field:GetText());local rule=M.session().watches[id]
      if not rule then return 'Select a watched item first.' end
      if preview and (preview~=M.watchPreview or GetTime()-preview.at>=9) then return 'Listing changed. Review the next offer.' end
      if not preview and not (q and q.snipe) then M.monitorPrices(false) end
      if shown then
        if q~=M.quote or q.total~=shown or q.auctionID~=auction or q.id~=id or shown>rule.cap then return 'Quote changed. Review the current total.' end
        local ok,why=M.confirmMaterial();return why or (ok and 'Purchase requested.' or 'Quote expired.')
      end
      if q and GetTime()-q.at<9 and q.id==id then return 'Waiting for the auction house.' end
      local ok,why=M.startMaterial(id,{n=1,cap=preview and math.min(preview.price,rule.cap) or rule.cap,key=rule.key})
      if not ok then return why end
      if preview then M.watchPreview=nil;M.quote.snipe=true end
      M.quote.watch=true;rule.checks=(rule.checks or 0)+1
      return 'Checking one unit against your ceiling.'
    end,shown and (q.id..'/'..(q.auctionID or 0)..'/'..shown..'/'..q.at) or preview)
  elseif mode=='Sell session' then
    local s=M.session()
    hint:SetText('Resume your selling session here. Your protected items and reserves apply on Market Sell.')
    action(4,M.sellingTimer and 'Finish timed pass' or 'Time a selling pass',M.timeSelling)
    local stages={'Post ready stacks','Review held items','Review undercuts','Collect returned mail','Relist from bags'}
    action(1,'Previous step',function()s.stage=math.max(1,s.stage-1)end)
    action(2,s.stage==5 and 'Finish session' or 'Next step',function()s.stage=s.stage%5+1 end)
    action(3,'Go to step',function()
      if s.stage==4 then return 'Visit a mailbox and collect returned auctions. Reopen /fm session to relist.' end
      if s.stage==3 then return ui.review() end
      local why=ui.openAH('ForeverMarketSell')
      if not why then M.openTools('Sell session') end
      return why
    end)
    summary:SetText(('Step %d of 5 / %s'):format(s.stage,stages[s.stage]))
    if s.sellTrials and s.sellTrials[1] then
      local t=s.sellTrials[1];add('Last timed selling pass',t.elapsed..'s / '..t.posts..' confirmed posts / '..(t.counted and (t.clicks..' AH or mailbox clicks') or 'click counts unavailable'))
    end
    local snapshot,why=ForeverMarketPostingPreview()
    if snapshot then
      add('Ready to post',snapshot.ready..' stacks / gross '..coins(snapshot.gross))
      add('Worth reviewing',snapshot.hold..' held / '..snapshot.checking..' still checking')
      for _,row in ipairs(snapshot.rows) do
        if (s.stage==1 or s.stage==5) and row.ready then add(row.name,row.state,'Post',row.post)
        elseif s.stage==2 and not row.ready then add(row.name,row.state) end
      end
    else add('Bag prices',why or 'Open Market Sell to check your bags.') end
    if s.stage==4 and MailFrame and MailFrame:IsShown() then
      for _,row in ipairs(M.returnLetters()) do add(row.name,row.n..' returned / ready to collect','Collect',function()return M.collectReturn(row)end) end
      return
    end
    local returns=M.account().returns or {}
    for key,letters in pairs(returns) do
      local id,n=key:match('^(%d+)/(%d+)$')
      if id then add(name(tonumber(id)),(letters*tonumber(n))..' units in last-seen returned mail') end
    end
  elseif mode=='Realm coverage' then
    hint:SetText('See how much evidence your own scans have collected on this market.')
    local c=M.marketCoverage()
    action(1,'Open Market Scan',function()return ui.openAH('ForeverMarketScanTab')end)
    summary:SetText(c and not c.done and 'Reading local prices…' or c and (c.items..(c.snapshot and ' base items in the latest snapshot' or ' base items observed in the last 14 days')) or 'Visit an auctioneer and run a market scan to build local prices.')
    if c then
      local keys={};for k in pairs(c.categories) do keys[#keys+1]=k end;table.sort(keys)
      for _,k in ipairs(keys) do local v=c.categories[k];add(k,v.all..' priced / '..v.repeatDays..' with at least 3 bulk-price days in 14') end
    end
  elseif mode=='Conversions' then
    hint:SetText('Compare one purchase with vendoring, reposting or selling its disenchant materials.')
    summary:SetText('Positive disenchant spreads from your observed yields. Inspect the live price before buying.')
    local snap=ForeverMarketReadySnapshot()
    if not snap then add('No recent auction snapshot','Run Market Scan at the auction house.');return end
    local list={}
    for id in pairs(M.account().manager and M.account().manager.samples or {}) do
      local book=snap.books[id]
      if book then
        local net,count,parts=M.disenchantValue(id)
        if net and net>book.low then list[#list+1]={id=id,net=net,count=count,parts=parts,price=book.low,gain=net-book.low} end
      end
    end
    table.sort(list,function(a,b)return a.gain>b.gain or a.gain==b.gain and a.id<b.id end)
    for _,r in ipairs(list) do
      add(name(r.id),'Buy '..coins(r.price)..' / estimated disenchant gain '..coins(r.gain)..' / '..r.count..' samples','Details',function()ui.page('Conversion detail',r.id)end)
    end
    if #list==0 then add('No observed profitable conversions','Disenchant items to record yields, then scan the AH for material prices.') end
  elseif mode=='Conversion detail' then
    local id=ui.compareID;local snap=ForeverMarketReadySnapshot()
    local book=snap and snap.books[id]
    if not book then summary:SetText('Refresh the market snapshot.');return end
    local net,count,parts=M.disenchantValue(id);local resale=M.prices(id)
    hint:SetText('Estimated proceeds per item, including the configured auction fee and loss allowance.')
    summary:SetText(name(id))
    add('Buy one',coins(book.low),'Review',function()return ui.offer(id,book.low)end)
    add('Vendor',coins(select(11,C_Item.GetItemInfo(id))))
    add('Repost',coins(resale and (ForeverMarketSaleNet(resale)-ForeverMarketDepositLoss(1))))
    add('Disenchant',coins(net)..' / '..(count or 0)..' observed results')
    add('Expected materials',parts or 'Missing material prices')
    add('Estimated gain',coins(net and net-book.low))
  elseif mode=='Run detail' then
    local f=ForeverMarketTradingFund();local id=ui.compareID;local r=(f.sessions or {})[id]
    if not r then summary:SetText('Select a completed pass in Scan outcomes.');return end
    local o=M.runOutcomes(f)[id] or {spent=0,profit=0,open=0}
    hint:SetText('Payouts count when collected during the first seven days after each purchase.')
    summary:SetText(date('%b %d %H:%M',r.at)..' / '..r.state)
    add('Starting cash',coins(r.cash)..' / '..(r.target/100)..'% target')
    add('Live checks',r.checked..' checked / '..r.missed..' unanswered')
    add('Deals found',r.hits..' / first deal '..(r.first and math.floor(r.first)..'s' or 'none'))
    add('Elapsed time',r.elapsed..' seconds')
    add('Spent',coins(o.spent))
    add('Collected profit',coins(o.profit))
    add('Stock at cost',coins(o.open))
    if r.ids then add('Same-list comparison',#r.ids..' sampled items','Compare',function()ui.page('Comparison',id)end) end
  elseif mode=='Rule presets' then
    hint:SetText('Enter one item ID or a saved group path at left. Preview a preset before applying.')
    local presets={{'Keep supplies',{reserve=5}},{'Limit stock',{stock=5,postCap=5}},{'Cover craft cost',{craftPct=120}}}
    local s=M.session()
    local id=ui.itemID(field:GetText());local ids={}
    if id and id>0 then ids[1]=id else
      local path=field:GetText()
      for k,p in pairs(s.groupPaths or {}) do if p==path or p:sub(1,#path+1)==path..string.char(96) then ids[#ids+1]=k end end
    end
    table.sort(ids)
    for i,p in ipairs(presets) do action(i,p[1],function()M.selectedPreset=i end) end
    local choice=presets[M.selectedPreset or 1]
    summary:SetText(choice[1]..' / '..#ids..' matching items / existing unrelated rules are kept')
    for _,k in ipairs(ids) do
      local changes={}
      local g=M.group(k) or {}
      for key,v in pairs(choice[2]) do changes[#changes+1]=key..' '..(g[key] or 0)..' to '..v end
      add(name(k),table.concat(changes,', '))
    end
    action(4,'Apply preset',function()
      if #ids==0 or field:GetText()~=ui.presetInput then return 'Refresh the preview for your current item or group.' end
      for _,k in ipairs(ids) do
        M.group(k);local groups=M.account().desk.groups;local g=groups[k] or {stock=0,margin=0,cap=0}
        local updated={};for key,v in pairs(g) do updated[key]=v end
        for key,v in pairs(choice[2]) do updated[key]=v end;groups[k]=updated
      end
      M.invalidate();return 'Applied '..choice[1]..' to '..#ids..' items.'
    end)
    if #ids==0 then for _,p in pairs(s.groupPaths or {}) do
      if not ids[p] then ids[p]=true;add(p,'Imported group','Select',function()field:SetText(p)end) end
    end end
  elseif mode=='Comparison' then
    local f=ForeverMarketTradingFund();local r=(f.sessions or {})[ui.compareID]
    if not r or not r.ids then summary:SetText('Complete a benchmark first.');return end
    hint:SetText('Paste the other addon’s qualifying item IDs at left (or none). Enter elapsed seconds at right.')
    action(1,'Record comparison',function()
      local seconds=tonumber(second:GetText());local raw=field:GetText()
      if not seconds or seconds<0 or seconds>86400 or raw=='' then return 'Enter results and elapsed seconds.' end
      local allowed,other={},{}
      for _,id in ipairs(r.ids) do allowed[id]=true end
      if raw:lower()~='none' then
        for token in raw:gmatch('[^,%s]+') do
          local id=tonumber(token:match('^i:(%d+)$') or token)
          if not allowed[id] then return 'Item outside this benchmark: '..token end
          other[id]=true
        end
        if not next(other) then return 'Enter IDs or none.' end
      end
      r.comparison={elapsed=seconds,found=other}
    end)
    action(2,'Copy search list',function()
      local names={};for _,id in ipairs(r.ids) do names[#names+1]='"'..name(id)..'"' end
      field:SetText(table.concat(names,'\n'));field:SetFocus();field:HighlightText()
      return 'Copy the selected list. Replace it with qualifying IDs when recording the comparison.'
    end)
    summary:SetText('Compare '..#r.ids..' sampled items / fund '..coins(r.cash)..' / target '..(r.target/100)..'%')
    if r.comparison then
      add('Elapsed time',r.elapsed..'s Forever Market / '..r.comparison.elapsed..'s comparison')
      for _,id in ipairs(r.ids) do
        local fm=(r.found or {})[id];local other=r.comparison.found[id]
        if fm or other then add(name(id),fm and other and 'Both found' or fm and 'Forever Market only' or 'Comparison only / review listing timing') end
      end
    end
    for _,id in ipairs(r.ids) do add(name(id),'Comparison item ID '..id) end
  elseif mode=='Scan results' then
    hint:SetText('Each pass includes zero-deal runs. Seven-day outcomes use collected payouts and confirmed losses.')
    local f=ForeverMarketTradingFund();local ids={}
    for id in pairs(f.sessions or {}) do ids[#ids+1]=id end;table.sort(ids,function(a,b)return a>b end)
    summary:SetText(#ids..' recorded passes / spendable fund at scan start')
    for i,g in ipairs({1,5,50}) do action(i,'Test '..g..' gold',function()
      local why=ui.openAH('ForeverMarketBuy')
      if why then return why end
      ForeverMarketBenchmark(g)
    end) end
    action(4,'Test all three',function()
      local why=ui.openAH('ForeverMarketBuy')
      if why then return why end
      ForeverMarketBenchmark('all')
    end)
    local outcomes=M.runOutcomes(f)
    for _,id in ipairs(ids) do
      local r=f.sessions[id];local o=outcomes[id] or {profit=0,open=0,spent=0}
      add(date('%b %d %H:%M',r.at)..' / '..coins(r.cash),r.hits..' deals / spent '..coins(o.spent)..' / profit '..coins(o.profit),'Details',function()ui.page('Run detail',id)end)
    end
    if #ids==0 then add('No completed passes yet','Set a fund and scan in Market Buy. Try 1g, 5g and 50g on separate passes.') end
  end
end
function M.runOutcomes(f)
  local results={}
  for _,r in ipairs(f.flips or {}) do
    if r.run then
      local o=results[r.run] or {profit=0,open=0,spent=0};results[r.run]=o
      local basis=math.floor(r.cost*(r.weekPaid or 0)/r.n)
      o.profit=o.profit+(r.weekNet or 0)-basis-(r.weekLost or 0)
      o.spent=o.spent+r.cost;o.open=o.open+r.cost-basis
    end
  end
  return results
end
