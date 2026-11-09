local playeractionpicker
local playercontroller
local combat

local function CheckMod(name)
  for k,v in pairs(GLOBAL.ModManager.mods) do
    if v.modinfo.name == name then
      return true
    end
  end
end

local function IsDefaultScreen()
  local screen = GLOBAL.TheFrontEnd:GetActiveScreen()
  local screenName = screen and screen.name or ""
  return screenName:find("HUD") ~= nil and not CheckMod("ReForged")
end

local function Hit(target,px,pz,mod)
  local function cb()
    if mod=="mouse" then
      GLOBAL.SendRPCToServer(GLOBAL.RPC.LeftClick, GLOBAL.ACTIONS.ATTACK.code, px, pz, target, nil, 10, true)
    elseif mod=="keyboard" then
      GLOBAL.SendRPCToServer(GLOBAL.RPC.AttackButton,target,true)
    end
  end
  local function DoAction()
    if playercontroller:CanLocomote() then
      local action = GLOBAL.BufferedAction(GLOBAL.ThePlayer, target, GLOBAL.ACTIONS.ATTACK)
      action.preview_cb = cb()
      playercontroller:DoAction(action)
    else
      cb()
    end
  end
  DoAction()
end

local Cheatthread
local function Start()
  if not IsDefaultScreen() then return end
  if GLOBAL.ThePlayer == nil then return end
  if GLOBAL.ThePlayer.Cheatthread ~= nil then return end
  playeractionpicker = GLOBAL.ThePlayer.components.playeractionpicker
  playercontroller = GLOBAL.ThePlayer.components.playercontroller
  combat = GLOBAL.ThePlayer.replica.combat
  local target
  local function HitAndRun()
    if target ~= nil 
    and target:IsValid() 
    and target.replica.health ~= nil 
    and not target.replica.health:IsDead() 
    and combat:CanTarget(target) then
      local px,py,pz = GLOBAL.ThePlayer:GetPosition():Get()
      Hit(target,px,pz,"mouse")
    else
      local retarget=combat:GetTarget()
      local isctrlpressed=GLOBAL.TheInput:IsControlPressed(GLOBAL.CONTROL_FORCE_ATTACK)
      target=playercontroller:GetAttackTarget(isctrlpressed,retarget,retarget~=nil)
    end
  end
  if Cheatthread==nil then
    Cheatthread=GLOBAL.ThePlayer:DoPeriodicTask(GLOBAL.FRAMES,HitAndRun)
  end
end

local function Stop()
  if IsDefaultScreen() and Cheatthread ~= nil then
    Cheatthread:Cancel()
    Cheatthread=nil
  end
end

local function GetKeyFromConfig(config)
  local key = GetModConfigData(config, true)
  if type(key) == "string" and GLOBAL:rawget(key) 
  then key = GLOBAL[key] end
  return type(key) == "number" and key or -1
end

if GetKeyFromConfig("Attack_key") then
  GLOBAL.TheInput:AddKeyDownHandler(GetKeyFromConfig("Attack_key"), Start)
  GLOBAL.TheInput:AddKeyUpHandler(GetKeyFromConfig("Attack_key"), Stop)
end


 -- Don't Attack Wall

local comb_rep = GLOBAL.require "components/combat_replica"
local old_IsAlly = comb_rep.IsAlly
function comb_rep:IsAlly(guy,...)
  if guy:HasTag("wall") then
    return true
  end
  return old_IsAlly(self,guy,...)
end