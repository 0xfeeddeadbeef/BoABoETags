--[[

Copyright 2022 (c) Giorgi Chakhidze

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software,
and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions
of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED
TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.

]]--

-- Based on BindsWhen addon by Phanx ( https://github.com/phanx-wow/BindsWhen/blob/master/LICENSE.md )

------------------------------------------------------------------------
-- Text to show for each binding type

local BoA = "|cffe6cc80BoA|r" -- heirloom item color
local BoE = "|cff1eff00BoE|r" -- uncommon item color
local BoP = false -- not displayed

------------------------------------------------------------------------
-- Map tooltip text to display text

local textForBind = {
    [ITEM_ACCOUNTBOUND]        = BoA,
    [ITEM_BNETACCOUNTBOUND]    = BoA,
    [ITEM_BIND_TO_ACCOUNT]     = BoA,
    [ITEM_BIND_TO_BNETACCOUNT] = BoA,
    [ITEM_BIND_ON_EQUIP]       = BoE,
    [ITEM_BIND_ON_USE]         = BoE,
    [ITEM_SOULBOUND]           = BoP,
    [ITEM_BIND_ON_PICKUP]      = BoP,
}

------------------------------------------------------------------------
-- Which binding types can change during gameplay (BoE)

local temporary = {
    [BoE] = true,
}

-- Keep a cache of which items are BoA or BoE

local textForItem = {}

------------------------------------------------------------------------
-- Use _DebugLog addon for debugging

--[[
local function DebugPrintf(...)
    local status, res = pcall(format, ...)
    if status then
        if DLAPI then DLAPI.DebugLog('BindsWhenII', res) end
    end
end
]]--

------------------------------------------------------------------------
-- Clear cached BoE items when confirming to bind something

local function ClearTempCache()
    --DebugPrintf('WARN~Clearing the temporary cache.')
    for id, text in pairs(textForItem) do
        if ( temporary[text] ) then
            textForItem[id] = nil
        end
    end
end

hooksecurefunc('BindEnchant', ClearTempCache)
-- This does not work. Switched to EQUIP_BIND_CONFIRM event handling instead.
-- hooksecurefunc('ConfirmBindOnUse', ClearTempCache)

------------------------------------------------------------------------
-- Tooltip for scanning for Binds on X text

local scanTip = CreateFrame('GameTooltip', 'BindsWhenScanTooltip')
for i = 1, 6 do
    local L = scanTip:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
    scanTip:AddFontStrings(L, scanTip:CreateFontString(nil, 'OVERLAY', 'GameFontNormal'))
    scanTip[i] = L
end

local eventFrame = CreateFrame('Frame', 'BindsWhenEventFrame')
eventFrame:RegisterEvent('EQUIP_BIND_CONFIRM')
eventFrame:SetScript('OnEvent', function(self, event, ...)
    if ( event == 'EQUIP_BIND_CONFIRM' ) then
        ClearTempCache()
    end
end)

------------------------------------------------------------------------
-- Keep a cache of which items are BoA or BoE

local function GetBindText(arg1, arg2)
    local link, setTooltip, onlyBoA
    if ( arg1 == 'player' ) then
        link = GetInventoryItemLink(arg1, arg2)
        setTooltip = scanTip.SetInventoryItem
    elseif arg2 then
        link = GetContainerItemLink(arg1, arg2)
        setTooltip = scanTip.SetBagItem
    else
        link = arg1
        setTooltip = scanTip.SetHyperlink
        onlyBoA = true
    end
    if ( not link ) then
        return
    end

    local item = onlyBoA and link or (arg1 .. arg2 .. link)
    local text = textForItem[item]
    if text then
        return text
    end

    scanTip:SetOwner(WorldFrame, 'ANCHOR_NONE')
    setTooltip(scanTip, arg1, arg2)
    for i = 1, 6 do
        local bind = scanTip[i]:GetText()
        -- Ignore recipes
        if ( bind and strmatch(bind, USE_COLON) ) then
            break
        end
        local text = bind and textForBind[bind]
        if text then
            -- Don't save BoE text for non-recipe hyperlinks, eg. Bagnon cached items
            if ( onlyBoA and text ~= BoA ) then
                return
            end
            textForItem[item] = text
            return text
        end
    end
    textForItem[item] = false
end

------------------------------------------------------------------------
-- Add text string to an item button

local function SetItemButtonBindType(button, text)
    local bindsOnText = button.bindsOnText
    if ( not text and not bindsOnText ) then return end
    if ( not text ) then
        return bindsOnText:SetText("")
    end
    if ( not bindsOnText ) then
        -- See ItemButtonTemplate.Count @ ItemButtonTemplate.xml#13
        bindsOnText = button:CreateFontString(nil, 'ARTWORK', 'GameFontNormalOutline')
        bindsOnText:SetPoint('BOTTOMRIGHT', -5, 2)
        button.bindsOnText = bindsOnText
    end
    bindsOnText:SetText(text)
end

------------------------------------------------------------------------
-- Update default bag and bank frames

local function BindsWhen_OnUpdate(frame)
    local bag = frame:GetID()
    for _, button in frame:EnumerateValidItems() do
        local slot = button:GetID()
        local text = not button.Count:IsShown() and GetBindText(bag, slot)
        SetItemButtonBindType(button, text)
    end
    --DebugPrintf('OK~Invoked BindsWhen_OnUpdate for bag '..bag)
end

if ( _G.ContainerFrame_Update ) then
    hooksecurefunc('ContainerFrame_Update', BindsWhen_OnUpdate)
else
    -- Can't use ContainerFrameUtil_EnumerateContainerFrames because it depends on the combined bags setting
    hooksecurefunc(ContainerFrameCombinedBags, 'UpdateItems', BindsWhen_OnUpdate)
    -- Hook each bag's update function:
    for _, frame in ipairs(UIParent.ContainerFrames) do
        hooksecurefunc(frame, 'UpdateItems', BindsWhen_OnUpdate)
    end
end

hooksecurefunc('BankFrameItemButton_Update', function(button)
    local bag = button.isBag and -4 or button:GetParent():GetID()
    local slot = button:GetID()
    local text = not button.Count:IsShown() and GetBindText('player', button:GetInventorySlot())
    SetItemButtonBindType(button, text)
    --DebugPrintf('OK~Invoked BankFrameItemButton_Update for bank bag '..bag)
end)

------------------------------------------------------------------------
