local build = require("jolt.build")
local config = require("jolt.config")
local log = require("jolt.log").scoped("watch")

local M = {}

local handle = nil
function M.start(opts)
  if handle then
    return
  end
  opts = config.extend(opts)

  build.build_all(opts)

  if M.headless then
    log("watch currently unsupported in headless mode")
    log("exiting")
    return
  end

  handle = vim.uv.new_fs_event()
  if not handle then
    log("unable to create uv event handle", vim.log.levels.ERROR)
    return
  end

  vim.uv.fs_event_start(handle, opts.content_dir, { recursive = true }, function(err, f, e)
    if not f or f == "" or f:match("%~$") or f:match("^%d+$") then
      return
    end

    if e.rename then
      return
    end

    if err then
      vim.schedule(function()
        log(err)
      end)
      return
    end

    vim.schedule(function()
      log(f .. " changed!")
    end)
  end)

  vim.g.jolt_watching = true
  log("started!")
end

function M.stop()
  if handle then
    vim.uv.fs_event_stop(handle)
    handle:close()
    handle = nil
  end

  vim.g.jolt_watching = false
end

return M
