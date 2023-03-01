local function stringSplit(str, delimiter)
    if str == nil or str == "" or delimiter == nil then
        return nil
    end

    local result = {}
    for match in (str .. delimiter):gmatch("(.-)" .. delimiter) do
        table.insert(result, match)
    end
    return result
end

-- 解析每个
local function parseEvery(range, min, max)
    assert(range == "*" or range == "?", string.format("parseEvery Err. \'%s\'", range))
    local values = {}
    for i = min, max, 1 do
        table.insert(values, i)
    end
    return values
end

-- 解析指定
local function parseSpecify(range, min, max)
    local values = {}
    -- 单个
    if tonumber(range) then
        local value = tonumber(range)
        assert(min <= value and value <= max, string.format("parseSpecify Err. \'%s\'", range))
        table.insert(values, value)
        return values
    end
    -- 多个
    assert(not string.find(range, "[-/*]"), string.format("parseSpecify Err. \'%s\'", range))
    local list = stringSplit(range, ",")
    for _, value in pairs(list) do
        value = tonumber(value)
        assert(min <= value and value <= max, string.format("parseSpecify Err. \'%s\'", range))
        table.insert(values, value)
    end
    return values
end

-- 解析周期
local function parseCycle(range, min, max)
    range = string.gsub(range, '^*/', string.format("%s-%s/", min, max))
    assert(string.find(range, "^[0-9]"), string.format("parseSpecify Err. \'%s\'", range))
    local values = {}
    -- 从 X 到 Y，每 Z 执行一次
    local start, finish, step = range:match("(%d+)-?(%d*)/?(%d*)")
    assert(start)
    start, finish, step = tonumber(start), tonumber(finish), tonumber(step)
    assert(min <= start and start <= max)
    finish = finish or max
    assert(min <= finish and finish <= max)
    if not step or step == 0 then
        step = 1
    end

    if start <= finish then
        for value = start, finish, step do
            if value >= min and value <= max then
                table.insert(values, value)
            end
        end
    else
        for value = start, max, step do
            table.insert(values, value)
        end
        for value = min, finish, step do
            table.insert(values, value)
        end
    end
    return values
end

local function getParseFunc(range)
    if range == "*" or range == "?" then
        return parseEvery
    elseif tonumber(range) or string.find(range, ",") then
        return parseSpecify
    elseif string.find(range, "-") or string.find(range, "/") then
        return parseCycle
    else
        assert(false, string.format("getParseFunc Err. \'%s\'", range))
    end
end

local ParseRange = {
    Second = function(range)
        assert(not string.find(range, "[^0-9,-/*]"), string.format("Parse Sceond Err. \'%s\'", range))
        local parseFunc = getParseFunc(range)
        return parseFunc(range, 0, 59)
    end,
    Minute = function(range)
        assert(not string.find(range, "[^0-9,-/*]"), string.format("Parse Minute Err. \'%s\'", range))
        local parseFunc = getParseFunc(range)
        return parseFunc(range, 0, 59)
    end,
    Hour = function(range)
        assert(not string.find(range, "[^0-9,-/*]"), string.format("Parse Hour Err. \'%s\'", range))
        local parseFunc = getParseFunc(range)
        return parseFunc(range, 0, 23)
    end,
    Day = function(range)
        assert(not string.find(range, "[^0-9,-/*L?]"), string.format("Parse Day Err. \'%s\'", range))
        -- 当月最后一天
        if range == "L" then
            return {-1}
        end
        local parseFunc = getParseFunc(range)
        return parseFunc(range, 1, 31)
    end,
    Month = function(range)
        assert(not string.find(range, "[^0-9,-/*]"), string.format("Parse Month Err. \'%s\'", range))
        local parseFunc = getParseFunc(range)
        return parseFunc(range, 1, 12)
    end,
    Weekday = function(range)
        assert(not string.find(range, "[^0-9,-/*?]"), string.format("Parse Weekday Err. \'%s\'", range))
        local parseFunc = getParseFunc(range)
        return parseFunc(range, 1, 7)
    end
}

function parseCrontab(strCrontab)
    assert(not string.find(strCrontab, "[^[0-9] ,-/*?L]"), string.format("ParseCrontab Err. \'%s\'", strCrontab))
    local list = stringSplit(strCrontab, " ")
    assert(#list == 6, string.format("ParseCrontab Err. \'%s\'", strCrontab))

    local crontab = {
        second = ParseRange.Second(list[1]),
        minute = ParseRange.Minute(list[2]),
        hour = ParseRange.Hour(list[3]),
        day = ParseRange.Day(list[4]),
        month = ParseRange.Month(list[5]),
        weekday = ParseRange.Weekday(list[6])
    }

    -- 检查月份最大天数
    local minDay = math.huge
    for _, day in pairs(crontab.day) do
        minDay = math.min(minDay, day)
    end
    if minDay > 29 then
        assert(#crontab.month > 2 or crontab.month[1] ~= 2,
            string.format("非法：%s月份 %s天 ???", crontab.month[1], minDay))
    end
    if minDay == 31 then
        local find = false
        local monthIndex = {
            [1] = true,
            [3] = true,
            [5] = true,
            [7] = true,
            [8] = true,
            [10] = true,
            [12] = true
        }
        for _, month in pairs(crontab.month) do
            if monthIndex[month] then
                find = true
            end
        end
        assert(find, string.format("非法：%s...月份 %s天 ???", crontab.month[1], minDay))
    end
    return crontab
end

local YearMonthDayCache = {}
local function getMonthDay(year, month)
    assert(year)
    assert(1 <= month and month <= 12)

    YearMonthDayCache[year] = YearMonthDayCache[year] or {}
    if YearMonthDayCache[year][month] then
        return YearMonthDayCache[year][month]
    end

    local day = os.date("*t", os.time({
        year = year,
        month = month + 1,
        day = 0
    })).day
    YearMonthDayCache[year][month] = day
    return day
end

function nextCrontab(crontab, baseTime)
    if type(crontab) == "string" then
        crontab = parseCrontab(crontab)
    end

    baseTime = baseTime or os.time()
    local timeWheel = setmetatable({
        time = os.date("*t", baseTime)
    }, {
        __index = function(tab, k)
            if k == "timestamp" then
                return os.time(tab.time)
            elseif k == "format" then
                return function()
                    return os.date("%Y-%m-%d %H:%M:%S %A", tab.timestamp)
                end
            elseif k == "lastDayOfTheMonth" then
                return getMonthDay(tab.time.year, tab.time.month) - tab.time.day - 1
            elseif k == "nextMonth" then
                return function()
                    local oldTimestamp = tab.timestamp
                    local time = tab.time
                    time.month, time.day, time.hour, time.min, time.sec = time.month + 1, 1, 0, 0, 0
                    assert(tab.timestamp > oldTimestamp)
                    tab.time = os.date("*t", tab.timestamp)
                end
            elseif k == "nextDay" then
                return function()
                    local oldTimestamp = tab.timestamp
                    local time = tab.time
                    time.day, time.hour, time.min, time.sec = time.day + 1, 0, 0, 0
                    assert(tab.timestamp > oldTimestamp)
                    tab.time = os.date("*t", tab.timestamp)
                end
            elseif k == "nextHour" then
                return function()
                    local oldTimestamp = tab.timestamp
                    local time = tab.time
                    time.hour, time.min, time.sec = time.hour + 1, 0, 0
                    assert(tab.timestamp > oldTimestamp)
                    tab.time = os.date("*t", tab.timestamp)
                end
            elseif k == "nextMinute" then
                return function()
                    local oldTimestamp = tab.timestamp
                    local time = tab.time
                    time.min, time.sec = time.min + 1, 0
                    assert(tab.timestamp > oldTimestamp)
                    tab.time = os.date("*t", tab.timestamp)
                end
            elseif k == "nextSecond" then
                return function()
                    local oldTimestamp = tab.timestamp
                    local time = tab.time
                    time.sec = time.sec + 1
                    assert(tab.timestamp > oldTimestamp)
                    tab.time = os.date("*t", tab.timestamp)
                end
            else
                return tab.time[k]
            end
        end
    })

    local function isMatch(cron, value)
        if #cron == 0 then
            return true
        end
        for _, v in ipairs(cron) do
            if v == value then
                return true
            end
        end
        return false
    end

    local MAX_CYCLE = 10000
    while true do
        while true do
            if not isMatch(crontab.month, timeWheel.month) then
                timeWheel:nextMonth()
                break
            end
            if not isMatch(crontab.day, timeWheel.day) and not isMatch(crontab.day, timeWheel.lastDayOfTheMonth) then
                timeWheel:nextDay()
                break
            end
            local wday = timeWheel.wday + 6
            if wday > 7 then
                wday = wday % 7
            end
            if not isMatch(crontab.weekday, wday) then
                timeWheel:nextDay()
                break
            end
            if not isMatch(crontab.hour, timeWheel.hour) then
                timeWheel:nextHour()
                break
            end
            if not isMatch(crontab.minute, timeWheel.min) then
                timeWheel:nextMinute()
                break
            end
            if not isMatch(crontab.second, timeWheel.sec) then
                timeWheel:nextSecond()
                break
            end
            return timeWheel.timestamp
        end
        MAX_CYCLE = MAX_CYCLE - 1
        assert(MAX_CYCLE > 0)
    end
end

local startAt = os.clock()
local now = os.time()
local count = 10
local strCrontab = "1 2 0-10/5 L 4 *"
-- local strCrontab = "0 0 0 29 2 7"
print(">>> " .. strCrontab)
for i = 1, count do
    local nextAt = nextCrontab(strCrontab, now)
    print(string.format("[%s/%s] %s", i, count, os.date("%Y-%m-%d %H:%M:%S %A", nextAt)))
    now = nextAt + 1
end
local endAt = os.clock()
print(string.format("[%s] 总耗时：%s  平均耗时：%s", strCrontab, endAt - startAt, (endAt - startAt) / count))
