local spawn = require("awful.spawn")
local utils = require("awesome-wm-widgets.pactl-widget.utils")

local pactl = {}


function pactl.volume_increase(device, step)
    spawn('pactl set-sink-volume ' .. device .. ' +' .. step .. '%', false)
end

function pactl.volume_decrease(device, step)
    spawn('pactl set-sink-volume ' .. device .. ' -' .. step .. '%', false)
end

function pactl.mute_toggle(device)
    spawn('pactl set-sink-mute ' .. device .. ' toggle', false)
end

function pactl.get_volume_and_mute_async(device, callback)
    assert(type(device) == "string")
    assert(type(callback) == "function")

    spawn.easy_async_with_shell(
        "timeout 2s sh -c 'pactl get-sink-volume "
            .. device
            .. "; printf \"__MUTE__\\n\"; LC_ALL=C pactl get-sink-mute "
            .. device
            .. "'",
        function(stdout)
            local volume_output, mute_output = stdout:match("^(.-)__MUTE__\n(.*)$")
            if not volume_output then
                callback(nil, nil)
                return
            end

            local volume, channels = 0, 0
            for level in volume_output:gmatch("(%d?%d?%d)%%") do
                if channels == 32 then break end
                volume = volume + tonumber(level)
                channels = channels + 1
            end

            callback(channels > 0 and volume / channels or nil, mute_output:find("yes") ~= nil)
        end
    )
end

local function parse_sinks_and_sources(default_sink, default_source, output)

    local sinks = {}
    local sources = {}

    local device
    local ports
    local key
    local value
    local in_section

    local lines = 0
    for line in output:gmatch('[^\r\n]*') do
        lines = lines + 1
        if lines > 4096 then return {}, {} end

        if string.match(line, '^%a+ #') then
            in_section = nil
        end

        local is_sink_line = string.match(line, '^Sink #')
        local is_source_line = string.match(line, '^Source #')

        if is_sink_line or is_source_line then
            in_section = "main"

            device = {
                id = line:match('#(%d+)'),
                is_default = false
            }
            if is_sink_line then
                table.insert(sinks, device)
            else
                table.insert(sources, device)
            end
        end

        -- Found a new subsection
        if in_section ~= nil and string.match(line, '^\t%a+:$') then
            in_section = utils.trim(line):lower()
            in_section = string.sub(in_section, 1, #in_section-1)

            if in_section == 'ports' then
                ports = {}
                device['ports'] = ports
            end
        end

        -- Found a key-value pair
        if string.match(line, "^\t*[^\t]+: ") then
            local t = utils.split(line, ':')
            key = utils.trim(t[1]):lower():gsub(' ', '_')
            value = utils.trim(t[2])
        end

        -- Key value pair on 1st level
        if in_section ~= nil and string.match(line, "^\t[^\t]+: ") then
            device[key] = value

            if key == "name" and (value == default_sink or value == default_source) then
                device['is_default'] = true
            end
        end

        -- Key value pair in ports section
        if in_section == "ports" and string.match(line, "^\t\t[^\t]+: ") then
            ports[key] = value
        end
    end

    return sinks, sources
end

function pactl.get_sinks_and_sources_async(callback)
    assert(type(callback) == "function")

    spawn.easy_async_with_shell(
        "timeout 2s sh -c 'printf \"__SINK__\\n\"; pactl get-default-sink; printf \"__SOURCE__\\n\"; "
            .. "pactl get-default-source; printf \"__LIST__\\n\"; LC_ALL=C pactl list'",
        function(stdout)
            local sink, source, output = stdout:match("^__SINK__\n(.-)__SOURCE__\n(.-)__LIST__\n(.*)$")
            if not output then
                callback({}, {})
                return
            end

            callback(parse_sinks_and_sources(utils.trim(sink), utils.trim(source), output))
        end
    )
end

function pactl.set_default(type, name)
    spawn('pactl set-default-' .. type .. ' "' .. name .. '"', false)
end


return pactl
