local handler, timers, sent, lines
local now, installed = 100, "0.10.1"
local function loadAddon()
  timers,sent,lines={},{},{}
  print=function(line) lines[#lines+1]=line end
  C_AddOns={GetAddOnMetadata=function() return installed end}
  C_ChatInfo={RegisterAddonMessagePrefix=function() end,SendAddonMessage=function(p,m,c) sent[#sent+1]={p,m,c} end}
  C_Timer={After=function(_,callback) timers[#timers+1]=callback end}
  CreateFrame=function() return {RegisterEvent=function() end,SetScript=function(_,_,f) handler=f end} end
  IsInGuild=function() return true end
  IsInGroup=function() return false end
  IsInRaid=IsInGroup
  GetTime=function() return now end
  dofile("src/Version.lua")
  handler(nil,"PLAYER_LOGIN")
end
local function receive(msg,channel,prefix)
  handler(nil,"CHAT_MSG_ADDON",prefix or "ForeverMarketV1",msg,channel or "GUILD")
end
local function flush() local q=timers;timers={};for _,f in ipairs(q) do f() end end
loadAddon()
flush()
assert(#sent==1 and sent[1][2]=="Q0.10.1")
for _,v in ipairs({"Q0.10.0","V0.9.99","V0.10.1","V999999.1.1","V0.11.0-alpha","garbage"}) do receive(v) end
receive("V8.8.8","SAY");receive("V8.8.8","GUILD","wrong")
assert(#lines==0)
receive("V0.10.2");receive("V0.10.2");receive("V0.10.1")
assert(#lines==1 and ForeverMarketDB.peerVersion=="0.10.2")
loadAddon();receive("V0.10.2");assert(#lines==0)
flush();now=200;receive("Q0.9.9");flush()
assert(sent[#sent][2]=="V0.10.1")
receive("Q0.11.0");assert(#lines==1)
installed="0.11.0";loadAddon();ForeverMarketVersionStatus()
assert(#lines==1 and lines[1]:find("No newer",1,true))
