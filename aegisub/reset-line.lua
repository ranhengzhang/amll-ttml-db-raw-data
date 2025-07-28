local tr = aegisub.gettext

script_name = tr"reset line - 还原行内容"
script_description = tr"reset lines to original state"
script_author = "ranhengzhang@gmail.com"
script_version = "1"

function reset_line(subs)
    for i = #subs, 1, -1 do
        local line = subs[i]
        if (line.class == "dialogue" and line.effect == "fx") then
            subs.delete(i)
        elseif (line.class == "dialogue" and (line.effect == "" or line.effect == "karaoke")) then
            if (line.style == "orig" or line.style == "ts" or line.style == "roma") then
                line.comment = false
                subs[i] = line
            end
        end
    end

    aegisub.set_undo_point(tr "reset lines")
end

aegisub.register_macro(script_name, script_description, reset_line)
