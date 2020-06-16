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
local ASANA_GET_TASKS_ROUTE="https://app.asana.com/api/1.0/user_task_lists/%s/tasks?completed_since=now&opt_fields=name,due_on"
local ASANA_POST_TASK_ROUTE="https://app.asana.com/api/1.0/tasks?assignee=%i&workspace=%i&due_on=%s&name=%s"

local function asanaApiHeaders()
    return {
        Accept = "application/json",
        Authorization = string.format("Bearer %s", obj.config.asana_api_pat)
    }
end

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

local function promptForTask()
    -- TODO: Support "cancel" button
    local _, taskName = hs.dialog.textPrompt("Create reminder task", "Please enter the task name you'd like to create. Note: It will be assigned to you, and due today.", "", "Create Task")
    print("Creating task now...", taskName)

    -- TODO: Instead of constants, can use API on init to get these IDs.
    -- TODO: Put in central "reminder" project?
    local postUrl = string.format(ASANA_POST_TASK_ROUTE, obj.config.asana_user_id, obj.config.asana_workspace_id, os.date("%Y-%m-%d"), hs.http.encodeForQuery(taskName))

    hs.http.asyncPost(postUrl, "", asanaApiHeaders(), function(response_status, response_body, response_headers) print(response_status, response_body, response_headers) end)

    -- TODO: Add notification/alert that confirms creation, or shows error (with content, so no dataloss)
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
    table.insert(results, {
        sortVal = 1,
        title = "Create Reminder Task",
        fn = function() promptForTask() end,
    })
    table.insert(results, { sortVal = 2, title = "-" })
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
    local fetchUrl = string.format(ASANA_GET_TASKS_ROUTE, obj.config.asana_task_list_id)

    print("Fetching now...", printableNow())
    hs.http.asyncGet(fetchUrl, asanaApiHeaders(), onResponse)
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
---              asana_user_id:      Asana User ID (required)
---              asana_workspace_id: Asana Workspace ID (required)
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
    self.timer = hs.timer.new(self.config.refresh_interval, onInterval)
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
