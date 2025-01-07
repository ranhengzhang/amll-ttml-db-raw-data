clipboard = require 'aegisub.clipboard'
util = require 'aegisub.util'
re = require 'aegisub.re'
-- xmlSimple = require 'xmlSimple'

local tr = aegisub.gettext

-- 函数调用时, 当函数为单个参数, 且值为字符串, 表时可以不加括号
script_name = tr "ASS2TTML - AMLL歌词格式转换"
script_description = tr "将ASS格式的字幕文件转为TTML文件"
script_author = "ranhengzhang@gmail.com"
script_version = "0.1"
script_modified = "2024-12-17"

include("karaskel.lua")

-- local xml = xmlSimple.newParser()

local ui_config = {
    {
        class = "label",
        label = "网易云音乐 ID(s)",
        name = "tag_ncmMusicId",
        x = 0,
        y = 0,
        width = 1
    }, {class = "edit", name = "ncmMusicIds", x = 1, y = 0, width = 16}, {
        class = "label",
        label = "QQ 音乐 ID(s)",
        name = "tag_qqMusicId",
        x = 0,
        y = 1,
        width = 1
    }, {class = "edit", name = "qqMusicIds", x = 1, y = 1, width = 16}, {
        class = "label",
        label = "Spotify 音乐 ID(s)",
        name = "tag_spotifyId",
        x = 0,
        y = 2,
        width = 1
    }, {class = "edit", name = "spotifyIds", x = 1, y = 2, width = 16}, {
        class = "label",
        label = "Apple Music 音乐 ID(s)",
        name = "tag_appleMusicId",
        x = 0,
        y = 3,
        width = 1
    }, {class = "edit", name = "appleMusicIds", x = 1, y = 3, width = 16}, {
        class = "label",
        label = "歌曲的 ISRC 号码(s)",
        name = "tag_isrc",
        x = 0,
        y = 4,
        width = 1
    }, {class = "edit", name = "isrcs", x = 1, y = 4, width = 16}, {
        class = "label",
        label = "歌曲作者",
        name = "tag_artists",
        x = 18,
        y = 0,
        width = 1
    }, {class = "edit", name = "artistss", x = 19, y = 0, width = 16}, {
        class = "label",
        label = "歌曲专辑",
        name = "tag_album",
        x = 18,
        y = 1,
        width = 1
    }, {class = "edit", name = "albums", x = 19, y = 1, width = 16}, {
        class = "label",
        label = "歌曲名称",
        name = "tag_musicName",
        x = 18,
        y = 2,
        width = 1
    }, {class = "edit", name = "musicNames", x = 19, y = 2, width = 16}, {
        class = "label",
        label = "歌词作者 Github ID",
        name = "tag_ttmlAuthorGithub",
        x = 18,
        y = 3,
        width = 1
    }, {class = "edit", name = "ttmlAuthorGithubs", x = 19, y = 3, width = 16},
    {
        class = "label",
        label = "歌曲作者 Github 用户名",
        name = "tag_ttmlAuthorGithubLogin",
        x = 18,
        y = 4,
        width = 1
    },
    {class = "edit", name = "ttmlAuthorGithubLogins", x = 19, y = 4, width = 16}
}

local anti = false

local marked = {}

function add_mark(actor, num, is_bg)
    for mark in actor:gmatch('x%-mark[%w%-]*') do
        if marked[mark] == nil then
            marked[mark] = {}
        end
        table.insert(marked[mark], string.format("第%d行%s", num, is_bg and '和声部分' or ''))
    end
end

function pre_process(subtitles)
    local subs = {}
    local meta, styles = karaskel.collect_head(subtitles, true)

    for i = 1, #subtitles do
        local line = table.copy(subtitles[i])
        if line.effect == "" or line.effect == "karaoke" then
            karaskel.preproc_line_text(meta, styles, line)
            if line.style == "orig" and line.actor:find("x-mark") ~= nil then
                if line.actor:find("x-bg") ~= nil then
                    add_mark(line.actor, #subs, true)
                else
                    add_mark(line.actor, #subs+1, false)
                end
            end
            if line.actor:find('x-bg') ~= nil then
                local parent_line = table.copy(subs[#subs])
                if line.style == "orig" then
                    parent_line.bg_line = line
                    parent_line.end_time =
                        math.max(parent_line.end_time, line.end_time)
                elseif line.style == "ts" or line.style == "roma" then
                    parent_line.bg_line[line.style .. "_line"] = line
                end
                subs[#subs] = parent_line
            else
                if line.style == "orig" then
                    subs[#subs + 1] = line
                elseif line.style == "roma" or line.style == "ts" then
                    orig_line = table.copy(subs[#subs])
                    orig_line[line.style .. "_line"] = line
                    subs[#subs] = orig_line
                end
            end
        end
    end

    return subs
end

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

    for i = 1, #line.kara do
        local syl = util.copy(line.kara[i])

        if syl.text_stripped ~= '' then
            syl.text_stripped = xml_symbol(syl.text_stripped)
            syl.text_stripped = syl.text_stripped:gsub('%s+', ' ')
            if (syl.duration == 0 and syl.text_stripped:match('^%s+$') == nil) then
                syl.end_time = syl.end_time + 3
            end
            if line.actor:find('x-bg') ~= nil and i == 1 then
                syl.text_stripped = '(' .. syl.text_stripped
            end
            if line.actor:find('x-bg') ~= nil and i == #line.kara then
                syl.text_stripped = syl.text_stripped .. ')'
            end

            local start_time = time_to_string(syl.start_time + line.start_time)
            local end_time = time_to_string(syl.end_time + line.start_time)
            table.insert(ttml,
                         string.format('<span begin="%s" end="%s">%s</span>',
                                       start_time, end_time, syl.text_stripped))
            aegisub.debug.out(string.format('<%s,%s>%s', start_time, end_time,
                                            syl.text_stripped))
        end
    end
    aegisub.debug.out('\r\n')

    return table.concat(ttml)
end

function generate_line(line, n)
    local ttml = ""
    local is_bg = line.actor:find('x-bg') ~= nil

    if line.actor:find('x-anti') ~= nil then anti = true end

    if is_bg then
        ttml = ttml .. '<span ttm:role="x-bg"'
    else
        ttml = ttml .. '<p'
    end

    local start_time = time_to_string(line.start_time)
    local end_time = time_to_string(line.end_time)
    ttml = ttml .. string.format(' begin="%s" end="%s"', start_time, end_time)
    aegisub.debug.out(string.format('[%s,%s]', start_time, end_time))

    if not is_bg then
        ttml = ttml .. string.format(' ttm:agent="%s" itunes:key="L%d"',
                                     line.actor:find('x-anti') == nil and 'v1' or
                                         'v2', n)
    end

    ttml = ttml .. '>'

    ttml = ttml .. generate_kara(line)

    if line['roma_line'] ~= nil then
        ttml = ttml .. '<span ttm:role="x-roman">' .. line['roma_line'].text ..
                   '</span>'
    end
    if line['ts_line'] ~= nil then
        ttml = ttml .. '<span ttm:role="x-translation" xml:lang="zh-CN">' ..
                   line['ts_line'].text .. '</span>'
    end
    if line['bg_line'] ~= nil then
        ttml = ttml .. generate_line(line.bg_line, -1)
    end

    if is_bg then
        ttml = ttml .. '</span>'
    else
        ttml = ttml .. '</p>'
    end

    return ttml
end

function generate_body(subtitles)
    body = ""

    body = body ..
               string.format('<body dur="%s">',
                             time_to_string(subtitles[#subtitles].end_time))
    body = body .. string.format('<div begin="%s" end="%s">',
                                 time_to_string(subtitles[1].start_time),
                                 time_to_string(subtitles[#subtitles].end_time))

    local lines = {}
    for i = 1, #subtitles do
        table.insert(lines, generate_line(subtitles[i], i))
    end

    return body .. table.concat(lines) .. '</div></body>'
end

function split(str)
    local rst = {}
    str:gsub('[^,&/]+', function(w) rst[#rst + 1] = w:trim(); end)
    return rst
end

function generate_meta(key, value)
    local ttml = {}
    local values = split(value)

    for i = 1, #values do
        aegisub.debug.out(key .. ':\t　' .. values[i]:trim() .. '\r\n')
        table.insert(ttml, string.format('<amll:meta key="%s" value="%s"/>',
                                         key, xml_symbol(values[i]:trim())))
    end

    return table.concat(ttml)
end

function generate_head(metas)
    local ttml = {}

    table.insert(ttml, '<ttm:agent type="person" xml:id="v1"/>')

    if anti then table.insert(ttml, '<ttm:agent type="other" xml:id="v2"/>') end

    local ids = {'ncmMusicId', 'qqMusicId', 'spotifyId', 'appleMusicId', 'isrc'}
    for i = 1, #ids do
        if metas[ids[i] .. 's']:trim() ~= '' then
            table.insert(ttml, generate_meta(ids[i], metas[ids[i] .. 's']))
        end
    end

    local keys = {
        'musicName', 'artists', 'album', 'ttmlAuthorGithub',
        'ttmlAuthorGithubLogin'
    }
    for i = 1, #keys do
        table.insert(ttml, generate_meta(keys[i], metas[keys[i] .. 's']))
    end

    return '<head><metadata>' .. table.concat(ttml) .. '</metadata></head>'
end

function show_marks()
    aegisub.debug.out('\n\n')
    for mark, lines in pairs(marked) do
        aegisub.debug.out(mark .. ': ' .. table.concat(lines, '，') .. '\n')
    end
end

-- ! @bref 插件主函数
-- !
-- ! @param subtitles: Aegisub传入, userdata类型
-- ! @param selected_lines: 选择的行数, Aegisub传入, table类型
-- ! @param active_line: 当前选中的行, number类型
function script_main(subtitles)
    local btn, result = aegisub.dialog.display(ui_config, {"Start", "Cancel"})

    if btn == false or btn == "Cancel" then aegisub.cancel() end

    local options = util.deep_copy(result)

    local subs = util.deep_copy(subtitles)
    subs = pre_process(subs)

    if #subs == 0 then aegisub.cancel() end

    local body = generate_body(subs)
    local head = generate_head(options)
    local ttml =
        '<tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata" xmlns:amll="http://www.example.com/ns/amll" xmlns:itunes="http://music.apple.com/lyric-ttml-internal">' ..
            head .. body .. '</tt>'
    btn, _ = aegisub.dialog.display({
        {
            class = "textbox",
            name = "ttml",
            value = ttml,
            x = 0,
            y = 0,
            width = 75,
            height = 15
        }
    }, {"Copy", "Save", "Close"})

    if btn == "Copy" then
        local try_copy = clipboard.set(ttml)
        while (not try_copy) do
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
            }, {"Retry", "Cancel"})
            if btn == "Retry" then
                try_copy = clipboard.set(ttml)
            else
                try_copy = true
            end
        end
    elseif btn == "Save" then
        local ttml_file = aegisub.dialog.save('保存TTML文件',
                                              'D:/Users/LEGION/Desktop/amll-ttml-db-raw-data',
                                              options.musicNames .. '.ttml',
                                              'TTML files (.ttml)|.ttml')
        if ttml_file ~= nil then
            local file = assert(io.open(ttml_file, "w"))
            file:write(ttml)
            file:close()
        end
    end

    show_marks();
end

aegisub.register_macro(script_name, script_description, script_main)
