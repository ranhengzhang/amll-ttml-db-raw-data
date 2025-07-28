local clipboard = require 'aegisub.clipboard'
local re = require 'aegisub.re'
local unicode = require 'aegisub.unicode'
local tr = aegisub.gettext

script_name = tr"Add Trans - 添加翻译"
script_description = tr"add translate from clipboard"
script_author = "ranhengzhang@gmail.com"
script_version = "1"

include("utils.lua")

function add_trans(subs, sel)
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
    local count = 0
    for _, i in ipairs(sel) do
        local line = subs[i]
        if (line.class == "dialogue" and not line.comment and line.style == "orig" and (line.effect:trim() == "" or line.effect:trim() == "karaoke")) then
            count = count + 1
        end
    end
    if #texts ~= count then
        aegisub.log("false\r\n")
        aegisub.log(string.format("%d:%d\r\n", #texts, #sel))
        for i=1, #texts do
            aegisub.log(string.format("%d=>【%s】\r\n", i, texts[i]))
        end
        aegisub.cancel()
    end

    local n = 0
    for _, i in ipairs(sel) do
        local line = subs[i + n]
        if (line.class == "dialogue" and not line.comment and line.style == "orig" and (line.effect:trim() == "" or line.effect:trim() == "karaoke")) then
            local trans_line = table.copy(line)

            n = n + 1
            trans_line.style = "ts"
            trans_line.actor = ""
            trans_line.text = table.remove(texts, 1)
            aegisub.log('┌─' .. line.text .. '\r\n')
            subs.insert(i + n, trans_line)
            aegisub.log('└─' .. trans_line.text .. '\r\n\r\n')
        end
        line = nil
    end

    aegisub.set_undo_point(tr "replace rows")

    return {}
end

aegisub.register_macro(script_name, script_description, add_trans)
