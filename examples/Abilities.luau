local sentinel = require(game.ServerScriptService.Sentinel.Service).Get()
local Abilities = {}

function Abilities.TeleportToSpawn(player, serverSpawn)
    assert(serverSpawn:IsA("BasePart") and serverSpawn.Anchored)
    return sentinel:Teleport(player, serverSpawn.CFrame + Vector3.new(0, 4, 0))
end

function Abilities.SetSprint(player, enabled)
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    local speed = enabled and 24 or 16
    sentinel:SetAllowedSpeed(player, speed + 4)
    humanoid.WalkSpeed = speed
end

function Abilities.AllowKnockback(player)
    sentinel:AllowMovement(player, 2, "validated combat knockback")
end
return Abilities
