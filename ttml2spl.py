import os.path
import re
from collections import deque
import xml.dom.minidom
from xml.dom.minidom import Document, Element


class TTMLTime:
    __pattern = re.compile(r'\d+')

    def __init__(self, centi: str):
        if centi == '': return
        # 使用 finditer 获取匹配的迭代器
        matches = TTMLTime.__pattern.finditer(centi)
        # 获取下一个匹配
        iterator = iter(matches)  # 将匹配对象转换为迭代器

        self.__minute:int = int(next(iterator).group())
        self.__second:int = int(next(iterator).group())
        self.__micros:int = int(next(iterator).group())

    def __str__(self):
        return f'<{self.__minute:02}:{self.__second:02}.{self.__micros:03}>'

    def __ge__(self, other):
        return (self.__minute, self.__second, self.__micros) >= (other.__minute, other.__second, other.__micros)

    def __ne__(self, other):
        return (self.__minute, self.__second, self.__micros) != (other.__minute, other.__second, other.__micros)

class TTMLLine:
    def __init__(self, element:Element):
        self.__element = element
        self.__orig_line = deque(['\n'])
        self.__ts_line:str = ""
        self.__roma_line:str = ""
        self.__bg_line:TTMLLine|None = None

        # 获取传入元素的 begin 和 end 属性
        lbegin:str = element.getAttribute("begin")
        lend:str = element.getAttribute("end")

        self.__orig_line.append(f'[{lbegin}]')

        # 获取 <p> 元素的所有子节点，包括文本节点
        child_elements:list[Element] = element.childNodes  # iter() 会返回所有子元素和文本节点

        # 遍历所有子元素
        for child in child_elements:
            if child.nodeType == 3 and child.nodeValue:  # 如果是文本节点（例如空格或换行）
                self.__orig_line.append(child.nodeValue)
            else:
                # 获取 <span> 中的属性
                role:str = child.getAttribute("ttm:role")

                # 没有role代表是一个syl
                if role == "":
                    if child.childNodes[0].nodeValue:
                        last = self.__orig_line[-1]
                        if isinstance(last, TTMLTime) and last >= sbegin:
                            self.__orig_line.pop()
                        sbegin:TTMLTime = TTMLTime(child.getAttribute("begin"))
                        send:TTMLTime = TTMLTime(child.getAttribute("end"))
                        self.__orig_line.append(sbegin)
                        self.__orig_line.append(child.childNodes[0].nodeValue)
                        self.__orig_line.append(send)

                elif role == "x-bg":
                    # 和声行
                    self.__bg_line = TTMLLine(child)
                elif role == "x-translation":
                    # 翻译行
                    self.__ts_line = f'{child.childNodes[0].data}'
                elif role == "x-roman":
                    # 音译行
                    self.__roma_line = f'{child.childNodes[0].data}'

        last = self.__orig_line.pop()
        if (not isinstance(last, TTMLTime)) or (last != send):
            self.__orig_line.append(last)
        self.__orig_line.append(f'[{lend}]')

    def __raw(self):
        raw:list[str] = ['\n']

        for child in self.__element.childNodes:
            if child.nodeType == 3:
                raw.append(child.nodeValue)
                continue
            role: str = child.getAttribute("ttm:role")
            if role == "":
                if child.childNodes:
                    raw.append("".join([v.nodeValue for v in child.childNodes]))
                else:
                    raw.append(child.nodeValue)

        return "".join(raw)

    def __str__(self):
        ttml:list[str] = [''.join([str(v) for v in self.__orig_line])]
        if self.__bg_line:
            ttml.insert(1, self.__bg_line.__raw())
        if self.__ts_line:
            ttml.append('\n'+self.__ts_line)
            if self.__bg_line and  self.__bg_line.__ts_line:
                ttml.append(f'\n({self.__bg_line.__ts_line})')
        if self.__roma_line:
            ttml.append('\n'+self.__roma_line)
            if self.__bg_line and self.__bg_line.__roma_line:
                ttml.append(f'\n({self.__bg_line.__roma_line})')

        return ''.join(ttml)



if __name__ == '__main__':
    ttml_path = input('TTML文件路径：')

    try:
        # 解析XML文件
        dom = xml.dom.minidom.parse(ttml_path)  # 假设文件名是 'books.xml'
        tt: Document = dom.documentElement  # 获取根元素

        # 获取tt中的body/head元素
        body = tt.getElementsByTagName('body')[0]
        head = tt.getElementsByTagName('head')[0]

        if body and head:
            # 获取body/head中的<div>/<metadata>子元素
            div = body.getElementsByTagName('div')[0]
            metadata = head.getElementsByTagName('metadata')[0]

            # 获取div中的所有<p>子元素
            p_elements = div.getElementsByTagName('p')
            meta_elements = metadata.getElementsByTagName('amll:meta')

            with open(os.path.splitext(os.path.basename(ttml_path))[0] + '.lrc', 'w') as spl_file:
                tags:dict[str, str] = {
                    "musicName": "ti",
                    "album": "al",
                    "artists": "ar"
                }

                for meta in meta_elements:
                    key: str = meta.getAttribute("key")
                    value: str = meta.getAttribute("value")
                    if key in tags:
                        tag = f"[{tags[key]}:{value}]\n"
                        print(f"内嵌元数据：{tag}")
                        spl_file.write(tag)

                # 遍历每个<p>元素
                for p in p_elements:
                    line_obj = TTMLLine(p)

                    # 打印或返回最终的行
                    print(f"\n第{p_elements.index(p)}行内容：{line_obj}")
                    spl_file.write(str(line_obj))

                print(f"\nSPL文件{os.path.splitext(os.path.basename(ttml_path))[0]}.lrc写入完成")
        else:
            print("错误: 找不到<body>元素")

    except FileNotFoundError as e:
        print(f"错误：{e}")
    except xml.parsers.expat.ExpatError as e:
        print(f"XML 解析错误：{e}")
    except Exception as e:
        print(f"发生了未知错误：{e}")