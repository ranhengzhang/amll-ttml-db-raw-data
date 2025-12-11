--[[
ASS2TTML 转换脚本
功能：将ASS格式的字幕文件转换为TTML文件，支持多种音乐平台ID和元数据。
作者：ranhengzhang@gmail.com
版本：0.1
创建日期：2024-12-17
]] -- 导入所需模块
clipboard = require 'aegisub.clipboard'
util = require 'aegisub.util'
re = require 'aegisub.re'

-- 获取翻译函数
local tr = aegisub.gettext

-- 脚本元数据定义
script_name = tr "ASS2TTML - AMLL歌词格式转换"
script_description = tr "将ASS格式的字幕文件转为TTML文件"
script_author = "ranhengzhang@gmail.com"
script_version = "1.5 Wriothesley"
script_modified = "2025-12-11"

-- 包含karaskel库，用于卡拉OK处理
include("karaskel.lua")

local last_dir = nil
local last_file = nil

--[[
主函数：脚本入口点
参数：
  subtitles: Aegisub传入的字幕数据，userdata类型
]]
function script_main(subtitles)
    local anti = false -- 标记是否有反色或独唱部分
    local marked = {} -- 存储标记信息

    --[[
    函数：添加标记
    参数：
      actor: 演员字符串，包含标记信息
      num: 行号
      is_bg: 是否为背景行
    ]]
    local function add_mark(actor, num, is_bg)
        for mark in actor:gmatch('x%-mark[%w%-]*') do
            if marked[mark] == nil then marked[mark] = {} end
            table.insert(marked[mark], string.format("第%d行%s", num,
                                                     is_bg and '和声部分' or
                                                         ''))
        end
    end

    --[[
    函数：转义XML特殊字符
    参数：
      value: 输入字符串
    返回值：转义后的字符串
    ]]
    local function xml_symbol(value)
        value = string.gsub(value, "&", "&amp;"); -- 转义 & 符号
        value = string.gsub(value, "<", "&lt;"); -- 转义 < 符号
        value = string.gsub(value, ">", "&gt;"); -- 转义 > 符号
        value = string.gsub(value, "\"", "&quot;"); -- 转义 " 符号
        value = string.gsub(value, "\'", "&apos;"); -- 转义 ' 符号
        return value;
    end

    local title = ""; -- 歌曲标题
    local script_offset = {}; -- 脚本时间偏移
    local part_split = false; -- 是否分段

    --[[
    函数：预处理字幕行
    参数：
      subtitles: 原始字幕数据
    返回值：处理后的字幕行列表
    ]]
    local function pre_process(subtitles)
        local is_bg = false -- 当前行是否为背景行
        local subs = {} -- 存储处理后的行
        local meta, styles = karaskel.collect_head(subtitles, true) -- 收集元数据和样式

        for i = 1, #subtitles do
            local line = table.copy(subtitles[i]) -- 复制行数据
            if subtitles[i].class == "info" then
                -- 处理信息行
                if subtitles[i].key == "Title" then
                    title = subtitles[i].value -- 获取标题
                elseif subtitles[i].key == "Update Details" then
                    local value = subtitles[i].value
                    -- 去掉字符串中的 `\[.*?\]`
                    value, _ = re.sub(value, "\\[.*?\\]", "")
                    value:gsub("([+-]%d+)", function(v)
                        -- config.offset[#config.offset + 1] = tonumber(v)
                        table.insert(script_offset, tonumber(v))
                    end)
                end
            else
                if line.effect == "" or line.effect == "karaoke" then
                    line.raw = line.raw:gsub('%s+', ' ') -- 规范化空白字符
                    line.text, _ = re.sub(line.text,
                                          "(?<=\\\\-)([^\\}]+\\}[^\\}]+)(?=\\})",
                                          "\\1\\\\-X") -- 处理特定模式
                    karaskel.preproc_line_text(meta, styles, line) -- 预处理行文本
                    if line.style == "orig" then
                        is_bg = line.actor:find("x%-bg") and
                                    line.actor:find("x%-chor") == nil -- 检查是否为背景行
                        if line.actor:find("x%-mark") ~= nil then -- 处理标记
                            if is_bg then
                                add_mark(line.actor, #subs, true) -- 添加背景行标记
                            else
                                add_mark(line.actor, #subs + 1, false) -- 添加普通行标记
                            end
                        end
                        local part = line.actor:find("x%-part") -- 检查分段
                        if part ~= nil then
                            part_split = true -- 设置分段标志
                        end
                    end
                    if is_bg then
                        -- 处理背景行
                        local parent_line = table.copy(subs[#subs])
                        if line.style == "orig" then
                            line.ts_line = {n = 0} -- 初始化时间轴行
                            parent_line.bg_line = line -- 设置背景行
                        elseif line.style == "roma" and
                            line.actor:find("x%-replace") == nil then
                            parent_line.bg_line["roma_line"] = line -- 设置罗马音行
                        elseif line.style == "ts" then
                            local bg_line = parent_line.bg_line
                            local ts_line = bg_line["ts_line"]
                            ts_line.n = ts_line.n + 1
                            ts_line[ts_line.n] = line -- 添加时间轴行
                            bg_line["ts_line"] = ts_line
                            parent_line.bg_line = bg_line
                        end
                        subs[#subs] = parent_line
                    else
                        -- 处理普通行
                        if line.style == "orig" then
                            line.ts_line = {n = 0} -- 初始化时间轴行
                            subs[#subs + 1] = line -- 添加行
                        elseif line.style == "roma" and
                            line.actor:find("x%-replace") == nil then
                            orig_line = table.copy(subs[#subs])
                            orig_line["roma_line"] = line -- 设置罗马音行
                            subs[#subs] = orig_line
                        elseif line.style == "ts" then
                            orig_line = table.copy(subs[#subs])
                            local ts_line = orig_line["ts_line"]
                            ts_line.n = ts_line.n + 1
                            ts_line[ts_line.n] = line -- 添加时间轴行
                            subs[#subs] = orig_line
                        end
                    end
                end
            end
        end

        -- 处理分段信息
        if part_split then
            local first_part = re.find(subs[1].actor, "(?<=x-part:)[A-z]+")
            if first_part ~= nil then
                part_split = first_part[1].str -- 获取分段类型
                subs[1].actor, _ = re.sub(subs[1].actor, "x-part:[A-z]+", "") -- 移除分段标记
            else
                part_split = "Verse" -- 默认分段
            end
        end

        return subs
    end

    local offset -- 时间偏移

    --[[
    函数：将时间转换为字符串格式
    参数：
      time: 时间值（毫秒）
    返回值：格式化的时间字符串（HH:MM:SS.mmm）
    ]]
    local function time_to_string(time)
        time = time + offset -- 应用偏移
        local res = string.format("%02d.%03d", math.floor(time / 1000) % 60,
                                  time % 1000) -- 秒和毫秒
        time = math.floor(time / 60000) -- 转换为分钟
        local hour = ""
        if time >= 60 then
            hour = string.format("%d:", math.floor(time / 60)) -- 小时
            time = time % 60
        end
        local minute = string.format("%02d:", time) -- 分钟

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

    -- 优化选项
    local optimize = false -- 是否优化TTML结构
    local split_space = false -- 是否拆分空格
    local merge_space = false -- 是否合并空格
    local merge_symbol = false -- 是否合并符号
    local pre_symbols = "([<（【〔［｛〈《｢「『'“'" -- 前括号符号

    --[[
    函数：生成卡拉OK部分的TTML
    参数：
      line: 字幕行数据
    返回值：TTML字符串
    ]]
    local function generate_kara(line)
        local ttml = {n = 0} -- 存储TTML部分

        for i = 1, #line.kara do
            local syl = util.copy(line.kara[i]) -- 复制音节数据
            syl.text_stripped = xml_symbol(syl.text_stripped) -- 转义XML字符

            if syl.inline_fx == "merge" or syl.inline_fx == "M" and ttml.n > 0 then
                -- 合并音节
                local stext = syl.text_stripped
                local last = ttml[ttml.n - 1]

                while last.stext:trim() == "" and ttml.n > 0 do
                    stext = last.stext .. stext -- 合并空白
                    ttml.n = ttml.n - 1
                    last = ttml[ttml.n - 1]
                end
                last.stext = last.stext .. stext -- 追加文本
                last.send = time_to_string(syl.end_time + line.start_time) -- 更新结束时间
                ttml[ttml.n - 1] = last
            elseif syl.inline_fx == "text" or syl.inline_fx == "T" then
                -- 文本音节
                ttml[ttml.n] = {stext = syl.text_stripped, sfx = "text"}
                ttml.n = ttml.n + 1
            elseif syl.inline_fx == "zero" or syl.inline_fx == "Z" then
                -- 零时长音节
                local space = nil
                if split_space then
                    space = re.find(syl.text_stripped, "(?<=.)(\\ |\\　)$") -- 查找尾部空格
                    syl.text_stripped = re.sub(syl.text_stripped,
                                               "(\\ |\\　)$", "") -- 移除尾部空格
                end

                -- 处理零时音节的时间逻辑
                local base_time = syl.start_time + line.start_time
                local start_time, end_time

                if i == 1 then
                    -- 如果是第一个音节：时间设为 (n-5, n)
                    start_time = base_time - 5
                    end_time = base_time
                else
                    -- 如果不是第一个音节：时间设为 (n, n+5)
                    start_time = base_time
                    end_time = base_time + 5
                end

                ttml[ttml.n] = {
                    sbegin = start_time,
                    send = end_time,
                    stext = syl.text_stripped
                }
                ttml.n = ttml.n + 1
                if split_space and space then
                    local hole_time = time_to_string(syl.end_time +
                                                         line.start_time) -- 空格时间
                    ttml[ttml.n] = {
                        sbegin = hole_time,
                        send = hole_time,
                        stext = space[1].str -- 添加空格
                    }
                    ttml.n = ttml.n + 1
                end
            else
                -- 普通音节
                local space = nil
                if split_space then
                    space = re.find(syl.text_stripped, "^(\\ |\\　)(?=.)") -- 查找头部空格

                    if space then
                        syl.text_stripped, _ =
                            re.sub(syl.text_stripped, "^(\\ |\\　)", "") -- 移除头部空格
                        local hole_time =
                            time_to_string(syl.start_time + line.start_time) -- 空格时间
                        ttml[ttml.n] = {
                            sbegin = hole_time,
                            send = hole_time,
                            stext = space[1].str -- 添加空格
                        }
                        ttml.n = ttml.n + 1
                    end

                    space = re.find(syl.text_stripped, "(?<=.)(\\ |\\　)$") -- 查找尾部空格
                    if space then
                        syl.text_stripped =
                            re.sub(syl.text_stripped, "(\\ |\\　)$", "") -- 移除尾部空格
                    end
                end
                if syl.duration == 0 then
                    -- 处理零时长音节
                    if i < #line.kara and line.kara[i + 1].duration == 0 and
                        (syl.inline_fx ~= "zero" and syl.inline_fx ~= "Z") then -- 向后合并连续无时长音节
                        local next_syl = line.kara[i + 1]
                        next_syl.text_stripped =
                            syl.text_stripped .. line.kara[i + 1].text_stripped -- 合并文本
                        line.kara[i + 1] = next_syl
                        goto continue -- 跳过当前音节
                    end
                    if unicode.len(syl.text_stripped:trim()) == 0 and
                        merge_space then -- 合并时长为 0 的空格
                        if i == 1 and #line.kara > 2 then
                            goto continue -- 首字符跳过
                        else
                            ttml[ttml.n - 1].stext =
                                ttml[ttml.n - 1].stext .. syl.text_stripped -- 合并到前一个音节
                        end
                    elseif unicode.len(syl.text_stripped:trim()) == 1 and
                        merge_symbol then -- 合并时长为 0 的单个非空字符
                        if i == 1 and #line.kara > 2 then -- 首字符向后合并
                            line.kara[2].text_stripped =
                                syl.text_stripped .. line.kara[2].text_stripped
                        elseif i > 1 and i < #line.kara and
                            pre_symbols:find(syl.text_stripped) ~= nil then -- 特殊字符向后合并
                            line.kara[i + 1].text_stripped =
                                syl.text_stripped ..
                                    line.kara[i + 1].text_stripped
                        else
                            ttml[ttml.n - 1].stext =
                                ttml[ttml.n - 1].stext .. syl.text_stripped -- 合并到前一个音节
                            if split_space and space then
                                local hole_time =
                                    time_to_string(syl.end_time +
                                                       line.start_time) -- 空格时间
                                ttml[ttml.n] = {
                                    sbegin = hole_time,
                                    send = hole_time,
                                    stext = space[1].str -- 添加空格
                                }
                                ttml.n = ttml.n + 1
                            end
                        end
                    else -- 时长为 0 的不合并字符
                        local start_time =
                            time_to_string(syl.start_time + line.start_time) -- 开始时间
                        local end_time =
                            time_to_string(syl.end_time + line.start_time + 5) -- 结束时间
                        ttml[ttml.n] = {
                            sbegin = start_time,
                            send = end_time,
                            stext = syl.text_stripped
                        }
                        ttml.n = ttml.n + 1
                        if split_space and space then
                            ttml[ttml.n] = {
                                sbegin = end_time,
                                send = end_time,
                                stext = space[1].str -- 添加空格
                            }
                            ttml.n = ttml.n + 1
                        end
                    end
                elseif syl.text_stripped ~= '' then
                    -- 正常时长音节
                    if syl.duration == 0 and not (syl.text_stripped == ' ') then
                        syl.end_time = syl.end_time + 5 -- 调整结束时间
                    end

                    local start_time = time_to_string(syl.start_time +
                                                          line.start_time) -- 开始时间
                    local end_time = time_to_string(syl.end_time +
                                                        line.start_time) -- 结束时间
                    ttml[ttml.n] = {
                        sbegin = start_time,
                        send = end_time,
                        stext = syl.text_stripped
                    }
                    ttml.n = ttml.n + 1
                    if split_space and space then
                        local hole_time =
                            time_to_string(syl.end_time + line.start_time) -- 空格时间
                        ttml[ttml.n] = {
                            sbegin = hole_time,
                            send = hole_time,
                            stext = space[1].str -- 添加空格
                        }
                        ttml.n = ttml.n + 1
                    end
                end
            end
            ::continue:: -- 跳转标签
        end

        local text = {} -- 存储最终文本

        for i = 0, ttml.n - 1 do
            local syl = ttml[i]
            if line.is_bg and i == 0 then
                syl.stext = '(' .. syl.stext -- 背景行开头加括号
            end
            if line.is_bg and i == ttml.n - 1 then
                syl.stext = syl.stext .. ')' -- 背景行结尾加括号
            end
            if syl.sfx == "text" then
                table.insert(text, syl.stext) -- 直接添加文本
            elseif optimize and
                (syl.sbegin == syl.send or syl.stext:trim() == "") then
                table.insert(text, syl.stext) -- 优化模式下添加空白或零时长
            else
                table.insert(text,
                             string.format(
                                 '<span begin="%s" end="%s">%s</span>', -- 生成span标签
                                 syl.sbegin, syl.send, syl.stext))
            end
        end

        return table.concat(text) -- 连接所有文本
    end

    --[[
    函数：生成单行TTML
    参数：
      line: 字幕行数据
      n: 行号
    返回值：TTML字符串
    ]]
    local function generate_line(line, n)
        local ttml = ""
        local is_other = line.actor:find('x%-anti') ~= nil or
                             line.actor:find('x%-duet') ~= nil or
                             line.actor:find('x%-solo') ~= nil -- 检查是否为其他角色

        line.is_bg = line.actor:find('x%-bg') ~= nil -- 设置是否为背景行
        if is_other then anti = true end -- 标记有反色或独唱

        if line.is_bg then
            ttml = ttml .. '<span ttm:role="x-bg"' -- 背景行使用span
        else
            ttml = ttml .. '<p' -- 普通行使用p标签
        end

        ttml = ttml ..
                   string.format(' begin="%s" end="%s"',
                                 time_to_string(min_start_time(line)),
                                 time_to_string(max_end_time(line))) -- 添加时间属性

        if not line.is_bg then
            ttml = ttml ..
                       string.format(' ttm:agent="%s" itunes:key="L%d"', -- 添加代理和键
                                     is_other and 'v2' or 'v1', n)
        end

        ttml = ttml .. '>' -- 关闭开始标签

        ttml = ttml .. generate_kara(line) -- 生成卡拉OK部分

        if line['roma_line'] ~= nil then
            ttml = ttml .. '<span ttm:role="x-roman">' .. -- 添加罗马音
                       xml_symbol(line['roma_line'].text_stripped:trim()) ..
                       '</span>'
        end
        if line['ts_line'].n ~= 0 then
            for i = 1, line['ts_line'].n do
                local ts_line = line['ts_line'][i]
                local lang = 'zh-CN' -- 默认语言
                if ts_line.actor:find('x%-lang') ~= nil then
                    lang = ts_line.actor:match('x%-lang%:[%w%-]*'):sub(8) -- 提取语言
                end
                ttml = ttml .. '<span ttm:role="x-translation" xml:lang="' ..
                           lang .. '">' .. -- 添加翻译
                           xml_symbol(ts_line.text_stripped:trim()) .. '</span>'
            end
        end
        if line['bg_line'] ~= nil then
            ttml = ttml .. generate_line(line.bg_line, -1) -- 递归生成背景行
        end

        if line.is_bg then
            ttml = ttml .. '</span>' -- 关闭背景span
        else
            ttml = ttml .. '</p>' -- 关闭p标签
        end

        return ttml
    end

    --[[
    函数：生成TTML body部分
    参数：
      subtitles: 处理后的字幕行列表
    返回值：TTML body字符串
    ]]
    local function generate_body(subtitles)
        local body =
            string.format('<body dur="%s">', -- 身体标签，带持续时间
            time_to_string(max_end_time(subtitles[#subtitles])))

        local n = 1 -- 行计数器
        local lines = {} -- 存储行TTML
        table.insert(lines, string.format('<div begin="%s" end="', -- 开始div
        time_to_string(min_start_time(subtitles[1]))))
        table.insert(lines, "00:00.000") -- 临时结束时间
        table.insert(lines, string.format('"%s>',
                                          part_split and
                                              string.format(
                                                  ' itunes:song-part="%s"', -- 添加歌曲部分
                                                  part_split) or ''))
        for i = 1, #subtitles do
            local line = subtitles[i]
            if line.actor:find('x%-part') then
                -- 处理分段
                local part = re.find(line.actor, "(?<=x-part:)[A-z]+")[1].str
                lines[2] = time_to_string(max_end_time(subtitles[i - 1])) -- 更新前一个div的结束时间
                body = body .. table.concat(lines) -- 添加当前div
                lines = {} -- 重置行
                table.insert(lines,
                             string.format('</div><div begin="%s" end="', -- 新div
                                           time_to_string(min_start_time(line))))
                table.insert(lines, "00:00.000") -- 临时结束时间
                table.insert(lines, string.format('"%s>', string.format(
                                                      ' itunes:song-part="%s"',
                                                      part)))
            end
            if line.actor:find('x%-chor') ~= nil then
                -- 处理和声行
                if line.actor:find('x%-bg') ~= nil then
                    local bg_line = table.copy(line)
                    line.bg_line = bg_line -- 设置背景行
                    line.actor = line.actor:gsub('x%-bg', '') -- 移除背景标记
                else
                    table.insert(lines, generate_line(line, n)) -- 生成和声行
                    n = n + 1
                    if line.actor:find('x%-anti') ~= nil or
                        line.actor:find('x%-duet') ~= nil or
                        line.actor:find('x%-solo') then
                        line.actor = line.actor:gsub('x%-anti', '') -- 移除反色标记
                        line.actor = line.actor:gsub('x%-duet', '') -- 移除二重唱标记
                    else
                        line.actor = 'x-anti ' .. line.actor -- 添加反色标记
                    end
                end
            end
            table.insert(lines, generate_line(line, n)) -- 生成普通行
            n = n + 1
        end
        lines[2] = time_to_string(max_end_time(subtitles[#subtitles])) -- 设置最终结束时间

        return body .. table.concat(lines) .. '</div></body>' -- 返回完整body
    end

    --[[
    函数：分割字符串
    参数：
      str: 输入字符串
    返回值：分割后的字符串列表
    ]]
    local function split(str)
        local rst = {}
        str:gsub('[^,&/]+', function(w) rst[#rst + 1] = w:trim(); end) -- 使用gsub分割
        return rst
    end

    --[[
    函数：生成元数据TTML
    参数：
      key: 元数据键
      value: 元数据值
    返回值：TTML元数据字符串
    ]]
    local function generate_meta(key, value)
        local ttml = {}
        local values = split(value) -- 分割值

        for i = 1, #values do
            aegisub.log(key .. ':\t　' .. values[i]:trim() .. '\r\n') -- 日志输出
            table.insert(ttml,
                         string.format('<amll:meta key="%s" value="%s"/>', key, -- 生成meta标签
                                       xml_symbol(values[i]:trim())))
        end

        return table.concat(ttml)
    end

    --[[
    函数：生成TTML head部分
    参数：
      metas: 元数据选项
    返回值：TTML head字符串
    ]]
    local function generate_head(metas)
        local ttml = {}

        table.insert(ttml, '<ttm:agent type="person" xml:id="v1"/>') -- 添加代理v1

        if anti then
            table.insert(ttml, '<ttm:agent type="other" xml:id="v2"/>') -- 如果有反色，添加代理v2
        end

        local ids = {
            'ncmMusicId', 'qqMusicId', 'spotifyId', 'appleMusicId', 'isrc' -- 音乐ID列表
        }
        for i = 1, #ids do
            if metas[ids[i] .. 's']:trim() ~= '' then
                table.insert(ttml, generate_meta(ids[i], metas[ids[i] .. 's'])) -- 生成音乐ID元数据
            end
        end

        local keys = {
            'musicName', 'artists', 'album', 'ttmlAuthorGithub',
            'ttmlAuthorGithubLogin' -- 其他元数据键
        }
        for i = 1, #keys do
            table.insert(ttml, generate_meta(keys[i], metas[keys[i] .. 's'])) -- 生成元数据
        end

        return '<head><metadata>' .. table.concat(ttml) .. '</metadata></head>' -- 返回head
    end

    --[[
    函数：提取文件路径
    参数：
      filename: 文件名
    返回值：路径部分
    ]]
    local function stripfilename(filename)
        -- return string.match(filename, "(.+)/[^/]*%.%w+$") -- *nix system
        return string.match(filename, "(.+)\\[^\\]*%.%w+$") -- windows  -- 匹配路径
    end

    --[[
    函数：提取文件名
    参数：
      filename: 完整路径
    返回值：文件名部分
    ]]
    local function strippath(filename)
        -- return string.match(filename, ".+/([^/]*%.%w+)$") -- *nix system
        return string.match(filename, ".+\\([^\\]*%.%w+)$") -- windows  -- 匹配文件名
    end

    --[[
    函数：显示标记信息
    ]]
    local function show_marks()
        aegisub.log('\n\n') -- 空行
        for mark, lines in pairs(marked) do
            aegisub.log(mark .. ': ' .. table.concat(lines, '，') .. '\n') -- 输出标记信息
        end
    end

    -- 主处理流程
    local subs = util.deep_copy(subtitles) -- 深拷贝字幕数据
    subs = pre_process(subs) -- 预处理

    if #script_offset == 0 then script_offset = {0} end
    -- 用户界面配置
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
        },
        {
            class = "edit",
            name = "musicNames",
            x = 19,
            y = 2,
            width = 16,
            value = title
        }, {
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
            class = #script_offset > 1 and "dropdown" or "intedit",
            name = "offset",
            x = 1,
            y = 5,
            width = 1,
            items = #script_offset > 1 and script_offset or nil,
            value = #script_offset > 1 and "" or script_offset[1]
        },
        {class = "label", label = "ms", name = "ms", x = 2, y = 5, width = 1},
        {
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
        },
        {
            class = "checkbox",
            name = "symbol",
            x = 30,
            y = 5,
            width = 1,
            value = true
        }, {
            class = "label",
            label = "合并单个(半/全角)标点",
            name = "tag_symbol",
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

    -- 显示对话框获取用户输入
    local btn, result = aegisub.dialog.display(ui_config, {"Start", "Cancel"})

    if btn == false or btn == "Cancel" then aegisub.cancel() end -- 用户取消

    local options = util.deep_copy(result) -- 复制选项
    offset = tonumber(options["offset"]) or 0 -- 设置时间偏移
    split_space = options["space"] == "拆分" -- 设置空格处理方式
    merge_space = options["space"] == "合并"
    merge_symbol = options["symbol"] -- 设置符号合并
    optimize = options["optimize"] -- 设置优化

    if #subs == 0 then aegisub.cancel() end -- 无数据时取消

    local body = generate_body(subs) -- 生成body
    local head = generate_head(options) -- 生成head
    local ttml = -- 组合完整TTML

        '<tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata" xmlns:amll="http://www.example.com/ns/amll" xmlns:itunes="http://music.apple.com/lyric-ttml-internal">' ..
            head .. body .. '</tt>'

    -- 显示结果对话框
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
        -- 复制到剪贴板
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
                try_copy = clipboard.set(ttml) -- 重试复制
            else
                try_copy = true -- 跳过
            end
        end
    elseif btn == "Save" then
        -- 保存到文件
        local ttml_file = aegisub.dialog.save('保存TTML文件', last_dir or
                                                  'D:/Users/LEGION/Desktop/amll-ttml-db-raw-data', -- 默认路径
                                              last_file or
                                                  ((title or options.musicNames) ..
                                                      '.ttml'), -- 文件名
        'TTML files (*.ttml)|*.ttml') -- 文件类型
        if ttml_file ~= nil then
            last_dir = stripfilename(ttml_file) -- 更新最后路径
            last_file = strippath(ttml_file) -- 更新最后文件名
            local file = assert(io.open(ttml_file, "w")) -- 打开文件
            file:write(ttml) -- 写入TTML
            file:close() -- 关闭文件
        end
    end

    show_marks(); -- 显示标记信息
end

-- 注册宏
aegisub.register_macro(script_name, script_description, script_main);
