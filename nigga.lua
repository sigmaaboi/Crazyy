-- Auto join variables
local autoJoin5v5 = false
local autoJoin3v3 = false
local autoJoinBattleRoyale = false
local joining = false

-- Friend party variables
local selectedFriends = {}
local inviteFriend = false
local autoInviteFriends = false
local waitingForFriend = false
local friendsInParty = {}

-- Auto replay variables
local autoReplay5v5 = false
local autoReplay3v3 = false
local autoReplayBattleRoyale = false
local replaying = false
local replayWaitTime = 5 -- Wait time before checking replay conditions

-- NEW: Replay priority system
local replayInProgress = false
local replayResultDetected = false
local lastResultTime = 0

-- Teleport toggles for each mode
local teleportEnabled3v3 = false
local teleportEnabled5v5 = false
local teleporting = false
local lastPosition = Vector3.new(0, 0, 0)

-- FIXED: Auto map center teleport variables
local autoMapCenterTeleport = false
local customPlatforms = {}
local mapCenters = {}
local lastDetectedMap = nil
local lastMapCenterTime = 0

-- Debug variables
local teleportCount = 0
local lastTeleportTime = 0

-- Config variables (Updated structure)
local autoLoadConfig = true
local currentConfigName = "default"
local hubFolder = "CrazyHub"
local configsFolder = hubFolder .. "/configs"
local autoLoadFile = hubFolder .. "/auto_load.txt"

-- ALL KNOWN MAPS
local mapNames = {
    "CapeCanaveral",
    "ChuninExams", 
    "HuecoMundo",
    "Namek",
    "Sandora",
    "Wisteria"
}

-- FIXED: Predefined safe positions for maps with correct heights (Y: 66 to avoid dead zone)
local mapSafePositions = {
    ["CapeCanaveral"] = Vector3.new(-1046, 66, 889),
    ["ChuninExams"] = Vector3.new(0, 66, 0),
    ["HuecoMundo"] = Vector3.new(0, 66, 0),
    ["Namek"] = Vector3.new(0, 66, 0),
    ["Sandora"] = Vector3.new(0, 66, 0),
    ["Wisteria"] = Vector3.new(0, 66, 0)
}

-- NEW: Check if player is in any map
local function isInAnyMap()
    for _, mapName in pairs(mapNames) do
        if workspace:FindFirstChild(mapName) then
            return true, mapName
        end
    end
    return false, nil
end

-- FIXED: Enhanced function to check if loading screen is visible
local function isLoadingScreenVisible()
    local success, result = pcall(function()
        -- Check ReactLoadingScreen
        local reactLoadingScreen = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("ReactLoadingScreen")
        if reactLoadingScreen and reactLoadingScreen.Visible then
            return true
        end
        
        -- Check any other loading screens
        local playerGui = game:GetService("Players").LocalPlayer.PlayerGui
        for _, gui in pairs(playerGui:GetChildren()) do
            if gui.Name:lower():find("loading") and gui.Visible then
                return true
            end
        end
        
        -- Check if player is still loading into game
        if not game:GetService("Players").LocalPlayer.Character then
            return true
        end
        
        return false
    end)
    
    return success and result
end

-- Function to check if PlayersLeft GUI is visible (Battle Royale lobby)
local function isPlayersLeftVisible()
    local success, result = pcall(function()
        local playersLeftGui = game:GetService("Players").LocalPlayer.PlayerGui.CoreSafeInsets.Gamemode.PlayersLeft.PlayersHolder
        if playersLeftGui and playersLeftGui.Visible then
            return true
        end
        return false
    end)
    
    return success and result
end

-- ADDED: Function to check if enemy left GUI is visible
local function isEnemyLeftVisible()
    local success, result = pcall(function()
        -- Check for enemy left notification
        local playerGui = game:GetService("Players").LocalPlayer.PlayerGui
        
        -- Check common enemy left GUI patterns
        for _, gui in pairs(playerGui:GetChildren()) do
            if gui.Visible then
                for _, element in pairs(gui:GetDescendants()) do
                    if element:IsA("TextLabel") then
                        local text = element.Text:lower()
                        if text:find("enemy") and text:find("left") then
                            return true
                        elseif text:find("opponent") and text:find("left") then
                            return true
                        elseif text:find("disconnected") then
                            return true
                        end
                    end
                end
            end
        end
        
        return false
    end)
    
    return success and result
end

-- Function to detect current map
local function getCurrentMap()
    for _, mapName in pairs(mapNames) do
        if workspace:FindFirstChild(mapName) then
            return mapName
        end
    end
    return nil
end

-- NEW: Enhanced replay result checks
local function checkForWin()
    local success, result = pcall(function()
        local gui = game:GetService("Players").LocalPlayer.PlayerGui.App.Main.Gamemode.Results.Holder.MatchEndedPlacement.Place1.Top
        return gui and gui.Visible and gui.Text == "You won!"
    end)
    return success and result
end

local function checkForLoss()
    local success, result = pcall(function()
        local gui = game:GetService("Players").LocalPlayer.PlayerGui.App.Main.Gamemode.Results.Holder.MatchEndedPlacement.Place1.Top
        return gui and gui.Visible and gui.Text == "You lost!"
    end)
    return success and result
end

local function checkBattleRoyalePlacement()
    local success, placement = pcall(function()
        local gui = game:GetService("Players").LocalPlayer.PlayerGui.App.Main.Gamemode.Results.Holder.MatchEndedPlacement.Place1.Top
        if gui and gui.Visible then
            for i = 1, 10 do
                if gui.Text == "You are #" .. i .. "!" then
                    return i
                end
            end
        end
        return nil
    end)
    return success and placement or false, nil
end

-- NEW: Check if we have a valid replay result and set priority
local function hasValidReplayResult()
    local won = checkForWin()
    local lost = checkForLoss()
    local _, placement = checkBattleRoyalePlacement()
    
    local hasResult = won or lost or placement ~= nil
    
    if hasResult and not replayResultDetected then
        -- First time detecting result - set priority for replay
        replayResultDetected = true
        replayInProgress = true
        lastResultTime = tick()
        print("[DEBUG] Replay result detected - blocking auto-join for 30 seconds")
    end
    
    return hasResult
end

-- NEW: Check if replay has priority over auto-join
local function isReplayBlocking()
    if replayInProgress then
        -- Keep blocking auto-join for 30 seconds after result detected
        if tick() - lastResultTime > 30 then
            replayInProgress = false
            replayResultDetected = false
            print("[DEBUG] Replay priority expired - auto-join unblocked")
            return false
        end
        return true
    end
    return false
end

-- FIXED: Function to calculate map center dynamically with SAFE HEIGHT (Y: 66)
local function calculateMapCenter(mapName)
    print("[DEBUG] Calculating center for map:", mapName)
    
    local success, result = pcall(function()
        local mapFolder = workspace:FindFirstChild(mapName)
        if not mapFolder then
            print("[DEBUG] Map folder not found:", mapName)
            return mapSafePositions[mapName] or Vector3.new(0, 66, 0)
        end
        
        print("[DEBUG] Found map folder:", mapFolder.Name)
        
        local minX, maxX = math.huge, -math.huge
        local minZ, maxZ = math.huge, -math.huge
        local partCount = 0
        
        -- Recursively find all parts in the map (ignoring Y for safety)
        local function scanParts(parent, depth)
            depth = depth or 0
            if depth > 10 then return end -- Prevent infinite recursion
            
            for _, obj in pairs(parent:GetChildren()) do
                if obj:IsA("BasePart") and obj.CanCollide then -- Only count solid parts
                    local pos = obj.Position
                    local size = obj.Size
                    
                    -- Calculate X and Z bounds only (ignore Y for safety)
                    minX = math.min(minX, pos.X - size.X/2)
                    maxX = math.max(maxX, pos.X + size.X/2)
                    minZ = math.min(minZ, pos.Z - size.Z/2)
                    maxZ = math.max(maxZ, pos.Z + size.Z/2)
                    
                    partCount = partCount + 1
                elseif obj:IsA("Folder") or obj:IsA("Model") then
                    scanParts(obj, depth + 1)
                end
            end
        end
        
        scanParts(mapFolder)
        
        print("[DEBUG] Scanned", partCount, "parts")
        
        if partCount > 0 then
            -- Calculate center point with FIXED SAFE HEIGHT
            local centerX = (minX + maxX) / 2
            local centerY = 66 -- FIXED: Safe height to avoid dead zone
            local centerZ = (minZ + maxZ) / 2
            
            local center = Vector3.new(centerX, centerY, centerZ)
            print("[DEBUG] Calculated center with safe height:", center)
            return center
        else
            print("[DEBUG] No valid parts found, using fallback")
            return mapSafePositions[mapName] or Vector3.new(0, 66, 0)
        end
    end)
    
    if success and result then
        print("[DEBUG] Successfully calculated center:", result)
        return result
    else
        print("[DEBUG] Error calculating center:", result, "- Using fallback")
        return mapSafePositions[mapName] or Vector3.new(0, 66, 0)
    end
end

-- FIXED: Function to create platform at position with SAFE HEIGHT (INVISIBLE)
local function createPlatform(position, mapName)
    print("[DEBUG] Creating invisible platform at:", position, "for map:", mapName)
    
    -- Ensure platform is at safe height
    local safePosition = Vector3.new(position.X, 64, position.Z) -- Platform at Y: 64, player at Y: 66
    
    local success, platform = pcall(function()
        local part = Instance.new("Part")
        part.Name = "CrazyHub_Platform_" .. (mapName or "Custom")
        part.Size = Vector3.new(25, 2, 25) -- Even bigger platform for safety
        part.Position = safePosition
        part.Anchored = true
        part.CanCollide = true
        part.Material = Enum.Material.ForceField
        part.BrickColor = BrickColor.new("Bright green") -- Green for safe zone
        part.Transparency = 1 -- INVISIBLE
        part.Shape = Enum.PartType.Block
        part.TopSurface = Enum.SurfaceType.Smooth
        part.BottomSurface = Enum.SurfaceType.Smooth
        
        -- Remove safety glow effect and text labels (commented out)
        -- No lights or text for stealth
        
        part.Parent = workspace
        print("[DEBUG] Invisible platform created successfully at safe height")
        return part
    end)
    
    if success then
        return platform
    else
        print("[DEBUG] Failed to create platform:", platform)
        return nil
    end
end

-- Function to remove platforms
local function removePlatforms()
    local success = pcall(function()
        -- Remove all platforms
        for mapName, platform in pairs(customPlatforms) do
            if platform and platform.Parent then
                platform:Destroy()
                print("[DEBUG] Removed platform for:", mapName)
            end
        end
        customPlatforms = {}
        
        -- Also remove any existing platforms with our naming pattern
        for _, obj in pairs(workspace:GetChildren()) do
            if obj.Name:find("CrazyHub_Platform") then
                obj:Destroy()
            end
        end
    end)
    
    return success
end

-- FIXED: Function to auto teleport to current map center with SAFE HEIGHT
local function autoTeleportToMapCenter()
    if not autoMapCenterTeleport then return end
    
    print("[DEBUG] Auto teleport to map center triggered")
    
    local success, err = pcall(function()
        local player = game.Players.LocalPlayer
        if not player or not player.Character then
            print("[DEBUG] No player or character")
            return
        end
        
        local hrp = player.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then
            print("[DEBUG] No HumanoidRootPart")
            return
        end
        
        -- Get current map
        local currentMap = getCurrentMap()
        if not currentMap then
            print("[DEBUG] No current map detected")
            return
        end
        
        print("[DEBUG] Current map:", currentMap)
        
        -- Check if this is a new map or first time
        local shouldTeleport = false
        if currentMap ~= lastDetectedMap then
            print("[DEBUG] New map detected:", currentMap, "Previous:", lastDetectedMap)
            shouldTeleport = true
            lastDetectedMap = currentMap
        elseif tick() - lastMapCenterTime > 10 then -- Also teleport every 10 seconds as backup
            print("[DEBUG] Backup teleport trigger")
            shouldTeleport = true
        end
        
        if not shouldTeleport then
            return
        end
        
        -- Calculate center with safe height
        local center = calculateMapCenter(currentMap)
        if not center then
            print("[DEBUG] Failed to calculate center")
            return
        end
        
        mapCenters[currentMap] = center
        
        -- Remove existing platform for this map
        if customPlatforms[currentMap] and customPlatforms[currentMap].Parent then
            customPlatforms[currentMap]:Destroy()
        end
        
        -- Create new platform at the center
        customPlatforms[currentMap] = createPlatform(center, currentMap)
        
        -- Wait a frame for platform to spawn
        task.wait(0.1)
        
        -- FIXED: Teleport player to SAFE HEIGHT (Y: 66)
        local teleportPosition = Vector3.new(center.X, 66, center.Z) -- Safe height
        hrp.CFrame = CFrame.new(teleportPosition)
        
        teleportCount = teleportCount + 1
        lastMapCenterTime = tick()
        
        print("[DEBUG] Teleported to SAFE HEIGHT:", teleportPosition, "Platform at:", Vector3.new(center.X, 64, center.Z))
        
        -- Show notification
        if library then
            library:Notify("✅ Teleported to " .. currentMap .. " center at SAFE HEIGHT (Y: 66)!", 4, "success")
        end
    end)
    
    if not success then
        print("[DEBUG] Auto teleport error:", err)
    end
end

-- Config System Functions (FIXED)
local function ensureFolders()
    if not isfolder(hubFolder) then
        makefolder(hubFolder)
    end
    if not isfolder(configsFolder) then
        makefolder(configsFolder)
    end
end

local function getConfigPath(configName)
    return configsFolder .. "/" .. configName .. ".json"
end

local function saveAutoLoadConfig(configName)
    ensureFolders()
    local success, err = pcall(function()
        writefile(autoLoadFile, configName)
    end)
    return success, err
end

local function getAutoLoadConfig()
    if isfile(autoLoadFile) then
        local success, configName = pcall(function()
            return readfile(autoLoadFile)
        end)
        if success and configName and configName ~= "" then
            return configName
        end
    end
    return "default"
end

local function saveConfig(configName)
    ensureFolders()
    
    local config = {
        autoJoin5v5 = autoJoin5v5,
        autoJoin3v3 = autoJoin3v3,
        autoJoinBattleRoyale = autoJoinBattleRoyale,
        selectedFriends = selectedFriends,
        inviteFriend = inviteFriend,
        autoInviteFriends = autoInviteFriends,
        autoReplay5v5 = autoReplay5v5,
        autoReplay3v3 = autoReplay3v3,
        autoReplayBattleRoyale = autoReplayBattleRoyale,
        teleportEnabled3v3 = teleportEnabled3v3,
        teleportEnabled5v5 = teleportEnabled5v5,
        autoMapCenterTeleport = autoMapCenterTeleport,
        autoLoadConfig = autoLoadConfig,
        currentConfigName = configName,
        replayWaitTime = replayWaitTime,
        savedBy = game.Players.LocalPlayer.Name,
        savedAt = os.time(),
        version = "2.2"
    }
    
    local success, err = pcall(function()
        local jsonConfig = game:GetService("HttpService"):JSONEncode(config)
        writefile(getConfigPath(configName), jsonConfig)
    end)
    
    -- Also save as auto-load config if auto-load is enabled
    if success and autoLoadConfig then
        saveAutoLoadConfig(configName)
    end
    
    return success, err
end

local function loadConfig(configName)
    local configPath = getConfigPath(configName)
    
    if not isfile(configPath) then
        return false, "Config file not found: " .. configName
    end
    
    local success, result = pcall(function()
        local configData = readfile(configPath)
        return game:GetService("HttpService"):JSONDecode(configData)
    end)
    
    if not success then
        return false, "Failed to parse config file: " .. tostring(result)
    end
    
    local config = result
    
    -- Apply config settings
    autoJoin5v5 = config.autoJoin5v5 or false
    autoJoin3v3 = config.autoJoin3v3 or false
    autoJoinBattleRoyale = config.autoJoinBattleRoyale or false
    selectedFriends = config.selectedFriends or {}
    inviteFriend = config.inviteFriend or false
    autoInviteFriends = config.autoInviteFriends or false
    autoReplay5v5 = config.autoReplay5v5 or false
    autoReplay3v3 = config.autoReplay3v3 or false
    autoReplayBattleRoyale = config.autoReplayBattleRoyale or false
    teleportEnabled3v3 = config.teleportEnabled3v3 or false
    teleportEnabled5v5 = config.teleportEnabled5v5 or false
    autoMapCenterTeleport = config.autoMapCenterTeleport or false
    autoLoadConfig = config.autoLoadConfig ~= nil and config.autoLoadConfig or true
    replayWaitTime = config.replayWaitTime or 5
    currentConfigName = configName
    
    -- Update auto-load file if auto-load is enabled
    if autoLoadConfig then
        saveAutoLoadConfig(configName)
    end
    
    return true, "Config loaded successfully"
end

-- FIXED getConfigList function
local function getConfigList()
    ensureFolders()
    local configs = {}
    
    -- Add default config first
    table.insert(configs, "default")
    
    local success, files = pcall(function()
        return listfiles(configsFolder)
    end)
    
    if success and files then
        for _, fullPath in pairs(files) do
            -- Extract just the filename from the full path
            local fileName = fullPath:match("([^/\\]+)$")
            
            -- Check if it's a JSON file
            if fileName and fileName:match("%.json$") then
                local configName = fileName:sub(1, -6) -- Remove .json extension
                
                -- Don't add default twice
                if configName ~= "default" then
                    -- Check if config already exists in list
                    local exists = false
                    for _, existingConfig in pairs(configs) do
                        if existingConfig == configName then
                            exists = true
                            break
                        end
                    end
                    
                    if not exists then
                        table.insert(configs, configName)
                    end
                end
            end
        end
    end
    
    return configs
end

local function deleteConfig(configName)
    if configName == "default" then
        return false, "Cannot delete default config"
    end
    
    local configPath = getConfigPath(configName)
    
    if isfile(configPath) then
        local success, err = pcall(function()
            delfile(configPath)
        end)
        
        -- If deleted config was the auto-load config, reset to default
        if success and getAutoLoadConfig() == configName then
            saveAutoLoadConfig("default")
        end
        
        return success, err
    end
    
    return false, "Config file not found"
end

local function setAutoLoadConfig(configName)
    if isfile(getConfigPath(configName)) then
        local success, err = saveAutoLoadConfig(configName)
        if success then
            currentConfigName = configName
            autoLoadConfig = true
        end
        return success, err
    else
        return false, "Config does not exist"
    end
end

local function disableAutoLoad()
    autoLoadConfig = false
    local success, err = pcall(function()
        if isfile(autoLoadFile) then
            delfile(autoLoadFile)
        end
    end)
    return success, err
end

-- Function to check if player is in an active match
local function isInActiveMatch()
    local success, result = pcall(function()
        local redScoreGui = game:GetService("Players").LocalPlayer.PlayerGui.CoreSafeInsets.Gamemode.RedScore
        if redScoreGui and redScoreGui.Visible then
            return true
        end
        return false
    end)
    
    return success and result
end

-- Function to get all players (for friend selection)
local function getAllPlayers()
    local playerNames = {}
    for _, player in pairs(game:GetService("Players"):GetPlayers()) do
        if player ~= game.Players.LocalPlayer then
            table.insert(playerNames, player.Name)
        end
    end
    return playerNames
end

-- Function to invite friend to party
local function inviteToParty(friendName)
    if not friendName or friendName == "" then return end
    
    local success, err = pcall(function()
        local targetPlayer = game:GetService("Players"):FindFirstChild(friendName)
        if targetPlayer then
            game:GetService("ReplicatedStorage")["RemoteService/Remotes"].InvitePlayer.E:FireServer(targetPlayer)
        end
    end)
end

-- Function to invite all selected friends
local function inviteAllSelectedFriends()
    for _, friendName in pairs(selectedFriends) do
        inviteToParty(friendName)
        task.wait(0.5)
    end
end

-- Function to check if friends are in party
local function checkFriendsInParty()
    local allFriendsInParty = true
    friendsInParty = {}
    
    for _, friendName in pairs(selectedFriends) do
        local success, result = pcall(function()
            local targetPlayer = game:GetService("Players"):FindFirstChild(friendName)
            if targetPlayer then
                return true
            end
            return false
        end)
        
        if success and result then
            friendsInParty[friendName] = true
        else
            friendsInParty[friendName] = false
            allFriendsInParty = false
        end
    end
    
    return allFriendsInParty
end

-- UPDATED: Auto join functions with MAP CHECKS + REPLAY PRIORITY
local function joinQueue(gameMode)
    if joining then 
        print("[DEBUG] Already joining, skipping...")
        return 
    end
    
    -- NEW: Check if replay has priority (result detected)
    if isReplayBlocking() then
        print("[DEBUG] Replay has priority over auto-join - blocking")
        return
    end
    
    -- NEW: Check if player is in any map (block auto-join)
    local inMap, mapName = isInAnyMap()
    if inMap then
        print("[DEBUG] Player is in map:", mapName, "- blocking auto-join")
        return
    end
    
    -- STRICT CHECK: Loading screen check
    if isLoadingScreenVisible() then
        print("[DEBUG] Loading screen visible, blocking auto-join")
        return
    end
    
    -- STRICT CHECK: PlayersLeft GUI check
    if isPlayersLeftVisible() then
        print("[DEBUG] PlayersLeft GUI visible, blocking auto-join")
        return
    end
    
    -- STRICT CHECK: Active match check
    if isInActiveMatch() then
        print("[DEBUG] Already in active match, blocking auto-join")
        return
    end
    
    -- Friend check
    if inviteFriend and #selectedFriends > 0 then
        if not checkFriendsInParty() then
            print("[DEBUG] Friends not in party, blocking auto-join")
            return
        end
    end
    
    joining = true
    print("[DEBUG] All checks passed, joining queue:", gameMode)

    local success, err = pcall(function()
        if gameMode == "BattleRoyaleFfa" then
            local args = {"BattleRoyaleFfa"}
            game:GetService("ReplicatedStorage"):WaitForChild("RemoteService/Remotes"):WaitForChild("JoinQueue"):WaitForChild("E"):FireServer(unpack(args))
        else
            game:GetService("ReplicatedStorage")["RemoteService/Remotes"].JoinQueue.E:FireServer(gameMode)
        end
    end)

    if not success then
        print("[DEBUG] Failed to join queue:", err)
    end

    task.wait(1)
    joining = false
end

-- UPDATED: Auto replay function with ENHANCED RESULT CHECKS + PRIORITY ACCESS
local function replayQueue(gameMode)
    if replaying then 
        print("[DEBUG] Already replaying, skipping...")
        return 
    end
    
    -- NEW: Enhanced check - only replay if we see valid results
    if not hasValidReplayResult() then
        print("[DEBUG] No valid replay result visible - blocking replay")
        return
    end
    
    -- Friend check
    if inviteFriend and #selectedFriends > 0 then
        if not checkFriendsInParty() then
            print("[DEBUG] Friends not in party, blocking replay")
            return
        end
    end
    
    replaying = true
    print("[DEBUG] Valid result detected, starting replay process for:", gameMode)
    
    -- WAIT before checking conditions
    print("[DEBUG] Waiting", replayWaitTime, "seconds before replay checks...")
    task.wait(replayWaitTime)
    
    -- Check if enemy left GUI is visible
    if isEnemyLeftVisible() then
        print("[DEBUG] Enemy left GUI visible, blocking replay")
        replaying = false
        return
    end
    
    -- Check loading screen again
    if isLoadingScreenVisible() then
        print("[DEBUG] Loading screen visible during replay, blocking")
        replaying = false
        return
    end
    
    -- Check if already in active match
    if isInActiveMatch() then
        print("[DEBUG] Already in active match during replay, blocking")
        replaying = false
        return
    end
    
    print("[DEBUG] All replay checks passed, proceeding with replay (priority access)")

    local success, err = pcall(function()
        if gameMode == "BattleRoyaleFfa" then
            local args = {"BattleRoyaleFfa"}
            game:GetService("ReplicatedStorage"):WaitForChild("RemoteService/Remotes"):WaitForChild("JoinQueue"):WaitForChild("E"):FireServer(unpack(args))
        else
            game:GetService("ReplicatedStorage")["RemoteService/Remotes"].JoinQueue.E:FireServer(gameMode)
        end
    end)

    if not success then
        print("[DEBUG] Failed to replay queue:", err)
    end

    task.wait(0.5)
    replaying = false
    
    -- Reset replay priority after successful replay
    replayInProgress = false
    replayResultDetected = false
    print("[DEBUG] Replay completed - auto-join unblocked")
end

-- Function to check if match ended (win or loss)
local function checkForMatchEnd()
    local success, result = pcall(function()
        local resultsGui = game:GetService("Players").LocalPlayer.PlayerGui.App.Main.Gamemode.Results
        if resultsGui and resultsGui.Visible then
            return true
        end
        
        local playerGui = game:GetService("Players").LocalPlayer.PlayerGui
        for _, gui in pairs(playerGui:GetChildren()) do
            if gui.Name:lower():find("result") or gui.Name:lower():find("end") then
                if gui.Visible then
                    return true
                end
            end
        end
        
        return false
    end)
    
    return success and result
end

-- Function to find enemy goal
local function getEnemyGoal()
    local success, result = pcall(function()
        local player = game.Players.LocalPlayer
        if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
            return nil
        end
        
        local playerPos = player.Character.HumanoidRootPart.Position
        local currentMap = getCurrentMap()
        
        if not currentMap then
            return nil
        end
        
        local mapFolder = workspace[currentMap]
        local goals = {}
        
        for _, obj in pairs(mapFolder:GetDescendants()) do
            if obj:IsA("BasePart") then
                local objName = obj.Name:lower()
                if objName:find("goal") or objName:find("net") or objName:find("target") then
                    local distance = (obj.Position - playerPos).Magnitude
                    table.insert(goals, {
                        goal = obj,
                        distance = distance,
                        name = obj.Name,
                        position = obj.Position
                    })
                end
            end
        end
        
        table.sort(goals, function(a, b)
            return a.distance > b.distance
        end)
        
        if #goals > 0 then
            local enemyGoal = goals[1]
            return enemyGoal.goal
        end
        
        return nil
    end)
    
    if success and result then
        return result
    else
        return nil
    end
end

-- Teleport function for 3v3
local function doTeleport3v3()
    if not teleportEnabled3v3 then return end
    
    teleporting = false
    
    local success, err = pcall(function()
        local player = game.Players.LocalPlayer
        if not player or not player.Character then
            return
        end
        
        local hrp = player.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then
            return
        end

        if workspace._Visuals and workspace._Visuals.Part then
            hrp.CFrame = workspace._Visuals.Part.CFrame + Vector3.new(0, 5, 0)
            task.wait(0.3)
        end

        local enemyGoal = getEnemyGoal()
        
        if enemyGoal then
            hrp.CFrame = enemyGoal.CFrame + Vector3.new(0, 2, 0)
            teleportCount = teleportCount + 1
            lastTeleportTime = tick()
        end
    end)
end

-- Teleport function for 5v5
local function doTeleport5v5()
    if not teleportEnabled5v5 then return end
    
    teleporting = false
    
    local success, err = pcall(function()
        local player = game.Players.LocalPlayer
        if not player or not player.Character then
            return
        end
        
        local hrp = player.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then
            return
        end

        if workspace._Visuals and workspace._Visuals.Part then
            hrp.CFrame = workspace._Visuals.Part.CFrame + Vector3.new(0, 5, 0)
            task.wait(0.3)
        end

        local enemyGoal = getEnemyGoal()
        
        if enemyGoal then
            hrp.CFrame = enemyGoal.CFrame + Vector3.new(0, 2, 0)
            teleportCount = teleportCount + 1
            lastTeleportTime = tick()
        end
    end)
end

-- Pre-load config using auto_load.txt
local function preLoadConfig()
    local autoLoadConfigName = getAutoLoadConfig()
    if autoLoadConfigName and isfile(getConfigPath(autoLoadConfigName)) then
        currentConfigName = autoLoadConfigName
        loadConfig(autoLoadConfigName)
        autoLoadConfig = true
    elseif isfile(getConfigPath("default")) then
        loadConfig("default")
        currentConfigName = "default"
    end
end

-- Pre-load config before creating UI
preLoadConfig()

-- Load XSX UI Library
local library = loadstring(game:HttpGet('https://raw.githubusercontent.com/depthso/XSX-UI-Library/refs/heads/main/xsx%20lib.lua'))()

-- Changeable Colors
library.headerColor = Color3.fromRGB(51, 158, 190)
library.companyColor = Color3.fromRGB(163, 151, 255)
library.acientColor = Color3.fromRGB(159, 115, 255)

-- Initialize Library
library:Init({
    version = "2.2",
    title = "Crazy Hub",
    company = "Crazy Hub",
    keybind = Enum.KeyCode.RightShift,
    BlurEffect = false,
})

-- Watermarks
library:Watermark("Crazy Hub | Jump Stars - Replay Priority Edition")

local FPSWatermark = library:Watermark("FPS")
game:GetService("RunService").RenderStepped:Connect(function(v)
    FPSWatermark:SetText("FPS: "..math.round(1/v))
end)

-- Intro
library:BeginIntroduction()
library:AddIntroductionMessage("Initializing Crazy Hub...")
wait(0.5)
library:AddIntroductionMessage("Loading Jump Stars features...")
wait(0.5)
library:AddIntroductionMessage("NEW: Replay Priority System...")
wait(0.5)
library:AddIntroductionMessage("NEW: Map Detection for Auto-Join...")
wait(0.5)
library:AddIntroductionMessage("NEW: Enhanced Replay Result Validation...")
wait(0.5)
library:AddIntroductionMessage("FIXED: Remote Conflict Resolution...")
wait(0.5)
library:AddIntroductionMessage("Safe Height Y: 66 (Avoiding Dead Zone)...")
wait(0.5)
library:AddIntroductionMessage("Crazy Hub on Top")
wait(0.5)
library:AddIntroductionMessage("Enjoy the script!")
wait(0.5)
library:AddIntroductionMessage("Welcome, sigmaaboi! (2025-06-26 09:18:23 UTC)")
wait(0.5)
library:EndIntroduction()

-- Create Main Tab
local mainTab = library:NewTab("Main Features")

-- Auto Features Section
mainTab:NewSection("Auto Join/Replay")

-- Status Label
local statusLabel = mainTab:NewLabel("Status: Ready", "left")

-- NEW: Map Status Label
local mapStatusLabel = mainTab:NewLabel("Map Status: None", "left")

-- NEW: Replay Priority Status
local replayPriorityLabel = mainTab:NewLabel("Replay Priority: None", "left")

-- Loading Screen Status
local loadingStatusLabel = mainTab:NewLabel("Loading Screen: Not Visible", "left")

-- PlayersLeft GUI Status
local playersLeftStatusLabel = mainTab:NewLabel("PlayersLeft GUI: Not Visible", "left")

-- Enemy Left GUI Status
local enemyLeftStatusLabel = mainTab:NewLabel("Enemy Left GUI: Not Visible", "left")

-- Auto Join Toggles (start with loaded values)
local autoJoinToggle5v5 = mainTab:NewToggle("Auto Join 5v5", autoJoin5v5, function(state)
    autoJoin5v5 = state
    if state then 
        autoJoin3v3 = false
        autoJoinBattleRoyale = false
        library:Notify("Auto Join 5v5 Enabled!", 3, "success")
    end
end)

local autoJoinToggle3v3 = mainTab:NewToggle("Auto Join 3v3", autoJoin3v3, function(state)
    autoJoin3v3 = state
    if state then 
        autoJoin5v5 = false
        autoJoinBattleRoyale = false
        library:Notify("Auto Join 3v3 Enabled!", 3, "success")
    end
end)

-- Battle Royale Auto Join Toggle
local autoJoinBattleRoyaleToggle = mainTab:NewToggle("Auto Join Battle Royale", autoJoinBattleRoyale, function(state)
    autoJoinBattleRoyale = state
    if state then 
        autoJoin5v5 = false
        autoJoin3v3 = false
        library:Notify("Auto Join Battle Royale Enabled!", 3, "success")
    end
end)

-- Auto Replay Toggles (start with loaded values)
local autoReplayToggle5v5 = mainTab:NewToggle("Auto Replay 5v5 (Win/Loss)", autoReplay5v5, function(state)
    autoReplay5v5 = state
    if state then 
        autoReplay3v3 = false
        autoReplayBattleRoyale = false
        library:Notify("Auto Replay 5v5 Enabled (Priority System)!", 3, "success")
    end
end)

local autoReplayToggle3v3 = mainTab:NewToggle("Auto Replay 3v3 (Win/Loss)", autoReplay3v3, function(state)
    autoReplay3v3 = state
    if state then 
        autoReplay5v5 = false
        autoReplayBattleRoyale = false
        library:Notify("Auto Replay 3v3 Enabled (Priority System)!", 3, "success")
    end
end)

-- Battle Royale Auto Replay Toggle
local autoReplayBattleRoyaleToggle = mainTab:NewToggle("Auto Replay Battle Royale (Top 10)", autoReplayBattleRoyale, function(state)
    autoReplayBattleRoyale = state
    if state then 
        autoReplay5v5 = false
        autoReplay3v3 = false
        library:Notify("Auto Replay Battle Royale Enabled (Priority System)!", 3, "success")
    end
end)

-- Replay Wait Time Slider
local replayWaitInput = mainTab:NewTextbox("Replay Wait Time (seconds)", tostring(replayWaitTime), "Enter wait time (1-15)", "small", true, false, function(val)
    local num = tonumber(val)
    if num and num >= 1 and num <= 15 then
        replayWaitTime = num
        library:Notify("Replay wait time set to " .. num .. " seconds!", 2, "success")
    end
end)

-- Friends Section
mainTab:NewSection("Auto Party")

-- Friend Party Toggle (start with loaded value)
local friendPartyToggle = mainTab:NewToggle("Enable Party Mode", inviteFriend, function(state)
    inviteFriend = state
    local message = state and "Friend Party Mode Enabled!" or "Friend Party Mode Disabled!"
    local notifType = state and "success" or "alert"
    library:Notify(message, 3, notifType)
end)

local autoInviteToggle = mainTab:NewToggle("Auto Invite Selected Friends", autoInviteFriends, function(state)
    autoInviteFriends = state
    local message = state and "Auto Invite Enabled!" or "Auto Invite Disabled!"
    local notifType = state and "success" or "alert"
    library:Notify(message, 3, notifType)
end)

-- Friend Selection
local friendDropdown = mainTab:NewSelector("Select Friends", "", getAllPlayers(), function(selected)
    if selected and selected ~= "" then
        -- Add friend to list if not already there
        local alreadySelected = false
        for _, friend in pairs(selectedFriends) do
            if friend == selected then
                alreadySelected = true
                break
            end
        end
        
        if not alreadySelected then
            table.insert(selectedFriends, selected)
            library:Notify("Added " .. selected .. " to party list!", 2, "success")
        else
            library:Notify(selected .. " is already in party list!", 2, "alert")
        end
    end
end)

-- Friend Management Buttons
mainTab:NewButton("Invite All Selected Friends", function()
    if #selectedFriends > 0 then
        inviteAllSelectedFriends()
        library:Notify("Invited " .. #selectedFriends .. " friends to party!", 3, "success")
    else
        library:Notify("No friends selected!", 2, "error")
    end
end)

mainTab:NewButton("Clear Selected Friends", function()
    selectedFriends = {}
    library:Notify("Cleared friend list!", 2, "alert")
end)

mainTab:NewButton("Refresh Player List", function()
    local players = getAllPlayers()
    library:Notify("Player list refreshed! Found " .. #players .. " players.", 3, "success")
end)

-- Selected Friends Display
local selectedFriendsLabel = mainTab:NewLabel("Selected Friends: None", "left")

-- Teleport Section
mainTab:NewSection("Auto Win")

-- Teleport Status
local teleportStatusLabel = mainTab:NewLabel("Teleport Count: 0", "left")

local teleportToggle3v3 = mainTab:NewToggle("Auto Win (3v3)", teleportEnabled3v3, function(state)
    teleportEnabled3v3 = state
    if state then 
        teleportEnabled5v5 = false
        autoMapCenterTeleport = false
        teleportCount = 0
        lastTeleportTime = 0
        library:Notify("3v3 Auto Win Enabled!", 3, "alert")
        
        if game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            lastPosition = game.Players.LocalPlayer.Character.HumanoidRootPart.Position
        end
        doTeleport3v3()
    end
end)

local teleportToggle5v5 = mainTab:NewToggle("Auto Win (5v5)", teleportEnabled5v5, function(state)
    teleportEnabled5v5 = state
    if state then 
        teleportEnabled3v3 = false
        autoMapCenterTeleport = false
        teleportCount = 0
        lastTeleportTime = 0
        library:Notify("5v5 Auto Win Enabled!", 3, "alert")
        
        if game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            lastPosition = game.Players.LocalPlayer.Character.HumanoidRootPart.Position
        end
        doTeleport5v5()
    end
end)

-- FIXED: Auto Map Center Teleport Toggle with SAFE HEIGHT
local autoMapCenterToggle = mainTab:NewToggle("✅ Safe Map Center Teleport (Y: 66)", autoMapCenterTeleport, function(state)
    autoMapCenterTeleport = state
    if state then 
        teleportEnabled3v3 = false
        teleportEnabled5v5 = false
        teleportCount = 0
        lastDetectedMap = nil -- Reset map detection
        lastMapCenterTime = 0
        
        -- Remove any existing platforms first
        removePlatforms()
        
        library:Notify("✅ Safe Map Center Teleport Enabled! (Y: 66 - Avoiding Dead Zone)", 4, "success")
        
        -- Immediately teleport to current map center
        task.wait(0.5) -- Small delay to ensure everything is ready
        autoTeleportToMapCenter()
    else
        -- Clean up platforms when disabled
        removePlatforms()
        lastDetectedMap = nil
        library:Notify("Safe Map Center Teleport Disabled!", 3, "alert")
    end
end)

-- Manual teleport button for testing
mainTab:NewButton("🚀 Manual Teleport to Safe Map Center", function()
    if not autoMapCenterTeleport then
        library:Notify("Enable Safe Map Center Teleport first!", 2, "error")
        return
    end
    
    autoTeleportToMapCenter()
    library:Notify("Manual teleport triggered at safe height!", 2, "success")
end)

-- Current Map Display
local mapLabel = mainTab:NewLabel("Current Map: Unknown", "left")

-- Match Status Display
local matchStatusLabel = mainTab:NewLabel("Match Status: Waiting", "left")

-- ADDED: Safe Height Display
local safeHeightLabel = mainTab:NewLabel("Safe Height: Y = 66 (Platform at Y = 64)", "left")

-- ADDED: Replay Wait Time Display
local replayWaitLabel = mainTab:NewLabel("Replay Wait Time: " .. replayWaitTime .. "s", "left")

-- Create Settings Tab
local settingsTab = library:NewTab("Settings")

-- Config Section
settingsTab:NewSection("Configuration")

-- Current Config Display
local currentConfigLabel = settingsTab:NewLabel("Current Config: " .. currentConfigName, "left")

-- Auto Load Status
local autoLoadLabel = settingsTab:NewLabel("Auto Load: " .. (autoLoadConfig and "Enabled" or "Disabled"), "left")

-- Config Name Input
local configNameInput = settingsTab:NewTextbox("Config Name", currentConfigName, "Enter config name", "medium", true, false, function(val)
    if val and val ~= "" then
        currentConfigName = val
    end
end)

-- Save Config Button
settingsTab:NewButton("Save Current Config", function()
    if currentConfigName and currentConfigName ~= "" then
        local success, err = saveConfig(currentConfigName)
        if success then
            library:Notify("Config '" .. currentConfigName .. "' saved successfully!", 3, "success")
        else
            library:Notify("Failed to save config: " .. tostring(err), 3, "error")
        end
    else
        library:Notify("Please enter a config name!", 2, "error")
    end
end)

-- Configs section
settingsTab:NewSection("Configs")

-- Config Dropdown with all available configs
local configList = getConfigList()
local configDropdown = settingsTab:NewSelector("Select Config", currentConfigName, configList, function(selected)
    if selected and selected ~= "" then
        local success, message = loadConfig(selected)
        if success then
            currentConfigName = selected
            library:Notify("Config '" .. selected .. "' loaded!.", 4, "success")
        else
            library:Notify("Failed to load config: " .. message, 3, "error")
        end
    end
end)

-- Store current configs in dropdown for comparison
local currentConfigsInDropdown = {}
for _, config in pairs(configList) do
    currentConfigsInDropdown[config] = true
end

-- Variable to track selected config for deletion
local selectedConfigForDeletion = currentConfigName

-- Update selected config when dropdown changes
configDropdown:SetFunction(function(selected)
    if selected and selected ~= "" then
        selectedConfigForDeletion = selected
        local success, message = loadConfig(selected)
        if success then
            currentConfigName = selected
            library:Notify("Config '" .. selected .. "' loaded! Restart script to see changes.", 4, "success")
        else
            library:Notify("Failed to load config: " .. message, 3, "error")
        end
    end
end)

-- Refresh button that actually updates the dropdown!
settingsTab:NewButton("Refresh Configs", function()
    local newConfigList = getConfigList()
    
    -- Remove configs that no longer exist
    for oldConfig, _ in pairs(currentConfigsInDropdown) do
        local stillExists = false
        for _, newConfig in pairs(newConfigList) do
            if newConfig == oldConfig then
                stillExists = true
                break
            end
        end
        
        if not stillExists then
            configDropdown:RemoveOption(oldConfig)
            currentConfigsInDropdown[oldConfig] = nil
        end
    end
    
    -- Add new configs that don't exist in dropdown
    for _, newConfig in pairs(newConfigList) do
        if not currentConfigsInDropdown[newConfig] then
            configDropdown:AddOption(newConfig)
            currentConfigsInDropdown[newConfig] = true
        end
    end
    
    library:Notify("Dropdown updated! Found " .. (#newConfigList) .. " configs.", 3, "success")
    
    if #newConfigList > 0 then
        local configNames = table.concat(newConfigList, ", ")
        library:Notify("Available configs: " .. configNames, 4, "")
    end
end)

-- Delete Selected Config Button
settingsTab:NewButton("Delete Selected Config", function()
    if not selectedConfigForDeletion or selectedConfigForDeletion == "" then
        library:Notify("No config selected for deletion!", 2, "error")
        return
    end
    
    if selectedConfigForDeletion == "default" then
        library:Notify("Cannot delete default config!", 2, "error")
        return
    end
    
    local success, err = deleteConfig(selectedConfigForDeletion)
    if success then
        -- Remove from dropdown
        configDropdown:RemoveOption(selectedConfigForDeletion)
        currentConfigsInDropdown[selectedConfigForDeletion] = nil
        
        library:Notify("Config '" .. selectedConfigForDeletion .. "' deleted successfully!", 3, "success")
        
        -- Reset to default if deleted config was current
        if selectedConfigForDeletion == currentConfigName then
            currentConfigName = "default"
            selectedConfigForDeletion = "default"
            loadConfig("default")
        end
    else
        library:Notify("Failed to delete config: " .. tostring(err), 3, "error")
    end
end)

-- Auto-Load Management Section
settingsTab:NewSection("Auto-Load Management")

-- Set Auto Load Config Button
settingsTab:NewButton("Set as Auto-Load Config", function()
    if currentConfigName and currentConfigName ~= "" then
        local success, err = setAutoLoadConfig(currentConfigName)
        if success then
            library:Notify("'" .. currentConfigName .. "' set as auto-load config!", 3, "success")
        else
            library:Notify("Failed to set auto-load: " .. tostring(err), 3, "error")
        end
    else
        library:Notify("Please enter a config name!", 2, "error")
    end
end)

-- Disable Auto Load Button
settingsTab:NewButton("Disable Auto-Load", function()
    local success, err = disableAutoLoad()
    if success then
        library:Notify("Auto-load disabled!", 3, "alert")
    else
        library:Notify("Failed to disable auto-load: " .. tostring(err), 3, "error")
    end
end)

-- Show Current Auto Load Config
settingsTab:NewButton("Show Auto-Load Config", function()
    local autoLoadConfigName = getAutoLoadConfig()
    if autoLoadConfigName then
        library:Notify("Current auto-load config: " .. autoLoadConfigName, 3, "")
    else
        library:Notify("No auto-load config set!", 2, "alert")
    end
end)

-- Reset to Default Button
settingsTab:NewButton("Reset to Default Settings", function()
    autoJoin5v5 = false
    autoJoin3v3 = false
    autoJoinBattleRoyale = false
    selectedFriends = {}
    inviteFriend = false
    autoInviteFriends = false
    autoReplay5v5 = false
    autoReplay3v3 = false
    autoReplayBattleRoyale = false
    teleportEnabled3v3 = false
    teleportEnabled5v5 = false
    autoMapCenterTeleport = false
    autoLoadConfig = true
    replayWaitTime = 5
    currentConfigName = "default"
    
    library:Notify("Settings reset to default! Restart script to see changes.", 3, "success")
end)

-- Info Section
settingsTab:NewSection("Information")

-- Version Info
settingsTab:NewLabel("Version: 2.2 (Replay Priority System)", "left")
settingsTab:NewLabel("Created by: Crazy", "left")
settingsTab:NewLabel("Current User: sigmaaboi", "left")
settingsTab:NewLabel("Loaded: 2025-06-26 09:18:23 UTC", "left")

-- NEW: Replay Priority Features Info
settingsTab:NewSection("Replay Priority System")
settingsTab:NewLabel("✅ NEW: Replay Priority over Auto-Join", "left")
settingsTab:NewLabel("✅ NEW: 30s Auto-Join Block on Results", "left")
settingsTab:NewLabel("✅ NEW: Remote Conflict Resolution", "left")
settingsTab:NewLabel("✅ Enhanced Result Detection", "left")

-- ADDED: Safe Height Info
settingsTab:NewSection("Safe Height Information")
settingsTab:NewLabel("✅ Player Teleport Height: Y = 66", "left")
settingsTab:NewLabel("✅ Platform Height: Y = 64", "left")
settingsTab:NewLabel("⚠️ Dead Zone Avoided: Y > 66", "left")
settingsTab:NewLabel("📍 CapeCanaveral: (-1046, 66, 889)", "left")

-- NEW: Protection Features Info
settingsTab:NewSection("Protection Features")
settingsTab:NewLabel("✅ Map Check: Blocks auto-join in maps", "left")
settingsTab:NewLabel("✅ Enhanced Replay: Waits for results", "left")
settingsTab:NewLabel("✅ Result Detection: Won/Lost/#", "left")
settingsTab:NewLabel("✅ Friend Party System", "left")

-- Folder Structure Info
settingsTab:NewLabel("Hub Folder: " .. hubFolder, "left")
settingsTab:NewLabel("Configs Folder: " .. configsFolder, "left")
settingsTab:NewLabel("Auto-Load File: auto_load.txt", "left")

-- Statistics
local configCountLabel = settingsTab:NewLabel("Total Configs: 0", "left")

-- Background Loops
spawn(function()
    while true do
        task.wait(3)
        
        if autoInviteFriends and #selectedFriends > 0 then
            local allInParty = checkFriendsInParty()
            
            if not allInParty and not waitingForFriend then
                waitingForFriend = true
                inviteAllSelectedFriends()
                task.wait(5)
                waitingForFriend = false
            end
        end
    end
end)

-- UPDATED: Auto join loop with MAP CHECKS + REPLAY PRIORITY
spawn(function()
    while true do
        task.wait(2) -- Reduced wait time for better responsiveness
        
        local success, err = pcall(function()
            -- STRICT CHECK: Loading screen first (most important)
            if not isLoadingScreenVisible() then
                -- STRICT CHECK: PlayersLeft GUI (Battle Royale lobby)
                if not isPlayersLeftVisible() then
                    -- STRICT CHECK: Already in active match
                    if not isInActiveMatch() then
                        -- STRICT CHECK: Not already joining
                        if not joining then
                            if autoJoin5v5 then
                                print("[DEBUG] Auto-join 5v5 triggered")
                                joinQueue("StarBall5v5")
                            elseif autoJoin3v3 then
                                print("[DEBUG] Auto-join 3v3 triggered")
                                joinQueue("StarBall3v3")
                            elseif autoJoinBattleRoyale then
                                print("[DEBUG] Auto-join Battle Royale triggered")
                                joinQueue("BattleRoyaleFfa")
                            end
                        else
                            print("[DEBUG] Already joining, skipping auto-join")
                        end
                    else
                        print("[DEBUG] Already in active match, skipping auto-join")
                    end
                else
                    print("[DEBUG] PlayersLeft GUI visible, skipping auto-join")
                end
            else
                print("[DEBUG] Loading screen visible, skipping auto-join")
            end
        end)
        
        if not success then
            print("[DEBUG] Auto-join loop error:", err)
        end
    end
end)

-- UPDATED: Enhanced replay loop (waits for specific results + priority system)
spawn(function()
    local lastReplayTime = 0
    
    while true do
        task.wait(0.5)
        
        if checkForMatchEnd() and hasValidReplayResult() then
            local currentTime = tick()
            
            -- Prevent spam replaying
            if currentTime - lastReplayTime > 10 then
                lastReplayTime = currentTime
                
                local won = checkForWin()
                local lost = checkForLoss()
                local _, placement = checkBattleRoyalePlacement()
                
                if autoReplay5v5 and (won or lost) then
                    print("[DEBUG] Auto-replay 5v5 triggered - Result:", won and "Won" or "Lost")
                    spawn(function() replayQueue("StarBall5v5") end)
                elseif autoReplay3v3 and (won or lost) then
                    print("[DEBUG] Auto-replay 3v3 triggered - Result:", won and "Won" or "Lost")
                    spawn(function() replayQueue("StarBall3v3") end)
                elseif autoReplayBattleRoyale and placement then
                    print("[DEBUG] Auto-replay Battle Royale triggered - Placement:", placement)
                    spawn(function() replayQueue("BattleRoyaleFfa") end)
                end
            end
        end
    end
end)

spawn(function()
    local player = game.Players.LocalPlayer

    while true do
        task.wait(0.2)
        
        local success, err = pcall(function()
            if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
                return
            end
            
            local currentPos = player.Character.HumanoidRootPart.Position
            local distance = (currentPos - lastPosition).Magnitude
            
            if distance > 30 or (teleportEnabled3v3 or teleportEnabled5v5) then
                if teleportEnabled3v3 then
                    doTeleport3v3()
                elseif teleportEnabled5v5 then
                    doTeleport5v5()
                end
                lastPosition = currentPos
            end
        end)
    end
end)

spawn(function()
    while true do
        task.wait(1)
        
        local success, err = pcall(function()
            if teleportEnabled3v3 then
                doTeleport3v3()
            elseif teleportEnabled5v5 then
                doTeleport5v5()
            end
        end)
    end
end)

-- FIXED: Auto Map Center Teleport Loop with SAFE HEIGHT
spawn(function()
    while true do
        task.wait(3) -- Check every 3 seconds
        
        if autoMapCenterTeleport then
            print("[DEBUG] Auto Map Center Loop - Checking...")
            
            local currentMap = getCurrentMap()
            if currentMap then
                print("[DEBUG] Current map detected:", currentMap)
                
                -- Check if map changed or enough time passed
                if currentMap ~= lastDetectedMap or tick() - lastMapCenterTime > 15 then
                    print("[DEBUG] Triggering auto teleport to SAFE HEIGHT - Map:", currentMap, "Last:", lastDetectedMap)
                    autoTeleportToMapCenter()
                end
            else
                print("[DEBUG] No map detected")
            end
        end
    end
end)

-- UPDATED: UI Update Loop with ENHANCED status including REPLAY PRIORITY
spawn(function()
    while true do
        task.wait(1)
        
        -- Update status labels
        local status = "Ready"
        local matchStatus = "Waiting"
        local loadingStatus = "Not Visible"
        local playersLeftStatus = "Not Visible"
        local enemyLeftStatus = "Not Visible"
        local replayPriorityStatus = "None"
        
        -- NEW: Check replay priority status
        if isReplayBlocking() then
            replayPriorityStatus = "🔄 Blocking Auto-Join (" .. math.ceil(30 - (tick() - lastResultTime)) .. "s)"
            status = "Replay Priority Active"
        end
        
        -- NEW: Check map status
        local inMap, mapName = isInAnyMap()
        
        if inMap then
            status = "In Map (" .. mapName .. ") - Auto-Join Blocked"
                        mapStatusLabel:SetText("Map Status: In " .. mapName .. " ❌")
        else
            mapStatusLabel:SetText("Map Status: None ✅")
            if isLoadingScreenVisible() then
                loadingStatus = "Visible (Blocking Auto-Join)"
                status = "Loading Screen Active"
            elseif isPlayersLeftVisible() then
                playersLeftStatus = "Visible (Blocking Auto-Join)"
                status = "In Battle Royale Lobby"
            elseif isEnemyLeftVisible() then
                enemyLeftStatus = "Visible (Blocking Replay)"
                status = "Enemy Left - Replay Blocked"
            elseif isInActiveMatch() then
                status = "In Match"
                matchStatus = "Active Match"
            elseif joining then
                status = "Joining Queue..."
                matchStatus = "Joining..."
            elseif replaying then
                status = "Replaying..."
                matchStatus = "Replaying..."
            elseif teleportEnabled3v3 or teleportEnabled5v5 then
                status = "Auto Teleport Active"
            elseif autoMapCenterTeleport then
                status = "✅ Safe Map Center Active (Y: 66)"
            end
        end
        
        statusLabel:SetText("Status: " .. status)
        loadingStatusLabel:SetText("Loading Screen: " .. loadingStatus)
        playersLeftStatusLabel:SetText("PlayersLeft GUI: " .. playersLeftStatus)
        enemyLeftStatusLabel:SetText("Enemy Left GUI: " .. enemyLeftStatus)
        replayPriorityLabel:SetText("Replay Priority: " .. replayPriorityStatus)
        teleportStatusLabel:SetText("Teleport Count: " .. teleportCount)
        matchStatusLabel:SetText("Match Status: " .. matchStatus)
        currentConfigLabel:SetText("Current Config: " .. currentConfigName)
        autoLoadLabel:SetText("Auto Load: " .. (autoLoadConfig and "Enabled" or "Disabled"))
        replayWaitLabel:SetText("Replay Wait Time: " .. replayWaitTime .. "s")
        
        -- Update map with safety info
        local currentMap = getCurrentMap()
        local mapText = "Current Map: " .. (currentMap or "Unknown")
        if autoMapCenterTeleport and currentMap then
            mapText = mapText .. " ✅"
        end
        mapLabel:SetText(mapText)
        
        -- Update selected friends display
        if #selectedFriends > 0 then
            local friendsList = table.concat(selectedFriends, ", ")
            selectedFriendsLabel:SetText("Selected Friends: " .. friendsList)
        else
            selectedFriendsLabel:SetText("Selected Friends: None")
        end
        
        -- Update config count
        local configs = getConfigList()
        configCountLabel:SetText("Total Configs: " .. #configs)
    end
end)

-- Character respawn detection with safe map center teleport
local player = game.Players.LocalPlayer
player.CharacterAdded:Connect(function(character)
    local success, err = pcall(function()
        character:WaitForChild("HumanoidRootPart", 10)
        
        if teleportEnabled3v3 then
            task.wait(0.5)
            doTeleport3v3()
        elseif teleportEnabled5v5 then
            task.wait(0.5)
            doTeleport5v5()
        elseif autoMapCenterTeleport then
            task.wait(2) -- Longer wait for character to fully load
            print("[DEBUG] Character respawned - triggering SAFE map center teleport")
            autoTeleportToMapCenter()
        end
    end)
end)

-- Clean up on script end
game:GetService("Players").PlayerRemoving:Connect(function(player)
    if player == game.Players.LocalPlayer then
        removePlatforms()
    end
end)

-- Success notification
local Clock = os.clock()
local Decimals = 2
local Time = (string.format("%."..tostring(Decimals).."f", os.clock() - Clock))
library:Notify("✅ Crazy Hub Replay Priority System loaded in " .. Time .. "s!", 5, "success")

-- Show config load status
if currentConfigName ~= "default" then
    library:Notify("Auto-loaded config: " .. currentConfigName, 3, "success")
end

-- Welcome notification with current date/time
library:Notify("Welcome back, sigmaaboi! Loaded on 2025-06-26 09:23:27 UTC", 4, "success")

-- Safe height notification
library:Notify("✅ SAFE HEIGHT: Player at Y=66, Platform at Y=64 (Dead zone avoided!)", 5, "success")

-- NEW: Replay priority system notification
library:Notify("🔄 NEW: Replay Priority System - Blocks auto-join for 30s after results!", 5, "success")

-- Enhanced features notification
library:Notify("🔧 FIXED: Remote Conflict Resolution & Map Detection!", 5, "success")

-- Create default config if it doesn't exist
spawn(function()
    task.wait(2)
    ensureFolders()
    if not isfile(getConfigPath("default")) then
        saveConfig("default")
        library:Notify("Default config created!", 3, "success")
    end
end)
