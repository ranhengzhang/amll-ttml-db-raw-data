clipboard = require 'aegisub.clipboard'
util = require 'aegisub.util'
re = require 'aegisub.re'

local tr = aegisub.gettext

-- 函数调用时, 当函数为单个参数, 且值为字符串, 表时可以不加括号
script_name = tr "ASS2TTML - AMLL歌词格式转换"
script_description = tr "将ASS格式的字幕文件转为TTML文件"
script_author = "ranhengzhang@gmail.com"
script_version = "0.8"
script_modified = "2025-06-03"

include("karaskel.lua")

local anti = false

local marked = {}

function add_mark(actor, num, is_bg)
    for mark in actor:gmatch('x%-mark[%w%-]*') do
        if marked[mark] == nil then marked[mark] = {} end
        table.insert(marked[mark], string.format("第%d行%s", num,
                                                 is_bg and '和声部分' or ''))
    end
end

function xml_symbol(value)
    value = string.gsub(value, "&", "&amp;"); -- '&' -> "&amp;"
    value = string.gsub(value, "<", "&lt;"); -- '<' -> "&lt;"
    value = string.gsub(value, ">", "&gt;"); -- '>' -> "&gt;"
    value = string.gsub(value, "\"", "&quot;"); -- '"' -> "&quot;"
    value = string.gsub(value, "\'", "&apos;"); -- '"' -> "&quot;"
    return value;
end

local title = "";
local script_offset = 0;

function pre_process(subtitles)
    local subs = {}
    local meta, styles = karaskel.collect_head(subtitles, true)

    for i = 1, #subtitles do
        local line = table.copy(subtitles[i])
        if subtitles[i].class == "info" then
            if subtitles[i].key == "Title" then
                title = subtitles[i].value
            elseif subtitles[i].key == "Update Details" then
                local res = subtitles[i].value:match("[+-]%d+")
                script_offset = tonumber(res or "0")
            end
        else
            if line.effect == "" or line.effect == "karaoke" then
                line.raw = line.raw:gsub('%s+', ' ')
                karaskel.preproc_line_text(meta, styles, line)
                if line.style == "orig" and line.actor:find("x-mark") ~= nil then -- 处理标记
                    if line.actor:find("x-bg") ~= nil then
                        add_mark(line.actor, #subs, true)
                    else
                        add_mark(line.actor, #subs + 1, false)
                    end
                end
                if line.actor:find('x-bg') ~= nil then
                    local parent_line = table.copy(subs[#subs])
                    if line.style == "orig" then
                        line.ts_line = {n = 0}
                        parent_line.bg_line = line
                        parent_line.end_time =
                            math.max(parent_line.end_time, line.end_time)
                    elseif line.style == "roma" then
                        parent_line.bg_line["roma_line"] = line
                    elseif line.style == "ts" then
                        local bg_line = parent_line.bg_line
                        local ts_line = bg_line["ts_line"]
                        ts_line.n = ts_line.n + 1
                        ts_line[ts_line.n] = line
                        bg_line["ts_line"] = ts_line
                        parent_line.bg_line = bg_line
                    end
                    subs[#subs] = parent_line
                else
                    if line.style == "orig" then
                        line.ts_line = {n = 0}
                        subs[#subs + 1] = line
                    elseif line.style == "roma" then
                        orig_line = table.copy(subs[#subs])
                        orig_line["roma_line"] = line
                        subs[#subs] = orig_line
                    elseif line.style == "ts" then
                        orig_line = table.copy(subs[#subs])
                        local ts_line = orig_line["ts_line"]
                        ts_line.n = ts_line.n + 1
                        ts_line[ts_line.n] = line
                        subs[#subs] = orig_line
                    end
                end
            end
        end
    end

    return subs
end

local offset

function time_to_string(time)
    time = time + offset
    return string.format("%02d:%02d.%03d", math.floor(time / 60000),
                         math.floor(time / 1000) % 60, time % 1000)
end

local split_space = false
local merge_space = false
local merge_symbol = false
local pre_symbols = "([<（【〔［｛〈《｢「『“‘"

function generate_kara(line)
    local ttml = {}

    for i = 1, #line.kara do
        local syl = util.copy(line.kara[i])
        syl.text_stripped = xml_symbol(syl.text_stripped)

        local space = nil
        if split_space then
            space = re.find(syl.text_stripped, "^(\\ |\\　)(?=.)")

            if space then
                syl.text_stripped =
                    re.sub(syl.text_stripped, "^(\\ |\\　)", "")
                local hole_time = time_to_string(syl.start_time +
                                                     line.start_time)
                table.insert(ttml, string.format('<span begin="%s" end="%s">',
                                                 hole_time, hole_time))
                table.insert(ttml, space[1].str)
                table.insert(ttml, '</span>')
            end

            space = re.find(syl.text_stripped, "(?<=.)(\\ |\\　)$")
            if space then
                syl.text_stripped =
                    re.sub(syl.text_stripped, "(\\ |\\　)$", "")
            end
        end
        if syl.duration == 0 then
            if i < #line.kara and line.kara[i + 1].duration == 0 then -- 合并连续无时长音节
                local next_syl = line.kara[i + 1]
                next_syl.text_stripped =
                    syl.text_stripped .. line.kara[i + 1].text_stripped
                line.kara[i + 1] = next_syl
                goto continue
            end
            local trimed = syl.text_stripped:trim() -- 不知道为什么 trim 和 unicode.len 放一起会报错😅
            if unicode.len(trimed) == 0 and merge_space then -- 时长为 0 的空格
                if i == 1 and #line.kara > 2 then
                    goto continue
                else
                    table.remove(ttml)
                    table.insert(ttml, syl.text_stripped)
                    table.insert(ttml, '</span>')
                end
            elseif unicode.len(trimed) == 1 and merge_symbol then -- 合并时长为 0 的单个非空字符
                if i == 1 and #line.kara > 2 then -- 首字符向后合并
                    line.kara[2].text_stripped =
                        syl.text_stripped .. line.kara[2].text_stripped
                elseif i > 1 and i < #line.kara and
                    pre_symbols:find(syl.text_stripped) ~= nil then -- 特殊字符向后合并
                    line.kara[i + 1].text_stripped =
                        syl.text_stripped .. line.kara[i + 1].text_stripped
                else
                    table.remove(ttml)
                    table.insert(ttml, syl.text_stripped)
                    table.insert(ttml, '</span>')
                    if split_space and space then
                        local hole_time =
                            time_to_string(syl.end_time + line.start_time)
                        table.insert(ttml, string.format(
                                         '<span begin="%s" end="%s">',
                                         hole_time, hole_time))
                        table.insert(ttml, space[1].str)
                        table.insert(ttml, '</span>')
                    end
                end
            else -- 时长为 0 的不合并字符
                local start_time = time_to_string(syl.start_time +
                                                      line.start_time)
                local end_time = time_to_string(syl.end_time + line.start_time)
                table.insert(ttml, string.format('<span begin="%s" end="%s">',
                                                 start_time, end_time))
                table.insert(ttml, syl.text_stripped)
                table.insert(ttml, '</span>')
                if split_space and space then
                    local hole_time = time_to_string(syl.end_time +
                                                         line.start_time)
                    table.insert(ttml, string.format(
                                     '<span begin="%s" end="%s">', hole_time,
                                     hole_time))
                    table.insert(ttml, space[1].str)
                    table.insert(ttml, '</span>')
                end
            end
        elseif syl.text_stripped ~= '' then
            if syl.duration == 0 and not (syl.text_stripped == ' ') then
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
            table.insert(ttml, string.format('<span begin="%s" end="%s">',
                                             start_time, end_time))
            table.insert(ttml, syl.text_stripped)
            table.insert(ttml, '</span>')
            if split_space and space then
                local hole_time = time_to_string(syl.end_time + line.start_time)
                table.insert(ttml, string.format('<span begin="%s" end="%s">',
                                                 hole_time, hole_time))
                table.insert(ttml, space[1].str)
                table.insert(ttml, '</span>')
            end
        end
        ::continue::
    end

    return table.concat(ttml)
end

function generate_line(line, n)
    local ttml = ""
    local is_bg = line.actor:find('x-bg') ~= nil

    if line.actor:find('x-anti') ~= nil or line.actor:find('x-duet') ~= nil then
        anti = true
    end

    if is_bg then
        ttml = ttml .. '<span ttm:role="x-bg"'
    else
        ttml = ttml .. '<p'
    end

    local start_time = time_to_string(line.start_time)
    local end_time = time_to_string(line.end_time)
    ttml = ttml .. string.format(' begin="%s" end="%s"', start_time, end_time)

    if not is_bg then
        ttml = ttml .. string.format(' ttm:agent="%s" itunes:key="L%d"',
                                     (line.actor:find('x-anti') == nil and
                                         line.actor:find('x-duet') == nil) and
                                         'v1' or 'v2', n)
    end

    ttml = ttml .. '>'

    ttml = ttml .. generate_kara(line)

    if line['roma_line'] ~= nil then
        ttml = ttml .. '<span ttm:role="x-roman">' ..
                   xml_symbol(line['roma_line'].text) .. '</span>'
    end
    if line['ts_line'].n ~= 0 then
        for i = 1, line['ts_line'].n do
            local ts_line = line['ts_line'][i]
            local lang = 'zh-CN'
            if ts_line.actor:find('x-lang') ~= nil then
                lang = ts_line.actor:match('x%-lang%:[%w%-]*'):sub(8)
            end
            ttml =
                ttml .. '<span ttm:role="x-translation" xml:lang="' .. lang ..
                    '">' .. xml_symbol(ts_line.text) .. '</span>'
        end
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
        aegisub.log(key .. ':\t　' .. values[i]:trim() .. '\r\n')
        table.insert(ttml,
                     string.format('<amll:meta key="%s" value="%s"/>', key,
                                   xml_symbol(values[i]:trim())))
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

-- 获取路径
function stripfilename(filename)
    -- return string.match(filename, "(.+)/[^/]*%.%w+$") --*nix system
    return string.match(filename, "(.+)\\[^\\]*%.%w+$") -- windows
end

-- 获取文件名
function strippath(filename)
    -- return string.match(filename, ".+/([^/]*%.%w+)$") -- *nix system
    return string.match(filename, ".+\\([^\\]*%.%w+)$") -- windows
end

function show_marks()
    aegisub.log('\n\n')
    for mark, lines in pairs(marked) do
        aegisub.log(mark .. ': ' .. table.concat(lines, '，') .. '\n')
    end
end

function deep_copy(source)
    if source == nil then return nil end
    if type(source) ~= "table" then return source end
    local target = {}
    local mt = getmetatable(source)
    if mt ~= nil then setmetatable(target, mt) end
    for i, v in pairs(source) do
        if type(v) == "table" then
            target[i] = deep_copy(v)
        else
            target[i] = v
        end
    end
    return target
end

-- ! @bref 插件主函数
-- !
-- ! @param subtitles: Aegisub传入, userdata类型
-- ! @param selected_lines: 选择的行数, Aegisub传入, table类型
-- ! @param active_line: 当前选中的行, number类型
function script_main(subtitles)
    local subs = deep_copy(subtitles)
    subs = pre_process(subs)

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
        }, {class = "edit", name = "appleMusicIds", x = 1, y = 3, width = 16},
        {
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
        }, {
            class = "edit",
            name = "ttmlAuthorGithubs",
            x = 19,
            y = 3,
            width = 16,
            value = "打开脚本更改这里"
        }, {
            class = "label",
            label = "歌曲作者 Github 用户名",
            name = "tag_ttmlAuthorGithubLogin",
            x = 18,
            y = 4,
            width = 1
        }, {
            class = "edit",
            name = "ttmlAuthorGithubLogins",
            x = 19,
            y = 4,
            width = 16,
            value = "打开脚本更改这里"
        }, {
            class = "label",
            label = "时间偏移",
            name = "tag_offset",
            x = 0,
            y = 5,
            width = 1
        }, {
            class = "intedit",
            name = "offset",
            x = 1,
            y = 5,
            width = 1,
            value = script_offset
        },
        {class = "label", label = "ms", name = "ms", x = 2, y = 5, width = 1},
        {
            class = "label",
            label = "空格处理方式",
            name = "tag_space",
            x = 19,
            y = 5,
            width = 1
        }, {
            class = "dropdown",
            name = "space",
            x = 21,
            y = 5,
            width = 1,
            items = {"不处理", "合并", "拆分"},
            value = "拆分"
        },
        {
            class = "checkbox",
            name = "symbol",
            x = 33,
            y = 5,
            width = 1,
            value = true
        }, {
            class = "label",
            label = "合并单个(半/全角)标点",
            name = "tag_symbol",
            x = 34,
            y = 5,
            width = 1
        }
    }

    local btn, result = aegisub.dialog.display(ui_config, {"Start", "Cancel"})

    if btn == false or btn == "Cancel" then aegisub.cancel() end

    local options = deep_copy(result)
    offset = options["offset"]
    split_space = options["space"] == "拆分"
    merge_space = options["space"] == "合并"
    merge_symbol = options["symbol"]

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
            height = 25
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
                                              (title or options.musicNames) ..
                                                  '.ttml',
                                              'TTML files (.ttml)|.ttml')
        if ttml_file ~= nil then
            local file = assert(io.open(ttml_file, "w"))
            file:write(ttml)
            file:close()
        end
    end

    show_marks();
end

aegisub.register_macro(script_name, script_description, script_main);
