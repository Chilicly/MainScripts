-- ========== FPS / 挂机优化（纯 Lua 5.1 写法，兼容常见执行器）==========
-- 读取 getgenv().FpsBoostConfig；没设置就用下面的 Defaults（等同配置 A：正常游玩）。
-- 所有改动只在本地客户端生效，不影响服务器和其他玩家；重进游戏即可恢复。
-- 用法见文件末尾的说明。
--
-- 相比 v5 的改动（大型游戏里"每隔一秒卡一下"）：
--  1. 动画检查不再每秒一口气扫完所有角色：改成每帧只做一点点（AnimBudgetMs 毫秒），
--     游戏卡的时候自动再减少；角色的位置用缓存好的根部件读取；离得近、本来就没暂停的角色
--     不再去取它的动画列表
--  2. 技能特效文件夹（_WorldOrigin）里存活很短的零件、动画控制器不再排队处理，
--     以前每放一次技能都要改一批网格、登记一批动画，现在直接跳过
--  3. 处理过的对象记下来：大游戏会把整座岛在场景和仓库之间来回搬，搬回来时不再重复检查
--  4. 扫描已有对象不再一次性 GetDescendants 整张地图（大游戏里一次就是几十万个对象），
--     先往下拆两层，再一块一块取
--
-- v5 相比 v4 的改动（去掉攻击 / 技能特效）：
--  1. Blox Fruits 的技能、攻击特效会放进 workspace._WorldOrigin，v5 单独监听这个文件夹，
--     特效一出现就当场处理（不排队），由 BF_SkillVFX 控制：off / light / full
--  2. 粒子改成"寿命归零"：技能大多用 :Emit() 一次性喷粒子，只关 Enabled 拦不住，
--     寿命设成 0 后喷出来也立刻消失；拖尾 / 光束改成全透明，游戏之后再打开也看不见
--  3. 全地图的粒子、拖尾、灯光等特效类对象改成出现就立刻处理，不再等后台队列，
--     角色身上的攻击特效、打中怪物的火花也能拦住
--  4. 可选：调用 Blox Fruits 自带的客户端优化器（BF_GameOptimizer）
--  5. 可选：提前处理 ReplicatedStorage.Unloaded 里还没加载的岛屿（BF_PreOptimizeUnloaded），
--     走到新岛屿时要改的东西已经改好，减少移动时的卡顿
--
-- v4 相比 v3 的改动（针对"注入后卡 30 秒、移动时很卡"）：
--  1. 只处理真正需要改的对象：按类名过滤，不再把整张地图的零件和杂物都排一遍队
--  2. 只在值不一样时才写属性；本来就看不见的零件直接跳过
--  3. 后台处理的速度跟着当前帧时间自动调节：游戏本来就卡的时候自动放慢，不会雪上加霜
--  4. 去掉了容易造成"一移动就反复加载"的改动：StreamOutBehavior、逐个模型改 LOD
--     （串流半径、workspace.LevelOfDetail 保留为可选项，默认关）
--  5. 逐个零件改材质 / 投影默认关闭：写入量最大，而且改材质会连带改摩擦和密度
--  6. 全局画质设置改完后先等 1.5 秒再开始扫场景；去掉了最后那次全量垃圾回收

local sleep = (task and task.wait) or wait
local spawnFn = (task and task.spawn) or spawn or function(f) f() end

-- 背景透明度：Roblox 的 PreferredTransparency 是个 0~1 的数。我的理解是 0 = 不额外加透明（背景不透明），
-- 1 = 按游戏原样。如果在你的客户端上效果相反，把下面两个数字对调即可。
local OPAQUE_VALUE = 0
local DEFAULT_TRANSPARENCY_VALUE = 1

-- ========== 默认配置（没写的项用这里的值，等同配置 A）==========
local Defaults = {
    Profile = "A",
    WorkBudgetMs = 3,

    -- 画质 / 渲染
    GraphicsLevel = 1,            -- 图形模式 = 最低
    FpsCap = 30,                 -- 解锁帧数上限；挂机想省电、降温可改成 30~60
    MeshOptimize = true,          -- Mesh 性能优化
    DisableShadows = true,        -- 关阴影
    PartCastShadow = false,       -- 逐个关零件投影：地图都隐藏了，没必要
    DisableEffects = true,        -- 关特效（粒子寿命归零、拖尾光束全透明、烟火爆炸关掉、全局风力清零）
    DisableHighlights = true,     -- 关所有 Highlight 高亮
    PostEffects = 2,              -- 后期效果全关（并关环境光照、环境混响）
    RemoveTextures = true,        -- 去贴图
    SmoothMaterials = false,      -- 不改材质：零件反正都隐藏了，而且改材质会连带改摩擦力
    LowWater = true,              -- 低水面
    RemoveGrass = true,           -- 去地形草
    DisableAllLights = true,      -- 全关灯光
    GraySky = true,               -- 天空变灰（不用 FFlag）
    GraySkyFFlag = true,         -- 再用 FFlag 把天空变灰；上一项看不出效果时再改成 true
    Disable3DRendering = false,   -- 关闭 3D 渲染：最极限的一项，画面会空白（界面还在）。想要就改成 true

    -- ---------- 角色 / 动画 ----------
    StripOtherAccessories = true, -- 去掉其他玩家的饰品和衣服
    LocalCharEffects = true,      -- 关掉你自己角色身上的特效
    ReduceAnimations = true,      -- 暂停其他玩家 / NPC 的动画（不动你自己的角色）
    AnimFreezeDistance = 0,       -- 0 = 其他所有角色和 NPC 都不播动画（模型都隐藏了，动画只是白算）
    AnimInterval = 1.0,           -- 所有角色检查完一整轮后，休息几秒再开始下一轮
    AnimBudgetMs = 0.5,           -- 动画检查每帧最多占用几毫秒（游戏卡时自动减少）；大游戏里还是一卡一卡就调小，比如 0.25

    -- ---------- 本地隐藏 ----------
    MapMode = "hide",             -- 地图全隐藏，碰撞仍在（想留个轮廓就改成 "translucent"）
    MapTranslucency = 0.85,       -- translucent 模式下的透明度（0~1）
    HideNPCs = true,              -- NPC 模型隐藏，hitbox 仍在
    HideOtherPlayers = true,      -- 其他玩家模型隐藏，实体仍在
    HideLocalCharacter = true,    -- 你自己的角色模型隐藏，实体仍在

    -- ---------- 串流 / 细节层级 ----------
    TuneStreaming = false,        -- 不调串流半径：调小可能让挂机脚本要找的怪物、物体没加载出来
    StreamingRadius = 512,        -- 上一项的目标半径
    ModelLOD = false,             -- workspace.LevelOfDetail；是否生效取决于游戏，默认不开

    -- ---------- 界面 ----------
    HideChat = true,              -- 隐藏聊天窗口（挂机时想看聊天就改成 false）
    HidePlayerList = true,        -- 隐藏玩家列表
    HideEmotes = true,            -- 隐藏表情菜单

    -- ---------- Roblox 设置 ----------
    MasterVolume = 0,             -- 音量 = 0
    AutoTranslation = false,      -- 自动翻译 = 关（Roblox 没开放脚本接口，脚本会提示"跳过"，请手动改）
    ExperienceLanguage = "en",    -- 作品语言 = 英语（同上，只能手动改；没有英语选项就用默认）
    ChatTranslation = false,      -- 聊天自动翻译 = 关
    FriendNotifications = false,  -- 游戏内好友通知 = 关（靠隐藏 CoreGui 通知容器实现，其他系统通知也会一起隐藏）
    OpaqueBackground = true,      -- 背景透明度 = 不透明
    PerformanceStats = false,      -- 表现统计 = 开
    Haptics = false,              -- 触觉 = 关
    ReduceMotion = true,          -- 减少动态 = 开
    HideNames = true,             -- 人物名字 = 隐藏（所有角色头顶的名字和血条）
    HideMyBadges = true,          -- 我的徽章 = 隐藏（同样靠隐藏 CoreGui 通知容器实现）
    ExtraGameSettings = {},       -- 你自己知道属性名的设置，填 { 属性名 = 值 }

    -- ---------- Blox Fruits 专项 ----------
    BloxFruits = "auto",          -- "auto" = 按 PlaceId 自动判断；true = 强制当作 Blox Fruits；false = 不处理
    BF_AllyVFX = false,           -- Ally VFX = 关
    BF_CameraShake = false,       -- Camera Shake = 关
    BF_DamageCounter = true,      -- Damage Counter = 开
    BF_ReduceMotion = true,       -- Reduce Motion = 开
    BF_FastMode = true,           -- 快速模式 = 开
    BF_RowNames = {},             -- 设置行名称对不上时手动指定
    BF_Debug = false,             -- true = 打印设置菜单里的行名
    BF_SkillVFX = "full",         -- 技能 / 攻击特效全部看不见（只改本地显示，伤害照常）
    BF_VFXKeepNames = { "Locations", "CannonBall" }, -- 技能特效文件夹里这些名字不碰（岛屿标记、海上事件的炮弹）
    BF_GameOptimizer = true,      -- 调用游戏自带的客户端优化器
    BF_PreOptimizeUnloaded = true, -- 提前处理还没加载的岛屿

    -- ---------- 通用 ----------
    OptimizeNewObjects = true,    -- 之后新加载出来的东西也自动处理
    Notify = true,                -- 完成后弹一条通知
    PrintReport = true,           -- 把每一项"成功 / 跳过"的情况打印到控制台
}

-- ========== 重复运行时先清掉上一次的监听和循环 ==========
local env = (getgenv and getgenv()) or _G
if env.__FpsBoostCleanup then
    pcall(env.__FpsBoostCleanup)
end
local alive = true
local conns = {}
env.__FpsBoostCleanup = function()
    alive = false
    for _, c in ipairs(conns) do
        pcall(function() c:Disconnect() end)
    end
end

-- ========== 读取 getgenv().FpsBoostConfig ==========
local User = (getgenv and getgenv().FpsBoostConfig) or {}
if type(User) ~= "table" then User = {} end
local C = {}
for k, v in pairs(Defaults) do
    if User[k] ~= nil then
        C[k] = User[k]
    else
        C[k] = v
    end
end
if type(C.ExtraGameSettings) ~= "table" then C.ExtraGameSettings = {} end
if type(C.BF_RowNames) ~= "table" then C.BF_RowNames = {} end
if type(C.BF_VFXKeepNames) ~= "table" then C.BF_VFXKeepNames = {} end

local vfxMode = string.lower(tostring(C.BF_SkillVFX or "off"))
if vfxMode ~= "light" and vfxMode ~= "full" then vfxMode = "off" end
local vfxKeep = {}
for _, name in ipairs(C.BF_VFXKeepNames) do
    vfxKeep[tostring(name)] = true
end

local postLevel = tonumber(C.PostEffects) or 0
local mapMode = string.lower(tostring(C.MapMode or "off"))
if mapMode ~= "hide" and mapMode ~= "translucent" then mapMode = "off" end
local mapTranslucency = tonumber(C.MapTranslucency) or 0.85
if mapTranslucency < 0 then mapTranslucency = 0 elseif mapTranslucency > 1 then mapTranslucency = 1 end
local hideAny = (mapMode ~= "off") or C.HideNPCs == true
    or C.HideOtherPlayers == true or C.HideLocalCharacter == true

-- ========== 服务 ==========
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local LocalPlayer = Players.LocalPlayer
local Terrain = Workspace:FindFirstChildOfClass("Terrain")

local GameSettings
pcall(function() GameSettings = UserSettings():GetService("UserGameSettings") end)

local GRAY = Color3.fromRGB(128, 128, 128)

-- 当前帧时间（由 Heartbeat 更新）。后台工作都按它自动放慢：游戏本来就卡时少做一点
local lastDt = 1 / 60

-- 把"每轮最多占用多少毫秒"按当前帧时间缩放：
--   帧时间 < 21ms（约 48 帧以上）：用满；< 34ms：只用三分之一；更卡：只用最低值
local function scaledBudget(ms, minSeconds)
    local full = (tonumber(ms) or 1) / 1000
    local b
    if lastDt < 0.021 then
        b = full
    elseif lastDt < 0.034 then
        b = full / 3
    else
        b = minSeconds
    end
    if b < minSeconds then b = minSeconds end
    return b
end

-- Blox Fruits 的技能特效文件夹（workspace._WorldOrigin），找到后赋值
local worldOrigin = nil

-- ========== 小工具 ==========
local function report(label, ok, detail)
    if not C.PrintReport then return end
    print("[FpsBoost] " .. (ok and "[成功] " or "[跳过] ") .. label .. (detail and ("：" .. detail) or ""))
end

local function safeCall(label, f, ...)
    local ok, err = pcall(f, ...)
    if not ok then
        print("[FpsBoost] " .. label .. " 出错：" .. tostring(err))
    end
end

local function normalize(s)
    return (tostring(s):lower():gsub("[^%w]", ""))
end

-- 往 UserGameSettings 写一个设置：按顺序试每个候选属性名，第一个写成功的就停
local function setGameSetting(label, propNames, value)
    if not GameSettings then
        report(label, false, "取不到 UserGameSettings")
        return
    end
    for _, name in ipairs(propNames) do
        local ok = pcall(function() GameSettings[name] = value end)
        if ok then
            report(label, true, name .. " = " .. tostring(value))
            return
        end
    end
    report(label, false, "没有可写的属性（" .. table.concat(propNames, "/") .. "），不同版本/执行器可能不开放")
end

-- ========== Roblox 设置 ==========
local function applyRobloxSettings()
    if C.MasterVolume ~= "keep" then
        local v = tonumber(C.MasterVolume)
        if v then
            if v < 0 then v = 0 elseif v > 1 then v = 1 end
            setGameSetting("音量", { "MasterVolume" }, v)
        end
    end
    if C.PerformanceStats ~= "keep" then
        setGameSetting("表现统计", { "PerformanceStatsVisible" }, C.PerformanceStats == true)
    end
    if C.Haptics ~= "keep" then
        setGameSetting("触觉", { "HapticStrength" }, (C.Haptics == true) and 1 or 0)
    end
    if C.ReduceMotion ~= "keep" then
        setGameSetting("减少动态", { "ReducedMotion" }, C.ReduceMotion == true)
    end
    if C.OpaqueBackground ~= "keep" then
        setGameSetting("背景透明度", { "PreferredTransparency" },
            (C.OpaqueBackground == true) and OPAQUE_VALUE or DEFAULT_TRANSPARENCY_VALUE)
    end
    if C.ChatTranslation ~= "keep" then
        setGameSetting("聊天自动翻译", { "ChatTranslationEnabled" }, C.ChatTranslation == true)
    end
    if C.AutoTranslation ~= "keep" then
        report("自动翻译", false, "没有已知的脚本接口，请在 Roblox 设置里手动设置（或把属性名填进 ExtraGameSettings）")
    end
    if C.ExperienceLanguage ~= "keep" then
        report("作品语言", false, "没有已知的脚本接口，请在 Roblox 设置里手动设置（或把属性名填进 ExtraGameSettings）")
    end
    for name, value in pairs(C.ExtraGameSettings) do
        setGameSetting("自定义设置 " .. tostring(name), { tostring(name) }, value)
    end
end

-- ========== 全局设置（画质、光照、地形、帧数上限、界面）==========
local function applyGlobalSettings()
    local cap = tonumber(C.FpsCap) or 0
    if cap > 0 then
        if setfpscap then
            local ok = pcall(setfpscap, cap)
            report("帧数上限", ok, ok and tostring(cap) or nil)
        else
            report("帧数上限", false, "执行器没有 setfpscap")
        end
    end

    if C.GraphicsLevel ~= "keep" then
        local lvl = math.floor(tonumber(C.GraphicsLevel) or 1)
        if lvl < 1 then lvl = 1 elseif lvl > 10 then lvl = 10 end
        local okR = pcall(function()
            settings().Rendering.QualityLevel = Enum.QualityLevel["Level" .. string.format("%02d", lvl)]
        end)
        local okS = pcall(function()
            GameSettings.SavedQualityLevel = Enum.SavedQualitySetting["QualityLevel" .. lvl]
        end)
        local okG = pcall(function() GameSettings.GraphicsQualityLevel = lvl end)
        report("图形等级", okR or okS or okG, "等级 " .. lvl)
    end

    if C.MeshOptimize then
        local ok = pcall(function()
            settings().Rendering.MeshPartDetailLevel = Enum.MeshPartDetailLevel.Level04
        end)
        report("网格细节", ok, ok and "最低" or nil)
    end

    if postLevel >= 1 then
        pcall(function() Lighting.EnvironmentDiffuseScale = 0 end)
        pcall(function() Lighting.EnvironmentSpecularScale = 0 end)
    end
    if postLevel >= 2 then
        pcall(function() SoundService.AmbientReverb = Enum.ReverbType.NoReverb end)
        if sethiddenproperty then
            -- 部分环境运行中改这个可能不会立刻生效
            pcall(sethiddenproperty, Lighting, "Technology", Enum.Technology.Compatibility)
        end
    end

    if C.DisableShadows then
        pcall(function() Lighting.GlobalShadows = false end)
        pcall(function() Lighting.ShadowSoftness = 0 end)
    end
    if C.SmoothMaterials then
        pcall(function() game:GetService("MaterialService").Use2022Materials = false end)
    end
    if C.DisableEffects then
        pcall(function() Workspace.GlobalWind = Vector3.new(0, 0, 0) end)
    end

    if Terrain then
        if C.LowWater then
            pcall(function() Terrain.WaterWaveSize = 0 end)
            pcall(function() Terrain.WaterWaveSpeed = 0 end)
            pcall(function() Terrain.WaterReflectance = 0 end)
            pcall(function() Terrain.WaterTransparency = 0 end)
        end
        if C.RemoveGrass then
            if sethiddenproperty then
                local ok = pcall(sethiddenproperty, Terrain, "Decoration", false)
                report("去地形草", ok)
            else
                report("去地形草", false, "执行器没有 sethiddenproperty")
            end
        end
        if C.DisableEffects or postLevel >= 2 or C.GraySky then
            local clouds = Terrain:FindFirstChildOfClass("Clouds")
            if clouds then
                pcall(function() clouds.Enabled = false end)
            end
        end
    end

    if C.Disable3DRendering then
        local ok = pcall(function() RunService:Set3dRenderingEnabled(false) end)
        report("关闭 3D 渲染", ok)
    end

    if C.HideChat then
        pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false) end)
    end
    if C.HidePlayerList then
        pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false) end)
    end
    if C.HideEmotes then
        pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, false) end)
    end
end

-- ========== 串流 / LevelOfDetail（默认关）==========
-- StreamingEnabled 在游戏运行中是改不了的（开不了也关不了）。这里只在你主动打开
-- TuneStreaming / ModelLOD 时，尝试改串流半径和 workspace.LevelOfDetail。
-- 这些属性本质上由服务器/游戏决定，客户端改了是否生效取决于游戏和执行器；
-- 如果打开后移动时变卡，就把它们关掉。
local function tuneStreaming()
    if C.ModelLOD then
        local ok = pcall(function() Workspace.LevelOfDetail = Enum.ModelLevelOfDetail.StreamingMesh end)
        report("workspace.LevelOfDetail", ok, ok and "StreamingMesh" or nil)
    end

    if not C.TuneStreaming then return end
    local okEnabled, enabled = pcall(function() return Workspace.StreamingEnabled end)
    if not (okEnabled and enabled == true) then
        report("串流半径", false, "这个游戏没有开 StreamingEnabled")
        return
    end

    local desired = tonumber(C.StreamingRadius) or 512
    local okMin, minRadius = pcall(function() return Workspace.StreamingMinRadius end)
    if okMin and type(minRadius) == "number" and desired < minRadius then
        desired = minRadius -- 目标半径不能小于最小半径
    end
    local okCur, current = pcall(function() return Workspace.StreamingTargetRadius end)
    if okCur and type(current) == "number" and current > desired then
        local ok = pcall(function() Workspace.StreamingTargetRadius = desired end)
        report("串流半径", ok, current .. " -> " .. desired)
    end
end

-- ========== 灰色天空 ==========
-- 优先用不碰 FFlag 的办法：清空天空盒和日月星星、把大气拉平、雾色设成灰色。
-- 这样做的前提是"没有天空盒时，背景会用雾色"——我没法在 Roblox 里实测，所以效果以实际画面为准；
-- 不行的话把 GraySkyFFlag 设成 true，再用 FFlag 兜底。
local function grayifySky(v)
    v.SkyboxBk = ""
    v.SkyboxDn = ""
    v.SkyboxFt = ""
    v.SkyboxLf = ""
    v.SkyboxRt = ""
    v.SkyboxUp = ""
    v.StarCount = 0
    v.CelestialBodiesShown = false
end

local function flattenAtmosphere(v)
    v.Density = 0
    v.Haze = 0
    v.Glare = 0
end

local function applyGraySky()
    if C.GraySky then
        if not Lighting:FindFirstChildOfClass("Sky") then
            -- 没有天空盒时引擎可能会画默认天空，补一个空的占位
            pcall(function()
                local s = Instance.new("Sky")
                s.Name = "FpsBoostBlankSky"
                grayifySky(s)
                s.Parent = Lighting
            end)
        end
        pcall(function() Lighting.FogColor = GRAY end)
        report("天空变灰（不用 FFlag）", true, "已执行：清空天空盒、拉平大气、雾色设成灰色，效果以实际画面为准")
    end

    if C.GraySkyFFlag then
        if setfflag then
            local ok1 = pcall(setfflag, "FFlagDebugSkyGray", "True")
            local ok2 = pcall(setfflag, "DebugSkyGray", "True")
            report("天空变灰（FFlag）", ok1 or ok2, "已写入 FFlagDebugSkyGray；运行中改 FFlag 往往要重进游戏才生效")
        else
            report("天空变灰（FFlag）", false, "执行器没有 setfflag，请改用执行器自带的 FFlag 设置")
        end
    end
end

-- ========== 光照里的对象：天空 / 大气 / 后期效果 ==========
local function optimizeLightingObject(v)
    if v:IsA("Sky") then
        if C.GraySky then grayifySky(v) end
    elseif v:IsA("Atmosphere") then
        if C.GraySky or postLevel >= 2 then flattenAtmosphere(v) end
    elseif v:IsA("PostEffect") then
        if postLevel >= 2 then
            v.Enabled = false
        elseif postLevel >= 1 and (v:IsA("BlurEffect") or v:IsA("BloomEffect")
                or v:IsA("DepthOfFieldEffect") or v:IsA("SunRaysEffect")) then
            v.Enabled = false
        end
    end
end

-- ========== 角色动画：远处的暂停，走近后恢复 ==========
-- 每个动画器登记成一条记录（缓存它的模型和根部件），由后台一点一点轮流检查：
-- 每帧最多占用 AnimBudgetMs 毫秒，检查完一整轮后再休息 AnimInterval 秒。
-- 这样大游戏里角色再多，也不会在某一帧集中检查而卡一下。
-- 你自己的角色（以及它身上的东西）永远不动：有些游戏的出招时机靠本地动画事件。
local animList = {}
local animSet = setmetatable({}, { __mode = "k" })
local frozenSpeed = setmetatable({}, { __mode = "k" }) -- 动画轨道 -> 被暂停前的原始速度

local function findRootPart(model)
    return model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
end

local function registerAnimator(a)
    if animSet[a] then return end
    if not a:IsDescendantOf(Workspace) then return end -- 仓库里的不管，搬进场景时会再登记
    local holder = a.Parent and a.Parent.Parent
    if not holder or holder == Workspace then return end
    local localChar = LocalPlayer and LocalPlayer.Character
    if localChar and (holder == localChar or holder:IsDescendantOf(localChar)) then return end

    local rec = { a = a, holder = holder, frozen = nil } -- frozen = nil：还不知道它的轨道是什么状态
    if holder:IsA("Model") then
        rec.isModel = true
        rec.root = findRootPart(holder)
    elseif holder:IsA("BasePart") then
        rec.root = holder
    else
        return
    end
    animSet[a] = true
    animList[#animList + 1] = rec
end

local function setTracksFrozen(a, freeze)
    for _, track in ipairs(a:GetPlayingAnimationTracks()) do
        if freeze then
            local speed = track.Speed
            if speed ~= 0 then
                frozenSpeed[track] = speed
                track:AdjustSpeed(0)
            end
        else
            local orig = frozenSpeed[track]
            if orig ~= nil then
                track:AdjustSpeed(orig)
                frozenSpeed[track] = nil
            end
        end
    end
end

local function processAnimRec(rec, camPos, freezeDist, resumeDist, localChar)
    local holder = rec.holder
    if localChar and (holder == localChar or holder:IsDescendantOf(localChar)) then
        if rec.frozen ~= false then
            setTracksFrozen(rec.a, false)
            rec.frozen = false
        end
        return
    end

    local root = rec.root
    local pos
    if root and root.Parent then
        pos = root.Position
    elseif rec.isModel then
        rec.root = findRootPart(holder) -- 根部件可能晚一点才加载出来
        pos = holder:GetPivot().Position
    else
        return
    end

    local dist = (pos - camPos).Magnitude
    if dist > freezeDist then
        -- 需要每轮都看一下：游戏会不断给 NPC 播新的动画
        setTracksFrozen(rec.a, true)
        rec.frozen = true
    elseif dist < resumeDist and rec.frozen ~= false then
        -- 离得近、本来就没暂停的角色，不去取它的动画列表
        setTracksFrozen(rec.a, false)
        rec.frozen = false
    end
end

local function animationLoop()
    local cursor = 1
    while alive and C.ReduceAnimations do
        local cam = Workspace.CurrentCamera
        local camPos = cam and cam.CFrame.Position
        if not camPos then
            sleep(1)
        else
            local freezeDist = tonumber(C.AnimFreezeDistance) or 150
            local resumeDist = freezeDist * 0.85 -- 留一段缓冲，避免在边界上来回切换
            local localChar = LocalPlayer and LocalPlayer.Character
            local budget = scaledBudget(C.AnimBudgetMs, 0.0002)
            local started = os.clock()
            local n = 0
            while cursor <= #animList do
                local rec = animList[cursor]
                local a = rec.a
                if not a.Parent or not a:IsDescendantOf(Workspace) then
                    -- 已经删除或移出场景：用最后一条补到这个位置，cursor 不动
                    animSet[a] = nil
                    animList[cursor] = animList[#animList]
                    animList[#animList] = nil
                else
                    pcall(processAnimRec, rec, camPos, freezeDist, resumeDist, localChar)
                    cursor = cursor + 1
                end
                n = n + 1
                if n % 8 == 0 and os.clock() - started > budget then break end
            end
            if cursor > #animList then
                cursor = 1
                sleep(tonumber(C.AnimInterval) or 1) -- 一整轮检查完，休息一下
            else
                sleep() -- 这一帧的额度用完了，下一帧接着来
            end
        end
    end
end

-- ========== 需要处理的对象类型 ==========
-- 按类名过滤，并且只登记当前配置真的用得到的类型；其他的一律不碰、不排队。
-- 之前卡 30 秒的一大原因就是把整张地图所有东西都挨个过了一遍。
local KIND = {}
local function addKind(kind, list)
    for _, cn in ipairs(list) do
        KIND[cn] = kind
    end
end

local needAllParts = hideAny or C.SmoothMaterials == true or C.PartCastShadow == true
if needAllParts then
    addKind("part", { "Part", "MeshPart", "UnionOperation", "NegateOperation", "WedgePart",
        "CornerWedgePart", "TrussPart", "Seat", "VehicleSeat", "SpawnLocation" })
elseif C.RemoveTextures or C.MeshOptimize then
    -- 只改网格贴图和网格精度的话，普通方块零件根本不用碰
    addKind("part", { "MeshPart", "UnionOperation", "NegateOperation" })
end
if C.DisableEffects then
    addKind("emitter", { "ParticleEmitter", "Trail", "Beam", "Smoke", "Fire", "Sparkles" })
    addKind("explosion", { "Explosion" })
end
if C.DisableHighlights then
    addKind("highlight", { "Highlight" })
end
if C.RemoveTextures then
    addKind("decal", { "Decal", "Texture" })
    addKind("surface", { "SurfaceAppearance" })
end
if C.DisableAllLights or C.DisableShadows then
    addKind("light", { "PointLight", "SpotLight", "SurfaceLight" })
end
if C.ReduceAnimations then
    addKind("animator", { "Animator" })
end
if C.HideNames == true then
    addKind("humanoid", { "Humanoid" })
end
if C.StripOtherAccessories then
    addKind("clothing", { "Accessory", "Shirt", "Pants", "ShirtGraphic", "CharacterMesh" })
end

-- 出现就立刻处理的类型：都是单次写入、开销很小的特效类对象。
-- 技能特效通常在出现的同一帧就开始播放，排队等后台处理就来不及了
local INSTANT = { emitter = true, explosion = true, highlight = true, light = true }

-- 特效类对象的类名
local EFFECT_CLASS = {
    ParticleEmitter = true, Trail = true, Beam = true, Smoke = true, Fire = true, Sparkles = true,
    PointLight = true, SpotLight = true, SurfaceLight = true, Highlight = true, Explosion = true,
}

local ZERO_LIFETIME = NumberRange.new(0)
local INVISIBLE_SEQ = NumberSequence.new(1)

-- 彻底关掉一个特效类对象：
--   粒子：除了关 Enabled，还把寿命设成 0。技能多数用 :Emit() 一次性喷粒子，只关 Enabled 拦不住，
--         寿命为 0 时喷出来也会立刻消失；
--   拖尾 / 光束：改成全透明。游戏攻击时常会重新打开它们（比如挥刀的拖尾），透明度一般不会去改；
--   灯光：关掉并把亮度设成 0。
local function killEffect(v)
    local cn = v.ClassName
    if cn == "ParticleEmitter" then
        v.Enabled = false
        v.Lifetime = ZERO_LIFETIME
    elseif cn == "Trail" or cn == "Beam" then
        v.Enabled = false
        v.Transparency = INVISIBLE_SEQ
    elseif cn == "Smoke" or cn == "Fire" or cn == "Sparkles" then
        v.Enabled = false
    elseif cn == "PointLight" or cn == "SpotLight" or cn == "SurfaceLight" then
        v.Enabled = false
        v.Brightness = 0
    elseif cn == "Highlight" then
        v.Enabled = false
    elseif cn == "Explosion" then
        v.Visible = false
    end
end

-- 判断一个模型是不是角色（有 Humanoid）：local = 你自己；player = 其他玩家；npc = 其他带 Humanoid 的模型
-- 肯定的结果一直缓存；"暂时不是角色"只缓存 5 秒（角色加载时 Humanoid 可能比零件晚出现）
local modelClass = setmetatable({}, { __mode = "k" })
local modelNeg = setmetatable({}, { __mode = "k" })

local function classifyModel(m)
    local cached = modelClass[m]
    if cached then return cached end
    local t = modelNeg[m]
    if t and os.clock() - t < 5 then return nil end
    if m:FindFirstChildOfClass("Humanoid") then
        local result
        if LocalPlayer and m == LocalPlayer.Character then
            result = "local"
        elseif Players:GetPlayerFromCharacter(m) then
            result = "player"
        else
            result = "npc"
        end
        modelClass[m] = result
        return result
    end
    modelNeg[m] = os.clock()
    return nil
end

-- 返回 "local" / "player" / "npc" / "map" / "ignore"（相机下面的东西不碰）
local function classifyPart(v)
    local m = v.Parent
    while m and m ~= Workspace do
        if m:IsA("Camera") then return "ignore" end
        if m:IsA("Model") then
            local c = classifyModel(m)
            if c then return c end
        end
        m = m.Parent
    end
    return "map"
end

-- 本地隐藏：只改 Transparency，碰撞、命中判定、服务器上的实体都不受影响
local function hidePart(v, cat)
    if cat == "map" then
        if mapMode == "hide" then
            v.Transparency = 1
        elseif mapMode == "translucent" then
            if v.Transparency < mapTranslucency then
                v.Transparency = mapTranslucency
            end
        end
    elseif cat == "npc" then
        if C.HideNPCs then v.Transparency = 1 end
    elseif cat == "player" then
        if C.HideOtherPlayers then v.Transparency = 1 end
    elseif cat == "local" then
        if C.HideLocalCharacter then v.Transparency = 1 end
    end
end

-- 零件：整个函数是用 pcall 包着调用的。每个属性都是"值不一样才写"，
-- 因为每次写入都会让引擎重新处理这个零件，白写是纯浪费
local function optimizePart(v)
    if v.Transparency >= 1 then return end -- 本来就看不见的零件，不用管

    if hideAny then
        local cat = classifyPart(v)
        if cat == "ignore" then return end
        hidePart(v, cat)
        if v.Transparency >= 1 then return end -- 已经被隐藏了，后面的画质调整没必要
    end

    if C.SmoothMaterials then
        if v.Material ~= Enum.Material.SmoothPlastic then
            v.Material = Enum.Material.SmoothPlastic
        end
        if v.Reflectance ~= 0 then
            v.Reflectance = 0
        end
    end
    if C.PartCastShadow and v.CastShadow then
        v.CastShadow = false
    end

    local cn = v.ClassName
    if cn == "MeshPart" then
        if C.RemoveTextures and v.TextureID ~= "" then
            v.TextureID = ""
        end
        if C.MeshOptimize and v.RenderFidelity ~= Enum.RenderFidelity.Performance then
            v.RenderFidelity = Enum.RenderFidelity.Performance
        end
    elseif C.MeshOptimize and (cn == "UnionOperation" or cn == "NegateOperation") then
        if v.RenderFidelity ~= Enum.RenderFidelity.Performance then
            v.RenderFidelity = Enum.RenderFidelity.Performance
        end
    end
end

local function optimizeInstance(v)
    local kind = KIND[v.ClassName]
    if not kind then return end

    if kind == "part" then
        optimizePart(v)
    elseif kind == "emitter" or kind == "explosion" or kind == "highlight" then
        killEffect(v)
    elseif kind == "decal" then
        if v.Transparency < 1 then
            local p = v.Parent
            if p and p:IsA("BasePart") then
                if p.Transparency >= 1 then return end -- 所在零件本来就看不见
                if classifyPart(p) ~= "map" then return end -- 角色的脸之类不动
            end
            v.Transparency = 1
        end
    elseif kind == "surface" then
        v:Destroy()
    elseif kind == "light" then
        if C.DisableAllLights then
            killEffect(v)
        elseif C.DisableShadows and v.Shadows then
            v.Shadows = false
        end
    elseif kind == "animator" then
        registerAnimator(v)
    elseif kind == "humanoid" then
        if v.DisplayDistanceType ~= Enum.HumanoidDisplayDistanceType.None then
            v.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        end
        v.NameDisplayDistance = 0
        v.HealthDisplayDistance = 0
    elseif kind == "clothing" then
        local parent = v.Parent
        local owner = parent and Players:GetPlayerFromCharacter(parent)
        if owner and owner ~= LocalPlayer then
            v:Destroy()
        end
    end
end

-- ========== 你自己角色身上的特效 ==========
local function optimizeLocalCharObject(v)
    if EFFECT_CLASS[v.ClassName] then
        killEffect(v)
    elseif v:IsA("ForceField") then
        v.Visible = false
    end
end

local function hookLocalCharacter(char)
    for _, v in ipairs(char:GetDescendants()) do
        pcall(optimizeLocalCharObject, v)
    end
    conns[#conns + 1] = char.DescendantAdded:Connect(function(v)
        pcall(optimizeLocalCharObject, v)
    end)
end

-- ========== 后台处理：新出现的对象排队 + 已有的对象分批扫描 ==========
-- 每一轮最多占用 WorkBudgetMs 毫秒，并且按当前帧时间自动缩放（见 scaledBudget）
local queue = {}
local qHead, qTail = 1, 0
local processedTotal = 0

-- 处理过的对象（弱引用，不妨碍回收）。大游戏会把整座岛在 ReplicatedStorage 和场景之间来回搬，
-- 搬回来时每个零件都会再触发一次"新对象"，处理过的直接跳过。动画器不记：它每次进场景都要重新登记
local done = setmetatable({}, { __mode = "k" })

local function processOne(v, kind)
    if kind ~= "animator" then
        if done[v] then return end
        done[v] = true
    end
    pcall(optimizeInstance, v)
    processedTotal = processedTotal + 1
end

-- 分批扫描：不对整张地图一次性 GetDescendants（大游戏里一次就是几十万个对象，光生成这张表就会卡一下），
-- 而是先往下拆 SPLIT_DEPTH 层（比如 workspace -> Map -> 每座岛），再一块一块地取
local SPLIT_DEPTH = 2
local rootStack, depthStack, rootTop = {}, {}, 0
local scanList, scanCount, scanIndex = nil, 0, 1
local scanDone = true

local function startScan(root)
    rootTop = 1
    rootStack[1] = root
    depthStack[1] = 0
    scanList, scanCount, scanIndex = nil, 0, 1
    scanDone = false
end

-- 场景里新出现的对象：特效类当场处理（开销很小，而且等不起），其余的排队交给后台
local function onWorkspaceAdded(v)
    local kind = KIND[v.ClassName]
    if not kind then return end
    if worldOrigin and v:IsDescendantOf(worldOrigin) then
        -- 技能特效文件夹里的东西只活一两秒：特效类交给 handleVFX（开了 BF_SkillVFX 时），
        -- 零件、贴图、动画器不排队（给短命的网格改精度反而会让引擎重新加载它）
        if vfxMode ~= "off" or not INSTANT[kind] then return end
    end
    if INSTANT[kind] then
        processOne(v, kind)
    elseif kind == "animator" or not done[v] then
        qTail = qTail + 1
        queue[qTail] = v
    end
end

local function currentBudget()
    return scaledBudget(C.WorkBudgetMs, 0.001)
end

local function workStep(budget)
    local started = os.clock()
    local n = 0

    -- 新出现的对象优先（它们是眼前正在加载的东西）
    while qHead <= qTail do
        local v = queue[qHead]
        queue[qHead] = nil
        qHead = qHead + 1
        if v and v.Parent then
            local kind = KIND[v.ClassName]
            if kind then processOne(v, kind) end
        end
        n = n + 1
        if n % 16 == 0 and os.clock() - started > budget then return end
    end
    qHead, qTail = 1, 0

    -- 然后继续扫已有的对象
    while not scanDone do
        if scanList and scanIndex <= scanCount then
            local v = scanList[scanIndex]
            scanList[scanIndex] = nil -- 用完就放掉引用
            scanIndex = scanIndex + 1
            local kind = KIND[v.ClassName]
            if kind and v.Parent then
                processOne(v, kind)
            end
            n = n + 1
            if n % 64 == 0 and os.clock() - started > budget then return end
        elseif rootTop > 0 then
            scanList = nil
            local root = rootStack[rootTop]
            local depth = depthStack[rootTop]
            rootStack[rootTop] = nil
            depthStack[rootTop] = nil
            rootTop = rootTop - 1
            if root.Parent then
                local kind = KIND[root.ClassName]
                if kind then processOne(root, kind) end
                if depth < SPLIT_DEPTH then
                    local ok, kids = pcall(function() return root:GetChildren() end)
                    if ok and kids then
                        for i = 1, #kids do
                            rootTop = rootTop + 1
                            rootStack[rootTop] = kids[i]
                            depthStack[rootTop] = depth + 1
                        end
                    end
                else
                    local ok, list = pcall(function() return root:GetDescendants() end)
                    if ok and list then
                        scanList, scanCount, scanIndex = list, #list, 1
                    end
                end
            end
            if os.clock() - started > budget then return end
        else
            scanList = nil
            scanDone = true
        end
    end
end

local function queueWorker()
    while alive do
        if qHead <= qTail or not scanDone then
            workStep(currentBudget())
        end
        sleep(0.03)
    end
end

-- ========== 好友通知 / 徽章通知：隐藏 CoreGui 的通知容器 ==========
-- Roblox 没有给脚本开放这两项设置，这里是用隐藏通知容器来做到"看不见"，
-- 代价是其他系统通知也会一起被隐藏
local function hideCoreNotifications()
    local ok, CoreGui = pcall(function() return game:GetService("CoreGui") end)
    if not ok or not CoreGui then
        report("好友/徽章通知", false, "拿不到 CoreGui")
        return
    end
    local rg = CoreGui:WaitForChild("RobloxGui", 10)
    local frame = rg and rg:WaitForChild("NotificationFrame", 10)
    if not frame then
        report("好友/徽章通知", false, "没找到 CoreGui 里的通知容器")
        return
    end
    pcall(function() frame.Visible = false end)
    conns[#conns + 1] = frame:GetPropertyChangedSignal("Visible"):Connect(function()
        if frame.Visible then
            pcall(function() frame.Visible = false end)
        end
    end)
    report("好友/徽章通知", true, "已隐藏 CoreGui 通知容器（其他系统通知也会一起被隐藏）")
end

-- ========== Blox Fruits 专项：点游戏自己设置菜单里的按钮 ==========
-- 路径 PlayerGui.Main.SettingsMenu.Content.ScrollingFrame.<行名>，行里 FirstButton = 开、SecondButton = 关。
-- 其中只有 FastMode 这一行的名字是确认过的，其余几行按关键字去匹配；
-- 匹配不到就把 BF_Debug 设成 true 看行名，再用 BF_RowNames 手动指定
local BF_PLACE_IDS = { [2753915549] = true, [4442272183] = true, [7449423635] = true }

local BF_KEYWORDS = {
    AllyVFX = { "allyvfx", "allyeffect", "allyfx", "ally" },
    CameraShake = { "camerashake", "screenshake", "shake" },
    DamageCounter = { "damagecounter", "damagenumber", "damagetext", "damage" },
    ReduceMotion = { "reducemotion", "reducedmotion", "motion" },
    FastMode = { "fastmode" },
}

local function isBloxFruits()
    if C.BloxFruits == true then return true end
    if C.BloxFruits == false then return false end
    return BF_PLACE_IDS[game.PlaceId] == true or game.GameId == 994732206
end

local function activateButton(btn)
    if firesignal then
        if pcall(firesignal, btn.Activated) then return true end
    end
    if getconnections then
        local ok = pcall(function()
            for _, c in ipairs(getconnections(btn.Activated)) do
                if c.Fire then
                    c:Fire()
                elseif c.Function then
                    c.Function()
                end
            end
        end)
        if ok then return true end
    end
    if firesignal then
        if pcall(firesignal, btn.MouseButton1Click) then return true end
    end
    return false
end

local function findBFRow(list, name)
    local override = C.BF_RowNames[name]
    if override then
        local r = list:FindFirstChild(override)
        if r then return r end
    end
    local keys = BF_KEYWORDS[name]
    local rows = list:GetChildren()
    -- 先按行名匹配，关键字从具体到宽泛
    for _, kw in ipairs(keys) do
        for _, row in ipairs(rows) do
            if normalize(row.Name):find(kw, 1, true) then return row end
        end
    end
    -- 行名对不上，再按行里文字标签的内容匹配
    for _, kw in ipairs(keys) do
        for _, row in ipairs(rows) do
            for _, d in ipairs(row:GetDescendants()) do
                if d:IsA("TextLabel") and normalize(d.Text):find(kw, 1, true) then return row end
            end
        end
    end
    return nil
end

local function applyBloxFruitsSettings()
    if not isBloxFruits() then return end

    local order = { "FastMode", "ReduceMotion", "CameraShake", "AllyVFX", "DamageCounter" }
    local wanted = {}
    for _, name in ipairs(order) do
        local v = C["BF_" .. name]
        if v ~= "keep" then
            wanted[#wanted + 1] = { name = name, enable = (v == true) }
        end
    end
    if #wanted == 0 then return end

    -- 等游戏界面加载出来（选完队伍之后才有）
    local pg = LocalPlayer and LocalPlayer:WaitForChild("PlayerGui", 60)
    local main = pg and pg:WaitForChild("Main", 120)
    local menu = main and main:WaitForChild("SettingsMenu", 30)
    local content = menu and menu:WaitForChild("Content", 30)
    local list = content and content:WaitForChild("ScrollingFrame", 30)
    if not list then
        report("Blox Fruits 设置", false, "没找到设置菜单（PlayerGui.Main.SettingsMenu.Content.ScrollingFrame）")
        return
    end

    if C.BF_Debug then
        for _, row in ipairs(list:GetChildren()) do
            print("[FpsBoost] Blox Fruits 设置行：" .. row.Name)
        end
    end

    for _, item in ipairs(wanted) do
        local label = "Blox Fruits " .. item.name .. " = " .. (item.enable and "开" or "关")
        local row = findBFRow(list, item.name)
        if not row then
            report(label, false, "没找到对应的设置行，可以开 BF_Debug 看行名，再用 BF_RowNames 指定")
        else
            local btn = row:FindFirstChild(item.enable and "FirstButton" or "SecondButton")
            if btn and activateButton(btn) then
                report(label, true, "行名 " .. row.Name)
            else
                report(label, false, "行 " .. row.Name .. " 里没找到可点的按钮")
            end
        end
    end
end

-- ========== Blox Fruits 技能 / 攻击特效：workspace._WorldOrigin ==========
-- Blox Fruits 把技能、攻击的特效放进 workspace._WorldOrigin。这里单独监听这个文件夹，特效一出现就当场处理：
--   light：去掉粒子、拖尾、光束、灯光、高亮、烟火这类特效对象；刀光、冲击波这类模型还在，
--          仍然看得出招式和范围，适合正常游玩
--   full ：再把这个文件夹里的零件和贴图也设成看不见（用 LocalTransparencyModifier，
--          游戏自己把 Transparency 渐变回来也盖不住），技能基本全看不见，适合挂机
-- 只改本地显示，不删除任何东西；伤害和命中都由服务器计算，不受影响。
-- BF_VFXKeepNames 里的名字（以及它们下面的东西）不碰：Locations 是岛屿位置标记，
-- CannonBall 是海上事件会用到的炮弹。伤害数字是界面（BillboardGui），不会被这里处理。
-- 即使 BF_SkillVFX = "off"，也会找到这个文件夹，好让后台跳过里面短命的零件（见 onWorkspaceAdded）

local function insideKept(v)
    local p = v
    while p and p ~= worldOrigin do
        if vfxKeep[p.Name] then return true end
        p = p.Parent
    end
    return false
end

local function handleVFX(v)
    local cn = v.ClassName
    local isEffect = EFFECT_CLASS[cn]
    local isVisual = (vfxMode == "full") and (cn == "Decal" or cn == "Texture" or v:IsA("BasePart"))
    if not isEffect and not isVisual then return end
    if insideKept(v) then return end
    if isEffect then
        killEffect(v)
    elseif v.LocalTransparencyModifier < 1 then
        v.LocalTransparencyModifier = 1
    end
end

local function hookWorldOrigin()
    local wo = Workspace:FindFirstChild("_WorldOrigin")
    local waited = 0
    while alive and not wo and waited < 60 do
        sleep(1)
        waited = waited + 1
        wo = Workspace:FindFirstChild("_WorldOrigin")
    end
    if not alive then return end
    if not wo then
        report("Blox Fruits 技能特效", false, "60 秒内没找到 workspace._WorldOrigin")
        return
    end
    worldOrigin = wo
    if vfxMode == "off" then
        report("Blox Fruits 技能特效", true, "模式 off：不处理特效，只让后台跳过技能特效文件夹")
        return
    end
    conns[#conns + 1] = wo.DescendantAdded:Connect(function(v)
        pcall(handleVFX, v)
    end)
    local list = wo:GetDescendants()
    for i = 1, #list do
        pcall(handleVFX, list[i])
        if i % 200 == 0 then
            sleep()
        end
    end
    report("Blox Fruits 技能特效", true, "模式 " .. vfxMode .. "，已监听 workspace._WorldOrigin")
end

-- ========== Blox Fruits 自带的客户端优化器 ==========
-- 游戏自己在 PlayerScripts 里放了一个优化器（OptimizerClientActor），给它发 "Optimize" 消息即可开启。
-- 找不到就跳过，不影响别的
local function callGameOptimizer()
    local ps = LocalPlayer and LocalPlayer:WaitForChild("PlayerScripts", 30)
    local actor = ps and ps:WaitForChild("OptimizerClientActor", 30)
    if not actor then
        report("Blox Fruits 自带优化器", false, "没找到 PlayerScripts.OptimizerClientActor")
        return
    end
    local ok = pcall(function() actor:SendMessage("Optimize", true) end)
    report("Blox Fruits 自带优化器", ok, ok and "已发送 Optimize" or nil)
end

-- ========== 主流程 ==========
spawnFn(function()
    safeCall("Roblox 设置", applyRobloxSettings)
    safeCall("全局画质", applyGlobalSettings)
    safeCall("串流/LOD", tuneStreaming)
    safeCall("灰色天空", applyGraySky)

    -- 画质等级这类全局设置刚改完，引擎自己要消化一阵，等一会儿再开始扫场景，避免卡顿叠加
    sleep(1.5)

    conns[#conns + 1] = RunService.Heartbeat:Connect(function(dt)
        lastDt = dt
    end)

    -- 先挂上监听再扫已有的对象，这样扫描期间新出现的东西也不会漏
    if C.OptimizeNewObjects then
        conns[#conns + 1] = Workspace.DescendantAdded:Connect(onWorkspaceAdded)
        conns[#conns + 1] = Lighting.DescendantAdded:Connect(function(v)
            pcall(optimizeLightingObject, v)
        end)
    end

    for _, v in ipairs(Lighting:GetDescendants()) do
        pcall(optimizeLightingObject, v)
    end

    if C.LocalCharEffects and LocalPlayer then
        if LocalPlayer.Character then
            safeCall("本地角色特效", hookLocalCharacter, LocalPlayer.Character)
        end
        conns[#conns + 1] = LocalPlayer.CharacterAdded:Connect(hookLocalCharacter)
    end

    -- 已有的对象：交给后台分批扫描
    if next(KIND) ~= nil then
        startScan(Workspace)
    end
    spawnFn(queueWorker)

    if C.ReduceAnimations then
        spawnFn(animationLoop)
    end
    if C.FriendNotifications == false or C.HideMyBadges == true then
        spawnFn(function() safeCall("好友/徽章通知", hideCoreNotifications) end)
    end
    spawnFn(function() safeCall("Blox Fruits 设置", applyBloxFruitsSettings) end)

    local isBF = isBloxFruits()
    if isBF then
        spawnFn(function() safeCall("Blox Fruits 技能特效", hookWorldOrigin) end)
    end
    if isBF and C.BF_GameOptimizer then
        spawnFn(function() safeCall("Blox Fruits 自带优化器", callGameOptimizer) end)
    end

    -- 等已有对象扫描完（最多等 180 秒）
    local waited = 0
    while alive and not scanDone and waited < 180 do
        sleep(0.25)
        waited = waited + 0.25
    end

    report("场景处理", true, "共改动 " .. processedTotal .. " 个对象")
    if C.Notify then
        pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = "FPS Boost（配置 " .. tostring(C.Profile) .. "）",
                Text = "场景处理完成，改动了 " .. processedTotal .. " 个对象",
                Duration = 6,
            })
        end)
    end

    -- Blox Fruits：岛屿离得远时放在 ReplicatedStorage.Unloaded 里，走近才搬进场景。
    -- 趁现在空闲把它们也处理掉，以后走到新岛屿时要改的东西已经改好，移动时少卡一点。
    -- 只在场景扫描真的完成之后才开始，用的是同一个后台处理器，同样按帧时间自动放慢。
    if alive and scanDone and isBF and C.BF_PreOptimizeUnloaded and next(KIND) ~= nil then
        local unloaded = game:GetService("ReplicatedStorage"):FindFirstChild("Unloaded")
        if unloaded then
            local before = processedTotal
            startScan(unloaded)
            waited = 0
            while alive and not scanDone and waited < 600 do
                sleep(0.5)
                waited = waited + 0.5
            end
            report("预处理未加载岛屿", scanDone, "改动 " .. (processedTotal - before) .. " 个对象")
        else
            report("预处理未加载岛屿", false, "没找到 ReplicatedStorage.Unloaded")
        end
    end
end)

--[==[
================ 使用说明 ================

一、先 set getgenv，再运行脚本（两步缺一不可）
  1. 先执行配置表：fps_config_A_v6.lua 或 fps_config_B_v6.lua 的全部内容，
     它只是一句 getgenv().FpsBoostConfig = { ... }。
  2. 再执行本脚本。脚本启动时读取 getgenv().FpsBoostConfig；
     没有设置的话，用文件顶部 Defaults 里的值（等同配置 A）。
  也可以把配置表直接粘在本脚本最前面，一起执行。
  只想改个别项也行：不用整张表，写 getgenv().FpsBoostConfig = { MasterVolume = 0 }，
  没写的项用 Defaults 里的值。

二、A / B 两套怎么用
  A（正常游玩）：先执行 fps_config_A_v6.lua，再执行本脚本。
     提帧降负载，但不隐藏地图/NPC/玩家/本地角色，不关 3D 渲染，不动音量。
  B（极限挂机）：先执行 fps_config_B_v6.lua，再执行本脚本。
     地图、NPC、其他玩家和你自己的角色模型全部本地隐藏（碰撞和实体仍在），
     音量 0、图形最低、后期/特效/贴图/灯光全关，Roblox 各项设置按表里的值改。
     想要真正的极限，把 B 里的 Disable3DRendering 改成 true（画面会空白）。

三、切换与还原
  - 重复运行是安全的：会先清掉上一次留下的监听和循环。
  - 但已经改过的画面（透明度、删掉的贴图等）不会自动撤销。
    从 B 切回 A、或者想完全恢复，请重进游戏。
  - 关闭 3D 渲染后想恢复：重进游戏，或执行
    game:GetService("RunService"):Set3dRenderingEnabled(true)

四、如果还是卡：按这个顺序逐个排查（每次只改一项，重进游戏再试）
  1. WorkBudgetMs 调小（比如 1.5）：后台处理会更慢，但对帧数的影响更小。
  2. GraphicsLevel 改成 "keep"：改图形等级和网格细节会让引擎重新处理所有网格，
     刚注入时的那一阵卡顿很可能主要来自这里，这一项只能由引擎自己消化。
  3. MeshOptimize / RemoveTextures 先关掉：它们会逐个改网格零件。
  4. 大型游戏里"每隔一会儿卡一下"：先把 AnimBudgetMs 调小（比如 0.25），还卡就把 ReduceAnimations 关掉。
     动画检查是唯一定时跑的部分，人物 / NPC 越多影响越大。
  5. TuneStreaming、ModelLOD 保持关闭：打开后可能让移动时更卡。
  FpsCap = 999 在手机上长时间满负荷运行可能发热降频，也可以改成 60~120 试试。

五、几个要知道的限制
  - 自动翻译、作品语言：Roblox 没有给脚本开放接口，脚本只会提示"跳过"，请在 Roblox 设置里手动改。
  - 好友通知、我的徽章：靠隐藏 CoreGui 的通知容器实现，不是真的改了 Roblox 设置。
  - 背景透明度：如果效果和预期相反，把脚本顶部的 OPAQUE_VALUE 改成 1。
  - 灰色天空：先用不碰 FFlag 的办法；不行再把 GraySkyFFlag 设成 true。
    运行中改 FFlag 往往要重进游戏才生效，能在执行器里提前设好最稳。
  - 地形（Terrain）没法用透明度隐藏，B 模式下地形仍会画出来；要彻底不画只能关 3D 渲染。
  - Blox Fruits 设置：靠点游戏自己的设置按钮实现，只有 FastMode 一行的名字确认过，
    其余按关键字匹配。对不上就开 BF_Debug 看行名，再用 BF_RowNames 手动指定。
  - Blox Fruits 技能 / 攻击特效（BF_SkillVFX）：
      light（A 默认）：粒子、拖尾、光束、灯光这些去掉，刀光、冲击波模型还在，仍看得出招式范围。
      full（B 默认）：技能文件夹里的模型也全部看不见，打 Boss 时会看不到攻击范围，正常游玩慎用。
    只改本地显示，伤害和命中都由服务器计算，不受影响。
    如果 full 模式下有需要看见的东西也被隐藏了，把它的名字加进 BF_VFXKeepNames。
  - 角色身上的特效（光环、挥刀拖尾、打中怪物的火花等）由 DisableEffects 处理，不止 Blox Fruits，
    其他游戏也一样生效。
  - 每一项到底成没成功，看控制台里 [FpsBoost] 开头的日志（PrintReport = true 时会打印）。
]==]
