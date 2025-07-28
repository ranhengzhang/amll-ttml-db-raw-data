local tr = aegisub.gettext

script_name = tr "Fix Furi - 注音中的错误"
script_description = tr "Fix furi before karaoke"
script_author = "ranhengzhang@gmail.com"
script_version = "1"

include("karaskel.lua")
local re = require 'aegisub.re'
local unicode = require 'aegisub.unicode'

function fix_furi(subs)
    local expr_concat = re.compile("\\}\\{(?=\\\\[kK][of]?[0-9]+\\}[^\\{]+\\|[^\\<])")
    local expr_space = re.compile("\\|[^\\{]+\\ \\{")
    for i = 1, #subs do
        local line = table.copy(subs[i])
        if (line.effect == "" or line.effect == "karaoke") and line.style == "orig" then
            if expr_concat:find(line.text) ~= nil then
                aegisub.log(line.text .. '\r\n')
                line.text = re.sub(line.text, "\\}\\{(?=\\\\[kK][of]?[0-9]+\\}#\\|)", "}#|{")
                line.text = re.sub(line.text, "\\}\\{(?=\\\\[kK][of]?[0-9]+\\}[^#|]+\\|[^\\<])", "}|{")
                aegisub.log('⇓\r\n' .. line.text .. '\r\n\r\n')
                subs[i] = line
            end
            if expr_space:find(line.text) ~= nil then
                aegisub.log(line.text .. '\r\n')
                line.text = re.sub(line.text, "(?<=\\|)([^\\ \\{]+)\\ \\{", "\\1{\\\\ko0} {")
                aegisub.log('⇓\r\n' .. line.text .. '\r\n\r\n')
                subs[i] = line
            end
        end
    end
    aegisub.set_undo_point(tr "fix furi")
end

aegisub.register_macro(script_name, script_description, fix_furi)
