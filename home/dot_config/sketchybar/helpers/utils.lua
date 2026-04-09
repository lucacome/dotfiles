local M = {}

function M.trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function M.parse_lines(output)
  local result = {}
  for line in tostring(output or ""):gmatch("[^\r\n]+") do
    local value = M.trim(line)
    if value ~= "" then
      table.insert(result, value)
    end
  end
  return result
end

function M.shell_quote(value)
  local s = M.trim(value)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

return M
