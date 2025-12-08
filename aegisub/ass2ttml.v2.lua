-- ======================================================================
-- ASS2TTML V2 - AMLL歌词格式转换脚本
-- 功能：将Aegisub ASS格式字幕文件转换为TTML (Timed Text Markup Language) 格式
-- 作者：ranhengzhang@gmail.com
-- 版本：0.1
-- 创建日期：2025-08-26
-- 修改记录：
--   - 支持多语言翻译和音译
--   - 添加和声处理功能
--   - 优化TTML结构生成
-- ======================================================================

-- 导入Aegisub核心模块
local clipboard = require 'aegisub.clipboard'
local util = require 'aegisub.util'
local re = require 'aegisub.re'

-- 脚本元数据定义
-- 函数调用时, 当函数为单个参数, 且值为字符串, 表时可以不加括号
script_name = "ASS2TTML V2 - AMLL歌词格式转换 V2"
script_description = "将ASS格式的字幕文件转为TTML文件"
script_author = "ranhengzhang@gmail.com"
script_version = "1.0-Release Banyue"
script_modified = "2025-12-09"

-- 导入卡拉OK处理库
include("karaskel.lua")

-- ! @bref 插件主函数 - 处理ASS到TTML的完整转换流程
-- !
-- ! @param subtitles: Aegisub传入的字幕数据, userdata类型
-- ! @param selected_lines: 选择的行数, Aegisub传入, table类型
-- ! @param active_line: 当前选中的行, number类型
function script_main(subtitles)
    -- 配置参数初始化
    local config = {
        title = nil,           -- 歌曲标题
        offset = nil,          -- 时间偏移量
        part_split = nil,      -- 是否分段处理
        lang = nil             -- 语言设置
    }

    -- 数据处理容器
    local options = {
        lang = "zh-Hans"
    }
    local marked = {}          -- 标记信息存储
    local subs = {}            -- 处理后的字幕行
    local origs = {}           -- 原始字幕行
    local trans = {}           -- 翻译数据
    local words = {}           -- 单词数据
    local roman = {}           -- 罗马音数据

    -- ======================================================================
    -- 辅助函数：添加标记信息
    -- @param actor: 演员字段，包含标记信息
    -- @param num: 行号
    -- @param is_bg: 是否为背景行
    -- ======================================================================
    local function add_mark(actor, num, is_bg)
        for mark in actor:gmatch('x%-mark[%w%-]*') do
            if marked[mark] == nil then marked[mark] = {} end
            table.insert(marked[mark], string.format("第%d行%s", num,
                                                     is_bg and '和声部分' or
                                                         ''))
        end
    end

    -- ======================================================================
    -- XML符号转义函数
    -- 将特殊字符转换为XML实体以避免解析错误
    -- @param value: 需要转义的字符串
    -- @return: 转义后的字符串
    -- ======================================================================
    local function xml_symbol(value)
        value = string.gsub(value, "&", "&amp;"); -- '&' -> "&amp;"
        value = string.gsub(value, "<", "&lt;"); -- '<' -> "&lt;"
        value = string.gsub(value, ">", "&gt;"); -- '>' -> "&gt;"
        value = string.gsub(value, "\"", "&quot;"); -- '"' -> "&quot;"
        value = string.gsub(value, "\'", "&apos;"); -- '\'' -> "&apos;"
        return value;
    end

    -- ======================================================================
    -- 预处理函数：解析和准备字幕数据
    -- 提取脚本信息、处理标记、分离主行和背景行
    -- @param subtitles: 原始字幕数据
    -- ======================================================================
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
                    if line.style == "ts" and line.actor and line.actor:find("x%-replace") then
                        line.style = "roma"
                    end
                    line.is_bg = is_bg
                    line.raw = line.raw:gsub('%s+', ' ')
                    -- 处理卡拉OK音节标记
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
                    if line.is_bg then -- 背景行处理
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
                            local lang = options.lang .. '-Latn'
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
                    else -- 主行处理
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
                            local lang = options.lang .. '-Latn'
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

        -- 处理分段信息
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

    -- ======================================================================
    -- 时间格式化函数
    -- 将毫秒时间转换为TTML标准时间格式 (HH:MM:SS.mmm)
    -- @param time: 毫秒时间值
    -- @return: 格式化后的时间字符串
    -- ======================================================================
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

    local function max_end_time(line)
        return line['bg_line'] and
                   math.max(line.end_time, line.bg_line.end_time) or
                   line.end_time
    end

    local function min_start_time(line)
        return line['bg_line'] and
                   math.min(line.start_time, line.bg_line.start_time) or
                   line.start_time
    end

    -- ======================================================================
    -- 生成TTML行函数
    -- 将单个字幕行转换为TTML格式的<p>标签
    -- @param line: 字幕行数据
    -- @return: TTML格式的字符串
    -- ======================================================================
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

        -- 处理时间范围
        if line.bg_line then
            line.start_time = math.min(line.start_time, line.bg_line.start_time)
            line.end_time = math.max(line.end_time, line.bg_line.end_time)
        end

        table.insert(text, string.format(' begin="%s" end="%s"', time_to_string(min_start_time(line)),
                                         time_to_string(max_end_time(line))))

        table.insert(text, string.format(' ttm:agent="%s" itunes:key="L%d"',
                                         line.is_other and 'v2' or 'v1', line.L))

        table.insert(text, '>')

        table.insert(text, generate_kara(line.syls))

        -- 处理和声部分
        if line.bg_line then
            table.insert(text, [[ <span ttm:role="x-bg">]] ..
                             generate_kara(line.bg_line.syls) .. [[</span>]])
        end

        table.insert(text, line.is_bg and [[</span>]] or [[</p>]])

        return table.concat(text)
    end

    -- ======================================================================
    -- 生成TTML主体函数
    -- 构建完整的TTML <body> 部分，包含所有字幕行
    -- @return: TTML body部分的字符串
    -- ======================================================================
    local function generate_body()
        local text = {}
        table.insert(text, string.format('<body dur="%s">',
                                         time_to_string(max_end_time(origs[#origs]))))

        local lines = {}
        table.insert(lines, string.format('<div begin="%s" end="',
                                          time_to_string(min_start_time(origs[1]))))
        table.insert(lines, "00:00.000")
        table.insert(lines, string.format('"%s>', config.part_split and
                                              string.format(
                                                  ' itunes:song-part="%s"',
                                                  config.part_split) or ''))
        for i = 1, #origs do
            local line = origs[i]
            if line.part then
                lines[2] = time_to_string(max_end_time(origs[i - 1]))
                table.insert(text, table.concat(lines))
                lines = {}
                table.insert(lines, string.format('</div><div begin="%s" end="',
                                                  time_to_string(min_start_time(line))))
                table.insert(lines, "00:00.000")
                table.insert(lines, string.format('"%s>', string.format(
                                                      ' itunes:song-part="%s"',
                                                      line.part)))
            end
            table.insert(lines, generate_line(line))
        end
        lines[2] = time_to_string(max_end_time(origs[#origs]))
        table.insert(text, table.concat(lines))
        table.insert(text, string.format([[</div></body>]]))

        return table.concat(text)
    end

    -- ======================================================================
    -- 字符串分割函数
    -- 按逗号、&、/等分隔符分割字符串
    -- @param str: 输入字符串
    -- @return: 分割后的字符串数组
    -- ======================================================================
    local function split(str)
        local rst = {}
        str:gsub('[^,&/]+', function(w) rst[#rst + 1] = w:trim(); end)
        return rst
    end

    -- ======================================================================
    -- 生成元数据函数
    -- 创建TTML格式的元数据标签
    -- @param key: 元数据键
    -- @param value: 元数据值
    -- @return: 元数据XML字符串
    -- ======================================================================
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

    -- ======================================================================
    -- 生成翻译部分函数
    -- 构建TTML的翻译和替换部分
    -- @return: 翻译部分的XML字符串
    -- ======================================================================
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

    -- ======================================================================
    -- 生成音译部分函数
    -- 构建TTML的音译部分，支持多语言罗马音
    -- @return: 音译部分的XML字符串
    -- ======================================================================
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
                                     word and syl.stext or syl.stext))
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

    -- ======================================================================
    -- 生成iTunes元数据函数
    -- 构建iTunes专用的元数据部分
    -- @return: iTunes元数据XML字符串
    -- ======================================================================
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

    -- ======================================================================
    -- 生成TTML头部函数
    -- 构建TTML文档的<head>部分，包含所有元数据
    -- @return: TTML head部分的字符串
    -- ======================================================================
    local function generate_head()
        local ttml = {}

        table.insert(ttml, '<ttm:agent type="person" xml:id="v1"/>')

        if options.anti then
            table.insert(ttml, '<ttm:agent type="other" xml:id="v2"/>')
        end

        -- 生成音乐平台ID元数据
        local ids = {
            'ncmMusicId', 'qqMusicId', 'spotifyId', 'appleMusicId', 'isrc'
        }
        for i = 1, #ids do
            if options[ids[i] .. 's']:trim() ~= '' then
                table.insert(ttml, generate_meta(ids[i], options[ids[i] .. 's']))
            end
        end

        -- 生成基本信息元数据
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

    -- ======================================================================
    -- 文件路径处理函数
    -- 从完整路径中提取目录路径
    -- @param filename: 完整文件名
    -- @return: 目录路径
    -- ======================================================================
    local function stripfilename(filename)
        -- return string.match(filename, "(.+)/[^/]*%.%w+$") --*nix system
        return string.match(filename, "(.+)\\[^\\]*%.%w+$") -- windows
    end

    -- ======================================================================
    -- 文件名提取函数
    -- 从完整路径中提取纯文件名
    -- @param filename: 完整路径
    -- @return: 文件名
    -- ======================================================================
    local function strippath(filename)
        -- return string.match(filename, ".+/([^/]*%.%w+)$") -- *nix system
        return string.match(filename, ".+\\([^\\]*%.%w+)$") -- windows
    end

    -- ======================================================================
    -- 显示标记信息函数
    -- 在日志中输出所有标记信息
    -- ======================================================================
    local function show_marks()
        aegisub.log('\n\n')
        for mark, lines in pairs(marked) do
            aegisub.log(mark .. ': ' .. table.concat(lines, '，') .. '\n')
        end
    end

    -- ======================================================================
    -- 收集音节数据函数
    -- 处理卡拉OK音节，合并、拆分和优化音节数据
    -- @param line: 字幕行数据
    -- @return: 处理后的音节数组
    -- ======================================================================
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

            -- 合并音节处理
            if syl.inline_fx == "merge" or syl.inline_fx == "M" and #syls > 0 then
                local stext = syl.text_stripped
                local last = syls[#syls]

                -- [修改开始] 计算当前正在被合并的音节原本包含的 furi 数量
                local current_furi_count = ((syl.furi.n ~= 0) and count_furi(syl.furi) or 1)
                -- [修改结束]

                while last.stext:trim() == "" and #syls > 0 do
                    stext = last.stext .. stext
                    table.remove(syls)
                    last = syls[#syls]
                end
                last.stext = last.stext .. stext
                last.send = syl.end_time + line.start_time

                -- [修改开始] 将 furi 计数累加到前一个音节上
                last.furi = (last.furi or 0) + current_furi_count
                -- [修改结束]

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
                        furi = ((syl.furi.n ~= 0) and count_furi(syl.furi) or 1)
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

        -- 处理和声行的括号
        if line.is_bg then
            syls[1].stext = '(' .. syls[1].stext
            syls[#syls].stext = syls[#syls].stext .. ')'
        end

        return syls
    end

    -- ======================================================================
    -- 收集罗马音数据函数
    -- 将罗马音数据与主音节对齐
    -- @param main_syls: 主音节数据
    -- @param roma_line: 罗马音行数据
    -- @return: 对齐后的罗马音数据
    -- ======================================================================
        -- ======================================================================
    -- 收集罗马音数据函数
    -- 将罗马音数据与主音节对齐
    -- @param main_syls: 主音节数据
    -- @param roma_line: 罗马音行数据
    -- @param line_num:  (新增) 当前行号，用于日志输出
    -- @return: 对齐后的罗马音数据
    -- ======================================================================
    local function collect_roma(main_syls, roma_line, line_num)

        -- [日志] 输出行号
        if line_num then
            aegisub.log(string.format("\nLine %d Start:\n", line_num))
        end

        local function insert_roma(syl)
            local index = -1

            for i = 1, #main_syls do
                local main_syl = main_syls[i]
                if type(main_syl.furi) == "number" and main_syl.furi > 0 and main_syl.stext:trim() ~= "" then
                    index = i
                    break
                end
            end

            if index ~= -1 then
                main_syls[index].roma = (main_syls[index].roma or "") .. syl.text_stripped
                main_syls[index].furi = main_syls[index].furi - 1

                -- [日志] 记录被吸收的 furi 片段到临时表 debug_parts 中
                if main_syls[index].debug_parts == nil then main_syls[index].debug_parts = {} end
                table.insert(main_syls[index].debug_parts, syl.text_stripped)
            end
        end

        local roma_syls = {}
        local packup = {}

        for i = 1, #main_syls do packup[i] = main_syls[i].furi end

        for i = 1, #roma_line.kara do
            local roma_syl = roma_line.kara[i]
            if roma_syl.text_stripped ~= "" then
                insert_roma(roma_syl)
            end
        end

        for i = 1, #main_syls do
            local main_syl = main_syls[i]

            -- [日志] 输出当前音节及其对应的罗马音列表
            if main_syl.stext:trim() ~= "" then
                aegisub.log(string.format("syl: %s\n", main_syl.stext))
                if main_syl.debug_parts then
                    for index, furi in ipairs(main_syl.debug_parts) do
                        aegisub.log(string.format("%s [%s]\n", (index == #main_syl.debug_parts-1) and "├─" or "└─", furi))
                    end
                end
            end
            -- [日志] 清理临时数据（可选）
            main_syl.debug_parts = nil

            table.insert(roma_syls, {
                sbegin = main_syl.sbegin,
                send = main_syl.send,
                stext = ((main_syl.roma and main_syl.roma:upper():trim() ~=
                    main_syl.stext:upper():trim()) or options.keep_roma) and main_syl.roma or ""
            })
            main_syls[i].furi = packup[i]
            main_syls[i].roma = nil
        end

        for i = 1, #roma_syls do
            if i > 1 and roma_syls[i].stext == "" and re.find(roma_syls[i-1].stext, ".(\\ |\\　)(?=$)") then
                roma_syls[i].stext = re.find(roma_syls[i-1].stext, "(\\ |\\　)(?=$)")[1].str
                roma_syls[i-1].stext = re.sub(roma_syls[i-1].stext, "(\\ |\\　)(?=$)", "")
            end
        end

        -- 处理和声行的罗马音括号
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


    -- ======================================================================
    -- 处理TTML数据函数
    -- 主数据处理流程，整合所有字幕行和辅助数据
    -- ======================================================================
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
                        -- [修改] 传入 index 参数
                        syls = collect_roma(orig.syls, roma_line, index),
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
                        -- [修改] 传入 index 参数
                        roman[lang].lines[#roman[lang].lines].bg_line =
                            collect_roma(orig.bg_line.syls, roma_line, index)
                    end
                end
            end
            table.insert(origs, orig)
            index = index + 1
        end
    end

    -- ======================================================================
    -- 生成完整TTML函数
    -- 构建完整的TTML文档
    -- @return: 完整的TTML XML字符串
    -- ======================================================================
    local function print_ttml()
        local text = {}
        if options.lang == nil then options.lang = "zh-Hans" end
        table.insert(text, string.format(
                         [[<tt xmlns="http://www.w3.org/ns/ttml" xmlns:amll="http://www.example.com/ns/amll" xmlns:itunes="http://music.apple.com/lyric-ttml-internal" xmlns:ttm="http://www.w3.org/ns/ttml#metadata" itunes:timing="Word" xml:lang="%s">]],
                         options.lang))
        table.insert(text, generate_head())
        table.insert(text, generate_body())
        table.insert(text, [[</tt>]])

        return table.concat(text)
    end

    -- ======================================================================
    -- 主执行流程
    -- ======================================================================

    -- 1. 预处理字幕数据
    pre_process(subtitles)

    -- 2. 构建用户界面配置
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
            value = "68000793"
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
            value = "ranhengzhang"
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
        },{
            class = "checkbox",
            name = "keep_roma",
            x = 27,
            y = 5,
            width = 1,
            value = true
        },{
            class = "label",
            label = "保留与原文相同的注音",
            name = "tag_keep_roma",
            x = 28,
            y = 5,
            width = 1
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

    -- 3. 显示用户对话框
    local btn, result = aegisub.dialog.display(ui_config, {"Start", "Cancel"})

    if btn == false or btn == "Cancel" then aegisub.cancel() end
    aegisub.log("ASS2TTML")

    -- 4. 处理用户输入
    options = util.deep_copy(result)
    options.split_space = options["space"] == "拆分"
    options.merge_space = options["space"] == "合并"

    if #subs == 0 then aegisub.cancel() end

    -- 5. 处理TTML数据
    process_ttml()

    -- 6. 生成TTML内容
    local ttml = print_ttml()

    -- 7. 显示结果对话框
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

    -- 8. 处理用户操作
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
                                                  options.musicNames) .. '.word.ttml',
                                              'TTML files (*.ttml)|*.ttml')
        if ttml_file ~= nil then
            local file = assert(io.open(ttml_file, "w"))
            file:write(ttml)
            file:close()
        end
    end

    -- 9. 显示标记信息
    show_marks();
end

-- ======================================================================
-- 注册Aegisub宏
-- 将脚本注册到Aegisub自动化菜单中
-- ======================================================================
aegisub.register_macro(script_name, script_description, script_main);
