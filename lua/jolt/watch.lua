local build = require("jolt.build")
local config = require("jolt.config")
local log = require("jolt.log").scoped("watch")
local uv = vim.uv

local M = {}

-- watch state
local handle = nil
local debounce = nil
local debounce_time = 750
local changed_files = {}
local mtimes = {}
local err

---@param opts? jolt.Config
--- Starts watching `opts.content_dir` for changes
--- Sets `vim.g.jolt_watching` to `true`
function M.start(opts)
  if vim.g.jolt_watching then
    log("already watching")
    return
  end
  opts = config.extend(opts)

  build.build_all(opts)

  handle, err = uv.new_fs_event()
  if not handle then
    log("unable to create uv event handle: " .. err, vim.log.levels.ERROR)
    return
  end

  debounce, err = uv.new_timer()
  if not debounce then
    log("unable to create uv timer: " .. err, vim.log.levels.ERROR)
    return
  end

  local send_changeset = vim.schedule_wrap(function()
    build.build_changeset(changed_files)
    changed_files = {}
  end)
  -- todo recurive flag is unsupported on linux
  --    create a fs event for each sub dir
  --    (this might even be the way for all)
  uv.fs_event_start(handle, opts.content_dir, { recursive = true }, function(err, f, e)
    if err then
      vim.schedule(function()
        log(err)
      end)
      return
    end

    if e.rename then
      return
    end

    if not f or f == "" or f:match("%~$") or f:match("^%d+$") then
      return
    end

    local stat = uv.fs_stat(opts.content_dir .. f)
    if not stat or stat.type == "directory" or mtimes[f] == stat.mtime.sec then
      return
    else
      mtimes[f] = stat.mtime.sec
    end

    changed_files[vim.fs.normalize(f)] = true

    if debounce:get_due_in() > 0 then
      debounce:again()
      return
    end

    debounce:start(debounce_time, debounce_time, function()
      send_changeset()
      debounce:stop()
    end)
  end)

  vim.g.jolt_watching = true
  if uv.os_uname().sysname:find("[Ll]inux") then
    log("recursive watch unsupported on linux :(", vim.log.levels.WARN)
  end
  log(("watching '%s' for changes..."):format(opts.content_dir))
end

--- stops watching `opts.content_dir`
function M.stop()
  if handle then
    vim.uv.fs_event_stop(handle)
    handle:close()
    handle = nil
  end

  if debounce then
    debounce:stop()
    debounce = nil
  end

  changed_files = {}

  log("stop")
  vim.g.jolt_watching = false
end

return M
