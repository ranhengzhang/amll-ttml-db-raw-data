import os.path
import re
from collections import deque
import xml.dom.minidom
from xml.dom.minidom import Document, Element


def line_num():
    line=0
    def fun()->int:
        nonlocal line
        line += 1
        return line
    return fun

get_line_num = line_num()

def new_line(element:Element)->str:
    line = deque([])
    ext_line = ''
    bg_line = False

    # 获取传入元素的 begin 和 end 属性
    lbegin = element.getAttribute("begin")
    lend = element.getAttribute("end")

    line.append(f'[{lbegin}]')

    # 获取 <p> 元素的所有子节点，包括文本节点
    child_elements:list[Element] = element.childNodes  # iter() 会返回所有子元素和文本节点

    # 遍历所有子元素
    for child in child_elements:
        if child.nodeType == 3:  # 如果是文本节点（例如空格或换行）
            line.append(child.nodeValue)
        else:
            # 获取 <span> 中的属性
            role = child.getAttribute("ttm:role")
            sbegin = child.getAttribute("begin")
            send = child.getAttribute("end")

            # 没有role代表是一个syl
            if role == '':
                if child.childNodes[0].nodeValue:
                    last = line[-1]
                    if last != f'<{sbegin}>':
                        line.append(f'<{sbegin}>')
                    line.append(child.childNodes[0].nodeValue)
                    line.append(f'<{send}>')

            elif role == "x-bg":
                # 如果属性 ttm:role="x-bg"
                bg_line = child
            elif role == 'x-roman' or role == 'x-translation':
                # 翻译行和音译行
                ext_line += f'\n{child.childNodes[0].data}'

    last = line.pop()
    rst = re.findall(r'[0-9]{1,3}:[0-9]{1,2}\.[0-9]{1,6}', last)
    if (not rst) or (rst[0] != send):
        line.append(last)
    line.append(f'[{lend}]')

    lrc = ''.join(line) + ext_line + '\n'

    if bg_line:
        lrc += new_line(bg_line)

    return lrc

if __name__ == '__main__':
    ttml_path = input('TTML文件路径：')

    try:
        # 解析XML文件
        dom = xml.dom.minidom.parse(ttml_path)  # 假设文件名是 'books.xml'
        tt:Document = dom.documentElement  # 获取根元素

        # 获取tt中的body元素
        body = tt.getElementsByTagName('body')[0]

        if body:
            # 获取body中的<div>子元素
            div = body.getElementsByTagName('div')[0]

            # 获取div中的所有<p>子元素
            p_elements = div.getElementsByTagName('p')

            with open(os.path.splitext(os.path.basename(ttml_path))[0]+'.lrc', 'w') as spl_file:
                # 遍历每个<p>元素
                for p in p_elements:
                    line = new_line(p)  # 将<p>的文本传递给new_line函数

                    # 打印或返回最终的行
                    print(f"第{get_line_num()}行内容：{line}")
                    spl_file.write(line)

                print(f"SPL文件{os.path.splitext(os.path.basename(ttml_path))[0]}.lrc写入完成")
        else:
            print("错误: 找不到<body>元素")

    except FileNotFoundError as e:
        print(f"错误：{e}")
    except xml.parsers.expat.ExpatError as e:
        print(f"XML 解析错误：{e}")
    except Exception as e:
        print(f"发生了未知错误：{e}")

