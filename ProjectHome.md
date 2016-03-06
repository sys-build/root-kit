本项目旨在共享一些辅助内核分析或开发的小工具。目前已经完成的或收集的有：

sniper-patch-carrier:

linux内核补丁集提交工具


allscript:

辅助linux内核调试的gdb脚本

checknostatic:

perl扫描脚本,寻找linux内核源码中 **可能** 需要改进的模块初始化和退出函数。


checkcomment:

perl扫描脚本，寻找linux内核源码中存在问题的函数注释，包含注释中参数个数比实际的多，少，以及名称不符


jffs2map：

shrek2写的观察jffs文件系统信息的模块，遵从作者指定的license。对应的文档是“JFFS2源代码情景分析（Beta2)"


TODO：


sniper-patch-carrier:

简化control文件的编写，减少工作量。把补丁集放到一个文件夹中，控制文件只需指定这个补丁集目录即可。把补丁的标题移到补丁内部，发送时在检测阶段把补丁标题提取出来。补丁标题由补自动分析生成，特别是为了省去 PATCH 序号/总数 部分的手工编写。


checkcomment：

实现参数名称和实际不符合的检测


findconfcomment:

留待编写，根据内核的编译配置项名称寻找到它的解释


merge-list\_for\_each\_entry:

留待编写，寻找内核源码中需要合并为list\_for\_each\_entry的代码


改掉源码中错误的英文。

改进perl的代码，加进代码的严格检测。

相关工具的说明可能在下面的文档中：
http://wiki.zh-kernel.org/sniper