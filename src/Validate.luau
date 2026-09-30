local Policy = require(script.Parent.Policy)
local Validate = {}

function Validate.Number(minimum, maximum, integer)
    return function(value)
        return Policy.Finite(value) and value >= minimum and value <= maximum and (not integer or value % 1 == 0)
    end
end

function Validate.String(maxBytes, pattern)
    return function(value)
        return type(value) == "string" and #value <= maxBytes and utf8.len(value) ~= nil
            and (not pattern or value:match(pattern) ~= nil)
    end
end

function Validate.Enum(values)
    local allowed = {}
    for _, value in ipairs(values) do allowed[value] = true end
    return function(value) return type(value) == "string" and allowed[value] == true end
end

function Validate.Boolean(value) return type(value) == "boolean" end

function Validate.Vector3(maxMagnitude)
    return function(value)
        return typeof(value) == "Vector3" and Policy.Finite(value.X) and Policy.Finite(value.Y)
            and Policy.Finite(value.Z) and value.Magnitude <= maxMagnitude
    end
end

function Validate.Optional(check)
    return function(value) return value == nil or check(value) end
end

function Validate.Object(schema)
    return function(value)
        if type(value) ~= "table" then return false end
        for key in pairs(value) do if not schema[key] then return false end end
        for key, check in pairs(schema) do if not check(value[key]) then return false end end
        return true
    end
end

function Validate.Instance(className, ancestor)
    return function(value)
        return typeof(value) == "Instance" and value:IsA(className) and value:IsDescendantOf(ancestor)
    end
end

function Validate.Payload(value, config)
    local visited, nodes = {}, 0
    local function scan(item, depth)
        nodes = nodes + 1
        if nodes > config.MaxPayloadNodes or depth > config.MaxPayloadDepth then return false end
        local kind = typeof(item)
        if kind == "nil" or kind == "boolean" then return true end
        if kind == "number" then return Policy.Finite(item) end
        if kind == "string" then return #item <= config.MaxStringBytes and utf8.len(item) ~= nil end
        if kind == "Vector3" then return Policy.Finite(item.X) and Policy.Finite(item.Y) and Policy.Finite(item.Z) end
        if kind == "Instance" then return true end
        if kind ~= "table" or visited[item] then return false end
        visited[item] = true
        for key, child in pairs(item) do
            if (type(key) ~= "string" and type(key) ~= "number") or not scan(key, depth + 1)
                or not scan(child, depth + 1) then return false end
        end
        visited[item] = nil
        return true
    end
    return scan(value, 0)
end
return Validate
