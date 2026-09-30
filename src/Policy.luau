local Policy = {}

function Policy.Finite(n)
    return type(n) == "number" and n == n and math.abs(n) < math.huge
end

function Policy.Bucket(bucket, now, rate, burst)
    if not bucket then bucket = { tokens = burst, time = now } end
    bucket.tokens = math.min(burst, bucket.tokens + math.max(0, now - bucket.time) * rate)
    bucket.time = now
    if bucket.tokens < 1 then return false, bucket end
    bucket.tokens = bucket.tokens - 1
    return true, bucket
end

function Policy.Decay(score, elapsed, halfLife)
    return score * 2 ^ (-math.max(0, elapsed) / halfLife)
end

function Policy.NewMovement()
    return { previous = nil, path = 0, elapsed = 0, hover = 0 }
end

function Policy.Reset(state, sample)
    state.previous, state.path, state.elapsed, state.hover = sample, 0, 0, 0
end

function Policy.Movement(state, sample, config)
    local reports = {}
    if not Policy.Finite(sample.x) or not Policy.Finite(sample.y) or not Policy.Finite(sample.z) then
        state.previous = nil
        return {{ rule = "movement.invalid", detail = "Non-finite position" }}
    end
    local old = state.previous
    if not old or sample.exempt then Policy.Reset(state, sample); return reports end
    local dt = sample.time - old.time
    if dt <= 0 or dt > config.MaxSampleGap then Policy.Reset(state, sample); return reports end
    local dx, dy, dz = sample.x - old.x, sample.y - old.y, sample.z - old.z
    local horizontal = math.sqrt(dx * dx + dz * dz)
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    local speed = sample.maxSpeed
    local margin = config.SpeedSlack + speed * math.min(config.PingAllowanceCap, math.max(0, sample.ping)) * 2
    if distance > math.max(config.TeleportDistance, speed * dt + margin) then
        table.insert(reports, { rule = "movement.teleport", detail = string.format("distance=%.1f dt=%.2f", distance, dt) })
        Policy.Reset(state, sample)
        return reports
    end
    state.path, state.elapsed = state.path + horizontal, state.elapsed + dt
    if state.elapsed >= config.SpeedWindow then
        if state.path > speed * state.elapsed + margin then
            table.insert(reports, { rule = "movement.speed", detail = string.format("observed=%.1f allowed=%.1f window=%.2f", state.path / state.elapsed, speed, state.elapsed) })
        end
        state.path, state.elapsed = 0, 0
    end
    if config.HoverEnabled and not sample.grounded and math.abs(dy / dt) < config.HoverVerticalSpeed then
        state.hover = state.hover + dt
        if state.hover >= config.HoverSeconds then
            table.insert(reports, { rule = "movement.hover", detail = string.format("airborne=%.1f verticalSpeed=%.1f", state.hover, dy / dt) })
            state.hover = 0
        end
    else state.hover = 0 end
    state.previous = sample
    return reports
end
return Policy
