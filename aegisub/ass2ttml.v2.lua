local clipboard = require 'aegisub.clipboard'
local util = require 'aegisub.util'
local re = require 'aegisub.re'

-- 函数调用时, 当函数为单个参数, 且值为字符串, 表时可以不加括号
script_name = "ASS2TTML V2 - AMLL歌词格式转换 V2"
script_description = "将ASS格式的字幕文件转为TTML文件"
script_author = "ranhengzhang@gmail.com"
script_version = "0.3-Beta Seth Lowell"
script_modified = "2025-08-26"

include("karaskel.lua")

-- ! @bref 插件主函数
-- !
-- ! @param subtitles: Aegisub传入, userdata类型
-- ! @param selected_lines: 选择的行数, Aegisub传入, table类型
-- ! @param active_line: 当前选中的行, number类型
function script_main(subtitles)
    local config = {
        title = nil,
        offset = nil,
        part_split = nil, -- 是否分段
        lang = nil
    }
    local options = {}
    local marked = {}
    local subs = {}
    local origs = {}
    local trans = {}
    local words = {}
    local roman = {}

    local function add_mark(actor, num, is_bg)
        for mark in actor:gmatch('x%-mark[%w%-]*') do
            if marked[mark] == nil then marked[mark] = {} end
            table.insert(marked[mark], string.format("第%d行%s", num,
                                                     is_bg and '和声部分' or
                                                         ''))
        end
    end

    local function xml_symbol(value)
        value = string.gsub(value, "&", "&amp;"); -- '&' -> "&amp;"
        value = string.gsub(value, "<", "&lt;"); -- '<' -> "&lt;"
        value = string.gsub(value, ">", "&gt;"); -- '>' -> "&gt;"
        value = string.gsub(value, "\"", "&quot;"); -- '"' -> "&quot;"
        value = string.gsub(value, "\'", "&apos;"); -- '"' -> "&quot;"
        return value;
    end

    local function pre_process(subtitles)
        local is_bg = false
        for i = 1, #subtitles do
            local line = table.copy(subtitles[i])
            if subtitles[i].class == "info" then -- 读取脚本信息
                if subtitles[i].key == "Title" then
                    config.title = subtitles[i].value
                elseif subtitles[i].key == "Update Details" then
                    local res = subtitles[i].value:match("[+-]%d+")
                    config.offset = tonumber(res or "0")
                elseif subtitles[i].key == "Original Script" then
                    options.lang = subtitles[i].value
                end
            else -- 读取字幕行
                if line.effect == "" or line.effect == "karaoke" then
                    line.is_bg = is_bg
                    line.raw = line.raw:gsub('%s+', ' ')
                    line.text, _ = re.sub(line.text,
                                          "(?<=\\\\-)([^\\}]+\\}[^\\}]+)(?=\\})",
                                          "\\1\\\\-X")
                    karaskel.preproc_line_text({}, {}, line)
                    if line.style == "orig" then
                        is_bg = line.actor:find("x-bg") and
                                    line.actor:find("x-chor") == nil
                        line.is_bg = is_bg
                        if line.actor:find("x-mark") ~= nil then -- 处理标记
                            if line.is_bg then
                                add_mark(line.actor, #subs, true)
                            else
                                add_mark(line.actor, #subs + 1, false)
                            end
                        end
                        local part = line.actor:find("x-part")
                        if part ~= nil then
                            config.part_split = true
                            line.part =
                                re.find(line.actor, "(?<=x-part:)[A-z]+")[1].str
                        end
                    end
                    if line.is_bg then -- 背景行
                        local parent_line = table.copy(subs[#subs])
                        if line.style == "orig" then
                            line.ts_line = {}
                            line.roma_line = {}
                            parent_line.bg_line = line
                            parent_line.end_time = math.max(
                                                       parent_line.end_time,
                                                       line.end_time)
                        elseif line.style == "roma" then
                            local bg_line = parent_line.bg_line
                            local roma_line = bg_line["roma_line"]
                            local lang = 'ja-Latn'
                            if line.actor:find('x-lang') ~= nil then
                                lang = line.actor:match('x%-lang%:[%w%-]*'):sub(
                                           8)
                            end
                            roman[lang] = {lines = {}}
                            roma_line[lang] = line
                            bg_line["roma_line"] = roma_line
                            parent_line.bg_line = bg_line
                        elseif line.style == "ts" then
                            local bg_line = parent_line.bg_line
                            local ts_line = bg_line["ts_line"]
                            local lang = 'zh-Hans'
                            if line.actor:find('x-lang') ~= nil then
                                lang = line.actor:match('x%-lang%:[%w%-]*'):sub(
                                           8)
                            end
                            trans[lang] = {}
                            ts_line[lang] = line
                            bg_line["ts_line"] = ts_line
                            parent_line.bg_line = bg_line
                        end
                        subs[#subs] = parent_line
                    else -- 主行
                        if line.style == "orig" then
                            line.ts_line = {}
                            line.roma_line = {}
                            if line.actor:find("x-chor") ~= nil then
                                if line.actor:find("x-bg") ~= nil then
                                    line.bg_line = table.copy(line)
                                    line.bg_line.is_bg = true
                                    table.insert(subs, line)
                                else
                                    local anotehr = table.copy(line)
                                    if line.actor:find("x-anti") ~= nil and
                                        line.actor:find("x-duet") ~= nil and
                                        line.actor:find("x-solo") ~= nil then
                                        anotehr.actor = 'x-anti ' ..
                                                            anotehr.actor
                                    else
                                        anotehr.actor = anotehr.actor:gsub(
                                                            "x%-anti", "")
                                        anotehr.actor = anotehr.actor:gsub(
                                                            "x%-duet", "")
                                    end
                                    table.insert(subs, line, anotehr)
                                end
                            else
                                table.insert(subs, line)
                            end
                        elseif line.style == "roma" then
                            local orig_line = table.copy(subs[#subs])
                            local roma_line = orig_line["roma_line"]
                            local lang = 'ja-Latn'
                            if line.actor:find('x-lang') ~= nil then
                                lang = line.actor:match('x%-lang%:[%w%-]*'):sub(
                                           8)
                            end
                            roman[lang] = {lines = {}}
                            roma_line[lang] = line
                            orig_line["roma_line"] = roma_line
                            subs[#subs] = orig_line
                        elseif line.style == "ts" then
                            local orig_line = table.copy(subs[#subs])
                            local ts_line = orig_line["ts_line"]
                            local lang = 'zh-Hans'
                            if line.actor:find('x-lang') ~= nil then
                                lang = line.actor:match('x%-lang%:[%w%-]*'):sub(
                                           8)
                            end
                            trans[lang] = {}
                            ts_line[lang] = line
                            orig_line["ts_line"] = ts_line
                            subs[#subs] = orig_line
                        end
                    end
                end
            end
        end

        if config.part_split then
            local first_part = re.find(subs[1].actor, "(?<=x-part:)[A-z]+")
            if first_part ~= nil then
                config.part_split = first_part[1].str
                subs[1].actor, _ = re.sub(subs[1].actor, "x-part:[A-z]+", "")
            else
                config.part_split = "Verse"
            end
        end
        subs[1].part = nil
    end

    local function time_to_string(time)
        time = time + options.offset
        local res = string.format("%02d.%03d", math.floor(time / 1000) % 60,
                                  time % 1000)
        time = math.floor(time / 60000)
        local hour = ""
        if time >= 60 then
            hour = string.format("%d:", math.floor(time / 60))
            time = time % 60
        end
        local minute = string.format("%02d:", time)

        return hour .. minute .. res
    end

    local function generate_line(line)
        local function generate_kara(syls)
            local text = {}

            for i = 1, #syls do
                local syl = syls[i]
                syl.stext = xml_symbol(syl.stext)
                if syl.sfx == "text" then
                    table.insert(text, syl.stext)
                elseif options.optimize and
                    (syl.sbegin == syl.send or syl.stext == "") then
                    table.insert(text, syl.stext)
                else
                    table.insert(text,
                                 string.format(
                                     '<span begin="%s" end="%s">%s</span>',
                                     time_to_string(syl.sbegin),
                                     time_to_string(syl.send), syl.stext))
                end
            end

            return table.concat(text)
        end

        local text = {}

        table.insert(text, [[<p]])

        if line.bg_line then
            line.start_time = math.min(line.start_time, line.bg_line.start_time)
            line.end_time = math.max(line.end_time, line.bg_line.end_time)
        end
        local start_time = time_to_string(line.start_time)
        local end_time = time_to_string(line.end_time)
        table.insert(text, string.format(' begin="%s" end="%s"', start_time,
                                         end_time))

        table.insert(text, string.format(' ttm:agent="%s" itunes:key="L%d"',
                                         line.is_other and 'v2' or 'v1', line.L))

        table.insert(text, '>')

        table.insert(text, generate_kara(line.syls))

        if line.bg_line then
            table.insert(text, [[ <span ttm:role="x-bg">]] ..
                             generate_kara(line.bg_line.syls) .. [[</span>]])
        end

        table.insert(text, line.is_bg and [[</span>]] or [[</p>]])

        return table.concat(text)
    end

    local function generate_body()
        local text = {}
        table.insert(text, string.format('<body dur="%s">',
                                         time_to_string(origs[#origs].end_time)))

        local lines = {}
        table.insert(lines, string.format('<div begin="%s" end="',
                                          time_to_string(origs[1].start_time)))
        table.insert(lines, "00:00.000")
        table.insert(lines, string.format('"%s>', config.part_split and
                                              string.format(
                                                  ' itunes:song-part="%s"',
                                                  config.part_split) or ''))
        for i = 1, #origs do
            local line = origs[i]
            if line.part then
                lines[2] = time_to_string(origs[i - 1].end_time)
                table.insert(text, table.concat(lines))
                lines = {}
                table.insert(lines, string.format('</div><div begin="%s" end="',
                                                  time_to_string(line.start_time)))
                table.insert(lines, "00:00.000")
                table.insert(lines, string.format('"%s>', string.format(
                                                      ' itunes:song-part="%s"',
                                                      line.part)))
            end
            table.insert(lines, generate_line(line))
        end
        lines[2] = time_to_string(origs[#origs].end_time)
        table.insert(text, table.concat(lines))
        table.insert(text, string.format([[</div></body>]]))

        return table.concat(text)
    end

    local function split(str)
        local rst = {}
        str:gsub('[^,&/]+', function(w) rst[#rst + 1] = w:trim(); end)
        return rst
    end

    local function generate_meta(key, value)
        local text = {}
        local values = split(value)

        for i = 1, #values do
            aegisub.log(key .. ':\t　' .. values[i]:trim() .. '\r\n')
            table.insert(text,
                         string.format('<amll:meta key="%s" value="%s"/>', key,
                                       xml_symbol(values[i]:trim()):trim()))
        end

        return table.concat(text)
    end

    local function generate_translations()
        local text = {}

        for lang, lines in pairs(trans) do
            table.insert(text, string.format(
                             [[<translation type="subtitle" xml:lang="%s">]],
                             lang))
            for i = 1, #lines do
                local line = lines[i]
                table.insert(text, string.format([[<text for="L%d">%s]], line.L,
                                                 xml_symbol(line.text or ''):trim()))
                if line.bg_line then
                    table.insert(text, string.format(
                                     [[ <span xmlns:ttm="http://www.w3.org/ns/ttml#metadata" ttm:role="x-bg" xmlns="http://www.w3.org/ns/ttml">(%s)</span>]],
                                     xml_symbol(line.bg_line):trim()))
                end
                table.insert(text, [[</text>]])
            end
            table.insert(text, [[</translation>]])
        end
        for lang, word in pairs(words) do
            table.insert(text, string.format(
                             [[<translation type="replacement" xml:lang="%s">]],
                             lang))
            table.insert(text, word)
            table.insert(text, [[</translation>]])
        end

        if #text > 0 then
            return [[<translations>]] .. table.concat(text) ..
                       [[</translations>]]
        else
            return [[<translations />]]
        end
    end

    local function generate_transliterations()
        local function generate_syls(syls, word)
            local text = {}
            for i = 1, #syls do
                local syl = syls[i]
                syl.stext = xml_symbol(syl.stext)
                if syl.sfx == "text" then
                    table.insert(text, syl.stext)
                elseif options.optimize and
                    (syl.sbegin == syl.send or syl.stext:trim() == "") then
                    table.insert(text, syl.stext)
                else
                    table.insert(text, string.format(
                                     [[<span begin="%s" end="%s" xmlns="http://www.w3.org/ns/ttml">%s</span>]],
                                     time_to_string(syl.sbegin),
                                     time_to_string(syl.send),
                                     word and syl.stext:trim() or syl.stext))
                end
            end
            return table.concat(text)
        end

        local text = {}

        table.insert(text, [[<transliterations>]])
        for lang, roma in pairs(roman) do
            if #roma.lines ~= 0 then
                local word = roma.replace == true
                local temp = {}

                if not word then
                    table.insert(text, string.format(
                                     [[<transliteration xml:lang="%s">]], lang))
                end
                for i = 1, #roma.lines do
                    local line = roma.lines[i]

                    table.insert(temp,
                                 string.format([[<text for="L%d">]], line.L))
                    table.insert(temp, generate_syls(line.syls, word))
                    if line.bg_line ~= nil then
                        table.insert(temp,
                                     [[ <span xmlns:ttm="http://www.w3.org/ns/ttml#metadata" ttm:role="x-bg" xmlns="http://www.w3.org/ns/ttml">]] ..
                                         generate_syls(line.bg_line, word) ..
                                         [[</span>]])
                    end
                    table.insert(temp, [[</text>]])
                end

                if word then
                    words[lang] = table.concat(temp)
                else
                    table.insert(text, table.concat(temp))
                    table.insert(text, [[</transliteration>]])
                end
            end
        end
        table.insert(text, [[</transliterations>]])

        return table.concat(text)
    end

    local function generate_iTunesMetadata()
        local transliterations = generate_transliterations()
        local translations = generate_translations()
        if translations ~= [[<translations />]] or transliterations then
            return
                [[<iTunesMetadata xmlns="http://music.apple.com/lyric-ttml-internal">]] ..
                    translations .. transliterations .. [[</iTunesMetadata>]]
        else
            return ''
        end
    end

    local function generate_head()
        local ttml = {}

        table.insert(ttml, '<ttm:agent type="person" xml:id="v1"/>')

        if options.anti then
            table.insert(ttml, '<ttm:agent type="other" xml:id="v2"/>')
        end

        local ids = {
            'ncmMusicId', 'qqMusicId', 'spotifyId', 'appleMusicId', 'isrc'
        }
        for i = 1, #ids do
            if options[ids[i] .. 's']:trim() ~= '' then
                table.insert(ttml, generate_meta(ids[i], options[ids[i] .. 's']))
            end
        end

        local keys = {
            'musicName', 'artists', 'album', 'ttmlAuthorGithub',
            'ttmlAuthorGithubLogin'
        }
        for i = 1, #keys do
            table.insert(ttml, generate_meta(keys[i], options[keys[i] .. 's']))
        end

        return '<head><metadata>' .. table.concat(ttml) ..
                   generate_iTunesMetadata() .. '</metadata></head>'
    end

    -- 获取路径
    local function stripfilename(filename)
        -- return string.match(filename, "(.+)/[^/]*%.%w+$") --*nix system
        return string.match(filename, "(.+)\\[^\\]*%.%w+$") -- windows
    end

    -- 获取文件名
    local function strippath(filename)
        -- return string.match(filename, ".+/([^/]*%.%w+)$") -- *nix system
        return string.match(filename, ".+\\([^\\]*%.%w+)$") -- windows
    end

    local function show_marks()
        aegisub.log('\n\n')
        for mark, lines in pairs(marked) do
            aegisub.log(mark .. ': ' .. table.concat(lines, '，') .. '\n')
        end
    end

    local function collect_syls(line)
        local function count_furi(furis)
            local n = 0
            for i = 1, furis.n do
                local furi = furis[i]
                if furi.text_stripped:trim() ~= '' then n = n + 1 end
            end
            return n
        end

        local pre_symbols = "([<（【〔［｛〈《｢「『“‘"
        local syls = {}

        for i = 1, #line.kara do
            local syl = util.copy(line.kara[i])

            if syl.inline_fx == "merge" or syl.inline_fx == "M" and #syls > 0 then
                local stext = syl.text_stripped
                local last = syls[#syls]

                while last.stext:trim() == "" and #syls > 0 do
                    stext = last.stext .. stext
                    table.remove(syls)
                    last = syls[#syls]
                end
                last.stext = last.stext .. stext
                last.send = syl.end_time + line.start_time
                syls[#syls] = last
            elseif syl.inline_fx == "text" or syl.inline_fx == "T" then
                table.insert(syls, {stext = syl.text_stripped, sfx = "text"})
            elseif syl.inline_fx == "zero" or syl.inline_fx == "Z" then
                local space = nil
                if options.split_space then
                    space = re.find(syl.text_stripped, "(?<=.)(\\ |\\　)$")
                    syl.text_stripped = re.sub(syl.text_stripped,
                                               "(\\ |\\　)$", "")
                end

                local start_time = syl.start_time + line.start_time
                local end_time = syl.start_time + line.start_time + 5
                table.insert(syls, {
                    sbegin = start_time,
                    send = end_time,
                    stext = syl.text_stripped
                })
                if options.split_space and space then
                    local hole_time = syl.end_time + line.start_time
                    table.insert(syls, {
                        sbegin = hole_time,
                        send = hole_time,
                        stext = space[1].str
                    })
                end
            else
                local space = nil
                if options.split_space then
                    space = re.find(syl.text_stripped, "^(\\ |\\　)(?=.)")

                    if space then
                        syl.text_stripped, _ =
                            re.sub(syl.text_stripped, "^(\\ |\\　)", "")
                        local hole_time = syl.start_time + line.start_time
                        table.insert(syls, {
                            sbegin = hole_time,
                            send = hole_time,
                            stext = space[1].str
                        })
                    end

                    space = re.find(syl.text_stripped, "(?<=.)(\\ |\\　)$")
                    if space then
                        syl.text_stripped =
                            re.sub(syl.text_stripped, "(\\ |\\　)$", "")
                    end
                end
                if syl.duration == 0 then
                    if i < #line.kara and line.kara[i + 1].duration == 0 and
                        (syl.inline_fx ~= "zero" and syl.inline_fx ~= "Z") then -- 向后合并连续无时长音节
                        local next_syl = line.kara[i + 1]
                        next_syl.text_stripped =
                            syl.text_stripped .. line.kara[i + 1].text_stripped
                        line.kara[i + 1] = next_syl
                        goto continue
                    end
                    if unicode.len(syl.text_stripped:trim()) == 0 and
                        options.merge_space then -- 合并时长为 0 的空格
                        if i == 1 and #line.kara > 2 then
                            goto continue
                        else
                            syls[#syls].stext =
                                syls[#syls].stext .. syl.text_stripped
                        end
                    elseif unicode.len(syl.text_stripped:trim()) == 1 and
                        options.merge_symbol then -- 合并时长为 0 的单个非空字符
                        if i == 1 and #line.kara > 2 then -- 首字符向后合并
                            line.kara[2].text_stripped =
                                syl.text_stripped .. line.kara[2].text_stripped
                        elseif i > 1 and i < #line.kara and
                            pre_symbols:find(syl.text_stripped) ~= nil then -- 特殊字符向后合并
                            line.kara[i + 1].text_stripped =
                                syl.text_stripped ..
                                    line.kara[i + 1].text_stripped
                        else
                            syls[#syls].stext =
                                syls[#syls].stext .. syl.text_stripped
                            if options.split_space and space then
                                local hole_time = syl.end_time + line.start_time
                                table.insert(syls, {
                                    sbegin = hole_time,
                                    send = hole_time,
                                    stext = space[1].str
                                })
                            end
                        end
                    else -- 时长为 0 的不合并字符
                        local start_time = syl.start_time + line.start_time
                        local end_time = syl.end_time + line.start_time + 5
                        table.insert(syls, {
                            sbegin = start_time,
                            send = end_time,
                            stext = syl.text_stripped
                        })
                        if options.split_space and space then
                            table.insert(syls, {
                                sbegin = end_time,
                                send = end_time,
                                stext = space[1].str
                            })
                        end
                    end
                elseif syl.text_stripped ~= '' then
                    if syl.duration == 0 and not (syl.text_stripped == ' ') then
                        syl.end_time = syl.end_time + 5
                    end

                    local start_time = syl.start_time + line.start_time
                    local end_time = syl.end_time + line.start_time
                    table.insert(syls, {
                        sbegin = start_time,
                        send = end_time,
                        stext = syl.text_stripped,
                        furi = syl.furi.n ~= 0 and count_furi(syl.furi) or 1
                    })
                    if options.split_space and space then
                        local hole_time = syl.end_time + line.start_time
                        table.insert(syls, {
                            sbegin = hole_time,
                            send = hole_time,
                            stext = space[1].str
                        })
                    end
                end
            end
            ::continue::
        end

        if line.is_bg then
            syls[1].stext = '(' .. syls[1].stext
            syls[#syls].stext = syls[#syls].stext .. ')'
        end

        return syls
    end

    local function collect_roma(main_syls, roma_line)
        local function insert_roma(syl)
            local primary = nil
            local secondary = nil

            for i = 1, #main_syls do
                local main_syl = main_syls[i]
                if main_syl.furi ~= nil and main_syl.furi ~= 0 and
                    re.find(main_syl.stext, "^\\s*$") == nil then
                    if main_syl.send - main_syl.sbegin > 5 then
                        primary = i
                        break
                    else
                        secondary = i
                    end
                end
            end

            if primary ~= nil then
                main_syls[primary].roma =
                    (main_syls[primary].roma or "") .. syl.text_stripped
                main_syls[primary].furi = main_syls[primary].furi - 1
            elseif secondary ~= nil then
                main_syls[secondary].roma =
                    (main_syls[secondary].roma or "") .. syl.text_stripped
                main_syls[secondary].furi = main_syls[secondary].furi - 1
            end
        end

        local roma_syls = {}
        local packup = {}

        for i = 1, #main_syls do packup[i] = main_syls[i].furi end

        for i = 1, #roma_line.kara do
            local roma_syl = roma_line.kara[i]
            insert_roma(roma_syl)
        end

        for i = 1, #main_syls do
            local main_syl = main_syls[i]
            table.insert(roma_syls, {
                sbegin = main_syl.sbegin,
                send = main_syl.send,
                stext = (main_syl.roma and main_syl.roma:upper():trim() ~=
                    main_syl.stext:upper():trim()) and main_syl.roma or "" -- 原为 main_syl.stext
            })
            main_syls[i].furi = packup[i]
            main_syls[i].roma = nil
        end

        if roma_line.is_bg then
            if roma_syls[1].stext:find('^%(') == nil then
                roma_syls[1].stext = '(' .. roma_syls[1].stext
            end
            if roma_syls[#roma_syls].stext:find('%)$') == nil then
                roma_syls[#roma_syls].stext = roma_syls[#roma_syls].stext .. ')'
            end
        end

        return roma_syls
    end

    local function process_ttml()
        local index = 1
        for i = 1, #subs do
            local line = table.copy(subs[i])

            -- 处理主行正文
            local orig = {
                is_other = line.actor:find('x-anti') ~= nil or
                    line.actor:find('x-duet') ~= nil or
                    line.actor:find('x-solo'),
                syls = collect_syls(line),
                L = index,
                start_time = line.start_time,
                end_time = line.end_time,
                part = line.part
            }
            if orig.is_other then options.anti = true end

            -- 处理主行翻译
            if line.ts_line ~= nil then
                for lang, ts_line in pairs(line.ts_line) do
                    table.insert(trans[lang],
                                 {L = index, text = ts_line.text:trim()})
                end
            end

            -- 处理主行音译
            if line.roma_line ~= nil then
                for lang, roma_line in pairs(line.roma_line) do
                    table.insert(roman[lang].lines, {
                        L = index,
                        syls = collect_roma(orig.syls, roma_line),
                        start_time = roma_line.start_time,
                        end_time = roma_line.end_time
                    })
                    if roma_line.actor:find('x-replace') ~= nil then
                        roman[lang].replace = true
                    end
                end
            end

            -- 处理和声行
            if line.bg_line ~= nil then
                local bg_line = table.copy(line.bg_line)

                -- 处理和声行正文
                orig.bg_line = {
                    syls = collect_syls(bg_line),
                    start_time = bg_line.start_time,
                    end_time = bg_line.end_time
                }

                -- 处理和声行翻译
                if bg_line.ts_line ~= nil then
                    for lang, ts_line in pairs(bg_line['ts_line']) do
                        if #trans[lang] == 0 or trans[lang][#trans[lang]].L ~=
                            index then
                            table.insert(trans[lang], {L = index, text = ""})
                        end
                        trans[lang][#trans[lang]].bg_line = ts_line.text:trim()
                    end
                end

                -- 处理和声行音译
                if bg_line.roma_line ~= nil then
                    for lang, roma_line in pairs(bg_line['roma_line']) do
                        if #roman[lang].lines == 0 or
                            roman[lang].lines[#roman[lang].lines].L ~= index then
                            table.insert(roman[lang].lines, {
                                L = index,
                                syls = {},
                                start_time = bg_line.roma_line.start_time,
                                end_time = bg_line.roma_line.end_time
                            })
                        end
                        roman[lang].lines[#roman[lang].lines].bg_line =
                            collect_roma(orig.bg_line.syls, roma_line)
                    end
                end
            end
            table.insert(origs, orig)
            index = index + 1
        end
    end

    local function print_ttml()
        local text = {}
        if options.lang == nil then options.lang = "zh-Hans" end
        table.insert(text, string.format(
                         [[<tt xmlns="http://www.w3.org/ns/ttml" xmlns:itunes="http://music.apple.com/lyric-ttml-internal" xmlns:ttm="http://www.w3.org/ns/ttml#metadata" itunes:timing="Word" xml:lang="%s">]],
                         options.lang))
        table.insert(text, generate_head())
        table.insert(text, generate_body())
        table.insert(text, [[</tt>]])

        return table.concat(text)
    end

    pre_process(subtitles)

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
        }, {
            class = "edit",
            name = "musicNames",
            x = 19,
            y = 2,
            width = 16,
            value = config.title
        }, {
            class = "label",
            label = "歌词作者 Github ID",
            name = "tag_ttmlAuthorGithubs",
            x = 18,
            y = 3,
            width = 1
        }, {
            class = "edit",
            name = "ttmlAuthorGithubs",
            x = 19,
            y = 3,
            width = 16,
            value = "打开脚本修改这里"
        }, {
            class = "label",
            label = "歌曲作者 Github 用户名",
            name = "tag_ttmlAuthorGithubLogins",
            x = 18,
            y = 4,
            width = 1
        }, {
            class = "edit",
            name = "ttmlAuthorGithubLogins",
            x = 19,
            y = 4,
            width = 16,
            value = "打开脚本修改这里"
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
            value = config.offset
        },
        {class = "label", label = "ms", name = "ms", x = 2, y = 5, width = 1},
        {
            class = "label",
            label = "歌词语言",
            name = "tag_lang",
            x = 14,
            y = 5,
            width = 1
        },
        {
            class = "edit",
            name = "lang",
            x = 16,
            y = 5,
            width = 1,
            value = options.lang
        }, {
            class = "label",
            label = "空格处理方式",
            name = "tag_space",
            x = 18,
            y = 5,
            width = 1
        }, {
            class = "dropdown",
            name = "space",
            x = 19,
            y = 5,
            width = 1,
            items = {"不处理", "合并", "拆分"},
            value = "拆分"
        }, {
            class = "checkbox",
            name = "merge_symbol",
            x = 30,
            y = 5,
            width = 1,
            value = true
        }, {
            class = "label",
            label = "合并单个(半/全角)标点",
            name = "tag_merge_symbol",
            x = 31,
            y = 5,
            width = 1
        }, {
            class = "checkbox",
            name = "optimize",
            x = 33,
            y = 5,
            width = 1,
            value = false
        }, {
            class = "label",
            label = "优化 TTML 结构",
            name = "tag_optimize",
            x = 34,
            y = 5,
            width = 1
        }
    }

    local btn, result = aegisub.dialog.display(ui_config, {"Start", "Cancel"})

    if btn == false or btn == "Cancel" then aegisub.cancel() end

    options = util.deep_copy(result)
    options.split_space = options["space"] == "拆分"
    options.merge_space = options["space"] == "合并"

    if #subs == 0 then aegisub.cancel() end

    process_ttml()

    local ttml = print_ttml()

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
                                              (config.title or
                                                  options.musicNames) .. '.ttml',
                                              'TTML files (*.ttml)|*.ttml')
        if ttml_file ~= nil then
            local file = assert(io.open(ttml_file, "w"))
            file:write(ttml)
            file:close()
        end
    end

    show_marks();
end

aegisub.register_macro(script_name, script_description, script_main);
