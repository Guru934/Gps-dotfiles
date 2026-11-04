-- Opt-in GPS additions for an existing Hyprland Lua configuration.
-- Load explicitly with: require("gps.integration")

local function shell_quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function resolve_gps_root()
    local root = os.getenv("GPS_ROOT")
    if root and root ~= "" then
        local marker = io.open(root .. "/scripts/gps-ipc", "r")
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
        return resolved:gsub("/dots/hypr/gps/integration%.lua$", "")
    end
    return nil
end

local root = resolve_gps_root()
if not root or root == "" then
    error("GPS integration could not resolve GPS_ROOT")
end

local gps_ipc = shell_quote(root .. "/scripts/gps-ipc")
local function ipc_command(args)
    return gps_ipc .. " " .. args
end

-- The active Caelestia Lua config loads its default bindings before this
-- integration. Remove only keys whose actions are deliberately reassigned to
-- GPS, then install the GPS launcher and utility bindings.
for _, key in ipairs({
    "SUPER + SUPER_L", "SUPER + SUPER_R", "SUPER + SPACE", "SUPER + R",
    "SUPER + Return", "SUPER + E", "SUPER + C", "SUPER + F",
    "SUPER + SHIFT + V", "SUPER + D", "SUPER + N", "SUPER + L",
    "SUPER + W", "SUPER + Q", "SUPER + Z", "SUPER + comma", "SUPER + V",
    "SUPER + ALT + C", "SUPER + SHIFT + R", "SUPER + SHIFT + P",
    "SUPER + SHIFT + Space", "Print", "SHIFT + Print", "ALT + Print",
}) do
    hl.unbind(key)
end

local gps_binds = {
    { "SUPER + Super_L", hl.dsp.exec_cmd(ipc_command("island launcher toggle")), { release = true } },
    { "SUPER + Super_R", hl.dsp.exec_cmd(ipc_command("island launcher toggle")), { release = true } },
    { "SUPER + R", hl.dsp.exec_cmd(ipc_command("island launcher toggle")) },
    { "SUPER + Space", hl.dsp.exec_cmd(ipc_command("island launcher toggle")) },
    { "SUPER + SHIFT + Space", hl.dsp.exec_cmd("fuzzel") },
    { "SUPER + Return", hl.dsp.exec_cmd("kitty") },
    { "SUPER + Z", hl.dsp.exec_cmd("kitty") },
    { "SUPER + Q", hl.dsp.exec_cmd("brave") },
    { "SUPER + E", hl.dsp.exec_cmd("thunar") },
    { "SUPER + C", hl.dsp.window.close() },
    { "SUPER + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }) },
    { "SUPER + SHIFT + V", hl.dsp.window.float() },
    { "SUPER + D", hl.dsp.exec_cmd(ipc_command("shell dashboard toggle")) },
    { "SUPER + N", hl.dsp.exec_cmd(ipc_command("shell notifcenter toggle")) },
    { "SUPER + W", hl.dsp.exec_cmd(ipc_command("shell wallpaper toggle")) },
    { "SUPER + comma", hl.dsp.exec_cmd(ipc_command("settings toggle")) },
    { "SUPER + V", hl.dsp.exec_cmd(ipc_command("shell clipboard toggle")) },
    { "SUPER + ALT + C", hl.dsp.exec_cmd(ipc_command("island control toggle")) },
    { "SUPER + L", hl.dsp.exec_cmd(shell_quote(root .. "/scripts/gps-lock")) },
    { "SUPER + SHIFT + R", hl.dsp.exec_cmd(shell_quote(root .. "/scripts/gps-record") .. " toggle") },
    { "SUPER + SHIFT + P", hl.dsp.exec_cmd(shell_quote(root .. "/scripts/gps-picker")) },
    { "Print", hl.dsp.exec_cmd(shell_quote(root .. "/scripts/gps-shot") .. " region") },
    { "SHIFT + Print", hl.dsp.exec_cmd(shell_quote(root .. "/scripts/gps-shot") .. " monitor") },
    { "ALT + Print", hl.dsp.exec_cmd(shell_quote(root .. "/scripts/gps-shot") .. " window") },
}

for _, binding in ipairs(gps_binds) do
    local options = binding[3] or {}
    options.description = "GPS: " .. binding[1]
    hl.bind(binding[1], binding[2], options)
end

-- Namespaces are GPS-owned and do not overlap Caelestia's layer namespaces.
hl.layer_rule({
    name = "gps-integration-rail",
    match = { namespace = "^gps-rail$" },
    blur = true,
    ignore_alpha = 0.25,
})

hl.layer_rule({
    name = "gps-integration-island",
    match = { namespace = "^island$" },
    blur = true,
    ignore_alpha = 0.25,
})
