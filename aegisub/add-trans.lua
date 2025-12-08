local clipboard = require 'aegisub.clipboard'
local re = require 'aegisub.re'
local unicode = require 'aegisub.unicode'
local tr = aegisub.gettext

script_name = tr "Add Trans - 添加翻译"
script_description = tr "add translate from clipboard"
script_author = "ranhengzhang@gmail.com"
script_version = "1"

include("utils.lua")
include("karaskel.lua")

function add_trans(subs, sel)
    local ui_config = {
        {
            class = "label",
            label = "语言",
            name = "tag_lang",
            x = 0,
            y = 0,
            width = 1
        }, {class = "edit", name = "lang", x = 4, y = 0, width = 1}
    }
    local btn, result = aegisub.dialog.display(ui_config, {"Start", "Cancel"})
    if btn == false or btn == "Cancel" then aegisub.cancel() end
    local lang = result["lang"] or "zh-CN"

    local text = clipboard.get()
    local texts = re.split(text:trim(), '[\r\n]{1,2}', true)
    local empty = {}

    for i = 1, #texts do
        if unicode.len(texts[i]:trim()) == 0 then
            table.insert(empty, i, 1)
        end
    end
    for i = 1, #empty do table.remove(texts, empty[i]) end
    local count = {}
    for _, i in ipairs(sel) do
        local line = subs[i]
        if ((line.class == "dialogue" and not line.comment) and line.style ==
            "orig" and
            (line.effect:trim() == "" or line.effect:trim() == "karaoke")) then
            karaskel.preproc_line_text({}, {}, line)
            table.insert(count, line.text_stripped)
        end
    end
    if #texts ~= #count then
        aegisub.log("false\r\n")
        aegisub.log(string.format("%d:%d\r\n", #texts, #count))
        for i = 1, #texts do
            aegisub.log(string.format("%d=>【%s】\r\n", i, texts[i]))
        end
        aegisub.cancel()
    end

    local n = 0
    for _, i in ipairs(sel) do
        local line = subs[i + n]
        if (line.class == "dialogue" and not line.comment and line.style ==
            "orig" and
            (line.effect:trim() == "" or line.effect:trim() == "karaoke")) then
            karaskel.preproc_line_text({}, {}, line)
            if line.text_stripped ~= texts[1] then
                local trans_line = table.copy(line)

                n = n + 1
                trans_line.style = "ts"
                if lang ~= "" then
                    trans_line.actor = "x-lang:" .. lang
                end
                trans_line.text = texts[1]
                aegisub.log('┌─' .. line.text_stripped .. '\r\n')
                subs.insert(i + n, trans_line)
                aegisub.log('└─' .. trans_line.text .. '\r\n\r\n')
            end
            table.remove(texts, 1)
        end
        line = nil
    end

    aegisub.set_undo_point(tr "replace rows")

    return {}
end

aegisub.register_macro(script_name, script_description, add_trans)
