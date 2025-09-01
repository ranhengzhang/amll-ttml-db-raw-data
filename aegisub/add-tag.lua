re = require 'aegisub.re'

local tr = aegisub.gettext

script_name = tr"Add TTML Tag - 添加 TTML 标记"
script_author = "ranhengzhang@gmail.com"
script_version = "1"

include("unicode.lua")
include("karaskel.lua")

function add_tag(subs, sel)
    local ui_config = {
        {class="label", label=tr"Tag - 标记", x=0, y=0},
        {class="dropdown", name="tag", x=1, y=0, width=1, items={"x-bg", "x-duet", "x-anti", "x-chor", "x-lang"}},
        {class="label", label=tr"Value - 值", x=0, y=1},
        {class="edit", name="value", x=1, y=1, width=1},
    }
    local btn, result = aegisub.dialog.display(ui_config, {"Start", "Cancel"})
    if btn == false or btn == "Cancel" then aegisub.cancel() end
    if result.tag == "" or result.tag:gmatch("x%-%a+(%-%a+)*") == nil then aegisub.cancel() end
    if result.tag == "x-lang" and result.value == "" then aegisub.cancel() end
    for _, i in ipairs(sel) do
        local line = table.copy(subs[i])
        line.actor, _ = re.sub(line.actor, result.tag .. "(:\\w+(-\\w+)*)?", "")
        line.actor = (line.actor .. " " .. result.tag .. (result.value ~= "" and ":"..result.value or "")):gsub("%s+", " ")
        subs[i] = line
    end
    aegisub.set_undo_point("add tag")
end

aegisub.register_macro(script_name, script_description, add_tag)
