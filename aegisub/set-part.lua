re = require 'aegisub.re'

local tr = aegisub.gettext

-- 函数调用时, 当函数为单个参数, 且值为字符串, 表时可以不加括号
script_name = tr "Set Part - 标记歌词部分"
script_description = tr "为当前行添加 x-part 标记, 用于分割歌词部分"
script_author = "ranhengzhang@gmail.com"
script_version = "0.1"
script_modified = "2024-12-17"

include("karaskel.lua")

function set_part(subs, sel)
    if #sel ~= 1 then
        aegisub.log("请选择 *1* 行\n")
        return
    end
    local line = subs[sel[1]]
    if line.class ~= "dialogue" or (line.effect ~= "" and line.effect ~= "karaoke") or line.style ~= "orig" or line.actor:find("x-bg") ~= nil then
        aegisub.log(tr "请选择 *主 orig* 行, 且 *不是 fx* 的行\n")
        return
    end

    local actor = line.actor
    actor = re.sub(actor, "x-part:[A-z]+", ""):trim()

    local ui_config = {
        {class = "label", name = "part_name_tag", label = "分段名称", x = 0, y = 0},
        {class = "dropdown", items = {"Verse（主歌）", "Chorus（副歌）", "PreChorus（预副歌）", "Bridge（桥段）", "Intro（前奏）", "Outro（尾奏）", "Refrain（叠句）", "Instrumental（器乐）"}, name = "part_name", value = "Verse（主歌）", x = 1, y = 0}
    }

    local btn, result = aegisub.dialog.display(ui_config, {"Set", "Cancel"})

    if btn == false or btn == "Cancel" then aegisub.cancel() end

    actor = re.sub(actor .. " x-part:" .. re.find(result.part_name, "^[A-z]+")[1].str, "\\s{2,}", " "):trim()
    line.actor = actor
    subs[sel[1]] = line

    aegisub.set_undo_point(tr"set part")
end

aegisub.register_macro(script_name, script_description, set_part)
