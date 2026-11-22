-- [ Services ] --
local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer

-- [ Webhook 設定 ] --
local WEBHOOK_URL = "這裡" -- 在引號內加入您的webhook

-- [ Webhook 輔助函數：獲取玩家頭像 ] --
local function GetUserAvatarUrl(userId)
    local requestFunc = (syn and syn.request) or (http and http.request) or request or (fluxus and fluxus.request)
    if not requestFunc then 
        return string.format("https://www.roblox.com/headshot-thumbnail/image?userId=%d&width=420&height=420&format=png", userId) 
    end

    local apiUrl = string.format("https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=%d&size=420x420&format=Png&isCircular=false", userId)
    local success, response = pcall(function()
        return requestFunc({
            Url = apiUrl,
            Method = "GET"
        })
    end)

    if success and response and response.Body then
        local decodeSuccess, data = pcall(function() return HttpService:JSONDecode(response.Body) end)
        if decodeSuccess and data and data.data and data.data[1] and data.data[1].imageUrl then
            return data.data[1].imageUrl
        end
    end

    return string.format("https://www.roblox.com/headshot-thumbnail/image?userId=%d&width=420&height=420&format=png", userId)
end

-- [ Discord Webhook：單純上線通知 (短短一句) ] --
local function SendOnlineWebhook(userName)
    if WEBHOOK_URL == "" then return end

    local requestFunc = (syn and syn.request) or (http and http.request) or request or (fluxus and fluxus.request)
    if not requestFunc then return end

    local data = {
        content = string.format("**```%s```** 目前在線上", userName)
    }

    pcall(function()
        requestFunc({
            Url = WEBHOOK_URL,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode(data)
        })
    end)
end

-- [ Discord Webhook：開放 Everyone 且在線 (允許跟服詳細卡片) ] --
local function SendDiscordWebhook(userName, userId)
    if WEBHOOK_URL == "" then return end

    local requestFunc = (syn and syn.request) or (http and http.request) or request or (fluxus and fluxus.request)
    if not requestFunc then return end

    local avatarUrl = GetUserAvatarUrl(userId)
    local pcScript = string.format("local remotes = game:GetService('ReplicatedStorage'):FindFirstChild('Remotes')\nif remotes and remotes:FindFirstChild('JoinPlayerFromProfile') then\n    remotes.JoinPlayerFromProfile:FireServer(%d)\nend", userId)
    local mobileScript = string.format("game:GetService('ReplicatedStorage').Remotes.JoinPlayerFromProfile:FireServer(%d)", userId)

    local embed = {
        title = "🚀 發現可跟服玩家",
        description = string.format("✨ **目標玩家:** `%s`\n🆔 **User ID:** `%d`\n🔑 **跟服權限:** `Everyone (所有人)`\n🌐 **狀態:** 🟢 在線", userName, userId),
        color = 0x22C55E,
        thumbnail = {
            url = avatarUrl
        },
        fields = {
            {
                name = "💻 電腦端加入腳本",
                value = string.format("```lua\n%s\n```", pcScript),
                inline = false
            },
            {
                name = "📱 手機端加入腳本",
                value = string.format("`%s`", mobileScript),
                inline = false
            }
        },
        footer = {
            text = "🛡️ PlayerTrackerX Pro • 監控系統",
        },
        timestamp = DateTime.now():ToIsoDate()
    }

    local data = {
        content = string.format("🎯 玩家 `%s` 目前開放跟服", userName), 
        embeds = {embed}
    }

    pcall(function()
        requestFunc({
            Url = WEBHOOK_URL,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode(data)
        })
    end)
end

-- [ Anti AFK 系統 ] --
_G.AntiAFK_ENABLED = true
_G.AntiAFK_Connection = nil

local function EnableAntiAFK()
    if _G.AntiAFK_Connection then
        _G.AntiAFK_Connection:Disconnect()
        _G.AntiAFK_Connection = nil
    end

    if getconnections then
        for _, conn in pairs(getconnections(LocalPlayer.Idled)) do
            conn:Disable()
        end
    end

    _G.AntiAFK_Connection = LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end

local function DisableAntiAFK()
    if _G.AntiAFK_Connection then 
        _G.AntiAFK_Connection:Disconnect()
        _G.AntiAFK_Connection = nil 
    end
end

if _G.AntiAFK_ENABLED then
    EnableAntiAFK()
end

-- [ 預設追蹤玩家名單 ] --
local targetUsers = {
    "NoctisAUS", "giozvq", "NovaExility", "MollaAmar", "ZeroZero_Two", "Abso_Delete", "SirReis", "kyt0kyt0",
    "Mertlcle", "Daigrock", "Axiore", "BluxxyGaming", "dethsmurf", "CJ_Oyer", "mrheffner_gg", "vidsmurf",
    "0BCLIFETIME", "orkoal", "Tacomura", "rip_indra", "Experimic", "arowe", "Uzi_London", "Guashiem",
    "torrtoise", "ShafiDev", "SylentAsura", "ElG8T", "my6thlife", "AznWay", "uranium_devil", "Nat_7517",
    "Krossful", "FRANKENSTEIN_L", "FindMotion", "rip_bac0nha", "arlthmetic", "rip_fud", "wenlocktoad",
    "RealmKisame", "mygame43", "OGTeranas", "testprem0", "mkivtt", "xonae", "iSekai_iSekai", "Uzoth",
    "Zioles", "numberskull999", "imLockGod", "KatakuriKloudz", "Kaidozyuh", "Rajo_END", "KoopekulYT",
    "MagicbusYT", "Senmarine", "jet5ss", "CRBoneMillion", "starcode_kitt", "oofficialnoobie", "JCDoesGaming_YT",
    "TheRealFoltyn", "TheGreatAced", "StarCode_fer", "Jujujutv1", "MouseTheBoi", "slat_real2", "EnyuZee",
    "NoobWithKitsunee", "MeteoricRBLX", "kyriemiles8", "Sai_JinWoo", "BloxyDRoblox", "geladobiel",
    "DefinitelyNotBaxtrix", "WoozerBloxYT", "divingintea", "Heorua", "HyperJay06_Official", "Smythsterr",
    "TyePHX", "Lunoven", "sappVFX", "RealYurl", "Generic_ult", "P4CKSTABBER", "MoraIins", "FallenER0S",
    "OutOfDinos", "nopatrol", "TobersDaArtisto", "thienbaokhang1", "Kuroxity", "fl8mey", "Bredddo",
    "Jurillianio", "EstheKing", "baswbaswbasw", "PuddingBumby", "Disard0", "Bread_Doppio", "MuG3ED",
    "tushai", "Korwiaa", "jers_e", "r_Forbidden", "UnrioChief1", "deadninjstar87",
    "LegendOfKio", "SirZareli", "Plokster", "Marubravery", "Artszy", "TrucBiduleur100", "AYoungPhienix",
    "FriedLemonsLoL", "SandiestSandy", "iPrefectSoul", "InfinityExtended", "Adcium", "DaylightSparkIe",
    "Poifilion", "xZenbrook", "TrayDonce", "khongco789", "dutbooot", "ExtremeBlastSS", "alexoi20",
    "wMadara_X", "Glitch1ng12", "Rusta_92", "tolovemnice", "IrohaIgarashiBaller", "thesilliestminty",
    "spiritualsound", "PringleCanKid", "truonked", "corina1234x", "icelandic123", "corazonqr",
    "rip_russiachat", "vanxing", "WELOVETOKYO", "truownk", "iIlillnickjenkinsill", "DragonDojoOwner",
    "fr33dim", "ProtoValence", "cooljustint1229", "SkhypeXD", "c0lbl0cks", "CorvusCoraxx", "APandaPoet",
    "catchymelodies", "lowendisekaialt", "ignotuscaligo", "MangoBytz", "vqanxx", "TretaTbh", "0Krvs",
    "rigtoni09", "DevForumOps", "BisoBlitz", "eternallav", "DevNexusCore", "b0bbber", "StalwartWarden",
    "devils21091", "Blotnik", "kablowert", "1OmniJelly1", "RayBloxSunshine", "newtonmetre", "MrChickenRocket",
    "golden_shellfish", "Doonkahn", "TB_Glitch", "NoDankMemesAllowed", "captainbramble", "CosmoSloth",
    "Felku", "undercover_admin23", "Arkesium", "RosesAreBlueish", "Suizei",
    "Quasiduck", "Azarth", "NOT_CRYTICAL", "BachaBlox", "drip_mama", "wenloco", "Phoeating", "vgmsgame",
    "brqod", "sisterton", "0MARIKENZ0", "norperz", "EIRodoIfo", "sarcxsm", "VehemenciaI", "owidhdk29", "MrPhyllister"
}

-- [ 現代化 UI 色彩配置 ] --
local Theme = {
    Background = Color3.fromRGB(24, 24, 27),
    Panel = Color3.fromRGB(39, 39, 42),
    PanelHover = Color3.fromRGB(63, 63, 70),
    Stroke = Color3.fromRGB(63, 63, 70),
    TextPrimary = Color3.fromRGB(244, 244, 245),
    TextSecondary = Color3.fromRGB(161, 161, 170),
    Accent = Color3.fromRGB(99, 102, 241),
    AccentHover = Color3.fromRGB(79, 70, 229),
    Success = Color3.fromRGB(34, 197, 94),
    SuccessHover = Color3.fromRGB(22, 163, 74),
    Danger = Color3.fromRGB(239, 68, 68),
    DangerHover = Color3.fromRGB(220, 38, 38),
    Warning = Color3.fromRGB(234, 179, 8),
    ScanIdle = Color3.fromRGB(139, 92, 246),
    ScanActive = Color3.fromRGB(82, 82, 91),
    ScanDone = Color3.fromRGB(16, 185, 129)
}

-- [ 輔助函數 ] --
local function Create(className, properties)
    local instance = Instance.new(className)
    for k, v in pairs(properties) do instance[k] = v end
    return instance
end

local function Tween(obj, props, duration)
    TweenService:Create(obj, TweenInfo.new(duration or 0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props):Play()
end

local function AddHover(btn, normalColor, hoverColor)
    btn.MouseEnter:Connect(function() Tween(btn, {BackgroundColor3 = hoverColor}) end)
    btn.MouseLeave:Connect(function() 
        if btn:GetAttribute("IsSelected") then return end
        Tween(btn, {BackgroundColor3 = normalColor}) 
    end)
end

-- [ 重置舊 GUI ] --
local parentContainer = gethui and gethui() or CoreGui
local oldGui = parentContainer:FindFirstChild("XuPlayerTrackerX")
if oldGui then oldGui:Destroy() end

-- [ 初始化 ScreenGui ] --
local ScreenGui = Create("ScreenGui", {
    Name = "XuPlayerTrackerX",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    Parent = parentContainer
})

-- 主視窗
local MainFrame = Create("Frame", {
    Name = "MainFrame",
    Size = UDim2.new(0, 560, 0, 340), 
    Position = UDim2.new(0.5, -280, 0.5, -170),
    BackgroundColor3 = Theme.Background,
    BorderSizePixel = 0,
    Parent = ScreenGui
})
Create("UICorner", {CornerRadius = UDim.new(0, 10), Parent = MainFrame})
Create("UIStroke", {Color = Theme.Stroke, Thickness = 1.5, Parent = MainFrame})

-- 頂部標題列
local TitleBar = Create("Frame", {
    Size = UDim2.new(1, 0, 0, 40),
    BackgroundColor3 = Theme.Background,
    BorderSizePixel = 0,
    Parent = MainFrame
})
Create("UICorner", {CornerRadius = UDim.new(0, 10), Parent = TitleBar})
Create("Frame", {
    Size = UDim2.new(1, 0, 0, 10),
    Position = UDim2.new(0, 0, 1, -10),
    BackgroundColor3 = Theme.Background,
    BorderSizePixel = 0,
    Parent = TitleBar
})
Create("Frame", {
    Size = UDim2.new(1, 0, 0, 1),
    Position = UDim2.new(0, 0, 1, 0),
    BackgroundColor3 = Theme.Stroke,
    BorderSizePixel = 0,
    Parent = TitleBar
})

local TitleLabel = Create("TextLabel", {
    Size = UDim2.new(1, -50, 1, 0),
    Position = UDim2.new(0, 16, 0, 0),
    BackgroundTransparency = 1,
    Text = "🛡️ 玩家狀態追蹤器 Pro",
    TextColor3 = Theme.TextPrimary,
    Font = Enum.Font.GothamBold,
    TextSize = 15,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = TitleBar
})

local CloseButton = Create("TextButton", {
    Size = UDim2.new(0, 30, 0, 30),
    Position = UDim2.new(1, -38, 0.5, -15),
    BackgroundColor3 = Theme.Background,
    Text = "X",
    TextColor3 = Theme.TextSecondary,
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    AutoButtonColor = false,
    Parent = TitleBar
})
Create("UICorner", {CornerRadius = UDim.new(0, 6), Parent = CloseButton})
AddHover(CloseButton, Theme.Background, Theme.Danger)
CloseButton.MouseEnter:Connect(function() Tween(CloseButton, {TextColor3 = Color3.fromRGB(255, 255, 255)}) end)
CloseButton.MouseLeave:Connect(function() Tween(CloseButton, {TextColor3 = Theme.TextSecondary}) end)

-- [ 左側：操作區 (寬 330) ] --
local LeftPanel = Create("Frame", {
    Size = UDim2.new(0, 330, 1, -55),
    Position = UDim2.new(0, 16, 0, 50),
    BackgroundTransparency = 1,
    Parent = MainFrame
})

-- 搜尋框
local InputBox = Create("TextBox", {
    Size = UDim2.new(1, 0, 0, 40),
    BackgroundColor3 = Theme.Panel,
    TextColor3 = Theme.TextPrimary,
    PlaceholderText = "輸入玩家名稱或 UserId...",
    PlaceholderColor3 = Theme.TextSecondary,
    Font = Enum.Font.GothamMedium,
    TextSize = 14,
    ClearTextOnFocus = false,
    Parent = LeftPanel
})
Create("UICorner", {CornerRadius = UDim.new(0, 8), Parent = InputBox})
Create("UIStroke", {Color = Theme.Stroke, Thickness = 1, Parent = InputBox})
Create("UIPadding", {PaddingLeft = UDim.new(0, 12), Parent = InputBox})

-- 檢查按鈕
local CheckBtn = Create("TextButton", {
    Size = UDim2.new(0, 106, 0, 36),
    Position = UDim2.new(0, 0, 0, 50),
    BackgroundColor3 = Theme.Accent,
    TextColor3 = Color3.new(1, 1, 1),
    Text = "🔍 檢查",
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    AutoButtonColor = false,
    Parent = LeftPanel
})
Create("UICorner", {CornerRadius = UDim.new(0, 8), Parent = CheckBtn})
AddHover(CheckBtn, Theme.Accent, Theme.AccentHover)

-- 加入按鈕
local JoinBtn = Create("TextButton", {
    Size = UDim2.new(0, 106, 0, 36),
    Position = UDim2.new(0, 112, 0, 50),
    BackgroundColor3 = Theme.Success,
    TextColor3 = Color3.new(1, 1, 1),
    Text = "🚀 加入",
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    AutoButtonColor = false,
    Parent = LeftPanel
})
Create("UICorner", {CornerRadius = UDim.new(0, 8), Parent = JoinBtn})
AddHover(JoinBtn, Theme.Success, Theme.SuccessHover)

-- 複製按鈕
local CopyBtn = Create("TextButton", {
    Size = UDim2.new(0, 106, 0, 36),
    Position = UDim2.new(0, 224, 0, 50),
    BackgroundColor3 = Theme.Panel,
    TextColor3 = Theme.TextPrimary,
    Text = "📋 複製",
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    AutoButtonColor = false,
    Parent = LeftPanel
})
Create("UICorner", {CornerRadius = UDim.new(0, 8), Parent = CopyBtn})
AddHover(CopyBtn, Theme.Panel, Theme.PanelHover)
Create("UIStroke", {Color = Theme.Stroke, Thickness = 1, Parent = CopyBtn})

-- 結果顯示區卡片
local ResultCard = Create("Frame", {
    Size = UDim2.new(1, 0, 0, 130),
    Position = UDim2.new(0, 0, 0, 100),
    BackgroundColor3 = Theme.Panel,
    Parent = LeftPanel
})
Create("UICorner", {CornerRadius = UDim.new(0, 8), Parent = ResultCard})
Create("UIStroke", {Color = Theme.Stroke, Thickness = 1, Parent = ResultCard})

local CardLayout = Instance.new("UIListLayout")
CardLayout.SortOrder = Enum.SortOrder.LayoutOrder
CardLayout.Padding = UDim.new(0, 10)
CardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
CardLayout.VerticalAlignment = Enum.VerticalAlignment.Center
CardLayout.Parent = ResultCard

Create("UIPadding", {
    PaddingLeft = UDim.new(0, 16),
    PaddingTop = UDim.new(0, 16),
    PaddingBottom = UDim.new(0, 16),
    Parent = ResultCard
})

local function CreateInfoLabel(icon, defaultText)
    local lbl = Create("TextLabel", {
        Size = UDim2.new(1, -20, 0, 18),
        BackgroundTransparency = 1,
        Text = icon .. " " .. defaultText,
        TextColor3 = Theme.TextPrimary,
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        RichText = true,
        Parent = ResultCard
    })
    return lbl
end

local S_NameLabel = CreateInfoLabel("👤", "玩家: <font color='#A1A1AA'>尚未查詢</font>")
local S_IDLabel = CreateInfoLabel("🆔", "ID: <font color='#A1A1AA'>-</font>")
local S_StatusLabel = CreateInfoLabel("🌐", "狀態: <font color='#A1A1AA'>閒置中</font>")
local S_JoinSettingLabel = CreateInfoLabel("🔑", "權限: <font color='#A1A1AA'>-</font>")

-- 一鍵掃描按鈕 
local ScanBtn = Create("TextButton", {
    Size = UDim2.new(1, 0, 0, 40),
    Position = UDim2.new(0, 0, 1, -40),
    BackgroundColor3 = Theme.ScanIdle, 
    TextColor3 = Color3.new(1, 1, 1),
    Text = "⚡ 啟動輪迴掃描",
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    AutoButtonColor = false,
    Parent = LeftPanel
})
Create("UICorner", {CornerRadius = UDim.new(0, 8), Parent = ScanBtn})
AddHover(ScanBtn, Theme.ScanIdle, Color3.fromRGB(124, 58, 237))

-- 暫停按鈕
local PauseBtn = Create("TextButton", {
    Size = UDim2.new(0, 40, 0, 40),
    Position = UDim2.new(1, -40, 1, -40),
    BackgroundColor3 = Theme.Warning,
    TextColor3 = Color3.new(1, 1, 1),
    Text = "⏸️",
    Font = Enum.Font.GothamBold,
    TextSize = 16,
    AutoButtonColor = false,
    Visible = false,
    Parent = LeftPanel
})
Create("UICorner", {CornerRadius = UDim.new(0, 8), Parent = PauseBtn})
AddHover(PauseBtn, Theme.Warning, Color3.fromRGB(202, 138, 4))

-- [ 右側：玩家選單與 Everyone (寬 185) ] --
local RightPanel = Create("Frame", {
    Size = UDim2.new(0, 185, 1, -55), 
    Position = UDim2.new(1, -201, 0, 50),
    BackgroundColor3 = Theme.Panel,
    BorderSizePixel = 0,
    Parent = MainFrame
})
Create("UICorner", {CornerRadius = UDim.new(0, 8), Parent = RightPanel})
Create("UIStroke", {Color = Theme.Stroke, Thickness = 1, Parent = RightPanel})

-- 分頁按鈕
local TabBar = Create("Frame", {
    Size = UDim2.new(1, -12, 0, 30),
    Position = UDim2.new(0, 6, 0, 6),
    BackgroundColor3 = Theme.Background,
    Parent = RightPanel
})
Create("UICorner", {CornerRadius = UDim.new(0, 6), Parent = TabBar})

local TabListBtn = Create("TextButton", {
    Size = UDim2.new(0.5, 0, 1, 0),
    BackgroundColor3 = Theme.PanelHover,
    TextColor3 = Theme.TextPrimary,
    Text = "📋 玩家名單",
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    AutoButtonColor = false,
    Parent = TabBar
})
Create("UICorner", {CornerRadius = UDim.new(0, 6), Parent = TabListBtn})

local TabRecordBtn = Create("TextButton", {
    Size = UDim2.new(0.5, 0, 1, 0),
    Position = UDim2.new(0.5, 0, 0, 0),
    BackgroundTransparency = 1,
    TextColor3 = Theme.TextSecondary,
    Text = "🔓 Everyone (0)",
    Font = Enum.Font.GothamBold,
    TextSize = 11,
    AutoButtonColor = false,
    Parent = TabBar
})
Create("UICorner", {CornerRadius = UDim.new(0, 6), Parent = TabRecordBtn})

-- 列表容器
local function CreateScrollList()
    local scrl = Create("ScrollingFrame", {
        Size = UDim2.new(1, -12, 1, -44),
        Position = UDim2.new(0, 6, 0, 42),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = Theme.Stroke,
        Parent = RightPanel
    })
    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 4)
    layout.Parent = scrl
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scrl.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 4)
    end)
    return scrl
end

local ListContainer = CreateScrollList()
local RecordContainer = CreateScrollList()
RecordContainer.Visible = false

-- 切換分頁邏輯
local function SwitchTab(activeBtn, inactiveBtn, showContainer, hideContainer)
    showContainer.Visible = true
    hideContainer.Visible = false
    Tween(activeBtn, {BackgroundTransparency = 0, BackgroundColor3 = Theme.PanelHover, TextColor3 = Theme.TextPrimary}, 0.2)
    Tween(inactiveBtn, {BackgroundTransparency = 1, TextColor3 = Theme.TextSecondary}, 0.2)
end

TabListBtn.MouseButton1Click:Connect(function() SwitchTab(TabListBtn, TabRecordBtn, ListContainer, RecordContainer) end)
TabRecordBtn.MouseButton1Click:Connect(function() SwitchTab(TabRecordBtn, TabListBtn, RecordContainer, ListContainer) end)

-- [ 邏輯處理區 ] --
local userIdCache = {}
local isBusy = false
local isScanning = false
local isPaused = false 
local selectedButton = nil
local everyoneRecords = {}
local everyoneCount = 0
local listButtonsMap = {}

local function setSelectedButton(btn)
    if selectedButton and selectedButton ~= btn then
        selectedButton:SetAttribute("IsSelected", false)
        Tween(selectedButton, {BackgroundColor3 = Theme.Background})
    end
    selectedButton = btn
    if selectedButton then
        selectedButton:SetAttribute("IsSelected", true)
        Tween(selectedButton, {BackgroundColor3 = Theme.Accent})
    end
end

local function highlightByName(name)
    local lowerName = string.lower(name)
    local function checkList(container)
        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("TextButton") then
                local cleanText = string.gsub(child.Text, "^[🟢🔴🔓]%s*", "")
                if string.lower(cleanText) == lowerName then
                    setSelectedButton(child)
                    return true
                end
            end
        end
    end
    if not checkList(ListContainer) then checkList(RecordContainer) end
end

local function addEveryoneRecord(userName, userId)
    if everyoneRecords[userId] then return end 
    everyoneCount = everyoneCount + 1
    everyoneRecords[userId] = true
    TabRecordBtn.Text = "🔓 Everyone (" .. everyoneCount .. ")"

    local RecordBtn = Create("TextButton", {
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundColor3 = Theme.Background,
        TextColor3 = Theme.Success,
        Text = "🔓 " .. userName,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        AutoButtonColor = false,
        Parent = RecordContainer
    })
    Create("UICorner", {CornerRadius = UDim.new(0, 6), Parent = RecordBtn})
    AddHover(RecordBtn, Theme.Background, Theme.PanelHover)

    RecordBtn.MouseButton1Click:Connect(function()
        InputBox.Text = userName
        setSelectedButton(RecordBtn)
        performCheck()
    end)
end

-- UI 拖拽邏輯
local dragging, dragInput, dragStart, startPos
TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = MainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
TitleBar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

CloseButton.MouseButton1Click:Connect(function()
    Tween(MainFrame, {Size = UDim2.new(0, 560, 0, 0), BackgroundTransparency = 1}, 0.3)
    for _, v in ipairs(MainFrame:GetChildren()) do if v:IsA("GuiObject") then v.Visible = false end end
    task.wait(0.3)
    ScreenGui:Destroy()
end)

local function getUserId(inputString)
    local cleanedInput = string.gsub(inputString, "^%s*(.-)%s*$", "%1")
    if cleanedInput == "" then return nil end
    local id = tonumber(cleanedInput)
    if id then return id end
    local lowerName = string.lower(cleanedInput)
    if userIdCache[lowerName] then return userIdCache[lowerName] end
    local success, result = pcall(function() return Players:GetUserIdFromNameAsync(cleanedInput) end)
    if success and result then 
        userIdCache[lowerName] = result
        return result 
    end
    return nil
end

local function checkOnlineData(data)
    if type(data) == "table" then
        return data.Online or data.IsOnline or (data.Server ~= nil) or false
    elseif data == true then return true end
    return false
end

local function fireJoinRequest(id)
    pcall(function()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if remotes and remotes:FindFirstChild("JoinPlayerFromProfile") then
            remotes.JoinPlayerFromProfile:FireServer(id)
        end
    end)
end

-- 執行狀態檢查的主函數
function performCheck()
    if isBusy then return end
    local inputStr = InputBox.Text
    if inputStr == "" then
        S_StatusLabel.Text = "🌐 狀態: <font color='#EAB308'>請輸入玩家名稱或 ID</font>"
        return
    end

    highlightByName(inputStr)
    isBusy = true
    S_NameLabel.Text = "👤 玩家: <font color='#FFFFFF'>" .. inputStr .. "</font>"
    S_StatusLabel.Text = "🌐 狀態: <font color='#A1A1AA'>獲取 ID 中...</font>"
    S_JoinSettingLabel.Text = "🔑 權限: <font color='#A1A1AA'>查詢中...</font>"

    task.spawn(function()
        local targetId = getUserId(inputStr)
        if not targetId then
            S_IDLabel.Text = "🆔 ID: <font color='#EF4444'>錯誤</font>"
            S_StatusLabel.Text = "🌐 狀態: <font color='#EF4444'>找不到該玩家</font>"
            S_JoinSettingLabel.Text = "🔑 權限: <font color='#A1A1AA'>-</font>"
            isBusy = false
            return
        end

        S_IDLabel.Text = "🆔 ID: <font color='#FFFFFF'>" .. targetId .. "</font>"
        S_StatusLabel.Text = "🌐 狀態: <font color='#A1A1AA'>查詢狀態中...</font>"

        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local getRemote = remotes and remotes:FindFirstChild("GetPlayerProfileData")

        if not getRemote then
            S_StatusLabel.Text = "🌐 狀態: <font color='#EF4444'>遊戲中找不到 Remote</font>"
            isBusy = false
            return
        end

        local success, data = pcall(function() return getRemote:InvokeServer(targetId) end)

        if success then
            local joinServerSetting = "Unknown"
            if type(data) == "table" and data.Settings and data.Settings.JoinServer then
                joinServerSetting = data.Settings.JoinServer
            end

            if data and checkOnlineData(data) then
                S_StatusLabel.Text = "🌐 狀態: <font color='#22C55E'>在線 (Online)</font>"
                if listButtonsMap[inputStr] then
                    listButtonsMap[inputStr].TextColor3 = Theme.Success
                    listButtonsMap[inputStr].Text = "🟢 " .. inputStr
                end

                if joinServerSetting == "Everyone" then
                    S_JoinSettingLabel.Text = "🔑 權限: <font color='#22C55E'>所有人 (Everyone)</font>"
                    addEveryoneRecord(inputStr, targetId)
                elseif joinServerSetting == "FriendsOnly" then
                    S_JoinSettingLabel.Text = "🔑 權限: <font color='#EAB308'>僅限好友 (FriendsOnly)</font>"
                elseif joinServerSetting == "Nobody" then
                    S_JoinSettingLabel.Text = "🔑 權限: <font color='#EF4444'>關閉 (Nobody)</font>"
                else
                    S_JoinSettingLabel.Text = "🔑 權限: <font color='#A1A1AA'>未知/隱藏</font>"
                end
            else
                S_StatusLabel.Text = "🌐 狀態: <font color='#EF4444'>離線 (Offline)</font>"
                if listButtonsMap[inputStr] then
                    listButtonsMap[inputStr].TextColor3 = Theme.Danger
                    listButtonsMap[inputStr].Text = "🔴 " .. inputStr
                end

                if joinServerSetting == "Everyone" then
                    S_JoinSettingLabel.Text = "🔑 權限: <font color='#22C55E'>所有人 (Everyone)</font>"
                elseif joinServerSetting == "FriendsOnly" then
                    S_JoinSettingLabel.Text = "🔑 權限: <font color='#EAB308'>僅限好友 (FriendsOnly)</font>"
                elseif joinServerSetting == "Nobody" then
                    S_JoinSettingLabel.Text = "🔑 權限: <font color='#EF4444'>關閉 (Nobody)</font>"
                else
                    S_JoinSettingLabel.Text = "🔑 權限: <font color='#A1A1AA'>未知/隱藏</font>"
                end
            end
        else
            S_StatusLabel.Text = "🌐 狀態: <font color='#EF4444'>查詢失敗 (無法獲取)</font>"
            S_JoinSettingLabel.Text = "🔑 權限: <font color='#EF4444'>讀取失敗</font>"
        end
        isBusy = false
    end)
end

-- 動態創建快捷選單按鈕
for _, userName in ipairs(targetUsers) do
    if userName ~= "" then
        local UserBtn = Create("TextButton", {
            Size = UDim2.new(1, 0, 0, 26),
            BackgroundColor3 = Theme.Background,
            TextColor3 = Theme.TextSecondary,
            Text = userName,
            Font = Enum.Font.GothamMedium,
            TextSize = 12,
            AutoButtonColor = false,
            Parent = ListContainer
        })
        Create("UICorner", {CornerRadius = UDim.new(0, 6), Parent = UserBtn})
        AddHover(UserBtn, Theme.Background, Theme.PanelHover)

        listButtonsMap[userName] = UserBtn

        UserBtn.MouseButton1Click:Connect(function()
            InputBox.Text = userName
            setSelectedButton(UserBtn)
            performCheck()
        end)
    end
end

-- [ 按鈕點擊事件 ] --
CheckBtn.MouseButton1Click:Connect(performCheck)

JoinBtn.MouseButton1Click:Connect(function()
    local inputStr = InputBox.Text
    if inputStr == "" then return end
    task.spawn(function()
        local targetId = getUserId(inputStr)
        if targetId then
            S_StatusLabel.Text = "🌐 狀態: <font color='#3B82F6'>嘗試發送加入請求...</font>"
            fireJoinRequest(targetId)
        else
            S_StatusLabel.Text = "🌐 狀態: <font color='#EF4444'>無效玩家，無法加入</font>"
        end
    end)
end)

CopyBtn.MouseButton1Click:Connect(function()
    local name = InputBox.Text
    if name ~= "" and setclipboard then
        setclipboard(name)
        local oldText = CopyBtn.Text
        CopyBtn.Text = "✅ 已複製"
        Tween(CopyBtn, {TextColor3 = Theme.Success}, 0.1)
        task.delay(1.5, function() 
            CopyBtn.Text = oldText 
            Tween(CopyBtn, {TextColor3 = Theme.TextPrimary}, 0.1)
        end)
    end
end)

PauseBtn.MouseButton1Click:Connect(function()
    isPaused = not isPaused
    if isPaused then
        PauseBtn.Text = "▶️"
        Tween(PauseBtn, {BackgroundColor3 = Theme.Success}, 0.2)
    else
        PauseBtn.Text = "⏸️"
        Tween(PauseBtn, {BackgroundColor3 = Theme.Warning}, 0.2)
    end
end)

-- 無限輪迴安全掃描系統
ScanBtn.MouseButton1Click:Connect(function()
    if isScanning then return end
    isScanning = true
    isPaused = false

    local validPlayers = {}
    for _, userName in ipairs(targetUsers) do
        if userName ~= "" then table.insert(validPlayers, userName) end
    end
    local totalPlayers = #validPlayers

    ScanBtn.Text = "🔄 準備無限掃描系統..."
    Tween(ScanBtn, {Size = UDim2.new(1, -46, 0, 40), BackgroundColor3 = Theme.ScanActive}, 0.3)

    PauseBtn.Visible = true
    PauseBtn.Text = "⏸️"
    PauseBtn.BackgroundColor3 = Theme.Warning

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local getRemote = remotes and remotes:FindFirstChild("GetPlayerProfileData")

    if not getRemote then
        ScanBtn.Text = "❌ 找不到 Remote 服務"
        Tween(ScanBtn, {BackgroundColor3 = Theme.Danger}, 0.3)
        task.wait(2)
        PauseBtn.Visible = false
        ScanBtn.Text = "⚡ 啟動輪迴掃描"
        Tween(ScanBtn, {Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Theme.ScanIdle}, 0.5)
        isScanning = false
        return
    end

    task.spawn(function()
        local loopRound = 1

        while isScanning do
            local processed = 0
            local onlineCount = 0

            everyoneRecords = {}
            everyoneCount = 0
            TabRecordBtn.Text = "🔓 Everyone (0)"
            for _, child in ipairs(RecordContainer:GetChildren()) do
                if child:IsA("TextButton") then child:Destroy() end
            end

            for _, userName in ipairs(validPlayers) do
                while isPaused do
                    ScanBtn.Text = string.format("⏸️ 掃描已暫停 (%d/%d)", processed, totalPlayers)
                    task.wait(0.2)
                end

                local targetId = getUserId(userName)
                if targetId then
                    local success, data = false, nil
                    local retries, maxRetries = 0, 3

                    while not success and retries < maxRetries do
                        success, data = pcall(function() return getRemote:InvokeServer(targetId) end)
                        if not success then
                            retries = retries + 1
                            task.wait(1) 
                        end
                    end

                    if success then
                        if data and checkOnlineData(data) then
                            onlineCount = onlineCount + 1
                            if listButtonsMap[userName] then
                                Tween(listButtonsMap[userName], {TextColor3 = Theme.Success}, 0.3)
                                listButtonsMap[userName].Text = "🟢 " .. userName
                            end

                            local joinServerSetting = type(data) == "table" and data.Settings and data.Settings.JoinServer

                            -- 判斷通知邏輯：如果是 Everyone 就只發詳細卡片，否則發送單純上線通知
                            if joinServerSetting == "Everyone" then
                                addEveryoneRecord(userName, targetId)
                                SendDiscordWebhook(userName, targetId)
                            else
                                SendOnlineWebhook(userName)
                            end
                        else
                            if listButtonsMap[userName] then
                                Tween(listButtonsMap[userName], {TextColor3 = Theme.Danger}, 0.3)
                                listButtonsMap[userName].Text = "🔴 " .. userName
                            end
                        end
                    end
                end

                processed = processed + 1
                if not isPaused then
                    ScanBtn.Text = string.format("🔄 第 %d 輪掃描中... %d/%d (發現 %d 人)", loopRound, processed, totalPlayers, onlineCount)
                end
                task.wait(0.4) 
            end

            ScanBtn.Text = string.format("✅ 第 %d 輪完成！共 %d 人在線上 (3秒後重新掃描)", loopRound, onlineCount)
            TabListBtn.Text = "📋 玩家名單 (" .. onlineCount .. " 在線)"
            Tween(ScanBtn, {BackgroundColor3 = Theme.ScanDone}, 0.3)

            task.wait(3)

            if not isScanning then
                PauseBtn.Visible = false
                Tween(ScanBtn, {Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Theme.ScanIdle}, 0.5)
                ScanBtn.Text = "⚡ 啟動輪迴掃描"
                return
            end

            Tween(ScanBtn, {BackgroundColor3 = Theme.ScanActive}, 0.3)
            loopRound = loopRound + 1
        end

        PauseBtn.Visible = false
        Tween(ScanBtn, {Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Theme.ScanIdle}, 0.5)
        ScanBtn.Text = "⚡ 啟動輪迴掃描"
    end)
end)