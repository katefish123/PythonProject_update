# LED0 常亮（Pango PDS）

适用器件：`PG2L100H-6FBG676`。

- 顶层源码：`top_led_on.v`
- 管脚约束：`top_led_on.fdc`
- 顶层模块：`top_led_on`
- LED0：A20，输出高电平点亮

在 PDS 新建 RTL Project 后，添加这两个文件；综合引擎选择 ADS，器件选择 `PG2L100H-6FBG676`。
