return function(remote, targetsFolder, onInteract)
    local sentinel = require(game.ServerScriptService.Sentinel.Service).Get()
    local V = sentinel.Validate
    local targets = {}
    for _, part in ipairs(targetsFolder:GetChildren()) do
        if part:IsA("BasePart") and part.Anchored then
            assert(not targets[part.Name], "Target names must be unique")
            targets[part.Name] = part
        end
    end
    local schema = V.Object({ targetId = V.String(48, "^[%w_%-]+$") })
    return sentinel:BindRemote(remote, {
        Rate = 2, Burst = 3, ArgCount = 1,
        Validate = function(player, payload)
            if not schema(payload) then return false end
            local target = targets[payload.targetId]
            return target ~= nil and target.Anchored and sentinel:HasLineOfSight(player, target, 12)
        end,
    }, function(player, payload)
        local target = targets[payload.targetId]
        if target and target.Anchored and sentinel:HasLineOfSight(player, target, 12) then
            onInteract(player, target)
        end
    end)
end
