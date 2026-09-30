local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Config = require(script.Parent.Config)
local Policy = require(script.Parent.Policy)
local Validate = require(script.Parent.Validate)
local Evidence = require(script.Parent.Evidence)
local RemoteGuard = require(script.Parent.RemoteGuard)
local Movement = require(script.Parent.Movement)
local Service = {}
Service.__index = Service
local singleton

function Service.Get()
    assert(RunService:IsServer(), "Sentinel is server-only")
    if singleton then return singleton end
    assert(Config.Mode == "Monitor", "This version supports Monitor mode only")
    assert(Config.SampleInterval >= 0.1 and Config.SampleInterval <= 2, "Invalid sample interval")
    assert(Config.ScoreHalfLife > 0 and Config.ReportCooldown >= 1 and Config.MaxEvidence >= 1, "Invalid evidence settings")
    local logger = require(script.Parent.Signal.Logger).Get()
    local evidence = Evidence.new(Config, logger)
    local self = setmetatable({ Logger = logger, Evidence = evidence, Validate = Validate, Config = Config,
        Remotes = RemoteGuard.new(Config, evidence, logger), Movement = Movement.new(Config, evidence, logger),
        Active = Config.Enabled, LastSample = os.clock() }, Service)
    singleton = self
    if Config.Enabled then
        self.Movement:Start()
        self.Removing = Players.PlayerRemoving:Connect(function(player)
            self.Evidence:Remove(player); self.Remotes:Remove(player)
        end)
        self.Heartbeat = RunService.Heartbeat:Connect(function()
            local now = os.clock()
            if now - self.LastSample >= Config.SampleInterval then
                self.LastSample = now
                self.Movement:Step(now)
            end
        end)
        logger:Info("sentinel.start", "Monitoring only; no automatic kicks or bans")
    end
    return self
end

function Service:BindRemote(remote, options, handler)
    assert(self.Active, "Sentinel is disabled; guarded remotes were not installed")
    return self.Remotes:Bind(remote, options, handler)
end
function Service:SetAllowedSpeed(player, speed) self.Movement:SetSpeed(player, speed) end
function Service:AllowMovement(player, seconds, reason) self.Movement:Exempt(player, seconds, reason) end
function Service:AllowSpeedBoost(player, speed, seconds) self.Movement:Boost(player, speed, seconds) end
function Service:GetEvidence(player) return self.Evidence:Get(player) end
function Service:GetStats() return { logs = self.Logger:GetStats(), remotes = table.clone(self.Remotes.Totals) } end

function Service:Teleport(player, target)
    assert(typeof(target) == "CFrame", "Teleport expects a server-chosen CFrame")
    local character = player.Character
    if not character then return false end
    self:AllowMovement(player, 2, "server teleport")
    character:PivotTo(target)
    return true
end

function Service:IsNear(player, target, maxDistance)
    if not Policy.Finite(maxDistance) or maxDistance <= 0 then return false end
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0
        or typeof(target) ~= "Instance" or not target:IsA("BasePart") or not target:IsDescendantOf(Workspace) then return false end
    local distance = (root.Position - target.Position).Magnitude
    return Policy.Finite(distance) and distance <= maxDistance
end

function Service:HasLineOfSight(player, target, maxDistance)
    if not self:IsNear(player, target, maxDistance) then return false end
    local character = player.Character
    local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
    if not head or not head:IsA("BasePart") then return false end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { character }
    params.RespectCanCollide = true
    local hit = Workspace:Raycast(head.Position, target.Position - head.Position, params)
    return hit == nil or hit.Instance == target
end
return Service
