--- === My Tasks ===
---
--- Show a preview of your Tasks (from Asana's API).
---
--- Requires an Asana "Personal Access Token" to get started.

-- Prevent GC: https://github.com/Hammerspoon/Spoons/blob/master/Source/Caffeine.spoon/init.lua
-- TODO: Is this needed?
local obj = { __gc = true }
setmetatable(obj, obj)
obj.__gc = function(t)
    t:stop()
end

-- Metadata
obj.name = "MyTasks"
obj.version = "0.1"
obj.author = "Eric Pelz <contact@ericpelz.com>"
obj.homepage = "https://www.ericpelz.com/"
obj.license = 'MIT - https://opensource.org/licenses/MIT'

-- Constants
local TITLE="∴"
local ASANA_FETCH_TASKS_ROUTE="https://app.asana.com/api/1.0/user_task_lists/%s/tasks?completed_since=now&opt_fields=name,due_on"

local function midnightInSec(due_on) 
    local dt = os.date("*t")
    dt.day = dt.day + 1
    dt.hour = 0
    dt.min = 0
    dt.sec = 0
    return os.time(dt)
end

local function dateStringToSeconds(dateString)
    if dateString == nil then return nil end

    local pattern = "(%d+)-(%d+)-(%d+)"
    local year, month, day = dateString:match(pattern)
    return os.time({year=year, month=month, day=day})
end

local function calculateTitle(num)
    if num == nil then return TITLE end
    return string.format("%s (%d)", TITLE, num)
end

local function printableNow()
    return os.date('%Y-%m-%d %H:%M:%S')
end

local function updateMenu(results)
    -- Count before adding extra items
    local numResults = #results

    -- Sort and clean up menu items
    table.insert(results, {
        sortVal = 0,
        title = string.format("Last updated: %s", printableNow()),
        fn = function() hs.urlevent.openURL("https://app.asana.com/") end,
    })
    table.insert(results, { sortVal = 1, title = "-" })
    table.sort(results, function(a, b) return a.sortVal < b.sortVal end)

    -- Update menu
    obj.menu:setTitle(calculateTitle(numResults))
    obj.menu:setMenu(results)
end

local function onResponse(status, body)
    print("Processing response...", printableNow())

    if status ~= 200 then
        print("Can't process status code", status)
        return
    end

    local response = hs.json.decode(body)
    local count = 0

-- TODO: Removed limit from request, but this will still truncate at 1000.
--    if response.next_page ~= null then
--        print("Asana Menubar response is missing results! You probably have more than 100 tasks.")
--        return
--    end

    local midnightSec = midnightInSec()
    -- TODO: Should be a map/filter, does that exist in Lua?
    local results = {}
    for _, v in pairs(response.data) do
        -- TODO: There's probably a cleaner way to do this in Lua.
        local gid = v.gid
        local name = v.name
        local due_on = v.due_on
        local due_on_sec = dateStringToSeconds(due_on)
        local url = string.format("https://app.asana.com/0/%s/%s/f", gid, gid)

        if due_on_sec ~= nil and midnightSec > due_on_sec then
            table.insert(results, {
                title = string.format("%s (Due %s)", name, due_on),
                fn = function() hs.urlevent.openURL(url) end,
                sortVal = due_on_sec
            })
        end

    end

    updateMenu(results)
    print("Menu updated", printableNow())
end

local function onInterval()
    local fetchUrl = string.format(ASANA_FETCH_TASKS_ROUTE, obj.config.asana_task_list_id)
    local headers = {
        Accept = "application/json",
        Authorization = string.format("Bearer %s", obj.config.asana_api_pat)
    }

    print("Fetching now...", printableNow())
    hs.http.asyncGet(fetchUrl, headers, onResponse)
end

--- MyTasks:start()
--- Method
--- Starts the MyTasks spoon
---
--- Parameters:
---  * config - A table containing configuration:
---              asana_api_pat:      Asana Personal Access Token (required)
---              asana_task_list_id: Asana Task List (required)
---                                  https://developers.asana.com/docs/get-a-users-task-list
---              refresh_interval:   Interval in seconds to refresh (default 300)
---
--- Returns:
---  * self
function obj:start(config)
    self.config = config
    self.config.refresh_interval = config.refresh_interval or 300

    if self.menu then self:stop() end
    self.menu = hs.menubar.new()
    if self.menu then
        self.menu:setTitle(calculateTitle(nil))
        self.menu:setMenu({
            { title = "Loading..."}
        })
    end
    
    -- Start timer, and immediately start
    self.timer = hs.timer.new(config.refresh_interval, onInterval)
    self.timer:start()
    onInterval()

    return self
end

--- MyTasks:stop()
--- Method
--- Stop running the spoon
---
--- Parameters: none
---
--- Returns:
---  * self
function obj:stop()
	self.menu:removeFromMenuBar()
	self.timer:stop()

	return self
end

return obj