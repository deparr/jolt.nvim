if vim.g.loaded_jolt then
  return
end
vim.g.loaded_jolt = true

local jolt = require("jolt")
local commands = require("jolt.command")

vim.api.nvim_create_user_command("Jolt", function(args)
  local main = args.fargs[1] or "build"
  local sub = args.fargs[2]

  -- todo clean this up
  local cmd
  if main == "build" then
    cmd = jolt.build
  elseif main == "watch" then
    cmd = jolt.watch
  elseif main == "serve" then
    cmd = jolt.serve
  elseif main == "clean" then
    cmd = jolt.clean
  else
    jolt.log(("invalid command '%s'"):format(main))
    return
  end

  if sub then
    if sub == "start" then
      cmd = function()
        jolt.start(main)
      end
    elseif sub == "stop" then
      cmd = function()
        jolt.stop(main)
      end
    else
      if main == "build" then
        jolt.log("build sub commands are unimplemented", vim.log.levels.ERROR)
        return
        -- cmd = function()
        --   jolt.build(sub)
        -- end
      else
        jolt.log(
          ("invalid subcommand '%s' for command '%s'"):format(sub, main),
          vim.log.levels.ERROR
        )
        return
      end
    end
  end

  if jolt.headless and commands.should_quit[main] then
    cmd()
    vim.cmd.quit()
  else
    vim.schedule(cmd)
  end
end, {
  desc = "Manage jolt.nvim",
  force = false,
  nargs = "*",
  bar = true,
  complete = function(lead, cmdline, _)
    local args = vim.split(cmdline, " +", { trimempty = true })
    local n = #args

    local new_arg = lead ~= ""
    if n == 1 or n == 2 and new_arg then
      return vim
        .iter(commands.main)
        :filter(function(v)
          return vim.startswith(v, lead)
        end)
        :totable()
    end

    local main = args[2]
    return (n < 3 or (new_arg and n == 3)) and commands[main](lead) or {}
  end,
})
