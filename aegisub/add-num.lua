local tr = aegisub.gettext

script_name = tr"Add line num - 添加行编号"
script_description = tr"Add line num as ttml"
script_author = "ranhengzhang@gmail.com"
script_version = "1"

include("unicode.lua")
include("karaskel.lua")

function add_num(subs)
    local L = 0
    for i = 1, #subs do
        local line = table.copy(subs[i])
        line.actor = string.gsub(' '..(line.actor or ''), '%sL_*%d+', ""):trim()
        line.actor = line.actor:gsub("____", ""):trim()
        line.actor = line.actor:gsub("%s+", " "):trim()
        if line.effect == "" or line.effect == "karaoke" then
            if line.style == "orig" and line.actor:find('x-bg') == nil then
                L = L+1
                line.actor = string.trim(string.format("L%3d", L):gsub(' ', '_') .. ' ' .. line.actor)
                if line.actor:find('x-chor') ~= nil then
                    L = L+1
                end
            else
                line.actor = '____ ' .. line.actor
            end
            subs[i] = line
        end
    end

    aegisub.set_undo_point(tr"add num")
end

aegisub.register_macro(script_name, script_description, add_num)
