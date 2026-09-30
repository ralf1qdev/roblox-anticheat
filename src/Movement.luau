local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local Policy = require(script.Parent.Policy)
local Movement = {}
Movement.__index = Movement

function Movement.new(config, evidence, logger)
    return setmetatable({ Config = config, Evidence = evidence, Logger = logger, Records = {}, Links = {} }, Movement)
end

function Movement:_reset(player, character)
    local old = self.Records[player]
    self.Records[player] = {
        character = character, state = Policy.NewMovement(), grace = os.clock() + self.Config.SpawnGrace,
        speed = old and old.speed or self.Config.DefaultMaxSpeed, boost = 0, boostUntil = 0,
        exemptUntil = 0, ping = 0, pingUpdated = -math.huge,
    }
end

function Movement:_add(player)
    if self.Links[player] then return end
    self:_reset(player, player.Character)
    self.Links[player] = player.CharacterAdded:Connect(function(character) self:_reset(player, character) end)
end

function Movement:Start()
    self.Added = Players.PlayerAdded:Connect(function(player) self:_add(player) end)
    self.Removing = Players.PlayerRemoving:Connect(function(player) self:Remove(player) end)
    for _, player in ipairs(Players:GetPlayers()) do self:_add(player) end
end

function Movement:Remove(player)
    if self.Links[player] then self.Links[player]:Disconnect() end
    self.Links[player], self.Records[player] = nil, nil
end

function Movement:SetSpeed(player, speed)
    assert(Policy.Finite(speed) and speed >= 0 and speed <= 1000, "Invalid allowed speed")
    if self.Records[player] then
        self.Records[player].speed = speed
        self.Records[player].state = Policy.NewMovement()
    end
end

function Movement:Exempt(player, duration, reason)
    assert(Policy.Finite(duration) and duration > 0 and duration <= 30, "Allowance must be 0–30 seconds")
    assert(type(reason) == "string" and #reason > 0 and #reason <= 80, "Provide a short reason")
    local record = self.Records[player]
    if record then
        record.exemptUntil = math.max(record.exemptUntil, os.clock() + duration)
        record.state = Policy.NewMovement()
        self.Logger:Debug("sentinel.allowance", reason, { userId = player.UserId, seconds = duration })
    end
end

function Movement:Boost(player, speed, duration)
    assert(Policy.Finite(speed) and speed >= 0 and speed <= 1000, "Invalid boost speed")
    assert(Policy.Finite(duration) and duration > 0 and duration <= 120, "Boost must be 0–120 seconds")
    local record = self.Records[player]
    if record then
        record.boost, record.boostUntil = speed, os.clock() + duration
        record.state = Policy.NewMovement()
    end
end

function Movement:Sample(player, record, now)
    local character = record.character
    if not character or character ~= player.Character then record.state = Policy.NewMovement(); return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or not root:IsA("BasePart") or humanoid.Health <= 0 then
        record.state = Policy.NewMovement(); return
    end
    local position = root.Position
    if not Policy.Finite(position.X) or not Policy.Finite(position.Y) or not Policy.Finite(position.Z) then
        self.Evidence:Add(player, "movement.invalid", "Non-finite root position")
        record.state = Policy.NewMovement(); return
    end
    if now - record.pingUpdated > 2 then
        record.pingUpdated = now
        local ok, ping = pcall(function() return player:GetNetworkPing() end)
        record.ping = ok and Policy.Finite(ping) and math.max(0, ping) or 0
    end
    local exempt = now < record.grace or now < record.exemptUntil or humanoid.SeatPart ~= nil or root.Anchored
    local sample = { x = position.X, y = position.Y, z = position.Z, time = now,
        ping = record.ping, grounded = true, exempt = exempt,
        maxSpeed = now < record.boostUntil and math.max(record.speed, record.boost) or record.speed }
    local params
    if not exempt and (self.Config.HoverEnabled or self.Config.NoclipEnabled) then
        params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { character }
        params.RespectCanCollide = true
        params.CollisionGroup = root.CollisionGroup
        if self.Config.HoverEnabled then
            sample.grounded = Workspace:Raycast(position, Vector3.new(0, -self.Config.GroundProbe, 0), params) ~= nil
        end
    end
    local previous = record.state.previous
    if self.Config.NoclipEnabled and not exempt and previous then
        local old = Vector3.new(previous.x, previous.y, previous.z)
        local delta = position - old
        local dt = now - previous.time
        if dt > 0 and dt <= self.Config.MaxSampleGap and delta.Magnitude > 3 and delta.Magnitude < 40 then
            local hit = Workspace:Raycast(old, delta, params)
            if hit and hit.Distance > 0.5 and hit.Distance < delta.Magnitude - 0.5
                and math.abs(hit.Normal.Y) < 0.3 then
                self.Evidence:Add(player, "movement.noclip", string.format("collidable wall intersected, travel=%.1f", delta.Magnitude))
            end
        end
    end
    for _, report in ipairs(Policy.Movement(record.state, sample, self.Config)) do
        self.Evidence:Add(player, report.rule, report.detail)
    end
end

function Movement:Step(now)
    for player, record in pairs(self.Records) do
        local ok = pcall(function() self:Sample(player, record, now) end)
        if not ok then
            record.state = Policy.NewMovement()
            if not record.errorAt or now - record.errorAt > 30 then
                record.errorAt = now
                self.Logger:Error("sentinel.monitor", "Movement monitor failed for a player", { userId = player.UserId })
            end
        end
    end
end

function Movement:Destroy()
    if self.Added then self.Added:Disconnect() end
    if self.Removing then self.Removing:Disconnect() end
    for _, link in pairs(self.Links) do link:Disconnect() end
    table.clear(self.Links)
    table.clear(self.Records)
end
return Movement
