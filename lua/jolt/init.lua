local build = require("jolt.build")
local config = require("jolt.config")
local serve = require("jolt.serve")
local watch = require("jolt.watch")
local log = require("jolt.log")

local M = {}

M.log = log
M.headless = config.headless
M.setup = config.setup
M.build = function(what)
  if not what then
    build.build_all()
  else
    log("TODO granular build unimplemented")
  end
end
M.clean = build.clean
M.serve = serve.start
M.watch = watch.start

function M.start(what)
  if what == "watch" then
    -- watch.start()
  elseif what == "serve" then
    serve.start()
  else
    log(("bad start target '%s'"):format(what))
  end
end

function M.stop(what)
  if what == "watch" then
    -- watch.stop()
  elseif what == "serve" then
    serve.stop()
  else
    log(("bad stop target '%s'"):format(what))
  end
end

return M
