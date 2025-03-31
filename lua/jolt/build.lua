local djot = require("djot")
local config = require("jolt.config")
local log = require("jolt.log").scoped("build")
local fs = vim.fs

local M = {}

---@param opts? jolt.Config
--- cleans `opts.out_dir`, if it exists
function M.clean(opts)
  opts = opts or config.extend()
  if opts.out_dir ~= "~" or opts.out_dir ~= "/" then
    fs.rm(opts.out_dir, { recursive = true, force = true })
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

--- todo this is not robust
local function ensure_dir_exists(path)
  local parent = vim.fn.fnamemodify(path, ":e") == "" and path or fs.dirname(path)
  vim.fn.mkdir(parent, "p")
end

local function write_all(paths)
  for file, content in pairs(paths) do
    ensure_dir_exists(file)
    write_file(file, content)
  end
end

---@param list table<any>
---@param new table<any>
--- appends values from `new` that aren't already in `list` to `list`
local function add_if_not_present(list, new)
  for _, v in ipairs(new) do
    if not vim.list_contains(list, v) then
      table.insert(list, v)
    end
  end
end

local function capture_name_to_class_name(name)
  return "hl-" .. (name:gsub("%.", "-"))
end

local function html_escape(str)
  str = str:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
  -- todo tabs ??
  return str
end

---@param code string|string[] code block content, either as lines or string
---@param lang string language to highlight as
---@return table<string> rendered_lines, table<string> styles
local function highlight_code(code, lang)
  local code_lines
  if type(code) == "table" then
    code_lines = code
    code = table.concat(code, "\n")
  else
    code_lines = vim.split(code, "\n")
  end

  local parser = vim.treesitter.get_string_parser(code, lang, {})
  local root = parser:parse() or error("todo parse timed out")
  if #root > 1 then
    log("TODO wrap_and_highlight_code: parse injected languages")
  end
  root = root[1]:root()
  local queryset = vim.treesitter.query.get(lang, "highlights")

  if not queryset then
    log("no highlight queryset for lang: " .. lang, vim.log.levels.WARN)
    return vim
      .iter(code_lines)
      :map(function(v)
        return ('<span class="line">%s</span>'):format(v)
      end)
      :totable(),
      {}
  end

  local rendered = {}
  local styles = {}
  local linenr = 0
  local cursor = 0
  local open_line = '<span class="line">'
  local close_line = "</span>"
  local empty_line = open_line .. close_line
  local line = { open_line }
  local finish_line = function(diff)
    linenr = linenr + diff
    table.insert(line, close_line)
    table.insert(rendered, table.concat(line, ""))
    -- insert empty after finished line, diff is number of lines between
    -- line being finished and the next non-empty line
    if diff > 1 then
      for _ = 1, diff - 1 do
        table.insert(rendered, empty_line)
      end
    end
    line = { open_line }
    cursor = 0
  end

  local function range_equal(a, b)
    return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
  end
  local function range_within(a, b)
    return a[1] == b[1] and a[2] >= b[2] and a[4] <= b[4]
  end
  local prev_range = { -1, -1, -1, -1 }
  for id, node in queryset:iter_captures(root, code) do
    local name = queryset.captures[id]
    local srow, scol, erow, ecol = node:range()

    if name == "spell" or name == "nospell" or name == "none" or name:sub(1, 1) == "_" then
      goto continue
    end

    styles["@" .. name] = true

    if srow ~= erow then
      log(
        ("TSNode spans lines at code block %s:%d, output will likely be scuffed"):format(
          lang,
          linenr
        )
      )
    end

    if srow > linenr then
      finish_line(srow - linenr)
      prev_range = { -1, -1, -1, -1 }
    end

    local rendered_node = code_lines[linenr + 1]:sub(scol + 1, ecol)
    local class = capture_name_to_class_name(name)
    rendered_node = ('<span class="%s">%s</span>'):format(class, html_escape(rendered_node))

    local cur_range = { srow, scol, erow, ecol, name = name }
    if range_equal(cur_range, prev_range) then
      if line[#line] == open_line then
        log(lang .. ":" .. linenr .. " replaced a line open tag. this is likely a bug")
      end
      line[#line] = rendered_node
      styles["@" .. prev_range.name] = nil
    elseif range_within(cur_range, prev_range) then
      -- todo nested captures will be harder than
      -- I thought, just remove their hls for now
      styles["@" .. cur_range.name] = nil
    else
      -- regular node
      if scol > cursor then
        local normal = code_lines[linenr + 1]:sub(cursor + 1, scol)
        table.insert(line, html_escape(normal))
      end

      table.insert(line, rendered_node)

      prev_range = cur_range
      cursor = ecol
    end

    ::continue::
  end

  finish_line(0)

  return rendered, vim.tbl_keys(styles)
end

---@param code string|string[] code block content
---@param lang string language to highlight as
---@return string rendered, table<string> styles
local function wrap_and_highlight_code(code, lang)
  local rendered_lines, styles = highlight_code(code, lang)

  table.insert(rendered_lines, 1, "<code>")
  table.insert(rendered_lines, 1, "<pre>")
  table.insert(rendered_lines, 1, '<figure class="code-block">')

  table.insert(rendered_lines, "</code>")
  table.insert(rendered_lines, "</pre>")
  table.insert(rendered_lines, "</figure>")

  local rendered = vim.trim(vim.iter(rendered_lines):join("\n"))

  return rendered, styles
end

---@param name string css class name to convert
---@return string vim_hl_name
local function class_name_to_hl_name(name)
  return (name:gsub("^hl-", "@"):gsub("%-", "."))
end

---@param name string vim hl_group to convert
---@return string css_class_name
local function hl_name_to_class_name(name)
  return (name:gsub("^%@", "hl-"):gsub("%.+", "-"))
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

---@param hl_groups table<string, vim.api.keyset.highlight>
--- generates css classes for the given highlight groups
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

---@param opts jolt.Config
---@param hl_groups table<string> hl groups to generate styles for
---@return string css_stylesheet
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
    if not config.headless then
      vim.o.bg = restore_bg
      vim.cmd.colorscheme(restore)
    end
  end

  return ([[%s

@media(prefers-color-scheme: light) {
	%s
}]]):format(table.concat(dark, "\n"), table.concat(light, "\n\t"))
end

---@param document AST djot ast
---@param code_styles table<string> list of highlight groups used by code blocks
---@return table<string, string|number> metadata
--- Filters a page. Highlighting code blocks, anchoring headers, and setting metadata
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
        local code, styles = wrap_and_highlight_code(vim.trim(element.text), element.lang)
        element.text = code
        add_if_not_present(code_styles, styles)
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

-- Build State
local page_metadata = {}
local templates = {}
local code_styles = {}
local rendered_pages = {}

---@param opts? jolt.Config
function M.build_all(opts)
  opts = opts or config.extend(opts)

  if vim.fn.isdirectory(opts.out_dir) == 1 then
    if #vim.fn.glob(fs.joinpath(opts.out_dir, "/*"), true, true) > 0 then
      -- todo maybe clean should happen before writes, can skip equal content
      M.clean()
    end
  else
    vim.fn.mkdir(opts.out_dir, "p")
  end

  log("start")

  local pages = {}
  local static = {}

  for file, type in fs.dir(opts.content_dir, { depth = opts.depth }) do
    if type == "directory" then
    elseif type == "file" then
      local ext = vim.fn.fnamemodify(file, ":e")
      local basename = vim.fn.fnamemodify(file, ":t:r")
      local path_noext = vim.fn.fnamemodify(file, ":r")
      local real_path = fs.joinpath(opts.content_dir, file)

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
        local should_copy = file:match("^.+%.dj%.draft$") == nil
        static[file] = should_copy
      end
    end
  end

  local out_paths = {}
  for url, document in pairs(pages) do
    local metadata = M.filter(document, code_styles)
    metadata.title = metadata.title or opts.default_title
    metadata.template = metadata.template or opts.default_template
    metadata.description = metadata.description or metadata.title
    if metadata.slot then
      log(url .. " has invalid metadata key 'slot', clearing", vim.log.levels.WARN)
      metadata.slot = nil
    end

    page_metadata[url] = metadata

    -- todo nested templates
    local rendered = djot.render_html(document)
    rendered_pages[url] = rendered
    rendered = templates[metadata.template]:gsub(opts.template_main_slot, rendered)
    rendered = rendered:gsub("::([%w_]+)::", metadata)

    local out_path
    -- speical cases
    -- index -> index.html
    -- 404 -> 404.html
    local tail = fs.basename(url)
    if tail == "404" or tail == "index" then
      out_path = fs.joinpath(opts.out_dir, url .. ".html")
    else
      out_path = fs.joinpath(opts.out_dir, url, "index.html")
    end

    if out_paths[out_path] ~= nil then
      log(
        ("muilple in-files mapped to same the out-file '%s'"):format(out_path),
        vim.log.levels.WARN
      )
    end
    out_paths[out_path] = rendered
  end

  write_all(out_paths)

  if #code_styles > 0 then
    local hl_styles = generate_code_styles(opts, code_styles)
    static["css/highlight.css"] = hl_styles
  end

  M.write_static(static, opts)

  -- log(("build: %s"):format(vim.inspect(vim.tbl_keys(rendered_pages))))
  log(("complete, rendered %d pages"):format(#vim.tbl_keys(out_paths)))
end

---@param files table<string> the changeset, file paths relative to `opts.content_dir`
---@param opts? jolt.Config
function M.build_changeset(files, opts)
  opts = opts or config.extend()
  local pages = {}
  local updated_templates = {}
  local static = {}

  -- todo dedup this
  for file, _ in pairs(files) do
    local ext = vim.fn.fnamemodify(file, ":e")
    local basename = vim.fn.fnamemodify(file, ":t:r")
    local path_noext = vim.fn.fnamemodify(file, ":r")
    local real_path = fs.joinpath(opts.content_dir, file)

    if ext == "dj" then
      local raw = load_file(real_path)
      local ast = djot.parse(raw, false, function(a)
        log("djot: " .. vim.inspect(a))
      end)
      pages[path_noext] = ast
    elseif ext == "html" then
      local templ = load_file(real_path)
      updated_templates[basename] = templ
    else
      local should_copy = file:match("^.+%.dj%.draft$") == nil
      static[file] = should_copy
    end
  end

  local new_code_styles = {}
  local out_paths = {}
  -- todo dedup this
  for url, document in pairs(pages) do
    local metadata = M.filter(document, new_code_styles)
    metadata.title = metadata.title or opts.default_title
    metadata.template = metadata.template or opts.default_template
    metadata.description = metadata.description or metadata.title
    if metadata.slot then
      log(url .. " has invalid metadata key 'slot', clearing", vim.log.levels.WARN)
      metadata.slot = nil
    end
    page_metadata[url] = metadata

    local rendered = djot.render_html(document)
    rendered_pages[url] = rendered
    rendered = templates[metadata.template]:gsub(opts.template_main_slot, rendered)
    rendered = rendered:gsub("::([%w_]+)::", metadata)

    local out_path
    -- speical cases
    -- index -> index.html
    -- 404 -> 404.html
    local tail = fs.basename(url)
    if tail == "404" or tail == "index" then
      out_path = fs.joinpath(opts.out_dir, url .. ".html")
    else
      out_path = fs.joinpath(opts.out_dir, url, "index.html")
    end

    if out_paths[out_path] ~= nil then
      log(
        ("muilple in-files mapped to same the out-file '%s'"):format(out_path),
        vim.log.levels.WARN
      )
    end
    out_paths[out_path] = rendered
  end

  write_all(out_paths)

  if #new_code_styles > 0 then
    local old_style_len = #code_styles
    add_if_not_present(code_styles, new_code_styles)
    if old_style_len ~= #code_styles then
      local hl_groups = vim.iter(code_styles):map(class_name_to_hl_name):totable()
      local hl_styles = generate_code_styles(opts, hl_groups)
      static["css/highlight.css"] = hl_styles
    end
  end

  M.write_static(static, opts)

  if #vim.tbl_keys(updated_templates) > 0 then
    log("template reloading current unsupported :(")
  end

  log("complete")
end

---@param static table<string, string|boolean> files to copy
---@param opts? jolt.Config
function M.write_static(static, opts)
  opts = opts or config.extend()
  for file, content in pairs(static) do
    local out = fs.joinpath(opts.out_dir, file)
    if type(content) == "boolean" and content then
      local in_ = fs.joinpath(opts.content_dir, file)
      ensure_dir_exists(out)
      local _, err = vim.uv.fs_copyfile(in_, out, nil)
      if err then
        log(err)
      end
    elseif type(content) == "string" then
      ensure_dir_exists(out)
      write_file(out, content)
    end
  end
end

return M
