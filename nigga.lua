----- Crazy hub
-- Auto join variables
local autoJoin5v5 = false
local autoJoin3v3 = false
local joining = false

-- Friend party variables
local selectedFriends = {}
local inviteFriend = false
local autoInviteFriends = false
local waitingForFriend = false
local friendsInParty = {}

-- Auto replay variables (simplified)
local autoReplay5v5 = false
local autoReplay3v3 = false
local replaying = false
local replayWaitTime = 5

-- Teleport toggles for each mode
local teleportEnabled3v3 = false
local teleportEnabled5v5 = false
local teleporting = false
local lastPosition = Vector3.new(0, 0, 0)

-- Debug variables
local teleportCount = 0
local lastTeleportTime = 0

-- UPDATED: Combat system variables
local autoAttackEnabled = false
local aimLockEnabled = false
local enemyVisualsEnabled = false
local wallCheckEnabled = true
local attackRange = 50
local aimSmoothness = 0.3
local autoFireRate = 0.1
local lastAttackTime = 0
local currentTarget = nil
local enemyOutlines = {}
local activateSkillRemotePath = "RemoteService/Remotes/ActivateSkill/E"
local ActivateSkillRemote = nil
local remotesReady = false

-- Grass detection system
local grassInstances = {}

-- Config variables (Updated structure)
local autoLoadConfig = true
local currentConfigName = "default"
local hubFolder = "Crazy-Hub"
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

-- IMPROVED: Grass detection function that gets ALL grass objects
local function updateGrassInstances()
    grassInstances = {}
    
    -- Check for grass in all known maps
    for _, mapName in pairs(mapNames) do
        local mapFolder = workspace:FindFirstChild(mapName)
        if mapFolder then
            -- Most maps have grass under Dynamic folder
            local dynamicFolder = mapFolder:FindFirstChild("Dynamic")
            if dynamicFolder then
                -- Look for grass folder
                local grassFolder = dynamicFolder:FindFirstChild("Grass")
                if grassFolder then
                    -- Add all grass children to exclusion list
                    for _, grass in pairs(grassFolder:GetChildren()) do
                        table.insert(grassInstances, grass)
                    end
                    print("Found " .. #grassFolder:GetChildren() .. " grass instances in " .. mapName)
                end
                
                -- Some maps might have it under a different name
                for _, folder in pairs(dynamicFolder:GetChildren()) do
                    if string.find(string.lower(folder.Name), "grass") or 
                       string.find(string.lower(folder.Name), "plant") or 
                       string.find(string.lower(folder.Name), "bush") or
                       string.find(string.lower(folder.Name), "foliage") then
                        for _, item in pairs(folder:GetChildren()) do
                            table.insert(grassInstances, item)
                        end
                        print("Found " .. #folder:GetChildren() .. " foliage instances in " .. folder.Name)
                    end
                end
            end
            
            -- Some maps might have grass at root level
            for _, folder in pairs(mapFolder:GetChildren()) do
                if string.find(string.lower(folder.Name), "grass") or 
                   string.find(string.lower(folder.Name), "plant") or 
                   string.find(string.lower(folder.Name), "bush") or
                   string.find(string.lower(folder.Name), "foliage") then
                    for _, item in pairs(folder:GetChildren()) do
                        table.insert(grassInstances, item)
                    end
                    print("Found " .. #folder:GetChildren() .. " foliage instances in root of " .. mapName)
                end
            end
        end
    end
    
    print("Total foliage instances found for grass penetration: " .. #grassInstances)
end

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

-- NEW: Check if "Play Again" button is visible
local function isPlayAgainButtonVisible()
    local success, result = pcall(function()
        local button = game:GetService("Players").LocalPlayer.PlayerGui.App.Main.Gamemode.Results.ButtonHolder.PlayAgain.Button
        return button and button.Visible and button.Parent.Visible
    end)
    return success and result
end

-- NEW: Combat System Functions
-- IMPROVED: Find remote with exact path
local function tryGetRemotes()
    local remote = game:GetService("ReplicatedStorage"):FindFirstChild(activateSkillRemotePath)
    if remote then
        return remote
    end
    
    -- Try using WaitForChild with a timeout
    local success, result = pcall(function()
        return game:GetService("ReplicatedStorage"):WaitForChild("RemoteService/Remotes"):WaitForChild("ActivateSkill"):WaitForChild("E", 1)
    end)
    
    if success and result then
        return result
    end
    
    return nil
end

-- FIXED: Wall check with TRUE grass penetration - excludes ALL grass from raycast
local function isWallBetweenTarget(target)
    if not wallCheckEnabled then return false end
    if not target or not target.character then return false end
    
    local localPlayer = game:GetService("Players").LocalPlayer
    if not localPlayer.Character or not localPlayer.Character:FindFirstChild("HumanoidRootPart") then return false end
    
    local playerHRP = localPlayer.Character.HumanoidRootPart
    local targetHRP = target.character:FindFirstChild("HumanoidRootPart")
    if not targetHRP then return false end
    
    local direction = (targetHRP.Position - playerHRP.Position)
    local raycastParams = RaycastParams.new()
    
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    local excludeList = {localPlayer.Character, target.character}
    
    -- Add all players to exclude list
    for _, plr in pairs(game:GetService("Players"):GetPlayers()) do
        if plr.Character then
            table.insert(excludeList, plr.Character)
        end
    end
    
    -- CRITICAL FIX: Add ALL grass instances to exclude list so raycast ignores them completely
    for _, grass in pairs(grassInstances) do
        table.insert(excludeList, grass)
    end
    
    raycastParams.FilterDescendantsInstances = excludeList
    
    local raycastResult = workspace:Raycast(playerHRP.Position, direction, raycastParams)
    
    if raycastResult then
        local hitObject = raycastResult.Instance
        print("Wall detected (after grass exclusion):", hitObject:GetFullName(), "- blocking shot")
        return true -- Hit a real wall/obstacle (grass was excluded from raycast)
    else
        print("Clear shot - no walls detected (grass ignored)")
        return false -- Clear shot (grass was ignored)
    end
end

-- Enemy functions
local function getEnemyPlayers()
    local enemies = {}
    local localPlayer = game:GetService("Players").LocalPlayer
    local charactersFolder = workspace:FindFirstChild("_Characters")
    if not charactersFolder then return enemies end
    
    for _, character in pairs(charactersFolder:GetChildren()) do
        if character ~= localPlayer.Character and 
           character:FindFirstChild("HumanoidRootPart") and 
           character:FindFirstChild("Humanoid") and 
           character.Humanoid.Health > 0 then
            local player = game:GetService("Players"):FindFirstChild(character.Name)
            table.insert(enemies, {player = player, character = character, isNPC = player == nil})
        end
    end
    return enemies
end

-- Get closest enemy without wall check interference
local function getClosestEnemy()
    local localPlayer = game:GetService("Players").LocalPlayer
    if not localPlayer.Character or not localPlayer.Character:FindFirstChild("HumanoidRootPart") then return nil end
    
    local playerPosition = localPlayer.Character.HumanoidRootPart.Position
    local closestEnemy, closestDistance = nil, attackRange
    
    for _, enemyData in pairs(getEnemyPlayers()) do
        if enemyData.character:FindFirstChild("HumanoidRootPart") then
            local distance = (enemyData.character.HumanoidRootPart.Position - playerPosition).Magnitude
            if distance < closestDistance then
                closestDistance = distance
                closestEnemy = enemyData
            end
        end
    end
    
    return closestEnemy, closestDistance
end

-- Visual functions
local function createEnemyOutline(character)
    if enemyOutlines[character] then return end
    
    local success, highlight = pcall(function()
        local h = Instance.new("Highlight")
        h.Name = "EnemyOutline"
        h.FillColor = Color3.fromRGB(255, 0, 0)
        h.OutlineColor = Color3.fromRGB(255, 255, 255)
        h.FillTransparency = 0.7
        h.OutlineTransparency = 0
        h.Adornee = character
        h.Parent = character
        return h
    end)
    
    if success then enemyOutlines[character] = highlight end
end

local function removeEnemyOutline(character)
    if enemyOutlines[character] then
        enemyOutlines[character]:Destroy()
        enemyOutlines[character] = nil
    end
end

local function updateEnemyVisuals()
    if not enemyVisualsEnabled then
        for character, _ in pairs(enemyOutlines) do removeEnemyOutline(character) end
        return
    end
    
    local localPlayer = game:GetService("Players").LocalPlayer
    if not localPlayer.Character or not localPlayer.Character:FindFirstChild("HumanoidRootPart") then return end
    
    local playerPosition = localPlayer.Character.HumanoidRootPart.Position
    local enemies = getEnemyPlayers()
    local currentEnemies = {}
    
    for _, enemyData in pairs(enemies) do
        local character = enemyData.character
        if character:FindFirstChild("HumanoidRootPart") then
            local distance = (character.HumanoidRootPart.Position - playerPosition).Magnitude
            
            if distance <= attackRange * 1.5 then
                currentEnemies[character] = true
                
                if not enemyOutlines[character] then
                    createEnemyOutline(character)
                end
                
                -- Update color based on selection and wall
                if enemyOutlines[character] then
                    if currentTarget and currentTarget.character == character then
                        if wallCheckEnabled and isWallBetweenTarget(currentTarget) then
                            -- Current target behind wall - yellow
                            enemyOutlines[character].FillColor = Color3.fromRGB(255, 255, 0)
                            enemyOutlines[character].OutlineColor = Color3.fromRGB(255, 0, 0)
                        else
                            -- Current target - orange (can shoot through grass)
                            enemyOutlines[character].FillColor = Color3.fromRGB(255, 165, 0)
                            enemyOutlines[character].OutlineColor = Color3.fromRGB(255, 255, 0)
                        end
                        enemyOutlines[character].FillTransparency = 0.5
                    else
                        -- Normal enemy - red
                        enemyOutlines[character].FillColor = Color3.fromRGB(255, 0, 0)
                        enemyOutlines[character].FillTransparency = 0.7
                        
                        -- Check if this enemy is behind a wall (grass ignored)
                        if wallCheckEnabled then
                            local tempTarget = {character = character}
                            if isWallBetweenTarget(tempTarget) then
                                enemyOutlines[character].FillColor = Color3.fromRGB(150, 150, 150)
                                enemyOutlines[character].FillTransparency = 0.8
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Remove outlines for enemies no longer in range
    for character, _ in pairs(enemyOutlines) do
        if not currentEnemies[character] then
            removeEnemyOutline(character)
        end
    end
end

-- Aiming functions
local function getCurrentAimDirection()
    local localPlayer = game:GetService("Players").LocalPlayer
    if not localPlayer.Character or not localPlayer.Character:FindFirstChild("HumanoidRootPart") then
        return Vector3.new(0, 0, -1)
    end
    
    local hrp = localPlayer.Character.HumanoidRootPart
    local lookDirection = hrp.CFrame.LookVector
    
    return Vector3.new(lookDirection.X, lookDirection.Y, lookDirection.Z)
end

local function getDirectionToTarget(target)
    if not target or not target.character or not target.character:FindFirstChild("HumanoidRootPart") then
        return getCurrentAimDirection()
    end
    
    local localPlayer = game:GetService("Players").LocalPlayer
    if not localPlayer.Character or not localPlayer.Character:FindFirstChild("HumanoidRootPart") then
        return Vector3.new(0, 0, -1)
    end
    
    local playerHRP = localPlayer.Character.HumanoidRootPart
    local targetHRP = target.character.HumanoidRootPart
    
    local direction = (targetHRP.Position - playerHRP.Position).Unit
    
    return Vector3.new(direction.X, direction.Y, direction.Z)
end

-- Aim lock that works regardless of wall check
local function aimAtTarget(target)
    if not target or not target.character or not target.character:FindFirstChild("HumanoidRootPart") then
        return false
    end
    
    local localPlayer = game:GetService("Players").LocalPlayer
    if not localPlayer.Character or not localPlayer.Character:FindFirstChild("HumanoidRootPart") then
        return false
    end
    
    local success = pcall(function()
        local playerHRP = localPlayer.Character.HumanoidRootPart
        local targetHRP = target.character.HumanoidRootPart
        
        local direction = (targetHRP.Position - playerHRP.Position).Unit
        local currentLookDirection = playerHRP.CFrame.LookVector
        local newDirection = currentLookDirection:Lerp(direction, aimSmoothness)
        
        local newCFrame = CFrame.lookAt(playerHRP.Position, playerHRP.Position + newDirection)
        playerHRP.CFrame = newCFrame
    end)
    
    return success
end

-- Attack function using the exact format from your example
local function performAttack(targetDirection)
    if not remotesReady then 
        return false 
    end
    
    local currentTime = tick()
    if currentTime - lastAttackTime < autoFireRate then
        return false
    end
    
    -- FIXED: Wall check (if enabled) - now properly ignores grass
    if wallCheckEnabled and currentTarget then
        local hasWall = isWallBetweenTarget(currentTarget)
        if hasWall then
            print("Attack blocked: Real wall detected between player and target (grass ignored)")
            return false
        else
            print("Attack allowed: Clear shot or only grass between player and target")
        end
    end
    
    -- Use provided direction or current aim
    local aimDirection = targetDirection or getCurrentAimDirection()
    
    local success = pcall(function()
        -- Exactly match the format from your example
        local args = {
            "MainAttack",
            vector.create(aimDirection.X, aimDirection.Y, aimDirection.Z)
        }
        
        -- Use the direct remote if we have it
        if ActivateSkillRemote then
            ActivateSkillRemote:FireServer(unpack(args))
        else 
            -- Otherwise try with the WaitForChild path as a fallback
            game:GetService("ReplicatedStorage"):WaitForChild("RemoteService/Remotes"):WaitForChild("ActivateSkill"):WaitForChild("E"):FireServer(unpack(args))
        end
        
        print("Attack fired successfully - shooting through grass or clear line of sight")
    end)
    
    if success then
        lastAttackTime = currentTime
    end
    
    return success
end

-- Manual attack with the correct vector format
local function performManualAttack()
    if not remotesReady then return false end
    
    local aimDirection = getCurrentAimDirection()
    
    local success = pcall(function()
        local args = {
            "MainAttack",
            vector.create(aimDirection.X, aimDirection.Y, aimDirection.Z)
        }
        
        if ActivateSkillRemote then
            ActivateSkillRemote:FireServer(unpack(args))
        else
            game:GetService("ReplicatedStorage"):WaitForChild("RemoteService/Remotes"):WaitForChild("ActivateSkill"):WaitForChild("E"):FireServer(unpack(args))
        end
    end)
    
    return success
end

-- Config System Functions
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
        -- Original settings
        autoJoin5v5 = autoJoin5v5,
        autoJoin3v3 = autoJoin3v3,
        selectedFriends = selectedFriends,
        inviteFriend = inviteFriend,
        autoInviteFriends = autoInviteFriends,
        autoReplay5v5 = autoReplay5v5,
        autoReplay3v3 = autoReplay3v3,
        teleportEnabled3v3 = teleportEnabled3v3,
        teleportEnabled5v5 = teleportEnabled5v5,
        replayWaitTime = replayWaitTime,
        
        -- Combat settings
        autoAttackEnabled = autoAttackEnabled,
        aimLockEnabled = aimLockEnabled,
        enemyVisualsEnabled = enemyVisualsEnabled, 
        wallCheckEnabled = wallCheckEnabled,
        attackRange = attackRange,
        aimSmoothness = aimSmoothness,
        autoFireRate = autoFireRate,
        
        -- General config
        autoLoadConfig = autoLoadConfig,
        currentConfigName = configName,
        savedBy = game.Players.LocalPlayer.Name,
        savedAt = os.time(),
        version = "2.3"
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
    
    -- Apply config settings - original settings
    autoJoin5v5 = config.autoJoin5v5 or false
    autoJoin3v3 = config.autoJoin3v3 or false
    selectedFriends = config.selectedFriends or {}
    inviteFriend = config.inviteFriend or false
    autoInviteFriends = config.autoInviteFriends or false
    autoReplay5v5 = config.autoReplay5v5 or false
    autoReplay3v3 = config.autoReplay3v3 or false
    teleportEnabled3v3 = config.teleportEnabled3v3 or false
    teleportEnabled5v5 = config.teleportEnabled5v5 or false
    replayWaitTime = config.replayWaitTime or 5
    
    -- Combat settings
    autoAttackEnabled = config.autoAttackEnabled or false
    aimLockEnabled = config.aimLockEnabled or false
    enemyVisualsEnabled = config.enemyVisualsEnabled or false
    wallCheckEnabled = config.wallCheckEnabled ~= nil and config.wallCheckEnabled or true
    attackRange = config.attackRange or 50
    aimSmoothness = config.aimSmoothness or 0.3
    autoFireRate = config.autoFireRate or 0.1
    
    -- General config
    autoLoadConfig = config.autoLoadConfig ~= nil and config.autoLoadConfig or true
    currentConfigName = configName
    
    -- Update auto-load file if auto-load is enabled
    if autoLoadConfig then
        saveAutoLoadConfig(configName)
    end
    
    return true, "Config loaded successfully"
end

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

-- UPDATED: Auto join functions with MAP CHECKS ONLY
local function joinQueue(gameMode)
    if joining then 
        return 
    end
    
    -- NEW: Check if player is in any map (block auto-join)
    local inMap, mapName = isInAnyMap()
    if inMap then
        return
    end
    
    -- STRICT CHECK: Loading screen check
    if isLoadingScreenVisible() then
        return
    end
    
    -- STRICT CHECK: Active match check
    if isInActiveMatch() then
        return
    end
    
    -- Friend check
    if inviteFriend and #selectedFriends > 0 then
        if not checkFriendsInParty() then
            return
        end
    end
    
    joining = true

    local success, err = pcall(function()
        game:GetService("ReplicatedStorage")["RemoteService/Remotes"].JoinQueue.E:FireServer(gameMode)
    end)

    task.wait(1)
    joining = false
end

-- NEW: Simple button-based replay system - FORCES through all checks
local function forceReplay(gameMode)
    if replaying then 
        return 
    end
    
    replaying = true
    
    -- Wait before proceeding
    task.wait(replayWaitTime)

    local success, err = pcall(function()
        game:GetService("ReplicatedStorage")["RemoteService/Remotes"].JoinQueue.E:FireServer(gameMode)
    end)

    task.wait(0.5)
    replaying = false
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
    version = "2.3",
    title = "Crazy Hub",
    company = "Crazy Hub",
    keybind = Enum.KeyCode.RightShift,
    BlurEffect = false,
})

-- Watermarks
library:Watermark("Crazy Hub | Jump Stars")

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
library:AddIntroductionMessage("Crazy Hub on Top")
wait(0.5)
library:AddIntroductionMessage("Enjoy the script!")
wait(0.5)
library:EndIntroduction()

-- Create Main Tab
local mainTab = library:NewTab("Main Features")

-- Auto Features Section
mainTab:NewSection("Auto Join/Replay")

-- Auto Join Toggles (start with loaded values)
local autoJoinToggle5v5 = mainTab:NewToggle("Auto Join 5v5", autoJoin5v5, function(state)
    autoJoin5v5 = state
    if state then 
        autoJoin3v3 = false
        library:Notify("Auto Join 5v5 Enabled!", 3, "success")
    end
end)

local autoJoinToggle3v3 = mainTab:NewToggle("Auto Join 3v3", autoJoin3v3, function(state)
    autoJoin3v3 = state
    if state then 
        autoJoin5v5 = false
        library:Notify("Auto Join 3v3 Enabled!", 3, "success")
    end
end)

-- Auto Replay Toggles (start with loaded values)
local autoReplayToggle5v5 = mainTab:NewToggle("Auto Replay 5v5", autoReplay5v5, function(state)
    autoReplay5v5 = state
    if state then 
        autoReplay3v3 = false
        library:Notify("Auto Replay 5v5 Enabled!", 3, "success")
    end
end)

local autoReplayToggle3v3 = mainTab:NewToggle("Auto Replay 3v3", autoReplay3v3, function(state)
    autoReplay3v3 = state
    if state then 
        autoReplay5v5 = false
        library:Notify("Auto Replay 3v3 Enabled!", 3, "success")
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

-- Teleport Section
mainTab:NewSection("Auto Win")

-- Teleport Status
local teleportStatusLabel = mainTab:NewLabel("Teleport Count: 0", "left")

local teleportToggle3v3 = mainTab:NewToggle("Auto Win (3v3)", teleportEnabled3v3, function(state)
    teleportEnabled3v3 = state
    if state then 
        teleportEnabled5v5 = false
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
        teleportCount = 0
        lastTeleportTime = 0
        library:Notify("5v5 Auto Win Enabled!", 3, "alert")
        
        if game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            lastPosition = game.Players.LocalPlayer.Character.HumanoidRootPart.Position
        end
        doTeleport5v5()
    end
end)

-- Current Map Display
local mapLabel = mainTab:NewLabel("Current Map: Unknown", "left")

-- ADDED: Replay Wait Time Display
local replayWaitLabel = mainTab:NewLabel("Replay Wait Time: " .. replayWaitTime .. "s", "left")

-- NEW: Create separate Party Tab
local partyTab = library:NewTab("Party")

-- Friend Party Features Section
partyTab:NewSection("Party Management")

-- Friend Party Toggle (start with loaded value)
local friendPartyToggle = partyTab:NewToggle("Enable Party Mode", inviteFriend, function(state)
    inviteFriend = state
    local message = state and "Friend Party Mode Enabled!" or "Friend Party Mode Disabled!"
    local notifType = state and "success" or "alert"
    library:Notify(message, 3, notifType)
end)

local autoInviteToggle = partyTab:NewToggle("Auto Invite Selected Friends", autoInviteFriends, function(state)
    autoInviteFriends = state
    local message = state and "Auto Invite Enabled!" or "Auto Invite Disabled!"
    local notifType = state and "success" or "alert"
    library:Notify(message, 3, notifType)
end)

-- Friend Selection Section
partyTab:NewSection("Friend Selection")

-- Friend Selection
local friendDropdown = partyTab:NewSelector("Select Friends", "", getAllPlayers(), function(selected)
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

-- Selected Friends Display
local selectedFriendsLabel = partyTab:NewLabel("Selected Friends: None", "left")

-- Friend Management Section
partyTab:NewSection("Party Actions")

-- Friend Management Buttons
partyTab:NewButton("Invite All Selected Friends", function()
    if #selectedFriends > 0 then
        inviteAllSelectedFriends()
        library:Notify("Invited " .. #selectedFriends .. " friends to party!", 3, "success")
    else
        library:Notify("No friends selected!", 2, "error")
    end
end)

partyTab:NewButton("Clear Selected Friends", function()
    selectedFriends = {}
    library:Notify("Cleared friend list!", 2, "alert")
end)

partyTab:NewButton("Refresh Player List", function()
    local players = getAllPlayers()
    library:Notify("Player list refreshed! Found " .. #players .. " players.", 3, "success")
end)

-- Party Status Section
partyTab:NewSection("Party Status")

-- Party status labels will be updated in the UI update loop
local partyStatusLabel = partyTab:NewLabel("Party Mode: Disabled", "left")
local friendsInPartyLabel = partyTab:NewLabel("Friends in Party: 0", "left")

-- NEW: Add the Combat tab with TRUE grass penetration
local combatTab = library:NewTab("Legit")

-- Combat Settings Section
combatTab:NewSection("Player Aid System")

-- Combat toggles
local autoAttackToggle = combatTab:NewToggle("Auto Attack", autoAttackEnabled, function(state)
    autoAttackEnabled = state
    if state then
        library:Notify("Auto Attack Enabled! " .. (wallCheckEnabled and "(With TRUE grass penetration)" or "(No wall check)"), 3, "success")
    else
        library:Notify("Auto Attack Disabled!", 3, "alert")
    end
end)

local aimLockToggle = combatTab:NewToggle("Aim Assist", aimLockEnabled, function(state)
    aimLockEnabled = state
    if state then
        library:Notify("Aim Assist Enabled!", 3, "success")
    else
        library:Notify("Aim Assist Disabled!", 3, "alert")
        currentTarget = nil
    end
end)

local wallCheckToggle = combatTab:NewToggle("Wall Check", wallCheckEnabled, function(state)
    wallCheckEnabled = state
    if state then
        library:Notify("Wall Check Enabled! TRUE grass penetration - raycast ignores ALL grass!", 3, "success")
    else
        library:Notify("Wall Check Disabled! Will attack through everything.", 3, "alert")
    end
end)

-- Combat sliders
combatTab:NewSlider("Attack Range", "", false, "", {min = 10, max = 100, default = attackRange}, function(val) attackRange = val end)
combatTab:NewSlider("Aim Smoothness", "", false, "", {min = 1, max = 10, default = math.floor(aimSmoothness * 10)}, function(val) aimSmoothness = val / 10 end)
combatTab:NewSlider("Fire Rate Delay", "ms", false, "", {min = 50, max = 500, default = math.floor(autoFireRate * 1000)}, function(val) autoFireRate = val / 1000 end)

-- IMPROVED: Grass detection controls with better explanation
combatTab:NewSection("Grass/Foliage Detection")

combatTab:NewButton("Update Grass Detection", function()
    updateGrassInstances()
    library:Notify("Found " .. #grassInstances .. " grass objects! Wall check will completely ignore these.", 3, "success")
end)

combatTab:NewToggle("Show Detected Objects", false, function(state)
    if state then
        for _, grass in pairs(grassInstances) do
            pcall(function()
                local h = Instance.new("Highlight")
                h.Name = "GrassHighlight"
                h.FillColor = Color3.fromRGB(0, 255, 0)
                h.OutlineColor = Color3.fromRGB(0, 128, 0)
                h.FillTransparency = 0.8
                h.OutlineTransparency = 0.5
                h.Adornee = grass
                h.Parent = grass
            end)
        end
        library:Notify("Showing " .. #grassInstances .. " grass objects that will be ignored", 3, "success")
    else
        for _, grass in pairs(grassInstances) do
            pcall(function()
                if grass:FindFirstChild("GrassHighlight") then
                    grass.GrassHighlight:Destroy()
                end
            end)
        end
        library:Notify("Hiding grass highlights", 3, "alert")
    end
end)

-- Visual features
combatTab:NewSection("Visual Options")

combatTab:NewToggle("Player Highlight", enemyVisualsEnabled, function(state)
    enemyVisualsEnabled = state
    if state then
        library:Notify("Player Highlight Enabled!", 3, "success")
    else
        library:Notify("Player Highlight Disabled!", 3, "alert")
        for character, outline in pairs(enemyOutlines) do removeEnemyOutline(character) end
    end
end)

-- Create Settings Tab (same as before)
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
            library:Notify("Config '" .. selected .. "' loaded!.", 4, "success")
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
    selectedFriends = {}
    inviteFriend = false
    autoInviteFriends = false
    autoReplay5v5 = false
    autoReplay3v3 = false
    teleportEnabled3v3 = false
    teleportEnabled5v5 = false
    autoLoadConfig = true
    replayWaitTime = 5
    currentConfigName = "default"
    
    -- Combat settings
    autoAttackEnabled = false
    aimLockEnabled = false
    enemyVisualsEnabled = false
    wallCheckEnabled = true
    attackRange = 50
    aimSmoothness = 0.3
    autoFireRate = 0.1
    
    library:Notify("Settings reset to default! Restart script to see changes.", 3, "success")
end)

-- Info Section
settingsTab:NewSection("Information")

-- Version Info
settingsTab:NewLabel("Version: 2.3", "left")
settingsTab:NewLabel("Created by: Crazy", "left")
settingsTab:NewLabel("Discord user: CraZ(z)Zy (craz_zy)", "left")

-- NEW: Discord Server Section
settingsTab:NewSection("Discord Server")
settingsTab:NewButton("Copy Discord Server Link", function()
    local discordLink = "https://discord.gg/8KWX2N8m"
    setclipboard(discordLink)
    library:Notify("Discord server link copied to clipboard! L-Hub: " .. discordLink, 5, "success")
end)
settingsTab:NewLabel("Join L-Hub for updates and support!", "left")

-- Folder Structure Info
settingsTab:NewSection("Location's for files")
settingsTab:NewLabel("Hub Folder: " .. hubFolder, "left")
settingsTab:NewLabel("Configs Folder: " .. configsFolder, "left")
settingsTab:NewLabel("Auto-Load File: auto_load.txt", "left")

-- Statistics
local configCountLabel = settingsTab:NewLabel("Total Configs: 0", "left")

-- Run initial grass detection
spawn(function()
    updateGrassInstances()
end)

-- CRITICAL FIX: Much more aggressive remote check for combat system
spawn(function()
    while true do
        ActivateSkillRemote = tryGetRemotes()
        if ActivateSkillRemote then
            remotesReady = true
            library:Notify("Player Assist systems ready! TRUE grass penetration active.", 3, "success")
            break
        else
            remotesReady = false
        end
        task.wait(1)
    end
end)

-- Background Loops
-- Friend auto-invite loop
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

-- Auto join loop
spawn(function()
    while true do
        task.wait(2)
        
        local success, err = pcall(function()
            if not isLoadingScreenVisible() then
                if not isInActiveMatch() then
                    if not joining then
                        if autoJoin5v5 then
                            joinQueue("StarBall5v5")
                        elseif autoJoin3v3 then
                            joinQueue("StarBall3v3")
                        end
                    end
                end
            end
        end)
    end
end)

-- Auto replay loop
spawn(function()
    local lastForceReplayTime = 0
    
    while true do
        task.wait(0.5)
        
        if isPlayAgainButtonVisible() then
            local currentTime = tick()
            
            -- Prevent spam force replaying
            if currentTime - lastForceReplayTime > 5 then
                lastForceReplayTime = currentTime
                
                if autoReplay5v5 then
                    spawn(function() forceReplay("StarBall5v5") end)
                    library:Notify("REPLAY 5v5", 3, "success")
                elseif autoReplay3v3 then
                    spawn(function() forceReplay("StarBall3v3") end)
                    library:Notify("REPLAY 3v3 !", 3, "success")
                end
            end
        end
    end
end)

-- Player movement monitoring for teleport
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

-- Teleport loop
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

-- Combat system auto-attack loop
spawn(function()
    while true do
        task.wait(0.05)
        
        -- Target acquisition
        local target, distance = getClosestEnemy()
        
        if target then
            currentTarget = target
            
            -- Aim lock
            if aimLockEnabled then
                aimAtTarget(target)
            end
            
            -- Auto attack
            if autoAttackEnabled and distance <= attackRange then
                -- Get attack direction
                local attackDirection = getDirectionToTarget(target)
                
                -- Directly attack (wall check with grass penetration is handled inside)
                performAttack(attackDirection)
            end
        else
            currentTarget = nil
        end
    end
end)

-- Enemy visuals update loop
spawn(function()
    while true do
        task.wait(0.2)
        if enemyVisualsEnabled then updateEnemyVisuals() end
    end
end)

-- NEW: Map change detection to update grass instances
workspace.ChildAdded:Connect(function(child)
    if table.find(mapNames, child.Name) then
        task.wait(2) -- Wait for the map to fully load
        updateGrassInstances()
        print("Map changed to " .. child.Name .. ", updated grass instances")
        if library then
            library:Notify("Map changed! Updated grass detection for " .. child.Name, 3, "success")
        end
    end
end)

-- UI Update Loop
spawn(function()
    while true do
        task.wait(1)
        
        -- Update status labels
        local status = "Ready"
        local matchStatus = "Waiting"
        
        -- Check map status
        local inMap, mapName = isInAnyMap()
        
        if inMap then
            status = "In Map (" .. mapName .. ") - Auto-Join Blocked"
        else
            if isLoadingScreenVisible() then
                status = "Loading Screen Active"
            elseif isEnemyLeftVisible() then
                status = "Enemy Left - Replay Blocked"
            elseif isInActiveMatch() then
                status = "In Match"
                matchStatus = "Active Match"
            elseif joining then
                status = "Joining Queue..."
                matchStatus = "Joining..."
            elseif replaying then
                status = "REPLAYING..."
                matchStatus = "Replaying..."
            elseif teleportEnabled3v3 or teleportEnabled5v5 then
                status = "Auto Teleport Active"
            end
        end
        
        teleportStatusLabel:SetText("Teleport Count: " .. teleportCount)
        currentConfigLabel:SetText("Current Config: " .. currentConfigName)
        autoLoadLabel:SetText("Auto Load: " .. (autoLoadConfig and "Enabled" or "Disabled"))
               replayWaitLabel:SetText("Replay Wait Time: " .. replayWaitTime .. "s")
        
        -- Update map display
        local currentMap = getCurrentMap()
        local mapText = "Current Map: " .. (currentMap or "Unknown")
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
        
        -- Update party status labels
        partyStatusLabel:SetText("Party Mode: " .. (inviteFriend and "Enabled" or "Disabled"))
        
        -- Count friends in party
        local friendsInPartyCount = 0
        for _, inParty in pairs(friendsInParty) do
            if inParty then
                friendsInPartyCount = friendsInPartyCount + 1
            end
        end
        friendsInPartyLabel:SetText("Friends in Party: " .. friendsInPartyCount .. "/" .. #selectedFriends)
    end
end)

-- Character respawn detection
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
        end
    end)
end)

-- Success notification
local Clock = os.clock()
local Decimals = 2
local Time = (string.format("%."..tostring(Decimals).."f", os.clock() - Clock))
library:Notify("Crazy Hub | Jump Stars " .. Time .. "s!", 5, "success")

-- Show config load status
if currentConfigName ~= "default" then
    library:Notify("Auto-loaded config: " .. currentConfigName, 3, "success")
end

-- Welcome notification with current date/time
library:Notify("Welcome back " .. game.Players.LocalPlayer.Name .. "!", 4, "success")

-- Discord server notification with clipboard copy
spawn(function()
    task.wait(3)
    local discordLink = "https://discord.gg/8KWX2N8m"
    setclipboard(discordLink)
    library:Notify("Discord server link copied to clipboard! Join L-Hub for updates!", 6, "success")
end)

-- Create default config if it doesn't exist
spawn(function()
    task.wait(2)
    ensureFolders()
    if not isfile(getConfigPath("default")) then
        saveConfig("default")
        library:Notify("Default config created!", 3, "success")
    end
end)

-- NEW: TRUE grass penetration status notification
spawn(function()
    task.wait(5)
    library:Notify("TRUE Grass Penetration Active! Raycast completely ignores all grass/foliage!", 4, "success")
end)

-- FINAL: Grass penetration confirmation
spawn(function()
    task.wait(8)
    if #grassInstances > 0 then
        library:Notify("✅ " .. #grassInstances .. " grass objects detected and excluded from wall detection!", 4, "success")
    else
        library:Notify("⚠️ No grass detected yet. Try 'Update Grass Detection' button in Legit tab.", 4, "alert")
    end
end)
