--{{{ utils
local function enumerate_files(path)
  local function recursive_enumerate(path, file_list)
    local items = love.filesystem.getDirectoryItems(path)
    for _, item in ipairs(items) do
      file = path .. '/' .. item
      info = love.filesystem.getInfo(file)
      if info.type == 'file' then
        table.insert(file_list, file)
      elseif info.type == 'directory' then
        recursive_enumerate(file, file_list)
      end
    end
  end
  local file_list = {}
  recursive_enumerate(path, file_list)
  return file_list
end

local function left_back(str, pattern)
  for k = -1, -(#str), -1 do
    local s = str:sub(k)
    local i, _ = s:find(pattern)
    if i then
      local out = s:sub(1, #str+k)
      return out ~= '' and out
    end
  end
end

local function right_back(str, pattern)
  for i = -1, -(#str), -1 do
    local s = str:sub(i)
    local _, j = s:find(pattern)
    if j then
      local out = s:sub(j+1)
      return out ~= '' and out
    end
  end
end

local function left(str, pattern)
  local i, _ = str:find(pattern)
  if i then
    local out = str:sub(1, i-1)
    return out ~= '' and out
  end
end

local function right(str, pattern)
  local _, j = str:find(pattern)
  if j then
    local out = str:sub(j+1)
    return out ~= '' and out
  end
end

local function split(str, delimiter)
  local result = {}
  local from  = 1
  local delim_from, delim_to = str:find(delimiter, from)
  while delim_from do
    table.insert(result, str:sub(from, delim_from-1))
    from = delim_to + 1
    delim_from, delim_to = str:find(delimiter, from)
  end
  table.insert(result, str:sub(from))
  return result
end

local id = 0
local function get_uid()
  id = id + 1
  return tostring(id) .. " "
end

local function find_any(str, table)
  for _, v in ipairs(table) do
    if str:find(v) then return true end
  end
end

local function contains(t, v)
  for _, u in ipairs(t) do
    if v == u then return true end
  end
end
--}}}

local function transform_update_assignment(line, assignment_type, transformed_lines)
  local indentation, lhs, _, rhs = line:match("(%s*)(%S+)(%s*%" .. assignment_type .. "=%s*)(.*)")
  local update_assignment_var = "update_assignment_" .. get_uid()
  local lhs_local_dec = "local " .. update_assignment_var .. "= " .. lhs
  local line_1 = indentation .. lhs_local_dec
  local line_2 = indentation .. update_assignment_var .. "= " .. update_assignment_var .. assignment_type .. " " .. rhs
  table.insert(transformed_lines, line_1)
  table.insert(transformed_lines, line_2)
end

local function tokenize_function_parameters(params)
  local out = {}
  for k, v in pairs(params) do
    if v:find("%s*(%S+)%s*=%s*(.+)") then
      local param_name, param_value = v:match("%s*(%S+)%s*=%s*(.+)")
      table.insert(out, {param_name, param_value})
    elseif v:find("%s*(%S+)") then
      local param_name = v:match("%s*(%S+)")
      table.insert(out, {param_name})
    end
  end
  return out
end

local function transform_function_declaration_arguments(line, transformed_lines)
  -- a, @b, c=2, @d=3
  local function transform(str, params)
    local function_lines = {}
    function_lines[1] = str
    for k, v in ipairs(params) do
      if not v[2] then -- a or @b
        if v[1]:find("self%.(%S+)") then
          local param_name = v[1]:match("self%.(%S+)")
          function_lines[1] = function_lines[1] .. param_name .. ", "
          -- self.param_name = param_name
          table.insert(function_lines, "  self." .. param_name .. " = " .. param_name)
        else
          function_lines[1] = function_lines[1] .. v[1] .. ", "
        end
      else -- c=2 or @d=3
        if v[1]:find("self%.(%S+)") then
          local param_name = v[1]:match("self%.(%S+)")
          function_lines[1] = function_lines[1] .. param_name .. ", "
          -- if param_name == nil then self.param_name = param_value else self.param_name = param_name end
          table.insert(function_lines, "  if " .. param_name .. " == nil then self." .. param_name .. " = " .. v[2] .. " else self." .. param_name .. " = " .. param_name .. " end")
        else
          function_lines[1] = function_lines[1] .. v[1] .. ", "
          -- if param_name == nil then param_name = param_value end
          table.insert(function_lines, "  if " .. v[1] .. " == nil then " .. v[1] .. " = " .. v[2] .. " end")
        end
      end
    end
    if #params > 0 then function_lines[1] = function_lines[1]:sub(1, -3) end
    function_lines[1] = function_lines[1] .. ")"
    table.insert(function_lines, "")
    return function_lines
  end

  local indentation = line:match("(%s*)function%(") or ""
  if line:find("function%((.*)%[\r\n]*$") then
    local params = tokenize_function_parameters(split(line:match("function%((.*)%)"), "%,"))
    local lines = transform("function(", params)
    for _, line in ipairs(lines) do table.insert(transformed_lines, indentation .. line) end
  elseif line:find("function %S+%((.*)%)") then
    local params = tokenize_function_parameters(split(line:match("function %S+%((.*)%)"), "%,"))
    local lines = transform("function " .. line:match("function (%S+)%(") .. "(", params)
    for _, line in ipairs(lines) do table.insert(transformed_lines, indentation .. line) end
  end
end

local function transform_with(i, j, lines, context)
  local line = lines[i]
  if line:find("%s*with%s*(.*)%s*=%s*(.*)") then -- with d = D!
    local indentation, lhs, tail = line:match("(%s*)with%s*(.*)%s*=%s*(.*)")
    local lhs_dec = indentation .. "do; " .. lhs .. "= " .. tail
    local var_name = ""
    if line:find("local ") then var_name = lhs:match("local (%S+)")
    elseif line:find("self%.") then var_name = lhs:match("(self%.%S+)%s*")
    else var_name = lhs:match("(%S+)%s*") end
    table.insert(context.lines, indentation .. "do;" .. lhs .. "= " .. tail)
    table.insert(context.withs, {i+1, j, var_name})
  elseif line:find("%s*with%s*(.*)") then -- with d
    local indentation, tail = line:match("(%s*)with%s*(%S+)")
    local var_name = "with_" .. get_uid()
    table.insert(context.lines, indentation .. "do; local " .. var_name .. " = " .. tail)
    table.insert(context.withs, {i+1, j, var_name})
  end
end

local function transform_switch(i, j, lines, transformed_lines, context)
  local line = lines[i]
  if line:find("%s*switch%s*(.*)") then
    local indentation, tail = line:match("(%s*)switch%s*(.*)")
    local var_name = "exp_" .. get_uid()
    table.insert(transformed_lines, indentation .. "local " .. var_name .. "= " .. tail)
    table.insert(context.switchs, {i+1, j, var_name})
  end
end

-- Transforms code contained in a block that needs to be changed in keeping with which type of block it is
-- with, switch, class
local function transform_blocks(lines)
  -- find block line number pairs
  local block_starting_keywords = {"function", "for", "while", "[^e]if", "repeat", "switch", "with", "class"}
  local block_starting_lines = {}
  local block_ending_lines = {}
  for i, line in ipairs(lines) do
    if find_any(line, block_starting_keywords) then
      table.insert(block_starting_lines, i)
    end
  end
  for i, line in ipairs(lines) do
    if line:find("end[\r\n]*$") then
      table.insert(block_ending_lines, i)
    end
  end
  local block_lines = {}
  for i = 1, #block_starting_lines do table.insert(block_lines, {v = block_starting_lines[i], starting = true}) end
  for i = 1, #block_ending_lines do table.insert(block_lines, {v = block_ending_lines[i], ending = true}) end
  table.sort(block_lines, function(a, b)
    if a.v == b.v then
      if a.starting then return true
      else return false end
    elseif a.v < b.v then return true
    else return false end
  end)
  local stack = {}
  local blocks = {}
  for _, line in ipairs(block_lines) do
    if line.starting then table.insert(stack, line.v) end
    if line.ending then 
      local removed_line = table.remove(stack)
      table.insert(blocks, {removed_line, line.v})
    end
  end

  -- handle withs
  local context = {}
  context.lines = {}
  context.withs = {}
  for i, line in ipairs(lines) do
    local modified = false
    for _, with in ipairs(context.withs) do
      if i >= with[1] and i <= with[2] then
        line = line:gsub(" %.", " " .. with[3] .. ".")
        line = line:gsub(" %:", " " .. with[3] .. ":")
        line = line:gsub(" %\\", " " .. with[3] .. ":")
        table.insert(transformed_lines, line)
        modified = true
      end
    end
    for _, block in ipairs(blocks) do -- handle start of block line and set context for next lines
      if i == block[1] then
        if line:find("%s*with%s+(.*)") then transform_with(block[1], block[2], lines, context); modified = true end
      end
    end
    if not modified then table.insert(context.lines, line) end
  end

  lines = copy(context.lines)

  -- handle switches

  --      if line:find("%s*switch%s+(.*)") then transform_switch(block[1], block[2], lines, transformed_lines, context); modified = true end
end

-- Transforms lines that introduce new lines or need more context before changes can be made
-- update assignments, self argument assignment, argument defaults
local function transform_line_complex(line, transformed_lines)
  local modified = false
  if line:find("%+%=") then transform_update_assignment(line, "+", transformed_lines); modified = true end -- update assignments
  if line:find("%-%=") then transform_update_assignment(line, "-", transformed_lines); modified = true end
  if line:find("%*%=") then transform_update_assignment(line, "*", transformed_lines); modified = true end
  if line:find("%/%=") then transform_update_assignment(line, "/", transformed_lines); modified = true end
  if line:find("%%%=") then transform_update_assignment(line, "%", transformed_lines); modified = true end
  if line:find("%.%.%=") then transform_update_assignment(line, "..", transformed_lines); modified = true end
  if line:find("or%=") then transform_update_assignment(line, "or", transformed_lines); modified = true end
  if line:find("and%=") then transform_update_assignment(line, "and", transformed_lines); modified = true end
  if line:find("function%((.*)%)") or line:find("function %S+%((.*)%)") then transform_function_declaration_arguments(line, transformed_lines); modified = true end -- self argument assignment, argument defaults
  if not modified then table.insert(transformed_lines, line) end
end

-- Transform symbols that only need to be directly changed into something else with little or no context
-- $, @, @:, @\, !=, fn, *, **, #{}, !, if, elseif, while, for
local function transform_line_simple(line, transformed_lines)
  if line:find("%$") then line = line:gsub("%$", "local ") end -- local
  if line:find("%@%:") then line = line:gsub("%@%:", "self:") end -- @: -> self:
  if line:find("%@%\\") then line = line:gsub("%@%\\", "self:") end -- @\ -> self:
  if line:find("%@") then line = line:gsub("%@", "self.") end -- @ -> self.
  if line:find("%\\") then line = line:gsub("%\\", ":") end -- \ -> :
  if line:find("%!%=") then line = line:gsub("%!%=", "~=") end -- != 
  if line:find("%#%{(.+)%}") then line = line:gsub("%#%{(.+)%}", '" .. tostring(%1) .. "') end -- string interpolation
  if line:find("%!") then line = line:gsub("%!", "()") end -- ! -> no parameter function call
  if line:find("fn") then line = line:gsub("fn", "function") end -- function
  if line:find("for (%S+) in %*(%S+)") then line = line:gsub("for (%S+) in %*(%S+)", "for _, %1 in ipairs(%2)") end -- * -> ipairs
  if line:find("for (%S+)%,%s*(%S+) in %&(%S+)") then line = line:gsub("for (%S+)%,%s*(%S+) in %&(%S+)", "for %1, %2 in pairs(%3)") end -- & -> pairs
  if line:find("for (.*)") then line = line:gsub("for (.*)", "for %1 do") end -- for
  if line:find("(%s*)(.+) if (.*)[\r\n]*$") then line = line:gsub("(%s*)(.*) if (.*)[\r\n]*$", "%1 if %3 then %2 end") end -- if decorator
  if line:find("(%s*)if (.*) then (%s*) end[\r\n]*$") then line = line:gsub("(.*)if (.*) then (%s*) end[\r\n]*$", "%1if %2 then") end -- if fix
  if line:find("elseif (.*)[\r\n]*$") then line = line:gsub("elseif (.*)[\r\n]*$", "elseif %1 then") end -- elseif
  if line:find("while (.*)[\r\n]*$") then line = line:gsub("while (.*)[\r\n]*$", "while %1 do") end -- while
  table.insert(transformed_lines, line)
end

local function transform_file(path)
  local lines = {}
  for line in love.filesystem.lines(path) do table.insert(lines, line) end
  local transformed_lines_simple = {}; for i = 1, #lines do transform_line_simple(lines[i], transformed_lines_simple) end
  local transformed_lines_complex = {}; for i = 1, #transformed_lines_simple do transform_line_complex(transformed_lines_simple[i], transformed_lines_complex) end
  local transformed_lines_blocks = transform_blocks(transformed_lines_complex)
  str = ""; for _, line in ipairs(transformed_lines_blocks) do str = str .. line .. "\n" end
  print(str)
end

function transform()
  local paths = enumerate_files("src")
  for _, path in ipairs(paths) do
    transform_file(path)
  end
end
