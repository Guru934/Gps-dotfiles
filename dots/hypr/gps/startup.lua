-- Explicit GPS startup hook. Requiring this module alone does nothing.
-- Opt in from the active Hyprland Lua config with:
-- require("gps.startup").enable()

local M = {}

local function shell_quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function resolve_gps_root()
    local root = os.getenv("GPS_ROOT")
    if root and root ~= "" then
        local marker = io.open(root .. "/scripts/gps-start-safe", "r")
        if marker then
            marker:close()
            return root
        end
    end

    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    local pipe = io.popen("readlink -f " .. shell_quote(source) .. " 2>/dev/null")
    if not pipe then
        return nil
    end
    local resolved = pipe:read("*l")
    pipe:close()
    if resolved then
        return resolved:gsub("/dots/hypr/gps/startup%.lua$", "")
    end
    return nil
end

function M.enable()
    local root = resolve_gps_root()
    if not root or root == "" then
        error("GPS startup hook could not resolve GPS_ROOT")
    end

    hl.on("hyprland.start", function()
        hl.exec_cmd(shell_quote(root .. "/scripts/gps-start-safe"))
    end)
end

return M
