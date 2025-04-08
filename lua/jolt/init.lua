local build = require("jolt.build")
local config = require("jolt.config")
local serve = require("jolt.serve")
local watch = require("jolt.watch")
local log = require("jolt.log").default

local M = {}

--- The default, top-level logger
M.log = log
--- true if neovim was started in headless mode
M.headless = config.headless
M.setup = config.setup
---@param what? string type of content to build, pass `nil` to build all
M.build = function(what)
  if not what then
    build.build_all()
  elseif what == "pages" then
    local pages = build.scan_pages()
    build.build_changeset(pages)
  elseif what == "static" then
    local static = build.scan_static()
    build.build_changeset(static)
  else
    log("invalid build sub-set: " .. what)
  end
end
M.clean = build.clean
M.serve = serve.start
M.watch = watch.start

---@param what? string which long-running service to start
function M.start(what)
  if what == "watch" then
    watch.start()
  elseif what == "serve" then
    serve.start()
  else
    log(("bad start target '%s'"):format(what))
  end
end

---@param what? string which long-running service to stop
function M.stop(what)
  if what == "watch" then
    watch.stop()
  elseif what == "serve" then
    serve.stop()
  else
    log(("bad stop target '%s'"):format(what))
  end
end

return M
