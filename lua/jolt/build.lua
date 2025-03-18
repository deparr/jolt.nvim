local djot = require("djot")
local config = require("jolt.config")
local log = require("jolt.log")

local M = {}

function M.clean(opts)
  opts = opts or config.extend()
  if opts.out_dir ~= "~" or opts.out_dir ~= "/" then
    vim.fs.rm(opts.out_dir, { recursive = true, force = true })
  else
    log(("wont remove out dir '%s'"):format(opts.out_dir), vim.log.levels.ERROR)
  end
end

local function load_file(path)
  local f, err = io.open(path, "r")
  if not f then
    error(("load_file: '%s': %s"):format(path, err))
  end

  local c = f:read("a")
  f:close()
  return c
end

local function write_file(path, content)
  local f, err = io.open(path, "w")
  if not f then
    error(("write_file: '%s': %s"):format(path, err))
  end

  f:write(content)
  f:close()
end

-- todo this is not robust
local function ensure_dir_exists(path)
  local parent = vim.fn.fnamemodify(path, ":e") == "" and path or vim.fs.dirname(path)
  vim.fn.mkdir(parent, "p")
end

local htmlbufnr = -1
local htmlwinnr = -1

local function highlight_code(code, lang)
  local tohtml = require("tohtml").tohtml
  htmlbufnr = vim.api.nvim_buf_is_valid(htmlbufnr) and htmlbufnr
    or vim.api.nvim_create_buf(true, true)
  htmlwinnr = vim.api.nvim_win_is_valid(htmlwinnr) and htmlwinnr
    or vim.api.nvim_open_win(htmlbufnr, false, { split = "right" })

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
    local match = s:find("font%-family") or s:find("^%.%-spell") or s:find("^body")
    if match == nil and not vim.tbl_contains(styles, s) then
      table.insert(styles, s)
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

  local blocks = {}
  for i = pre_start + 1, #html do
    local s = html[i]
    if s == "</pre>" then
      break
    end

    table.insert(blocks, s)
  end

  if blocks[#blocks] == "" then
    blocks[#blocks] = nil
  end

  for i, v in ipairs(blocks) do
    blocks[i] = ('<span class="line">%s</span>'):format(v)
  end

  table.insert(blocks, 1, "<code>")
  table.insert(blocks, 1, "<pre>")
  table.insert(blocks, 1, '<figure class="code-block">')

  table.insert(blocks, "</code>")
  table.insert(blocks, "</pre>")
  table.insert(blocks, "</figure>")

  local rendered = vim.trim(vim.iter(blocks):join("\n"))

  return rendered, styles
end

local function class_name_to_hl_name(name)
  return (name:sub(2):gsub("^%-", "@"):gsub("%-", "."):match("^(%S+) .*$"))
end

local function hl_name_to_class_name(name)
  return (name:gsub("%.", "-"):gsub("@", "-"))
end

local function hex_to_str(c)
  if type(c) == "string" and c:sub(1, 1) == "#" then
    return c
  end
  return ("#%06x"):format(c)
end

local function get_hl_defs(hl_groups)
  local used_hls = {}
  for _, group in ipairs(hl_groups) do
    used_hls[group] = vim.api.nvim_get_hl(0, { name = group, link = false })
  end
  return used_hls
end

--- generates a style file for the current colorscheme
local function generate_styles_for_colorscheme(hl_groups)
  local out = {}
  for name, hl in pairs(hl_groups) do
    local line = {
      hl.underline and "underline" or nil,
      hl.strikethrough and "line-through" or nil,
      hl.undercurl and "underline" or nil,
    }
    local attrs = {
      color = hl.fg and hex_to_str(hl.fg) or nil,
      ["font-style"] = hl.italic and "italic" or nil,
      ["font-weight"] = hl.bold and "bold" or nil,
      ["text-decoration-line"] = not #line == 0 and table.concat(line, " ") or nil,
      ["text-decoration-color"] = hl.sp and hex_to_str(hl.sp) or nil,
      ["text-decoration-style"] = hl.undercurl and "wavy" or nil,
    }
    local s = {}
    for attr, val in pairs(attrs) do
      table.insert(s, attr .. ": " .. val)
    end
    table.insert(out, (".%s {%s}"):format(hl_name_to_class_name(name), table.concat(s, "; ")))
  end

  return out
end

local function generate_code_styles(opts, hl_groups)
  local light, dark
  if type(opts.code_style) == "function" then
    light = opts.code_style("light", hl_groups)
    dark = opts.code_style("dark", hl_groups)

    light = generate_styles_for_colorscheme(light)
    dark = generate_styles_for_colorscheme(dark)
  else
    local restore = opts.code_style.restore or "default"
    local restore_bg = vim.o.bg
    vim.cmd("hi clear")
    vim.o.bg = "light"
    vim.cmd.colorscheme(opts.code_style.light)
    light = generate_styles_for_colorscheme(get_hl_defs(hl_groups))
    vim.cmd("hi clear")
    vim.o.bg = "dark"
    vim.cmd.colorscheme(opts.code_style.dark)
    dark = generate_styles_for_colorscheme(get_hl_defs(hl_groups))
    if #vim.tbl_keys(vim.api.nvim_list_uis()) > 0 then
      vim.o.bg = restore_bg
      vim.cmd.colorscheme(restore)
    end
  end

  return ([[%s

@media(prefers-color-scheme: light) {
	%s
}]]):format(table.concat(dark, "\n"), table.concat(light, "\n\t"))
end

function M.filter(document, code_styles)
  local metadata = {}
  local filters = {
    {
      link = function(element)
        local is_internal = element.destination and element.destination:match("^([#/])")
        if is_internal then
          if
            #element.destination > 1
            and element.destination:sub(#element.destination, #element.destination) == "/"
          then
            element.destination = element.destination:sub(1, #element.destination - 1)
          end
        elseif element.destination then
          if element.destination:match("^(https?):") then
            element.attr = element.attr or djot.ast.new_attributes()
            element.attr.target = "_blank"
          end
        end
      end,
      code_block = function(element)
        element.tag = "raw_block"
        element.format = "html"
        local code, styles = highlight_code(vim.trim(element.text), element.lang)
        element.text = code
        for _, s in ipairs(styles) do
          if not vim.tbl_contains(code_styles, s) then
            table.insert(code_styles, s)
          end
        end
      end,
      raw_block = function(element)
        if element.format == "meta" then
          for line in element.text:gmatch("[^\n]+") do
            local key, value = line:match("(%w+) *=%s*(.+)$")
            metadata[key] = value
          end
        end
      end,
      section = function(element)
        element.attr.id = element.attr.id:lower()
        -- todo header anchoring?
      end,
      image = function(element)
        -- todo I want to wrap images in figures
        -- element.tag = "raw_block"
        -- element.format = "html"
        -- local dest = element.destination
        -- local alt = element.children[1].text
        -- element.children = nil
        -- element.text = ('<figure><img src="%s" alt="%s"></img></figure>'):format(dest, alt)
      end,
    },
  }
  djot.filter.apply_filter(document, filters)
  return metadata
end

function M.build_all(opts)
  opts = config.extend(opts)

  if vim.fn.isdirectory(opts.out_dir) == 1 then
    if #vim.fn.glob(vim.fs.joinpath(opts.out_dir, "/*"), true, true) > 0 then
      -- todo maybe clean should happen before writes, can skip equal content
      M.clean()
    end
  else
    vim.fn.mkdir(opts.out_dir, "p")
  end

  log("build: start")

  local pages = {}
  local templates = {}
  local static = {}

  for file, type in vim.fs.dir(opts.content_dir, { depth = opts.depth }) do
    if type == "directory" then
    elseif type == "file" then
      local ext = vim.fn.fnamemodify(file, ":e")
      local basename = vim.fn.fnamemodify(file, ":t:r")
      local path_noext = vim.fn.fnamemodify(file, ":r")
      local real_path = vim.fs.joinpath(opts.content_dir, file)

      if ext == "dj" then
        local raw = load_file(real_path)
        local ast = djot.parse(raw, false, function(a)
          log("djot: ", a)
        end)
        pages[path_noext] = ast
      elseif ext == "html" then
        local templ = load_file(real_path)
        templates[basename] = templ
      else
        -- todo maybe some sort of user is_static filter
        local copy_file = file:match("^.+%.dj%.draft$") == nil
        static[file] = copy_file
      end
    end
  end

  local code_styles = {}
  local rendered_pages = {}
  for url, document in pairs(pages) do
    local metadata = M.filter(document, code_styles)
    metadata.title = metadata.title or opts.default_title
    metadata.template = metadata.template or opts.default_template
    metadata.description = metadata.description or metadata.title

    -- todo nested templates
    local rendered = djot.render_html(document)
    rendered = templates[metadata.template]:gsub(opts.template_main_slot, rendered)
    rendered = rendered:gsub("::([%w_]+)::", metadata)

    local out_path
    -- speical cases
    -- index -> index.html
    -- 404 -> 404.html
    if url == "404" or url == "index" then
      out_path = vim.fs.joinpath(opts.out_dir, url .. ".html")
    else
      out_path = vim.fs.joinpath(opts.out_dir, url, "index.html")
    end

    rendered_pages[out_path] = rendered
  end

  if #code_styles > 0 then
    local hl_groups = vim.iter(code_styles):map(class_name_to_hl_name):totable()
    local hl_styles = generate_code_styles(opts, hl_groups)
    static["css/highlight.css"] = hl_styles
  end

  if vim.api.nvim_buf_is_valid(htmlbufnr) then
    vim.api.nvim_buf_delete(htmlbufnr, { force = true })
  end
  if vim.api.nvim_win_is_valid(htmlwinnr) then
    vim.api.nvim_win_close(htmlwinnr, true)
  end

  for file, content in pairs(rendered_pages) do
    ensure_dir_exists(file)
    write_file(file, content)
  end

  for file, content in pairs(static) do
    local out = vim.fs.joinpath(opts.out_dir, file)
    if type(content) == "boolean" and content then
      local in_ = vim.fs.joinpath(opts.content_dir, file)
      ensure_dir_exists(out)
      local suc, err = vim.uv.fs_copyfile(in_, out, nil)
      if not suc then
        log(err)
      end
    elseif type(content) == "string" then
      ensure_dir_exists(out)
      write_file(out, content)
    end
  end

  -- log(("build: %s"):format(vim.inspect(vim.tbl_keys(rendered_pages))))
  log(("build: complete, rendered %d pages"):format(#vim.tbl_keys(rendered_pages)))
end

return M
