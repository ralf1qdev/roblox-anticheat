local Policy = require(script.Parent.Policy)
local Validate = require(script.Parent.Validate)
local RemoteGuard = {}
RemoteGuard.__index = RemoteGuard

function RemoteGuard.new(config, evidence, logger, clock)
    return setmetatable({ Config = config, Evidence = evidence, Logger = logger, Clock = clock or os.clock,
        Routes = {}, Count = 0, Totals = { accepted = 0, rejected = 0, failures = 0 } }, RemoteGuard)
end

function RemoteGuard:_process(route, player, args)
    if route.closed or route.removed[player] then return false end
    local now = self.Clock()
    local accepted, bucket = Policy.Bucket(route.buckets[player], now, route.rate, route.burst)
    route.buckets[player] = bucket
    local function reject(rule, reason)
        self.Totals.rejected = self.Totals.rejected + 1
        self.Evidence:Add(player, rule, route.name .. ": " .. reason)
        return false
    end
    if not accepted then return reject("remote.rate", "request budget exceeded") end
    if args.n ~= route.argCount then return reject("remote.payload", "argument count") end
    if not Validate.Payload(args, self.Config) then return reject("remote.payload", "payload bounds or type") end
    if route.busy[player] then return reject("remote.rate", "handler already in flight") end
    route.busy[player] = true
    local ok, valid = pcall(route.validate, player, table.unpack(args, 1, args.n))
    if route.closed or route.removed[player] then route.busy[player] = nil; return false end
    if not ok then
        route.busy[player] = nil
        self.Totals.failures = self.Totals.failures + 1
        self.Logger:Error("sentinel.validator", "Validator failed; request rejected", { route = route.name })
        return false
    end
    if valid ~= true then
        route.busy[player] = nil
        return reject("remote.schema", "schema or permission rejected")
    end
    if route.closed or route.removed[player] then route.busy[player] = nil; return false end
    local ran, result = pcall(route.handler, player, table.unpack(args, 1, args.n))
    route.busy[player] = nil
    if not ran then
        self.Totals.failures = self.Totals.failures + 1
        self.Logger:Error("sentinel.handler", "Gameplay handler failed", { route = route.name })
        return false
    end
    self.Totals.accepted = self.Totals.accepted + 1
    return true, result
end

function RemoteGuard:Bind(remote, options, handler)
    assert(remote:IsA("RemoteEvent"), "Bind expects a RemoteEvent")
    assert(not self.Routes[remote], "Remote already bound")
    assert(self.Count < self.Config.MaxRemoteBindings, "Remote binding limit reached")
    assert(type(options.Validate) == "function" and type(handler) == "function", "Validator and handler required")
    local rate, burst, argCount = options.Rate or 5, options.Burst or 8, options.ArgCount or 1
    assert(Policy.Finite(rate) and rate > 0 and rate <= 1000, "Invalid rate")
    assert(Policy.Finite(burst) and burst >= 1 and burst <= 1000, "Invalid burst")
    assert(Policy.Finite(argCount) and argCount >= 0 and argCount <= 16 and argCount % 1 == 0, "Invalid argument count")
    local route = { name = remote.Name:sub(1, 60), rate = rate, burst = burst, argCount = argCount,
        validate = options.Validate, handler = handler, buckets = {}, busy = {},
        removed = setmetatable({}, { __mode = "k" }), closed = false }
    self.Routes[remote] = route
    self.Count = self.Count + 1
    route.connection = remote.OnServerEvent:Connect(function(player, ...)
        self:_process(route, player, table.pack(...))
    end)
    return function()
        if route.closed then return end
        route.closed = true
        route.connection:Disconnect()
        self.Routes[remote] = nil
        self.Count = self.Count - 1
        table.clear(route.buckets)
    end
end

function RemoteGuard:Remove(player)
    for _, route in pairs(self.Routes) do
        route.removed[player] = true
        route.buckets[player] = nil
        route.busy[player] = nil
    end
end

function RemoteGuard:Destroy()
    for _, route in pairs(self.Routes) do
        route.closed = true
        route.connection:Disconnect()
    end
    table.clear(self.Routes)
    self.Count = 0
end
return RemoteGuard
