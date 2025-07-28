local clipboard = require 'aegisub.clipboard'
local tr = aegisub.gettext

-- 函数调用时, 当函数为单个参数, 且值为字符串, 表时可以不加括号
script_name = tr "Pure TTML - AMLL歌词格式转换(纯文本)"
script_description = tr "将ASS格式的字幕文件原样转为TTML文件"
script_author = "ranhengzhang@gmail.com"
script_version = "0.1"
script_modified = "2024-12-17"

include("karaskel.lua")

function time_to_string(time)
    return string.format("%02d:%02d.%03d", math.floor(time / 60000),
                         math.floor(time / 1000) % 60, time % 1000)
end

function xml_symbol(value)
    value = string.gsub(value, "&", "&amp;"); -- '&' -> "&amp;"
    value = string.gsub(value, "<", "&lt;"); -- '<' -> "&lt;"
    value = string.gsub(value, ">", "&gt;"); -- '>' -> "&gt;"
    value = string.gsub(value, "\"", "&quot;"); -- '"' -> "&quot;"
    value = string.gsub(value, "\'", "&apos;"); -- '"' -> "&quot;"
    return value;
end

function generate_kara(line)
    local ttml = {}

    for i = 1, line.kara.n do
        local syl = util.copy(line.kara[i])
        -- if syl.furi ~= nil and syl.furi.n <= 1 then
            syl.text = xml_symbol(syl.text)
            local start_time = time_to_string(syl.start_time + line.start_time)
            local end_time = time_to_string(syl.end_time + line.start_time)
            table.insert(ttml,
            string.format('<span begin="%s" end="%s">%s</span>',
                        start_time, end_time, syl.text))
        -- else
        if syl.furi ~= nil and syl.furi.n > 1 then
            for j = 2, syl.furi.n do
                local furi = util.copy(syl.furi[j])
                furi.text = xml_symbol(furi.text)
                local start_time = time_to_string(furi.start_time + line.start_time)
                local end_time = time_to_string(furi.end_time + line.start_time)
                table.insert(ttml,
                string.format('<span begin="%s" end="%s">%s</span>',
                            start_time, end_time, '#|'..furi.text))
            end
        end
        -- end
    end
    return table.concat(ttml)
end

function script_main(subtitles)
    local ttml = {};
    local start_time = 0;
    local end_time = 65537;
    local meta, styles = karaskel.collect_head(subtitles, false)
    for i = 1, #subtitles do
        local line = table.copy(subtitles[i])
        if (line.effect == "" or line.effect == "karaoke") and (line.style == "orig") then
            karaskel.preproc_line_text(meta, styles, line)
            start_time = math.min(start_time, line.start_time)
            end_time = math.max(end_time, line.end_time)
            local text = '<p'
            text = text .. string.format(' begin="%s" end="%s"', time_to_string(line.start_time), time_to_string(line.end_time))
            text = text .. '>'
            text = text .. generate_kara(line)
            text = text .. '</p>'
            table.insert(ttml, text)
            aegisub.log(text)
        end
    end
    local head = string.format('<body dur="%s"><div begin="%s" end="%s">', time_to_string(end_time), time_to_string(start_time), time_to_string(end_time))
    clipboard.set('<tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata" xmlns:amll="http://www.example.com/ns/amll" xmlns:itunes="http://music.apple.com/lyric-ttml-internal"><head><metadata><ttm:agent type="person" xml:id="v1" /></metadata></head>' .. head .. table.concat(ttml) .. '</div></body></tt>')
end

aegisub.register_macro(script_name, script_description, script_main);
