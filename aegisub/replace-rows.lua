local clipboard = require 'aegisub.clipboard'
local re = require 'aegisub.re'
local unicode = require 'aegisub.unicode'
local tr = aegisub.gettext

script_name = tr"replace rows - 替换行内容"
script_description = tr"replace rows from input"
script_author = "ranhengzhang@gmail.com"
script_version = "1"

include("utils.lua")

function replace_rows(subs, sel)
    local text = clipboard.get()
    local texts = re.split(text:trim(), '[\r\n]{1,2}', true)
    local empty = {}

    for i=1, #texts do
        if unicode.len(texts[i]:trim()) == 0 then
            table.insert(empty, i, 1)
        end
    end
    for i=1, #empty do
        table.remove(texts, empty[i])
    end
    if #texts ~= #sel then
        aegisub.log("false\r\n")
        aegisub.log(string.format("%d:%d\r\n", #texts, #sel))
        for i=1, #texts do
            aegisub.log(string.format("%d=>【%s】\r\n", i, texts[i]))
        end
        aegisub.cancel()
    end

    for _, i in ipairs(sel) do
        local line = subs[i]
        if (line.class == "dialogue" and not line.comment) then
            aegisub.log('┌─' .. line.text .. '\r\n')
            line.text = table.remove(texts, 1)
            aegisub.log('└─' .. line.text .. '\r\n\r\n')
            subs[i] = line
        end
    end

    aegisub.set_undo_point(tr "replace rows")
end

aegisub.register_macro(script_name, script_description, replace_rows)
