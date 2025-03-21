local M = {}

M.subcommands = {
  build = { "pages", "static" },
  watch = { "start", "stop" },
  serve = { "start", "stop" },
  clean = {},
}
M.main = { "build", "clean", "serve", "watch" }

--- Which commands should quit after running in
--- headless mode
M.should_quit = {
  build = true,
  clean = true,
  watch = false,
  serve = false,
}

setmetatable(M, {
  __index = function(t, k)
    return function(input)
      return vim
        .iter(t.subcommands[k] or {})
        :filter(function(subcmd)
          return vim.startswith(subcmd, input)
        end)
        :totable()
    end
  end,
})

return M
