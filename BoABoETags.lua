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

local textForItem = {}           -- context-aware cache (bags/bank/guild bank)
local textForItemHyperlink = {}  -- generic hyperlink cache (never overrides context)

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
    for id, text in pairs(textForItemHyperlink) do
        if ( temporary[text] ) then
            textForItemHyperlink[id] = nil
        end
    end
end

hooksecurefunc('BindEnchant', ClearTempCache)
-- This does not work. Switched to EQUIP_BIND_CONFIRM event handling instead.
-- hooksecurefunc('ConfirmBindOnUse', ClearTempCache)

------------------------------------------------------------------------
-- Tooltip for scanning for Binds on X text

-- Use the template so we can read TextLeftN regions reliably in 10.0
local scanTip = CreateFrame('GameTooltip', 'BindsWhenScanTooltip', UIParent, 'GameTooltipTemplate')

local eventFrame = CreateFrame('Frame', 'BindsWhenEventFrame')
eventFrame:RegisterEvent('EQUIP_BIND_CONFIRM')
eventFrame:SetScript('OnEvent', function(self, event, ...)
    if ( event == 'EQUIP_BIND_CONFIRM' ) then
        ClearTempCache()
    end
end)

------------------------------------------------------------------------
-- Tooltip scanning using C_TooltipInfo (Dragonflight+)
local function ScanBindFromTooltipInfo(info)
    if not info then return end
    if TooltipUtil and TooltipUtil.SurfaceArgs then
        TooltipUtil.SurfaceArgs(info)
    end
    if not info.lines then return end

    local sawBoA, sawBoE, sawBound = false, false, false
    for i = 1, #info.lines do
        local line = info.lines[i]
        if TooltipUtil and TooltipUtil.SurfaceArgs then
            TooltipUtil.SurfaceArgs(line)
        end
        local t = line and line.leftText
        local mapped = t and textForBind[t]
        if mapped ~= nil then
            if mapped == BoA then
                sawBoA = true
            elseif mapped == BoE then
                sawBoE = true
            else
                -- Soulbound / BoP (mapped == false) => considered bound
                sawBound = true
            end
        end
    end

    -- Precedence: BoA > Bound (no overlay) > BoE
    if sawBoA then return BoA end
    if sawBound then return false end
    if sawBoE then return BoE end
    return nil
end

-- New: scan by hyperlink (works for bank items resolved via C_Item)
local function GetBindTextFromLink(link)
    if not link then return end
    local cached = textForItemHyperlink[link]
    if cached ~= nil then
        return cached
    end
    local info = C_TooltipInfo and C_TooltipInfo.GetHyperlink and C_TooltipInfo.GetHyperlink(link)
    local text = ScanBindFromTooltipInfo(info)
    textForItemHyperlink[link] = text or false
    return text
end

local function GetBindText(bag, slot)
    local link = C_Container and C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot)
    if link ~= nil then
        -- Only consult the context-aware cache here (ignore generic hyperlink cache)
        local cached = textForItem[link]
        if cached ~= nil then
            return cached
        end
    end
    local info = C_TooltipInfo and C_TooltipInfo.GetBagItem and C_TooltipInfo.GetBagItem(bag, slot)
    local text = ScanBindFromTooltipInfo(info)
    if link ~= nil then
        textForItem[link] = text or false
    end
    return text
end

-- Helper: resolve a link for any item button (bags or bank)
local function ResolveButtonLink(button, bag, slot)
    -- Try container first
    if bag ~= nil and slot ~= nil and C_Container and C_Container.GetContainerItemLink then
        local link = C_Container.GetContainerItemLink(bag, slot)
        if link then return link end
    end
    -- Fallback: C_Item location from the button (works for bank/reagent/void where applicable)
    if button and button.GetItemLocation and C_Item and C_Item.DoesItemExist then
        local loc = button:GetItemLocation()
        if loc and C_Item.DoesItemExist(loc) then
            local ok, link = pcall(C_Item.GetItemLink, loc)
            if ok and link then return link end
        end
    end
end

-- Helper: does this button currently show an item icon?
local function ButtonHasItemIcon(button)
    if not button then return false end
    local tex
    if button.icon and button.icon.GetTexture then tex = button.icon:GetTexture() end
    if not tex and button.IconTexture and button.IconTexture.GetTexture then tex = button.IconTexture:GetTexture() end
    if not tex and button.Icon and button.Icon.GetTexture then tex = button.Icon:GetTexture() end
    if not tex and button.iconTexture and button.iconTexture.GetTexture then tex = button.iconTexture:GetTexture() end
    return tex ~= nil
end

-- Helper: current selected guild bank tab (safe)
local function GetSelectedGuildBankTabSafe()
    if type(GetCurrentGuildBankTab) == 'function' then
        return GetCurrentGuildBankTab()
    end
    if C_GuildBank and type(C_GuildBank.GetSelectedTab) == 'function' then
        local ok, tab = pcall(C_GuildBank.GetSelectedTab)
        if ok then return tab end
    end
    if GuildBankFrame and GuildBankFrame.selectedTab then
        return GuildBankFrame.selectedTab
    end
end

-- New: helpers to detect guild bank context/buttons
local function IsGuildBankVisible()
    return GuildBankFrame and GuildBankFrame:IsShown()
end

local function IsGuildBankButton(button)
    if not IsGuildBankVisible() then return false end
    if type(button) ~= 'table' then return false end
    if type(button.GetBagID) == 'function' then return false end -- guild bank buttons have no bagID
    local name = (type(button.GetName) == 'function' and button:GetName()) or ""
    return name:find("GuildBank") ~= nil
end

-- Guild bank: get bind text for the given slot in the selected tab
local function GetGuildBankBindText(slot)
    local tab = GetSelectedGuildBankTabSafe()
    if not tab or not slot then return end

    -- Prefer link (fast cache path)
    if type(GetGuildBankItemLink) == 'function' then
        local ok, link = pcall(GetGuildBankItemLink, tab, slot)
        if ok and link then
            return GetBindTextFromLink(link)
        end
    end

    -- Fallback: scan tooltip info directly
    if C_TooltipInfo and C_TooltipInfo.GetGuildBankItem then
        local ok, info = pcall(C_TooltipInfo.GetGuildBankItem, tab, slot)
        if ok then
            return ScanBindFromTooltipInfo(info)
        end
    end
end

-- Forward declaration so closures can call it before the function body appears
local UpdateContainerButtonBind

-- Add text string to an item button
local function SetItemButtonBindType(button, text)
    local fs = button.bindsOnText
    if not text then
        if fs then
            fs:SetText("")
            fs:Hide()              -- hide when empty to avoid “phantoms”
        end
        return
    end
    if not fs then
        fs = button:CreateFontString(nil, 'OVERLAY', 'GameFontNormalOutline')
        fs:SetPoint('TOPLEFT', 3, -3)
        button.bindsOnText = fs
        -- Clear overlay when the button is hidden/swapped (eg. tab switch)
        if button:HasScript("OnHide") and not button._boaboe_hideHooked then
            button._boaboe_hideHooked = true
            button:HookScript("OnHide", function(b)
                if b.bindsOnText then
                    b.bindsOnText:SetText("")
                    b.bindsOnText:Hide()
                end
                b._boaboe_lastLink = nil
            end)
        end
        -- Force recompute when the button becomes visible again (eg. tab switch back)
        if button:HasScript("OnShow") and not button._boaboe_showHooked then
            button._boaboe_showHooked = true
            button:HookScript("OnShow", function(b)
                b._boaboe_lastLink = nil
                if UpdateContainerButtonBind then
                    UpdateContainerButtonBind(b)
                end
            end)
        end
    end
    fs:SetText(text)
    fs:Show()
end

-- Central per-button updater
UpdateContainerButtonBind = function(button)
    if type(button) ~= 'table' or not button.GetID then return end

    -- Ensure show/hide hooks exist even before an overlay is created
    if button:HasScript("OnHide") and not button._boaboe_hideHooked then
        button._boaboe_hideHooked = true
        button:HookScript("OnHide", function(b)
            if b.bindsOnText then
                b.bindsOnText:SetText("")
                b.bindsOnText:Hide()
            end
            b._boaboe_lastLink = nil
            b._boaboe_lastSource = nil
        end)
    end
    if button:HasScript("OnShow") and not button._boaboe_showHooked then
        button._boaboe_showHooked = true
        button:HookScript("OnShow", function(b)
            b._boaboe_lastLink = nil
            b._boaboe_lastSource = nil
            if UpdateContainerButtonBind then
                UpdateContainerButtonBind(b)
            end
        end)
    end

    -- Force guild bank path for guild bank buttons
    if IsGuildBankButton(button) then
        local slot = button:GetID()
        local tab = GetSelectedGuildBankTabSafe()
        local link
        if tab and type(GetGuildBankItemLink) == 'function' then
            local ok, l = pcall(GetGuildBankItemLink, tab, slot)
            if ok then link = l end
        end
        if not link then
            SetItemButtonBindType(button, nil)
            button._boaboe_lastLink = nil
            button._boaboe_lastSource = nil
            return
        end

        local source = "guild"
        if button._boaboe_lastLink == link and button._boaboe_lastSource == source then
            return
        end
        button._boaboe_lastLink = link
        button._boaboe_lastSource = source

        local text = GetBindTextFromLink(link) or GetGuildBankBindText(slot)
        SetItemButtonBindType(button, text)
        return
    end

    -- Try to determine bagID from the button or its parent (covers bank buttons)
    local bag = (type(button.GetBagID) == 'function' and button:GetBagID()) or nil
    if bag == nil and not IsGuildBankVisible() then
        -- Only derive from parent when NOT in guild bank (parent:GetID can be a column index there)
        local parent = (type(button.GetParent) == 'function' and button:GetParent()) or nil
        if parent then
            if type(parent.GetBagID) == 'function' then
                bag = parent:GetBagID()
            elseif type(parent.GetID) == 'function' then
                bag = parent:GetID()
            end
        end
    end
    local slot = button:GetID()

    -- Normal container/bank path (prefer context-aware scan; fall back to hyperlink only if unknown)
    if bag ~= nil and slot ~= nil then
        local link = ResolveButtonLink(button, bag, slot) or (C_Container and C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot))
        if not link then
            SetItemButtonBindType(button, nil)
            button._boaboe_lastLink = nil
            button._boaboe_lastSource = nil
            return
        end

        local source = "bag"  -- context-aware
        if button._boaboe_lastLink == link and button._boaboe_lastSource == source then
            return
        end
        button._boaboe_lastLink = link
        button._boaboe_lastSource = source

        -- First try contextual scan (knows about Soulbound), only fall back if it returns nil
        local text = GetBindText(bag, slot)
        if text == nil then
            text = GetBindTextFromLink(link)
        end
        SetItemButtonBindType(button, text)
        return
    end

    -- Unknown type: try link-only and clear if none
    local link = ResolveButtonLink(button)
    if not link then
        SetItemButtonBindType(button, nil)
        button._boaboe_lastLink = nil
        button._boaboe_lastSource = nil
        return
    end

    local source = "link"
    if button._boaboe_lastLink == link and button._boaboe_lastSource == source then
        return
    end
    button._boaboe_lastLink = link
    button._boaboe_lastSource = source

    local text = GetBindTextFromLink(link)
    SetItemButtonBindType(button, text)
end

-- Update frame’s buttons and clear empties
local function BindsWhen_OnUpdate(frame)
    if frame.EnumerateValidItems then
        for a, b in frame:EnumerateValidItems() do
            local button = (type(b) == 'table' and b) or (type(a) == 'table' and a) or nil
            if button then
                UpdateContainerButtonBind(button)
            end
        end
    end

    -- Clear overlays on buttons that are now empty, by link (not by icon)
    if frame.GetChildren then
        local numChildren = select('#', frame:GetChildren())
        if numChildren and numChildren > 0 then
            local children = { frame:GetChildren() }
            for i = 1, #children do
                local child = children[i]
                if type(child) == 'table' and child.bindsOnText and child.GetID then
                    local link
                    if IsGuildBankButton(child) then
                        local tab = GetSelectedGuildBankTabSafe()
                        if tab and type(GetGuildBankItemLink) == 'function' then
                            local ok, l = pcall(GetGuildBankItemLink, tab, child:GetID())
                            if ok then link = l end
                        end
                    else
                        local bag = (type(child.GetBagID) == 'function' and child:GetBagID()) or nil
                        if bag ~= nil then
                            link = (C_Container and C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, child:GetID()))
                                or ResolveButtonLink(child, bag, child:GetID())
                        else
                            link = ResolveButtonLink(child)
                        end
                    end

                    if not link then
                        SetItemButtonBindType(child, nil)
                        child._boaboe_lastLink = nil
                        child._boaboe_lastSource = nil
                    end
                end
            end
        end
    end
end

-- New: explicit guild bank refresh (covers tab switches and data arrival)
local function RefreshGuildBankButtons()
    if not IsGuildBankVisible() then return end
    for col = 1, 7 do
        for row = 1, 14 do
            local btn = _G["GuildBankColumn"..col.."Button"..row]
            if btn and btn:IsVisible() then
                UpdateContainerButtonBind(btn)
            end
        end
    end
end

-- Forward declarations so the event handler captures locals (not globals)
local ForEachContainerFrame
local HookContainerFrames
local RefreshAllVisibleItemButtons

-- Driver
local driver = CreateFrame('Frame')
local function SafeRegisterEvent(frame, eventName)
    pcall(frame.RegisterEvent, frame, eventName)
end

SafeRegisterEvent(driver, 'PLAYER_LOGIN')
SafeRegisterEvent(driver, 'ADDON_LOADED')
SafeRegisterEvent(driver, 'BAG_UPDATE_DELAYED')
SafeRegisterEvent(driver, 'BANKFRAME_OPENED')
SafeRegisterEvent(driver, 'BANKFRAME_CLOSED')
SafeRegisterEvent(driver, 'PLAYERBANKSLOTS_CHANGED')

-- Guild bank events (safe across versions)
SafeRegisterEvent(driver, 'GUILDBANKFRAME_OPENED')
SafeRegisterEvent(driver, 'GUILDBANKFRAME_CLOSED')
SafeRegisterEvent(driver, 'GUILDBANKBAGSLOTS_CHANGED')
SafeRegisterEvent(driver, 'GUILDBANK_UPDATE_TABS')
SafeRegisterEvent(driver, 'GUILDBANK_ITEM_LOCK_CHANGED')

-- Reagent bank was folded into bank; keep these safe in case of legacy clients
SafeRegisterEvent(driver, 'REAGENTBANK_UPDATE')
SafeRegisterEvent(driver, 'REAGENTBANK_PURCHASED')

driver:SetScript('OnEvent', function(self, event, arg1)
    if event == 'ADDON_LOADED' then
        if arg1 == 'Blizzard_ContainerUI' or arg1 == 'BoABoETags' then
            HookContainerFrames()
        end
        return
    elseif event == 'PLAYER_LOGIN' then
        HookContainerFrames()
    elseif event == 'BANKFRAME_OPENED' then
        HookContainerFrames()
        C_Timer.After(0, RefreshAllVisibleItemButtons)
    elseif event == 'GUILDBANKFRAME_OPENED' then
        C_Timer.After(0, RefreshGuildBankButtons)
    elseif event == 'GUILDBANK_UPDATE_TABS' or event == 'GUILDBANKBAGSLOTS_CHANGED' or event == 'GUILDBANK_ITEM_LOCK_CHANGED' then
        C_Timer.After(0, RefreshGuildBankButtons)
    end

    ForEachContainerFrame(function(frame)
        if frame:IsShown() then
            BindsWhen_OnUpdate(frame)
        end
    end)
    RefreshAllVisibleItemButtons()
    RefreshGuildBankButtons()
end)

-- Helper: iterate container-like frames (bags/bank) robustly
ForEachContainerFrame = function(callback)
    local seen = {}
    local function consider(frame)
        if type(frame) ~= 'table' or seen[frame] then return end
        seen[frame] = true

        if type(frame.EnumerateValidItems) == 'function' then
            callback(frame)
        end

        if type(frame.GetChildren) == 'function' then
            local num = select('#', frame:GetChildren())
            for i = 1, num do
                consider(select(i, frame:GetChildren()))
            end
        end
    end

    if type(ContainerFrameUtil_EnumerateContainerFrames) == 'function' then
        for a, b in ContainerFrameUtil_EnumerateContainerFrames() do
            local f = (type(b) == 'table' and b) or (type(a) == 'table' and a) or nil
            if f then consider(f) end
        end
    end

    if ContainerFrameCombinedBags then
        consider(ContainerFrameCombinedBags)
    end

    -- Fallbacks: legacy container frames
    for i = 1, 20 do
        local f = _G["ContainerFrame"..i]
        if f then consider(f) end
    end

    -- Include bank subtree if open (new bank UI)
    if BankFrame and BankFrame:IsShown() then
        consider(BankFrame)
    end
end

HookContainerFrames = function()
    ForEachContainerFrame(function(frame)
        if frame._boaboe_hooked then return end
        frame._boaboe_hooked = true

        if type(frame.UpdateItems) == 'function' then
            hooksecurefunc(frame, 'UpdateItems', BindsWhen_OnUpdate)
        end
        if frame:HasScript("OnShow") then
            frame:HookScript("OnShow", function(f) BindsWhen_OnUpdate(f) end)
        end
        if frame:IsShown() then
            BindsWhen_OnUpdate(frame)
        end
    end)
end

-- Safety net: per-button OnUpdate (hits bank buttons too)
if ContainerFrameItemButtonMixin and ContainerFrameItemButtonMixin.OnUpdate then
    hooksecurefunc(ContainerFrameItemButtonMixin, 'OnUpdate', function(button)
        if type(button) ~= 'table' then return end
        UpdateContainerButtonBind(button)
    end)
end

-- Last-resort visible sweep to catch any item buttons (bags, bank, guild bank)
RefreshAllVisibleItemButtons = function()
    local f = EnumerateFrames()
    while f do
        if type(f) == 'table' and f:IsVisible() and type(f.GetID) == 'function' then
            local hasResolver = (type(f.GetBagID) == 'function')
                or (type(f.GetItemLocation) == 'function')
                or IsGuildBankButton(f)
            if hasResolver then
                UpdateContainerButtonBind(f)
            end
        end
        f = EnumerateFrames(f)
    end
end
