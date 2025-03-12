local djot = require("djot")

local M = {}

local htmlwinnr = nil
local htmlbufnr = -1

local function highlight_code(code, lang)
  local tohtml = require("tohtml").tohtml
  if htmlwinnr == nil or not vim.api.nvim_win_is_valid(htmlwinnr) then
    htmlbufnr = vim.api.nvim_create_buf(true, true)
    htmlwinnr = vim.api.nvim_open_win(htmlbufnr, false, { split = "right" })
  end

  vim.api.nvim_buf_set_lines(
    htmlbufnr,
    0,
    -1,
    false,
    type(code) == "string" and vim.split(code, "\n") or code
  )
  vim.bo[htmlbufnr].filetype = lang
  local html = tohtml(htmlwinnr, {})

  local style_start = html[7]
  assert(vim.startswith(style_start, "<style>"), "bad style tag pos")
  local styles = {}

  for i = 8, #html do
    local s = html[i]
    if s == "</style>" then
      break
    end
    local match = s:find("font%-family") or s:find("^%-spell")
    s, _ = s:gsub("^body", "figure") -- todo not sure
    if match == nil then
      styles[s] = true
    end
  end

  local pre_start = 7 + #styles + 1
  while pre_start < #html do
    local s = html[pre_start]
    if s == "<pre>" then
      break
    end
    pre_start = pre_start + 1
  end

  local rendered = { html[pre_start] }
  for i = pre_start + 1, #html do
    local s = html[i]

    table.insert(rendered, s)
    if s == "</pre>" then
      break
    end
  end

  rendered = vim
    .iter(rendered)
    :map(function(v)
      if v == "<pre>" or v == "</pre>" then
        return v
      end

      if v == "" then
        return nil
      end

      return '<span class="line">' .. v .. "</span>"
    end)
    :totable()
  table.insert(rendered, 1, "<figure>")

  return rendered, styles
end

---@class static.Config
local default_opts = {
  in_dir = ".",
  out_dir = "build/",
  pages_dir = "pages/",
  template_dir = "templates/",
  static_dir = "static/",
}

---@param opts? static.Config
function M.build(opts)
  if not opts then
    opts = vim.tbl_extend("keep", default_opts, {})
  end
  local cwd = vim.cmd.pwd()

  local queue = {
    "/index",
    -- "/404",
  }

  local visited = { ["/"] = true }
  local code_style = nil

  while #queue > 0 do
    local path = table.remove(queue, #queue)
    path = vim.fs.joinpath(opts.pages_dir, path)
    if path:sub(#path, #path) == "/" then
      path = path:sub(1, #path - 1)
    end

    local file, err = io.open(path .. ".dj", "r")
    if not file then
      vim.print(("error: on '%s': %s"):format(path, err))
      return
    end

    local content = file:read("a") or ""
    file:close()

    local document = djot.parse(content, false, function(a)
      vim.print("in warn: ", a)
    end)

    local metadata = {}
    -- todo do filters need to be rebuilt every file
    local filters = {
      {
        link = function(element)
          vim.print(element)
        end,
        code_block = function(element)
          element.tag = "raw_block"
          element.format = "html"
          local code, styles = highlight_code(vim.trim(element.text), element.lang)
          code_style = vim.tbl_extend("keep", code_style or {}, styles)
          element.text = vim.trim(table.concat(code, "\n"))
        end,
      },
    }

    djot.filter.apply_filter(document, filters)
    metadata.extra_styles = code_style

    local rendered = djot.render_html(document)
    vim.print("rendered:::::::", rendered)
    local out = io.open(path .. ".html", "w") or {}
    rendered = ([[<!doctype html>
<head>
<style>
%s
</style>
</head>
<body>
%s
</body>
</html>]]):format(table.concat(vim.tbl_keys(metadata.extra_styles), "\n"), rendered)
    out:write(rendered)
    vim.print("metadata::::::", metadata)
    out:close()
  end
end

return M
