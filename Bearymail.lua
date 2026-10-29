-- ============================================================================
-- БЛОК 1: БАЗА ДАННЫХ, КОНСТАНТЫ И УМНЫЙ СКАНЕР ВЕЩЕЙ
-- ============================================================================
local defaultDB = {
    targets = {},       -- Категории: ["Название подкласса"] = "ИмяПерсонажа"
    exceptions = {},    -- Исключения: [itemID] = "ИмяПерсонажа"
    blacklists = {},    -- Черные списки: ["ИмяПерсонажа"] = { [itemID] = true }
    characters = {}     -- Список зарегистрированных персонажей
}

local ITEM_CATEGORIES = {
    "Металл и камень",
    "Трава",
    "Кожа",
    "Ткань",
    "Наложение чар",
    "Мясо",
    "Рыба",
    "Стихии",         -- Новая категория!
    "Еда и напитки"   -- Новая категория!
}

local selectedCharacter = nil
local activeTab = 1

local categoryRows = {} 
local exceptionRows = {} 
local blacklistRows = {} 

local function ChatMsg(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[Bearymail]:|r " .. tostring(msg))
end
-- выбор категорий предметов
local function AssignCategoryToCharacter(category, charName, isChecked)
    if isChecked then
        BearymailDB.targets[category] = charName
        ChatMsg(string.format("Категория '%s' теперь отправляется персонажу %s", category, charName))
    else
        if BearymailDB.targets[category] == charName then
            BearymailDB.targets[category] = nil
            ChatMsg(string.format("Категория '%s' убрана от персонажа %s", category, charName))
        end
    end
end

-- ИСПРАВЛЕНИЕ: функция удаления персонажей
local function DeleteCharacterData(charName)
    if not charName then return end
    for i, name in ipairs(BearymailDB.characters) do
        if name == charName then 
            table.remove(BearymailDB.characters, i) 
            break 
        end
    end
    BearymailDB.blacklists[charName] = nil
    for cat, char in pairs(BearymailDB.targets) do 
        if char == charName then BearymailDB.targets[cat] = nil end 
    end
    for id, char in pairs(BearymailDB.exceptions) do 
        if char == charName then BearymailDB.exceptions[id] = nil end 
    end
end
-- Вперед-объявление главной функции обновления экрана для ссылок в коде
local UpdateContentDisplay

-- ============================================================================
-- НАДЁЖНЫЙ СКАНЕР СУМОК ДЛЯ СИРУСА (С ПОИСКОМ ПРЕДМЕТА)
-- ============================================================================
local function IsItemBound(bag, slot, itemID)
    local scanTooltip = _G["BM_ScanTooltip"] or CreateFrame("GameTooltip", "BM_ScanTooltip", nil, "GameTooltipTemplate")
    scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTooltip:ClearLines()
    
    -- Если нам передали bag и slot (робот у почты), сканируем напрямую
    if bag and slot then
        scanTooltip:SetBagItem(bag, slot)
    -- Если передали только ID (при добавлении мышкой), ищем эту вещь в сумках игрока
    elseif itemID then
        local foundInBag, foundInSlot = nil, nil
        for b = 0, 4 do
            local numSlots = GetContainerNumSlots(b)
            for s = 1, numSlots do
                if GetContainerItemID(b, s) == itemID then
                    foundInBag = b
                    foundInSlot = s
                    break
                end
            end
            if foundInBag then break end
        end
        
        -- Если нашли предмет в сумке, сканируем его реальное состояние
        if foundInBag and foundInSlot then
            scanTooltip:SetBagItem(foundInBag, foundInSlot)
        else
            -- Если предмета почему-то нет в сумке (взят из коллекции/книги), проверяем по ссылке
            scanTooltip:SetHyperlink("item:" .. itemID)
        end
    else
        return false
    end
    
    -- Читаем строки
    for i = 1, 10 do
        local leftLine = _G["BM_ScanTooltipTextLeft" .. i]
        if leftLine then
            local text = leftLine:GetText()
            if text and (text == "Персональный предмет" or string.find(text, "Персональный предмет")) then
                return true -- Жестко персональный
            end
        end
    end
    return false
end


-- ============================================================================
-- БЛОК 2 (ФИНАЛЬНЫЙ): СВОБОДНОЕ СОВМЕЩЕНИЕ ИСКЛЮЧЕНИЙ И ЧЕРНОГО СПИСКА
-- ============================================================================

local function AddItemToExceptions(itemID)
    if not selectedCharacter or not itemID then return end
    local itemName, itemLink = GetItemInfo(itemID)
    if not itemName then return end 
    
    -- ГЛОБАЛЬНОЕ ПРАВИЛО: Предмет в Исключениях (магнит) может быть только у одного твинка
    local oldOwner = BearymailDB.exceptions[itemID]
    if oldOwner and oldOwner ~= selectedCharacter then
        ChatMsg(string.format("Предмет %s перенесен в Магнит к %s (раньше магнитил к %s).", itemLink, selectedCharacter, oldOwner))
    elseif oldOwner == selectedCharacter then
        -- Если уже привязан к текущему, ничего не делаем
        return
    else
        ChatMsg(string.format("Предмет %s добавлен в Магнит для %s (все будут слать ему).", itemLink, selectedCharacter))
    end
    
    -- Записываем глобального получателя
    BearymailDB.exceptions[itemID] = selectedCharacter
    
    -- Никаких удалений из Черного списка! Предмет может быть в обоих списках одновременно.
    UpdateContentDisplay()
end

local function AddItemToBlacklist(itemID)
    if not selectedCharacter or not itemID then return end
    local itemName, itemLink = GetItemInfo(itemID)
    if not itemName then return end
    
    -- Инициализируем личный черный список для выбранного персонажа
    if not BearymailDB.blacklists[selectedCharacter] then 
        BearymailDB.blacklists[selectedCharacter] = {} 
    end
    
    -- Если предмет уже в личном ЧС, ничего не делаем
    if BearymailDB.blacklists[selectedCharacter][itemID] then return end
    
    -- Записываем в ЛИЧНЫЙ черный список (это личный щит твинка от отправки)
    BearymailDB.blacklists[selectedCharacter][itemID] = true
    ChatMsg(string.format("Предмет %s добавлен в Черный список для %s (он оставит его себе).", itemLink, selectedCharacter))
    
    -- Никаких удалений из Исключений! Списки независимы.
    UpdateContentDisplay()
end

-- ============================================================================
-- ИНТЕГРАЦИЯ ОКНА БЛАГОДАРНОСТИ (ОБ АДДОНЕ BEARMYIL) И КНОПКИ [?]
-- ============================================================================
local helpGui = nil -- Локальная переменная для хранения фрейма помощи

local function CreateHelpGUI()
    if helpGui then return helpGui end

    local hGui = CreateFrame("Frame", "BearymailHelpGUI", UIParent)
    hGui:SetSize(470, 180)
    hGui:SetPoint("CENTER", 0, 40)
    hGui:SetFrameStrata("DIALOG")
    hGui:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    hGui:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    hGui:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    
    hGui:EnableMouse(true)
    hGui:SetMovable(true)
    hGui:RegisterForDrag("LeftButton")
    hGui:SetScript("OnDragStart", hGui.StartMoving)
    hGui:SetScript("OnDragStop", hGui.StopMovingOrSizing)
    tinsert(UISpecialFrames, "BearymailHelpGUI")

    -- Заголовок окна (Адаптировано под Bearymail)
    local title = hGui:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("Об аддоне Bearymail")

    local closeBtn = CreateFrame("Button", nil, hGui, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -3, -3)

    -- Пояснительный текст
    local helpText = hGui:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    helpText:SetPoint("TOPLEFT", 16, -42)
    helpText:SetWidth(300)
    helpText:SetJustifyH("LEFT")
    helpText:SetText("Если Вам понравился аддон, можете пожертвовать мне золото через внутриигровую почту.\n\nСервер х5, |cff3fc7ebМедведж|r\n\n|cffffd100Поддержать автора вне игры можно по ссылке или QR-коду:|r")

    -- Поле ввода с ссылкой на Cloudtips
    local editBox = CreateFrame("EditBox", "BearymailDonateLinkEditBox", hGui)
    editBox:SetSize(290, 22)
    editBox:SetPoint("TOPLEFT", 16, -140)
    editBox:SetFontObject("GameFontHighlightSmall")
    editBox:SetAutoFocus(false)
    editBox:SetText("https://pay.cloudtips.ru/p/aff01756")
    editBox:SetTextInsets(6, 6, 0, 0)
    editBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 12, edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    editBox:SetBackdropColor(0.01, 0.01, 0.01, 1.0)
    editBox:SetBackdropBorderColor(0.4, 0.4, 0.4, 1.0)

    editBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    editBox:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Отображение QR-кода (Путь изменен на нашу папку Bearymail!)
    local qrFrame = CreateFrame("Frame", nil, hGui)
    qrFrame:SetSize(128, 128)
    qrFrame:SetPoint("TOPRIGHT", hGui, "TOPRIGHT", -18, -38) 
    
    local qrTexture = qrFrame:CreateTexture(nil, "ARTWORK")
    qrTexture:SetAllPoints(qrFrame)
    qrTexture:SetTexture("Interface\\AddOns\\Bearymail\\qr")
    qrFrame.texture = qrTexture

    hGui:Hide()
    helpGui = hGui
    return helpGui
end

-- ============================================================================
-- БЛОК 3: СОЗДАНИЕ ГЛАВНОГО ОКНА И ВНУТРЕННЕЙ ПОДЛОЖКИ
-- ============================================================================
local mainFrame = CreateFrame("Frame", "BearymailFrame", UIParent)
local contentFrame = CreateFrame("Frame", nil, mainFrame)
local contentText = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")

local function CreateMainLayout()
    mainFrame:SetSize(480, 480)
    mainFrame:SetPoint("CENTER", UIParent, "CENTER")
    mainFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
    mainFrame:Hide()

    local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", mainFrame, "TOP", 0, -16)
    title:SetText("Bearymail")

    local closeButton = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -5, -5)

    -- Создаем аккуратную круглую кнопку справки на основе гарантированной текстуры
    local helpButton = CreateFrame("Button", nil, mainFrame)
    helpButton:SetSize(16, 16) -- Идеальный компактный размер вровень с крестиком
    -- Позиция (-32, -13) аккуратно выровняет круглую кнопку левее крестика закрытия
    helpButton:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -32, -13)
    
    -- Накладываем красивую золотую иконку знака вопроса из файлов игры
    local helpTex = helpButton:CreateTexture(nil, "ARTWORK")
    helpTex:SetAllPoints(helpButton)
    helpTex:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
    helpButton.texture = helpTex
    
    -- Эффект подсвечивания при наведении мышки
    helpButton:SetScript("OnEnter", function(self)
        self.texture:SetVertexColor(1, 0.8, 0) -- делает значок ярче/золотее
    end)
    helpButton:SetScript("OnLeave", function(self)
        self.texture:SetVertexColor(1, 1, 1) -- возвращает стандартный цвет
    end)
    
    -- Скрипт клика: открывает/закрывает окно помощи
    helpButton:SetScript("OnClick", function()
        local gui = CreateHelpGUI()
        if gui:IsShown() then 
            gui:Hide() 
        else 
            gui:Show() 
        end
    end)


    contentFrame:SetSize(440, 310)
    contentFrame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 20, -115)
    contentFrame:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    
    contentText:SetPoint("CENTER", contentFrame, "CENTER", 0, 0)
end
-- ============================================================================
-- БЛОК 4: ОТРИСОВКА И ЛОГИКА ВКЛАДКИ «КАТЕГОРИИ»
-- ============================================================================
local function UpdateCategoriesTab()
    for i, row in ipairs(categoryRows) do
        local categoryName = row.categoryName
        if selectedCharacter then
            row:Show()
            local currentOwner = BearymailDB.targets[categoryName]
            if currentOwner == selectedCharacter then
                row.cb:SetChecked(true)
                row.statusText:SetText(string.format("|cff00ff00%s|r", selectedCharacter))
            elseif currentOwner then
                row.cb:SetChecked(false)
                row.statusText:SetText(string.format("|cffff0000Занято: %s|r", currentOwner))
            else
                row.cb:SetChecked(false)
                row.statusText:SetText("|cff888888(Не назначено)|r")
            end
        else
            row:Hide()
        end
    end
end

local function CreateCategoriesTabRows()
    for i, categoryName in ipairs(ITEM_CATEGORIES) do
        local row = CreateFrame("Frame", nil, contentFrame)
        row:SetSize(420, 30)
        row:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, -10 - ((i-1) * 32))
        row.categoryName = categoryName
        
        local cb = CreateFrame("CheckButton", "BM_CatCB_"..i, row, "UICheckButtonTemplate")
        cb:SetPoint("LEFT", row, "LEFT", 0, 0)
        cb:SetSize(26, 26)
        row.cb = cb
        
        local text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("LEFT", cb, "RIGHT", 5, 1)
        text:SetText(categoryName)
        
        local statusText = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        statusText:SetPoint("RIGHT", row, "RIGHT", -10, 1)
        row.statusText = statusText
        
        cb:SetScript("OnClick", function(self)
            AssignCategoryToCharacter(categoryName, selectedCharacter, self:GetChecked())
            UpdateCategoriesTab()
        end)
        
        row:Hide()
        table.insert(categoryRows, row)
    end
end
-- ============================================================================
-- БЛОК 5: ОТРИСОВКА И ЛОГИКА ВКЛАДОК «ИСКЛЮЧЕНИЯ» И «ЧЕРНЫЙ СПИСОК»
-- ============================================================================

-- Заготовка строки для Исключений
local function CreateExceptionRow(index)
    local row = CreateFrame("Frame", nil, contentFrame)
    row:SetSize(395, 24)
    row:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, -10 - ((index - 1) * 26))
    
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("LEFT", row, "LEFT", 5, 0)
    row.icon = icon
    
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", icon, "RIGHT", 7, 0)
    row.text = text
    
    local removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    removeBtn:SetSize(20, 20)
    removeBtn:SetPoint("RIGHT", row, "RIGHT", -5, 0)
    removeBtn:SetText("X")
    row.removeBtn = removeBtn
    
    row:Hide()
    table.insert(exceptionRows, row)
    return row
end

-- Функция обновления вкладки Исключений (Крестики исправлены)
local function UpdateExceptionsTab()
    -- Скрываем все строки пула перед перерисовкой
    for _, row in ipairs(exceptionRows) do row:Hide() end
    if not selectedCharacter then BearymailScrollFrame:Hide() return end
    
    -- Собираем из базы все ID для выбранного персонажа
    local list = {}
    for itemID, charName in pairs(BearymailDB.exceptions) do
        if charName == selectedCharacter then table.insert(list, itemID) end
    end
    table.sort(list)
    
    if #list == 0 then
        BearymailScrollFrame:Hide()
        -- ИСПРАВЛЕНО: Текст адаптирован под "Магнит" и автоматически подставляет ник твинка
        contentText:SetText(string.format("|cff888888Список пуст.\nПеретащите сюда предмет из сумки.\n\nВсе остальные ваши персонажи будут автоматически\nотсылать этот предмет персонажу %s.|r", selectedCharacter or "твинку"))
        contentText:Show()
        return
    end
    
    -- Активируем и настраиваем скролл-барьер Blizzard
    BearymailScrollFrame:Show()
    -- Аргументы: фрейм, общее число элементов, сколько строк влазит на экран (11), высота строки (26)
    FauxScrollFrame_Update(BearymailScrollFrame, #list, 11, 26)
    local offset = FauxScrollFrame_GetOffset(BearymailScrollFrame)
    
    -- Выводим ровно столько строк, сколько помещается на экране
    for i = 1, 11 do
        local dataIndex = offset + i
        local itemID = list[dataIndex]
        
        -- Получаем или создаем строку в пуле интерфейса
        local row = exceptionRows[i] or CreateExceptionRow(i)
        
        if itemID then
            local itemName, itemLink, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
            if itemName then
                row.icon:SetTexture(itemTexture)
                row.text:SetText(itemLink)
                
                -- Перепривязываем крестик на текущий скролл-элемент
                row.removeBtn.itemID = itemID
                row.removeBtn:SetScript("OnClick", function(self)
                    BearymailDB.exceptions[self.itemID] = nil
                    ChatMsg(string.format("Предмет %s удален из исключений.", itemLink))
                    UpdateContentDisplay()
                end)
                row:Show()
            end
        else
            row:Hide()
        end
    end
end

-- Заготовка строки для Черного списка
local function CreateBlacklistRow(index)
    local row = CreateFrame("Frame", nil, contentFrame)
    row:SetSize(395, 24)
    row:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, -10 - ((index - 1) * 26))
    
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("LEFT", row, "LEFT", 5, 0)
    row.icon = icon
    
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", icon, "RIGHT", 7, 0)
    row.text = text
    
    local removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    removeBtn:SetSize(20, 20)
    removeBtn:SetPoint("RIGHT", row, "RIGHT", -5, 0)
    removeBtn:SetText("X")
    row.removeBtn = removeBtn
    
    row:Hide()
    table.insert(blacklistRows, row)
    return row
end

-- Функция обновления вкладки Черного списка (Крестики исправлены)
local function UpdateBlacklistTab()
    for _, row in ipairs(blacklistRows) do row:Hide() end
    if not selectedCharacter then BearymailScrollFrame:Hide() return end
    
    local list = {}
    if BearymailDB.blacklists[selectedCharacter] then
        for itemID, allowed in pairs(BearymailDB.blacklists[selectedCharacter]) do
            if allowed then table.insert(list, itemID) end
        end
    end
    table.sort(list)
    
    if #list == 0 then
        BearymailScrollFrame:Hide()
        -- ИСПРАВЛЕНО: Теперь пишется ник конкретного выбранного персонажа
        contentText:SetText(string.format("|cff888888Черный список пуст.\nПеретащите сюда предмет из сумки,\nчтобы персонаж %s НИКОГДА\nне отправлял его по почте.|r", selectedCharacter or "выбранный"))
        contentText:Show()
        return
    end
    
    BearymailScrollFrame:Show()
    FauxScrollFrame_Update(BearymailScrollFrame, #list, 11, 26)
    local offset = FauxScrollFrame_GetOffset(BearymailScrollFrame)
    
    for i = 1, 11 do
        local dataIndex = offset + i
        local itemID = list[dataIndex]
        
        local row = blacklistRows[i] or CreateBlacklistRow(i)
        
        if itemID then
            local itemName, itemLink, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
            if itemName then
                row.icon:SetTexture(itemTexture)
                row.text:SetText(itemLink)
                
                row.removeBtn.itemID = itemID
                row.removeBtn:SetScript("OnClick", function(self)
                    if BearymailDB.blacklists[selectedCharacter] then
                        BearymailDB.blacklists[selectedCharacter][self.itemID] = nil
                        ChatMsg(string.format("Предмет %s удален из черного списка %s.", itemLink, selectedCharacter))
                        UpdateContentDisplay()
                    end
                end)
                row:Show()
            end
        else
            row:Hide()
        end
    end
end
-- ============================================================================
-- БЛОК 6: ВЕРХНЯЯ ПАНЕЛЬ НАСТРОЕК (ПЕРСОНАЖИ, ДРОПДАУН, КНОПКИ ГЛОБАЛЬНЫЕ)
-- ============================================================================
local charDropdown = CreateFrame("Frame", "BM_CharDropdown", mainFrame, "UIDropdownMenuTemplate")
local nameInput = CreateFrame("EditBox", "BM_NameInput", mainFrame, "InputBoxTemplate")

local function OnMenuClick(self)
    UIDropDownMenu_SetSelectedID(charDropdown, self:GetID())
    selectedCharacter = self.value
    UpdateContentDisplay()
end

local function InitDropdown(self, level)
    local info = UIDropDownMenu_CreateInfo()
    for i, charName in ipairs(BearymailDB.characters) do
        info.text = charName
        info.value = charName
        info.func = OnMenuClick
        info.checked = (selectedCharacter == charName)
        UIDropDownMenu_AddButton(info, level)
    end
end

local function RefreshDropdown()
    UIDropDownMenu_Initialize(charDropdown, InitDropdown)
    if #BearymailDB.characters > 0 then
        -- ИСПРАВЛЕНО: Жестко выбираем первого персонажа из массива, а не всю таблицу!
        if not selectedCharacter then selectedCharacter = BearymailDB.characters[1] end
        UIDropDownMenu_SetSelectedValue(charDropdown, selectedCharacter)
        UIDropDownMenu_SetText(charDropdown, selectedCharacter)
    else
        UIDropDownMenu_SetText(charDropdown, "Нет персонажей")
        selectedCharacter = nil
    end
    UpdateContentDisplay()
end

function CreateTopPanel()
    -- Переменная dropdownLabel доступна глобально для функции UpdateContentDisplay
    dropdownLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dropdownLabel:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 20, -50)
    dropdownLabel:SetText("Выберите персонажа для настройки:")

    charDropdown:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 5, -70)
    UIDropDownMenu_SetWidth(charDropdown, 160)

    -- Кнопки объявлены глобально (без local), чтобы скрывать их на вкладке рассылки
    BM_AddUserButton = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    BM_AddUserButton:SetSize(30, 22)
    BM_AddUserButton:SetPoint("LEFT", charDropdown, "RIGHT", -10, 2)
    BM_AddUserButton:SetText("+")

    BM_RemoveUserButton = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    BM_RemoveUserButton:SetSize(30, 22)
    BM_RemoveUserButton:SetPoint("LEFT", BM_AddUserButton, "RIGHT", 5, 0)
    BM_RemoveUserButton:SetText("-")

    -- Поле ввода имени
    nameInput:SetSize(110, 22)
    nameInput:SetPoint("LEFT", BM_RemoveUserButton, "RIGHT", 15, 0)
    nameInput:SetAutoFocus(false)
    nameInput:Hide()

    local inputPlaceholder = nameInput:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    inputPlaceholder:SetPoint("LEFT", nameInput, "LEFT", 5, 0)
    inputPlaceholder:SetText("Ник + Enter")

    nameInput:SetScript("OnTextChanged", function(self)
        if self:GetText() == "" then inputPlaceholder:Show() else inputPlaceholder:Hide() end
    end)

    -- Кнопка ПЛЮС
    BM_AddUserButton:SetScript("OnClick", function()
        if nameInput:IsShown() then nameInput:Hide() else nameInput:SetText("") nameInput:Show() nameInput:SetFocus() end
    end)

    nameInput:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        text = string.gsub(text, "%s+", "")
        if text and text ~= "" then
            local exists = false
            for _, name in ipairs(BearymailDB.characters) do
                if string.lower(name) == string.lower(text) then exists = true end
            end
            if not exists then
                table.insert(BearymailDB.characters, text)
                selectedCharacter = text
                RefreshDropdown()
                ChatMsg(string.format("Персонаж %s добавлен.", text))
            else
                ChatMsg("Ошибка: Такой персонаж уже есть.")
            end
        end
        self:Hide()
    end)

    -- Кнопка МИНУС
    BM_RemoveUserButton:SetScript("OnClick", function()
        if not selectedCharacter then return end
        DeleteCharacterData(selectedCharacter)
        selectedCharacter = nil -- Сбрасываем текущего, чтобы RefreshDropdown выбрал первого из оставшихся
        RefreshDropdown()
    end)
end

-- ============================================================================
-- БЛОК 7.1: ОБНОВЛЕННАЯ СИСТЕМА 4-Х ВКЛАДОК И МАКЕТ ВКЛАДКИ РАССЫЛКИ
-- ============================================================================
local sendFramesPool = {} -- Пул строк для отображения прогноза писем на 4-й вкладке

local function Tab_OnClick(self)
    local id = self:GetID()
    PanelTemplates_SetTab(mainFrame, id)
    activeTab = id
    UpdateContentDisplay()
end

-- Пересоздаем систему вкладок (теперь их 4!)
function CreateTabsSystem()
    -- ИСПРАВЛЕНО: Переименовали вкладку для лучшего понимания игроками
    local tabNames = { "Категории", "Магнит", "Черный список", "Рассылка" }
    local tabs = {}
    
    for i = 1, 4 do
        local tab = CreateFrame("Button", "BearymailFrameTab"..i, mainFrame, "CharacterFrameTabButtonTemplate")
        tab:SetID(i)
        tab:SetText(tabNames[i])
        tab:SetScript("OnClick", Tab_OnClick)
        
        if i == 1 then 
            tab:SetPoint("TOPLEFT", contentFrame, "BOTTOMLEFT", 5, 2)
        else 
            tab:SetPoint("TOPLEFT", tabs[i-1], "TOPRIGHT", -14, 0) 
        end
        tabs[i] = tab
    end
    
    PanelTemplates_SetNumTabs(mainFrame, 4)
    PanelTemplates_SetTab(mainFrame, 1)

    -- Создаем скролл-фрейм Blizzard для плавной прокрутки списков
    local scrollFrame = CreateFrame("ScrollFrame", "BearymailScrollFrame", contentFrame, "FauxScrollFrameTemplate")
    scrollFrame:SetSize(410, 290)
    scrollFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -10)
    
    -- Настроили колесико на шаг 22 пикселя
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, 22, UpdateContentDisplay)
    end)

    scrollFrame:Hide()

    -- СОЗДАЕМ КНОПКИ ДЛЯ 4-й ВКЛАДКИ (По умолчанию скрыты)
    -- Кнопка "Отправить"
    local runSendBtn = CreateFrame("Button", "BM_RunSendButton", contentFrame, "UIPanelButtonTemplate")
    runSendBtn:SetSize(120, 26)
    runSendBtn:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 30, 25)
    runSendBtn:SetText("Отправить")
    runSendBtn:Hide()

    -- Кнопка "Отмена"
    local cancelSendBtn = CreateFrame("Button", "BM_CancelSendButton", contentFrame, "UIPanelButtonTemplate")
    cancelSendBtn:SetSize(120, 26)
    cancelSendBtn:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -30, 25)
    cancelSendBtn:SetText("Отмена")
    cancelSendBtn:Hide()
    
    cancelSendBtn:SetScript("OnClick", function()
        mainFrame:Hide()
    end)

    -- Настраиваем окно на прием предметов (Drag-and-Drop)
    mainFrame:SetScript("OnReceiveDrag", function()
        if not selectedCharacter or (activeTab ~= 2 and activeTab ~= 3) then return end
        local cursorType, itemID = GetCursorInfo()
        if cursorType == "item" and itemID then
            ClearCursor()
            if IsItemBound(nil, nil, itemID) then
                local _, itemLink = GetItemInfo(itemID)
                ChatMsg(string.format("|cffff0000Ошибка:|r Предмет %s персональный, его нельзя отправить почтой!", itemLink or "предмет"))
                return
            end
            if activeTab == 2 then AddItemToExceptions(itemID)
            elseif activeTab == 3 then AddItemToBlacklist(itemID) end
        end
    end)
end

-- ============================================================================
-- БЛОК 7.2: АЛГОРИТМ ПРЕ-СКАНА СУМОК И ОТРИСОВКА ВИРТУАЛЬНЫХ ПИСЕМ
-- ============================================================================
local virtualMailQueue = {} -- Виртуальный список писем: { { target = "Ник", topic = "Тема", items = { { link, count } } } }

-- ============================================================================
-- СТРОКИ ОТЧЕТА С ПОДДЕРЖКОЙ ГРАФИЧЕСКИХ ИКОНОК ПРЕДМЕТОВ
-- ============================================================================
local function CreateSendReportRow(index)
    local row = CreateFrame("Frame", nil, contentFrame)
    row:SetSize(395, 20) -- Удобная компактная высота под иконку
    row:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, -10 - ((index - 1) * 22))
    
    -- Текстура иконки предмета (будет показываться только для строк с вещами)
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", row, "LEFT", 15, 0)
    row.icon = icon
    
    -- Текст ссылки или заголовка письма
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", icon, "RIGHT", 5, 0)
    row.text = text
    
    row:Hide()
    table.insert(sendFramesPool, row)
    return row
end

-- Функция пре-сканирования сумок (строит прогноз писем без отправки)
local function ScanBagsForVirtualQueue()
    virtualMailQueue = {}
    local currentPatternChar = UnitName("player")
    
    -- Временная таблица для распределения стаков предметов по твинкам и категориям
    -- Структура: [ИмяТвинка] = { [Категория] = { {link, count}, {link, count} } }
    local sortedItems = {}
    
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local itemLink = GetContainerItemLink(bag, slot)
            if itemLink then
                local itemID = tonumber(string.match(itemLink, "item:(%d+)"))
                if itemID then
                    local _, _, _, _, _, _, itemSubClass = GetItemInfo(itemLink)
                    
                    -- Проверяем личный ЧС (щит от самого себя)
                    local isBlacklisted = (BearymailDB.blacklists[currentPatternChar] and BearymailDB.blacklists[currentPatternChar][itemID])
                    -- Проверяем BoP подстраховку
                    if not isBlacklisted and IsItemBound(bag, slot, nil) then
                        isBlacklisted = true
                    end
                    
                    if not isBlacklisted then
                        local assignedChar = nil
                        local logCategoryName = "Ресурсы"
                        
                        if BearymailDB.exceptions[itemID] then
                            assignedChar = BearymailDB.exceptions[itemID]
                            logCategoryName = "Исключение"
                        elseif itemSubClass and BearymailDB.targets[itemSubClass] then
                            assignedChar = BearymailDB.targets[itemSubClass]
                            logCategoryName = itemSubClass
                        end
                        
                        -- Защита от самоотправки
                        if assignedChar and assignedChar ~= currentPatternChar then
                            local _, itemCount, locked = GetContainerItemInfo(bag, slot)
                            if not locked and (itemCount or 0) > 0 then
                                if not sortedItems[assignedChar] then sortedItems[assignedChar] = {} end
                                if not sortedItems[assignedChar][logCategoryName] then sortedItems[assignedChar][logCategoryName] = {} end
                                
                                table.insert(sortedItems[assignedChar][logCategoryName], { link = itemLink, count = itemCount })
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Генерируем письма (по 12 слотов на письмо) на основе отсортированных вещей
    for characterName, categories in pairs(sortedItems) do
        for logCategoryName, itemsList in pairs(categories) do
            local mailItemSlots = {}
            for _, itemData in ipairs(itemsList) do
                table.insert(mailItemSlots, itemData)
                
                -- Если накопилось 12 слотов, закрываем письмо и начинаем новое
                if #mailItemSlots == 12 then
                    table.insert(virtualMailQueue, { target = characterName, topic = logCategoryName, items = mailItemSlots })
                    mailItemSlots = {}
                end
            end
            -- Дозаписываем остатки вещей в финальное письмо для этой категории
            if #mailItemSlots > 0 then
                table.insert(virtualMailQueue, { target = characterName, topic = logCategoryName, items = mailItemSlots })
            end
        end
    end
end

-- ============================================================================
-- ОБНОВЛЕННАЯ ОТРИСОВКА 4-Й ВКЛАДКИ (С РЕАЛЬНЫМИ ИКОНКАМИ И ВЕЩАМИ)
-- ============================================================================
local function UpdateSendTab()
    -- Скрываем старый пул
    for _, row in ipairs(sendFramesPool) do 
        row:Hide() 
        if row.icon then row.icon:Hide() end
    end
    
    -- Структурированный массив данных для экрана
    -- Формат: { type = "title/line/item", text = "текст", id = itemID }
    local displayData = {}
    
    if #virtualMailQueue == 0 then
        if BearymailScrollFrame then BearymailScrollFrame:Hide() end
        contentText:SetText("|cff888888Почтовый конвейер пуст.\nВ сумках нет настроенных ресурсов\nдля ваших твинков.|r")
        contentText:Show()
        return
    end
    
    -- 1. Сводный заголовок
    table.insert(displayData, { type = "title", text = string.format("|cff00ff00Будет отправлено писем: %d шт.|r", #virtualMailQueue) })
    table.insert(displayData, { type = "line", text = "|cff444444_______________________________________________________|r" })
    
    -- 2. Разбираем очередь писем
    for mailIndex, mailData in ipairs(virtualMailQueue) do
        table.insert(displayData, { type = "title", text = string.format("|cffffd100Письмо %d|r : |cff00ffff[%s]|r (%s)", mailIndex, mailData.target, mailData.topic) })
        
        for _, item in ipairs(mailData.items) do
            local itemID = tonumber(string.match(item.link, "item:(%d+)"))
            table.insert(displayData, { 
                type = "item", 
                text = string.format("• |cffffffff%d|r шт. %s", item.count, item.link), 
                id = itemID 
            })
        end
        table.insert(displayData, { type = "line", text = "|cff444444_______________________________________________________|r" })
    end
    
    -- 3. Выводим на экран через скролл Blizzard
    if BearymailScrollFrame then BearymailScrollFrame:Show() end
    FauxScrollFrame_Update(BearymailScrollFrame, #displayData, 14, 22)
    local offset = FauxScrollFrame_GetOffset(BearymailScrollFrame)
    
    for i = 1, 14 do
        local dataIndex = offset + i
        local node = displayData[dataIndex]
        local row = sendFramesPool[i] or CreateSendReportRow(i)
        
        if node then
            if node.type == "item" and node.id then
                -- СТРОКА С ПРЕДМЕТОМ: Достаем иконку из кэша игры
                local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(node.id)
                if itemTexture then
                    row.icon:SetTexture(itemTexture)
                    row.icon:Show()
                    -- Подвигаем текст ровно к иконке
                    row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
                else
                    row.icon:Hide()
                    row.text:SetPoint("LEFT", row, "LEFT", 25, 0)
                end
                row.text:SetText(node.text)
            else
                -- ЗАГОЛОВОК ИЛИ ЛИНИЯ: Прячем иконку, сдвигаем текст влево
                row.icon:Hide()
                row.text:SetPoint("LEFT", row, "LEFT", 10, 0)
                row.text:SetText(node.text)
            end
            row:Show()
        else
            row:Hide()
        end
    end
end


-- ============================================================================
-- БЛОК 7.3: ОБНОВЛЕННЫЙ ДИСПЛЕЙ, СОБЫТИЯ ПОЧТЫ И РОБОТ КОНВЕЙЕРА С КОНТРОЛЕМ
-- ============================================================================

-- ============================================================================
-- ИСПРАВЛЕННЫЙ УМНЫЙ ДИС ПЛЕЙ (Скрывает ПЛЮС и МИНУС на 4-й вкладке)
-- ============================================================================
UpdateContentDisplay = function()
    if contentText then contentText:Hide() end
    for _, row in ipairs(categoryRows) do row:Hide() end
    for _, row in ipairs(exceptionRows) do row:Hide() end
    for _, row in ipairs(blacklistRows) do row:Hide() end
    for _, row in ipairs(sendFramesPool) do row:Hide() end
    
    if activeTab == 4 and selectedCharacter then
        -- СКРЫВАЕМ ВСЮ ВЕРХУШКУ ОКНА
        if BM_CharDropdown then BM_CharDropdown:Hide() end
        if BM_NameInput then BM_NameInput:Hide() end
        if dropdownLabel then dropdownLabel:Hide() end
        if BM_AddUserButton then BM_AddUserButton:Hide() end
        if BM_RemoveUserButton then BM_RemoveUserButton:Hide() end
        
        -- Сдвигаем рамку отчета на самый верх
        contentFrame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 20, -40)
        contentFrame:SetSize(440, 340)
        if BearymailScrollFrame then 
            BearymailScrollFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -10)
            BearymailScrollFrame:SetSize(410, 320)
        end
        
        if BM_RunSendButton then BM_RunSendButton:Show() end
        if BM_CancelSendButton then BM_CancelSendButton:Show() end
    else
        -- ВОЗВРАЩАЕМ НАСТРОЙКИ НА МЕСТО
        if BM_CharDropdown then BM_CharDropdown:Show() end
        if dropdownLabel then dropdownLabel:Show() end
        if BM_AddUserButton then BM_AddUserButton:Show() end
        if BM_RemoveUserButton then BM_RemoveUserButton:Show() end
        if BM_NameInput then BM_NameInput:Hide() end
        
        contentFrame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 20, -115)
        contentFrame:SetSize(440, 310)
        if BearymailScrollFrame then 
            BearymailScrollFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -10)
            BearymailScrollFrame:SetSize(410, 290)
        end
        
        if BM_RunSendButton then BM_RunSendButton:Hide() end
        if BM_CancelSendButton then BM_CancelSendButton:Hide() end
    end
    
    if not selectedCharacter then
        if BearymailScrollFrame then BearymailScrollFrame:Hide() end
        if contentText then
            contentText:SetText("|cff888888Сначала выберите или\nдобавьте персонажа сверху|r")
            contentText:Show()
        end
        return
    end
    
    if BearymailScrollFrame then BearymailScrollFrame:Hide() end
    
    if activeTab == 1 then UpdateCategoriesTab()
    elseif activeTab == 2 then UpdateExceptionsTab()
    elseif activeTab == 3 then UpdateBlacklistTab()
    elseif activeTab == 4 then 
        -- ИСПРАВЛЕНИЕ: Перед отрисовкой 4-й вкладки всегда запускаем актуальный пересчет сумок!
        ScanBagsForVirtualQueue() 
        UpdateSendTab() 
    end
end


-- Переменные состояния почтового робота
local isMailOpen = false
local delayTimer = 0
local delayActive = false
local isSending = false
local sessionLog = {}
local lastSnapshotHash = "" -- Уникальная строка состава сумок для умного контроля изменений

-- Функция генерации текстового хэша сумок
local function GetBagsSnapshotHash()
    local hash = ""
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local itemLink = GetContainerItemLink(bag, slot)
            if itemLink then
                local _, count = GetContainerItemInfo(bag, slot)
                hash = hash .. itemLink .. tostring(count or 1) .. ","
            end
        end
    end
    return hash
end

-- Функция вывода итогового отчета в чат
local function ShowMailSessionReport()
    local hasData = false
    for char, items in pairs(sessionLog) do
        for itemLink, count in pairs(items) do if count > 0 then hasData = true end end
    end
    if not hasData then return end
    
    ChatMsg("|cffffd100--- Отчет о рассылке Bearymail ---|r")
    for characterName, items in pairs(sessionLog) do
        local reportLines = {}
        for itemLink, count in pairs(items) do
            if count > 0 then
                table.insert(reportLines, string.format("|cffffffff%d|r шт. %s", count, itemLink))
            end
        end
        if #reportLines > 0 then
            ChatMsg(string.format("• |cff00ffff%s|r: отправлено %s", characterName, table.concat(reportLines, ", ")))
        end
    end
    ChatMsg("|cffffd100-----------------------------------|r")
    sessionLog = {}
end

-- ============================================================================
-- РОБОТ-КОНВЕЙЕР С ДИНАМИЧЕСКОЙ ТЕМОЙ ПИСЬМА (Bearymail: Имя предмета)
-- ============================================================================
local function ExecuteMailSendingQueue()
    if not isMailOpen then return end
    
    local currentMail = virtualMailQueue[1]
    if not currentMail then
        if BearymailFrame then BearymailFrame:Hide() end
        ShowMailSessionReport()
        isSending = false
        return
    end
    
    if MailFrameTab2 then MailFrameTab2:Click() end
    
    -- ОПРЕДЕЛЯЕМ ИМЯ ПЕРВОГО ПРЕДМЕТА ДЛЯ ТЕМЫ
    local firstItemSubject = currentMail.topic --Fallback-вариант, если кэш игры пуст
    if currentMail.items and currentMail.items[1] then
        local cleanName = GetItemInfo(currentMail.items[1].link)
        if cleanName then
            firstItemSubject = cleanName
        end
    end
    
    -- Заполняем бланк почты
    SendMailNameEditBox:SetText(currentMail.target)
    -- ИСПРАВЛЕНО: Тема теперь формируется динамически!
    SendMailSubjectEditBox:SetText("Bearymail: " .. firstItemSubject)
    
    local itemsInThisMail = {}
    local currentAttachmentCount = 0
    
    for _, itemData in ipairs(currentMail.items) do
        if currentAttachmentCount >= 12 then break end
        
        local slotFound = false
        for bag = 0, 4 do
            local numSlots = GetContainerNumSlots(bag)
            for slot = 1, numSlots do
                local itemLink = GetContainerItemLink(bag, slot)
                if itemLink and itemLink == itemData.link then
                    local _, itemCount, locked = GetContainerItemInfo(bag, slot)
                    if not locked and itemCount == itemData.count then
                        UseContainerItem(bag, slot)
                        currentAttachmentCount = currentAttachmentCount + 1
                        itemsInThisMail[itemLink] = (itemsInThisMail[itemLink] or 0) + itemCount
                        slotFound = true
                        break
                    end
                end
            end
            if slotFound then break end
        end
    end
    
    if currentAttachmentCount > 0 then
        isSending = true
        
        if not sessionLog[currentMail.target] then sessionLog[currentMail.target] = {} end
        for itemLink, count in pairs(itemsInThisMail) do
            sessionLog[currentMail.target][itemLink] = (sessionLog[currentMail.target][itemLink] or 0) + count
        end
        
        table.remove(virtualMailQueue, 1)
        -- Отправляем письмо с нашей новой динамической темой
        SendMail(currentMail.target, "Bearymail: " .. firstItemSubject, "")
    else
        table.remove(virtualMailQueue, 1)
        delayTimer = 0
        delayActive = true
    end
end


-- Скрытый обработчик почтового ящика и контроля сумок
local mailEventFrame = CreateFrame("Frame")
mailEventFrame:RegisterEvent("MAIL_SHOW")
mailEventFrame:RegisterEvent("MAIL_CLOSED")
mailEventFrame:RegisterEvent("MAIL_SEND_SUCCESS")
mailEventFrame:RegisterEvent("BAG_UPDATE") -- Следим за изменениями сумок в реальном времени

mailEventFrame:SetScript("OnUpdate", function(self, elapsed)
    if delayActive then
        delayTimer = delayTimer + elapsed
        if delayTimer >= 0.6 then
            delayActive = false
            delayTimer = 0
            if isMailOpen then
                if isSending then
                    -- Если мы в процессе отправки — шлем следующее письмо
                    ExecuteMailSendingQueue()
                else
                    -- Если просто открыто окно подтверждения — обновляем скан
                    ScanBagsForVirtualQueue()
                    UpdateContentDisplay()
                end
            end
        end
    end
end)

-- ============================================================================
-- ПРАВИЛЬНЫЙ ОБРАБОТЧИК СОБЫТИЙ ЯЩИКА (ЖДЕТ НАЖАТИЯ КНОПКИ)
-- ============================================================================
mailEventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "MAIL_SHOW" then
        isMailOpen = true
        isSending = false
        sessionLog = {}
        
        -- Делаем тихий пре-скан сумок
        ScanBagsForVirtualQueue()
        
        -- Если нашли вещи к рассылке, открываем окно на 4-й вкладке и ЖДЕМ
        if #virtualMailQueue > 0 then
            lastSnapshotHash = GetBagsSnapshotHash()
            activeTab = 4 -- Автоматически включаем вкладку "Рассылка"
            -- ИСПРАВЛЕНИЕ: Принудительно подсвечиваем 4-ю вкладку в интерфейсе игры
            PanelTemplates_SetTab(mainFrame, 4)

            -- Привязываем клик к кнопке "Отправить"
            if BM_RunSendButton then
                BM_RunSendButton:SetScript("OnClick", function()
                    local currentHash = GetBagsSnapshotHash()
                    if currentHash ~= lastSnapshotHash then
                        lastSnapshotHash = currentHash
                        ScanBagsForVirtualQueue()
                        UpdateContentDisplay()
                        ChatMsg("|cffff0000⚠️ Состав сумок изменился! Проверьте список писем и нажмите 'Отправить' еще раз.|r")
                        return
                    end
                    
                    isSending = true
                    if MailFrameTab2 then MailFrameTab2:Click() end
                    ExecuteMailSendingQueue() -- Вот теперь запускаем отправку только по клику!
                end)
            end
            
            RefreshDropdown()
            mainFrame:Show() 
        end
        
    elseif event == "MAIL_CLOSED" then
        isMailOpen = false
        delayActive = false
        isSending = false
        mainFrame:Hide()
        ShowMailSessionReport()
        
    elseif event == "MAIL_SEND_SUCCESS" then
        isSending = true -- Поддерживаем флаг, чтобы гнать очередь дальше через OnUpdate
        delayTimer = 0
        delayActive = true
        
    elseif event == "BAG_UPDATE" then
        -- Плавно обновляем список писем, если игрок перекладывает вещи при открытой почте
        if isMailOpen and not isSending and activeTab == 4 then
            delayTimer = 0
            delayActive = true
        end
    end
end)

-- ИНИЦИАЛИЗАЦИЯ И ЭВЕНТЫ ЯДРА BEARAMYIL
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    local arg1 = ...
    if event == "ADDON_LOADED" and arg1 == "Bearymail" then
        if not BearymailDB then BearymailDB = defaultDB end
        if not BearymailDB.characters then BearymailDB.characters = {} end
        if not BearymailDB.blacklists then BearymailDB.blacklists = {} end
        if not BearymailDB.exceptions then BearymailDB.exceptions = {} end
        if not BearymailDB.targets then BearymailDB.targets = {} end
        
        local myName = UnitName("player")
        local found = false
        for _, name in ipairs(BearymailDB.characters) do
            if name == myName then found = true break end
        end
        if not found then table.insert(BearymailDB.characters, myName) end
        
        CreateMainLayout()
        CreateTopPanel()
        CreateCategoriesTabRows()
        CreateTabsSystem()
        
        -- Регистрация окна в меню Интерфейс -> Модификации
        local optionsPanel = CreateFrame("Frame", "BearymailOptionsPanel", UIParent)
        optionsPanel.name = "Bearymail"
        local panelTitle = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        panelTitle:SetPoint("TOPLEFT", optionsPanel, "TOPLEFT", 16, -16)
        panelTitle:SetText("Bearymail — Настройки медвежьей почты /bm")
        local openMenuBtn = CreateFrame("Button", nil, optionsPanel, "UIPanelButtonTemplate")
        openMenuBtn:SetSize(160, 26)
        openMenuBtn:SetPoint("TOPLEFT", panelTitle, "BOTTOMLEFT", 0, -20)
        openMenuBtn:SetText("Открыть окно настроек")
        openMenuBtn:SetScript("OnClick", function()
            InterfaceOptionsFrameCancel:Click()
            if mainFrame then RefreshDropdown() mainFrame:Show() end
        end)
        InterfaceOptions_AddCategory(optionsPanel)
        
        tinsert(UISpecialFrames, "BearymailFrame")
        selectedCharacter = myName
        RefreshDropdown()
    end
end)

-- НАДЕЖНАЯ РЕГИСТРАЦИЯ КОМАНДЫ /bm
SLASH_BEARYMAIL1 = "/bm"
SlashCmdList["BEARYMAIL"] = function()
    if mainFrame then
        if mainFrame:IsShown() then mainFrame:Hide() else RefreshDropdown() mainFrame:Show() end
    end
end
--[[
-- ============================================================================
-- ИНТЕГРАЦИЯ В СТАНДАРТНОЕ МЕНЮ ИГРЫ (ИНТЕРФЕЙС -> МОДИФИКАЦИИ)
-- ============================================================================
local optionsPanel = CreateFrame("Frame", "BearymailOptionsPanel", UIParent)
optionsPanel.name = "Bearymail"

-- Создаем заголовок внутри панели настроек
local panelTitle = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
panelTitle:SetPoint("TOPLEFT", optionsPanel, "TOPLEFT", 16, -16)
panelTitle:SetText("Bearymail — Настройки медвежьей почты /bm")

-- Создаем кнопку для вызова главного окна настроек
local openMenuBtn = CreateFrame("Button", nil, optionsPanel, "UIPanelButtonTemplate")
openMenuBtn:SetSize(160, 26)
openMenuBtn:SetPoint("TOPLEFT", panelTitle, "BOTTOMLEFT", 0, -20)
openMenuBtn:SetText("Открыть окно настроек")

openMenuBtn:SetScript("OnClick", function()
    -- Закрываем стандартное меню интерфейса, чтобы оно не мешало
    InterfaceOptionsFrameCancel:Click() 
    -- Показываем наше красивое окно
    if BearymailFrame then
        RefreshDropdown()
        BearymailFrame:Show()
    end
end)

-- Регистрируем панель в стандартном интерфейсе WoW Лич Кинга
InterfaceOptions_AddCategory(optionsPanel)
--]]

-- ============================================================================
-- БЛОК 8: РОБОТ АВТОМАТИЧЕСКОЙ ПОЧТОВОЙ РАССЫЛКИ BEARMYIL
-- ============================================================================
local isMailOpen = false
local delayTimer = 0
local delayActive = false
local isSending = false
local sessionLog = {} 

-- Функция вывода КРАСИВОГО И ДЕТАЛИЗИРОВАННОГО отчета в чат по предметам
local function ShowMailSessionReport()
    local hasData = false
    for char, items in pairs(sessionLog) do
        for itemLink, count in pairs(items) do
            if count > 0 then hasData = true end
        end
    end
    
    if not hasData then return end
    
    ChatMsg("|cffffd100--- Отчет о рассылке Bearymail ---|r")
    for characterName, items in pairs(sessionLog) do
        local reportLines = {}
        for itemLink, count in pairs(items) do
            if count > 0 then
                -- Форматируем красиво: "Количество шт. [Ссылка на предмет]"
                table.insert(reportLines, string.format("|cffffffff%d|r шт. %s", count, itemLink))
            end
        end
        -- Соединяем предметы для одного персонажа через запятую
        if #reportLines > 0 then
            ChatMsg(string.format("• |cff00ffff%s|r: отправлено %s", characterName, table.concat(reportLines, ", ")))
        end
    end
    ChatMsg("|cffffd100-----------------------------------|r")
    sessionLog = {} 
end


-- ============================================================================
-- ЧАСТЬ 8.2: ИСПРАВЛЕННАЯ ФУНКЦИЯ СБОРА И ДЕТАЛЬНОГО ЛОГИРОВАНИЯ
-- ============================================================================
function ProcessMailQueue()
    if not isMailOpen or isSending then return end
    
    local currentAttachmentCount = 0
    local targetCharacter = nil
    local activeSubclass = nil
    
    -- Таблица для подсчета предметов КОНКРЕТНО в этом одном письме
    local itemsInThisMail = {} 
    
    local currentPatternChar = UnitName("player")
    
    SendMailNameEditBox:SetText("")
    SendMailSubjectEditBox:SetText("")
    
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            
            if currentAttachmentCount >= 12 then break end
            
            local itemLink = GetContainerItemLink(bag, slot)
            if itemLink then
                local itemID = tonumber(string.match(itemLink, "item:(%d+)"))
                
                if itemID then
                    local _, _, _, _, _, _, itemSubClass = GetItemInfo(itemLink)
                    
                    local isBlacklisted = false
                    if BearymailDB.blacklists[currentPatternChar] and BearymailDB.blacklists[currentPatternChar][itemID] then
                        isBlacklisted = true
                    end
                    
                    if not isBlacklisted then
                        local assignedChar = nil
                        local logCategoryName = "Ресурсы"
                        
                        if BearymailDB.exceptions[itemID] then
                            assignedChar = BearymailDB.exceptions[itemID]
                            logCategoryName = "Исключение"
                        elseif itemSubClass and BearymailDB.targets[itemSubClass] then
                            assignedChar = BearymailDB.targets[itemSubClass]
                            logCategoryName = itemSubClass
                        end
                        
                        if assignedChar and assignedChar ~= currentPatternChar then
                            
                            if not targetCharacter then
                                targetCharacter = assignedChar
                                activeSubclass = logCategoryName
                                
                                SendMailNameEditBox:SetText(targetCharacter)
                                SendMailSubjectEditBox:SetText(": " .. activeSubclass)
                            end
                            
                            if targetCharacter == assignedChar and (logCategoryName == activeSubclass or logCategoryName == "Исключение") then
                                
                                if IsItemBound(bag, slot, nil) then
                                    isBlacklisted = true 
                                end
                                
                                if not isBlacklisted then
                                    local _, itemCount, locked = GetContainerItemInfo(bag, slot)
                                    if not locked then
                                        UseContainerItem(bag, slot) 
                                        currentAttachmentCount = currentAttachmentCount + 1
                                        
                                        -- Сохраняем ссылку на предмет и прибавляем количество в этом письме
                                        itemsInThisMail[itemLink] = (itemsInThisMail[itemLink] or 0) + (itemCount or 1)
                                    end
                                end
                            end 
                            
                        end
                    end
                end
                
            end
        end
    end
    
    if targetCharacter and currentAttachmentCount > 0 then
        isSending = true
        
        -- Переносим собранные предметы из этого письма в общий лог сессии
        if not sessionLog[targetCharacter] then sessionLog[targetCharacter] = {} end
        for itemLink, count in pairs(itemsInThisMail) do
            sessionLog[targetCharacter][itemLink] = (sessionLog[targetCharacter][itemLink] or 0) + count
        end
        
        SendMail(targetCharacter, ": " .. activeSubclass, "")
    else
        ShowMailSessionReport()
    end
end


-- Отдельный скрытый фрейм для отслеживания открытия ящика
local mailEventFrame = CreateFrame("Frame")
mailEventFrame:RegisterEvent("MAIL_SHOW")
mailEventFrame:RegisterEvent("MAIL_CLOSED")
mailEventFrame:RegisterEvent("MAIL_SEND_SUCCESS")

mailEventFrame:SetScript("OnUpdate", function(self, elapsed)
    if delayActive then
        delayTimer = delayTimer + elapsed
        if delayTimer >= 0.6 then -- Безопасный таймаут для Сируса
            delayActive = false
            delayTimer = 0
            if isMailOpen and not isSending then
                ProcessMailQueue()
            end
        end
    end
end)

--[[
mailEventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "MAIL_SHOW" then
        isMailOpen = true
        isSending = false
        sessionLog = {}
        if MailFrameTab2 then MailFrameTab2:Click() end -- Принудительно открываем вкладку отправки
        
        delayTimer = 0
        delayActive = true
        
    elseif event == "MAIL_CLOSED" then
        isMailOpen = false
        delayActive = false
        isSending = false
        ShowMailSessionReport()
        
    elseif event == "MAIL_SEND_SUCCESS" then
        isSending = false
        delayTimer = 0
        delayActive = true -- Сервер подтвердил отправку, собираем следующее письмо
    end
end)
--]]