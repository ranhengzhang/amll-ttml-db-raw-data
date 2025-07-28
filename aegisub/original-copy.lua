clipboard = require 'aegisub.clipboard'

local tr = aegisub.gettext

script_name = tr"copy original text - 复制原文"
script_description = tr"copy original text to system clipboard"
script_author = "ranhengzhang@gmail.com"
script_version = "1"

include("karaskel.lua")

function original_copy(subs, sel)
    local btn, result = aegisub.dialog.display({
        {
            class = 'label',
            label = '是否添加编号',
            x = 0,
            y = 0
        }
    }, {"是", "否"})

    if btn == false then aegisub.cancel() end
    local need_number = (btn == "是")

    local text={}
    for _, i in ipairs(sel) do
        local line = table.copy(subs[i])
        if line.style == "orig" and (line.effect == "" or line.effect == "karaoke") then
            line.comment = false
            karaskel.preproc_line_text({}, {}, line)
            if need_number then
                line.text_stripped = string.format("%02d. %s", #text+1, line.text_stripped)
            end
            table.insert(text, line.text_stripped .. '\n')
            aegisub.debug.out(line.text_stripped..'\n')
        end
    end
    while (not clipboard.set(table.concat(text))) do
        btn, _ = aegisub.dialog.display({
            {
                class = 'label',
                label = '写入剪贴板失败，请点击重试或手动复制。',
                x = 0,
                y = 0
            }, {
                class = "textbox",
                name = "ttml",
                value = ttml,
                x = 0,
                y = 1,
                width = 75,
                height = 15
            }
        }, {"Retry", "Close"})
        if btn == "Close" then
            break
        end
    end
end

aegisub.register_macro(script_name, script_description, original_copy)
