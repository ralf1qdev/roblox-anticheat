local Policy = require(script.Parent.Policy)
local Evidence = {}
Evidence.__index = Evidence

function Evidence.new(config, logger, clock)
    return setmetatable({ Config = config, Logger = logger, Clock = clock or os.clock, Records = {} }, Evidence)
end

function Evidence:Add(player, rule, detail)
    local now = self.Clock()
    local record = self.Records[player]
    if not record then
        record = { score = 0, updated = now, rules = {}, keyCount = 0, recent = {}, total = 0 }
        self.Records[player] = record
    end
    record.score = Policy.Decay(record.score, now - record.updated, self.Config.ScoreHalfLife)
    record.updated, record.total = now, record.total + 1
    local bucket = record.rules[rule]
    if not bucket then
        if record.keyCount >= self.Config.MaxRuleKeys then return false end
        bucket = { last = -math.huge, suppressed = 0 }
        record.rules[rule] = bucket
        record.keyCount = record.keyCount + 1
    end
    if now - bucket.last < self.Config.ReportCooldown then
        bucket.suppressed = bucket.suppressed + 1
        return false
    end
    bucket.last = now
    record.score = math.min(self.Config.MaxScore, record.score + (self.Config.Weights[rule] or 3))
    local item = { time = os.time(), rule = rule, detail = tostring(detail):sub(1, 180), score = record.score,
        suppressed = bucket.suppressed }
    bucket.suppressed = 0
    table.insert(record.recent, item)
    if #record.recent > self.Config.MaxEvidence then table.remove(record.recent, 1) end
    self.Logger:Warn("sentinel." .. rule, "Monitor finding; not proof of cheating", {
        userId = player.UserId, score = math.floor(record.score), evidence = item.detail, repeated = item.suppressed,
    })
    return true
end

function Evidence:Get(player)
    local record = self.Records[player]
    if not record then return { score = 0, observations = 0, recent = {} } end
    local recent = {}
    for _, item in ipairs(record.recent) do table.insert(recent, table.clone(item)) end
    return { score = Policy.Decay(record.score, self.Clock() - record.updated, self.Config.ScoreHalfLife),
        observations = record.total, recent = recent }
end

function Evidence:Remove(player) self.Records[player] = nil end
return Evidence
