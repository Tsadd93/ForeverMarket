local prefix = "ForeverMarketV1"
local chat = C_ChatInfo
local getMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
local version = getMetadata and getMetadata("ForeverMarket", "Version")
local function parts(value)
  if type(value) ~= "string" or #value > 17 then return end
  local a,b,c = value:match("^(%d+)%.(%d+)%.(%d+)$")
  if not a or #a > 5 or #b > 5 or #c > 5 then return end
  return tonumber(a),tonumber(b),tonumber(c)
end
local function newer(candidate, baseline)
  local a,b,c = parts(candidate)
  local x,y,z = parts(baseline)
  if not a or not x then return false end
  if a ~= x then return a > x end
  if b ~= y then return b > y end
  return c > z
end
if not parts(version) then return end

local pending, lastSent = {}, {}
local channels = {GUILD=true, PARTY=true, RAID=true, INSTANCE_CHAT=true}
local function available(channel)
  if channel == "GUILD" then return IsInGuild() end
  if channel == "INSTANCE_CHAT" then return LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) end
  if channel == "RAID" then return IsInRaid() end
  return IsInGroup() and not IsInRaid()
end
local function schedule(channel, kind)
  local wait=math.max(0,30-(GetTime()-(lastSent[channel] or -1000)))
  if pending[channel] or (wait>0 and kind=="Q") then return end
  local ticket={}
  pending[channel]=ticket
  C_Timer.After(wait+1+math.random()*2,function()
    if pending[channel]~=ticket then return end
    pending[channel]=nil
    if available(channel) then
      lastSent[channel]=GetTime()
      chat.SendAddonMessage(prefix,kind..version,channel)
    end
  end)
end
local function poll()
  if not chat or not chat.SendAddonMessage or not C_Timer then return end
  if IsInGuild() then schedule("GUILD","Q") end
  for _,channel in ipairs({"INSTANCE_CHAT","RAID","PARTY"}) do
    if available(channel) then schedule(channel,"Q");break end
  end
end
local function latest()
  local known=ForeverMarketDB and ForeverMarketDB.peerVersion
  if newer(known,version) then return known end
end
local function notice(v)
  print("|cffffd100Forever Market|r "..v.." is available. You have "..version..". Update through WoWUp or github.com/drixthegamer/ForeverMarket/releases.")
end
function ForeverMarketVersionStatus()
  if latest() then notice(latest())
  else print("Forever Market "..version.." installed. No newer version reported by guild or group members yet.") end
  poll()
end
if not chat or not chat.RegisterAddonMessagePrefix or not C_Timer then return end
local frame=CreateFrame("Frame")
for _,event in ipairs({"PLAYER_LOGIN","CHAT_MSG_ADDON","GROUP_ROSTER_UPDATE","PLAYER_GUILD_UPDATE"}) do frame:RegisterEvent(event) end
local ready=false
frame:SetScript("OnEvent",function(_,event,received,msg,channel)
  if event=="PLAYER_LOGIN" then
    chat.RegisterAddonMessagePrefix(prefix)
    ready=true
    poll()
  elseif ready and event=="CHAT_MSG_ADDON" then
    if received~=prefix or not channels[channel] or type(msg)~="string" then return end
    local kind,v=msg:match("^([QV])([%d%.]+)$")
    if not parts(v) then return end
    if newer(v,latest() or version) then
      ForeverMarketDB=ForeverMarketDB or {}
      ForeverMarketDB.peerVersion=v
      notice(v)
    end
    if kind=="Q" and newer(version,v) then schedule(channel,"V")
    elseif kind=="V" and not newer(version,v) then pending[channel]=nil end
  elseif ready then poll() end
end)
