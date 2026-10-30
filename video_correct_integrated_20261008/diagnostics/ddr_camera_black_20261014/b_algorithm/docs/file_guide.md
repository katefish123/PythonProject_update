# 目录与逐文件指南

本页说明工程中每一类文件的职责、输入输出关系和是否应手工修改。当前源代码的改动集中在黑标记检测、ROI配置及对应测试/演示。透视求解、坐标、RGB插值和A/C缓存端口继续采用原数值与接口合同。

## 目录全景

```text
member_b_perspective_black/
├── README.md                 工程入口、运行步骤、备份和配置摘要
├── requirements.txt          Python必需/可选依赖
├── run_checks.bat            Windows完整验证入口
├── run_modelsim.do           ModelSim/Questa完整仿真入口
├── python/brect/             软件数值参考与命令行入口
├── rtl/                      9个可综合算法模块及源文件清单
├── scripts/                  5个生成/验证脚本
├── sim/                      自检查testbench及统一运行清单
├── examples/                 示例图、黑阈值/ROI、接线和配置记录
├── vectors/                  可复现测试输入与预期数值
├── results/                  当前版本实际运行的日志和结果
├── docs/                     算法、接口、集成、硬件、历史与本指南
└── backups/                  历史局部快照与迁移前生成产物
```

完整原工程ZIP和逐文件SHA256清单位于本目录的**上一级**，见 [根README的备份说明](../README.md#原工程与完整备份)。工程中出现的 `.DS_Store`、ModelSim `work/` 等也已包括在完整备份里；它们不属于算法源代码。

## 根目录入口

| 文件 | 作用 | 使用/修改建议 |
| --- | --- | --- |
| `README.md` | 使用入口、黑标记/ROI规则、运行命令、默认参数、集成边界 | 首先阅读；参数/入口变更时同步更新 |
| `requirements.txt` | `numpy`、`Pillow`依赖；注释说明摄像头可选`opencv-python` | 安装时使用；仅实际增加依赖才修改 |
| `run_checks.bat` | Windows调用完整检查运行器 | 在根目录双击或CMD执行；真正逻辑在`scripts/run_checks.py` |
| `run_modelsim.do` | 逐文件编译RTL/例子和SV，读取统一清单，执行仿真并检查通过位 | ModelSim/Questa入口，工作目录应为包根目录 |
| `.DS_Store` | macOS Finder的目录显示元数据 | 不参与运行、编译或测试，可忽略 |

运行ModelSim后可能重新生成 `modelsim.ini` 和 `work/`。旧版同名文件已放入本次历史归档；新生成文件说明见本页“ModelSim临时数据库”。

## python/：软件数值参考

`python/` 是导入根，设置 `PYTHONPATH=python` 后可以使用 `brect`。`python/.DS_Store` 只保存Finder元数据。`python/brect/` 内共有4个源文件：

| 文件 | 核心作用 | 从哪里使用 |
| --- | --- | --- |
| `__init__.py` | 汇总公共导入：`detect_markers`、`homography`、`map_float`、`rectify_float`、`solve_fixed`、`map_fixed`、`rectify_fixed` | `from brect import ...` |
| `golden.py` | RGB黑阈值+ROI检测、每角像素统计/质心、独立8×8浮点H求解、浮点坐标和手写最近邻/双线性采样 | 浮点参考、检测、CLI、演示与测试向量生成 |
| `fixed.py` | 整数H闭式求解、Q16.24系数、UQ12.8映射、邻域地址和最后截断的RGB插值 | 与RTL逐位对照；生成`.hex`/请求向量；定点参考图 |
| `cli.py` | 静态图片/摄像头入口；加载`--thresholds`、`--rois`，保存/显示浮点与定点结果 | `python -B -m brect.cli ...` |

只改黑色检测时，检查 `golden.py` 与 `rtl/marker_detector.v` 是否采用相同阈值、ROI和拒绝规则。不要为了改黑标记而更改RGB采样或输出色序。

## rtl/：FPGA算法源代码

`rtl/files.f` 是从包根目录使用的RTL源清单，包含下列9个Verilog文件。`b_rectifier` 是自动检测顶层，`perspective_core` 是固定H联调入口。

| 文件 | 模块职责 | 关键关系 |
| --- | --- | --- |
| `marker_detector.v` | 在4个ROI内统计黑像素数、x/y总和、包围盒，检查配置/面积/跨度/坐标，串行求TL/TR/BR/BL整数质心 | 输入源视频；输出四角、拒绝/快照丢弃状态；调用无符号迭代除法器 |
| `homography_solver.v` | 校验四边形和透视数值包络，闭式计算9个H系数 | 输入四角，使用共享有符号64位除法；错误保持前一H |
| `perspective_coord.v` | 对每笔目的坐标计算Nx、Ny、D，检查数值包络并得到UQ12.8源坐标 | 像素路径，标签/有效位同步流水；调用两路流水除法 |
| `bilinear_interp.v` | 对4个RGB888邻域像素进行3级双线性插值 | 最近邻通过重复同一像素复用；无效采样输出有效黑像素 |
| `perspective_core.v` | 组合坐标、采样边界、4邻域像素地址、请求元数据、缓存响应与插值 | A的缓存请求/响应接口集中在这里；可用固定H直接联调 |
| `b_rectifier.v` | 组合检测、求解和像素核心；控制更新节拍、active/pending H、目的帧边界提交、陈旧帧计数 | A/C最终接入的B顶层；转发6个黑阈值和16个ROI参数 |
| `unsigned_div_seq.v` | 无符号串行除法，busy期间忽略start，除零报错 | 检测器以40位配置求8个质心分量，其他场景默认64位 |
| `signed_div_seq.v` | signed64串行除法、向零截断；拒绝除零及最小负数/-1溢出 | H参数求解的共享算子 |
| `scaled_div_pipe.v` | 每拍一笔的非负变分母流水除法，输出12位整数+8位小数 | 坐标模块内部算子；逐级比较/减法，无逐像素组合`/` |
| `files.f` | 上述9个源文件的相对路径编译清单 | 从包根目录引用；新增/删除RTL文件时更新 |

阈值、ROI、尺寸、统计限值和更新节拍是**编译/综合时参数**。Python JSON不会被RTL读入。参数名和端口详见 [interfaces.md](interfaces.md) 与 [black_markers.md](black_markers.md)。

## scripts/：可复现生成与验证

| 文件 | 做什么 | 写出/检查的内容 |
| --- | --- | --- |
| `generate_vectors.py` | 固定随机种子创建小型黑标记场景、失检场景、H/坐标/RGB插值和逐请求参考 | 重建`vectors/`，更新`examples/source*`、`float*`、`fixed*`、`preview.png`及误差统计 |
| `make_demo.py` | 合成640×480纸面，4个黑角标记，保留黑正文/边框，以局部ROI避免正文干扰 | 重建`examples/demo_*.png`、`demo_parameters.json`和`rois_demo.json` |
| `test_models.py` | 浮点/定点、H几何包络、坐标/采样、黑阈值/ROI和非法配置模型回归 | 从数值独立参考检查Python；日志由完整运行器保存 |
| `test_modelsim_script.py` | 用真实Tcl解释器和ModelSim命令替身检查编译参数、清单、错误中止和二进制通过位 | 检查入口脚本控制；不运行原生ModelSim RTL仿真 |
| `run_checks.py` | 完整验证调度，失败即停止；编译/仿真，重读实际RTL导出并比对 | `results/verification.json`、日志、`.vvp`、CSV与重建PNG；读取`sim/tests.list` |

重新生成会覆盖同名向量、图片和常规结果。历史产物已归档；后续需要保留自己的运行证据时，应先复制对应结果到带日期目录。

## sim/：自检查测试

每个 `.sv` 都是仿真源，不加入FPGA综合。`tests.list` 每行包含一个测试顶层和预期成功标志；Icarus和ModelSim共用这份清单，必须包含每个 `tb_*.sv` 一次。测试通过还必须设置单比特 `test_passed=1`。

| 文件 | 成功标志 | 检查内容 |
| --- | --- | --- |
| `tb_perspective_coord.sv` | `COORD_PASS` | 坐标向量、分母/负值/比值边界、有效位、标签与流水空拍 |
| `tb_homography_solver.sv` | `SOLVER_PASS` | 不同四边形H系数、交叉/退化/倾斜拒绝、求解失败保持 |
| `tb_bilinear_interp.sv` | `INTERP_PASS` | RGB通道、0/半/255权重、截断、无效黑像素与标签 |
| `tb_marker_detector.sv` | `MARKER_PASS` | 黑阈值、ROI角点身份、质心、像素面积/跨度、越界、busy丢快照、首末像素与复位 |
| `tb_b_rectifier.sv` | `VIDEO_PASS` | 小场景全链路、建立H前黑屏、pending与换帧、失检保持、RTL逐像素输出 |
| `tb_cache_contract.sv` | `CACHE_CONTRACT_PASS` | 按序可变缓存延迟、空拍、逐笔最近邻/双线性切换、黑响应队列位置和元数据 |
| `tb_b_integration.sv` | `B_INTEGRATION_PASS` | 采集/目的请求并行、帧内H保持、提交和新solve_done同拍、在途事务复位 |
| `tb_request_boundaries.sv` | `BOUNDARIES_PASS` | 640×480、1920×1080、4096×4096代表性源尺寸，首末行列、地址步长、错误分类和贴边量化 |
| `tb_marker_config.sv` | `MARKER_CONFIG_PASS` | 奇数尺寸和局部ROI、黑阈值下界、源尺寸/统计/阈值/ROI非法配置，以及6对共享边界拒绝 |
| `tests.list` | 全套入口清单 | 定义实际运行项；局部通过不能输出全套成功标志 |

当前完整清单为9项；实际运行项始终以清单列出的顶层为准。每项覆盖边界由其代码和日志说明；缓存模型通过不代表DDR实测吞吐。

## vectors/：向量格式与阶段

全部向量由 `scripts/generate_vectors.py` 可重建，主要供testbench读取。修改算法时修改生成器和独立参考，再重建；不要只手改预期文件让测试通过。

| 文件 | 具体作用/格式 |
| --- | --- |
| `source0.hex` | 场景0完整源图，逐行、每像素一行6位十六进制RGB888；用于初次H0检测 |
| `source1.hex` | 场景1移动后的四黑标记源图；用于检测H1和最近邻输出 |
| `source2.hex` | 从场景1去掉右下黑标记，验证失检和保留旧H |
| `expected0.hex` | 场景0在H0下的定点双线性预期图，RGB888逐像素 |
| `expected1.hex` | 场景1在H1下的定点最近邻预期图，RGB888逐像素 |
| `precommit.hex` | 源图已换成场景1、H1尚pending时，仍使用H0的参考输出 |
| `hold.hex` | 场景2失检后保留H1的参考输出 |
| `bootstrap_req.txt` | 建立有效H前的目的请求，`inside=0`，用于验证黑响应仍保留位置 |
| `frame0_req.txt` | 完整场景0目的请求及H0参考地址/权重 |
| `precommit_req.txt` | 待更新H尚未提交阶段的小批请求，使用旧H |
| `frame1_req.txt` | H1提交后场景1完整目的请求，最近邻模式 |
| `hold_req.txt` | 失检保留H1阶段的完整目的请求 |
| `coord.txt` | 空拍标志、目的x/y、tag、9个40位二补码H系数、预期UQ12.8 x/y和错误位 |
| `interp.txt` | 空拍、tag、inside、fx/fy、4个RGB888像素和预期RGB888 |
| `solver.txt` | 4点整数坐标、预期拒绝位、9个40位二补码定点H系数 |
| `manifest.json` | 种子、图像尺寸、向量数、各场景四角/H/采样方法、浮点与定点误差统计 |

所有 `*_req.txt` 逐行字段为：`tag inside error addr00 addr10 addr01 addr11 fx fy`，数值为十进制。`tag={y[11:0],x[11:0]}`，地址单位是像素；RGB888源/预期`.hex`为十六进制。H系数文件需要按40位二补码解释，不能直接当无符号系数。输入/输出维度及向量数以 `manifest.json` 和testbench读取方式为准。

## examples/：图片与配置

| 文件 | 作用 | 来源/使用方式 |
| --- | --- | --- |
| `thresholds.json` | Python统一黑色通道阈值 | `--thresholds`加载；格式为`black -> [[Rmin,Gmin,Bmin],[Rmax,Gmax,Bmax]]` |
| `rois_demo.json` | 四演示角点附近±12像素闭矩形，避开黑正文 | `--rois`加载；TL/TR/BR/BL对应输出顺序；须按自己的场景改范围 |
| `source0.png` | 小场景0源图，黑标记供默认四象限检测 | `generate_vectors.py`生成，与`source0.hex`逐像素对应 |
| `source1.png` | 小场景1源图 | 与`source1.hex`对应 |
| `source2.png` | 去掉右下标记的小场景源图 | 与`source2.hex`对应，用于失检 |
| `float0.png`、`fixed0.png` | 场景0浮点与定点双线性图 | 对照数值误差，`fixed0.png`与`expected0.hex`对应 |
| `float1.png`、`fixed1.png` | 场景1浮点与定点最近邻图 | `fixed1.png`与`expected1.hex`对应 |
| `preview.png` | 小场景输入/矫正并排预览 | 重建向量时生成，放大便于肉眼检查 |
| `demo_document.png` | 演示纸面的平直原稿，含黑文字、网格和轮廓 | 合成场景原稿，210×297 |
| `demo_input.png` | 640×480合成倾斜纸面与四个黑标记 | 静态CLI演示输入，必须配局部ROI |
| `demo_float.png`、`demo_fixed.png` | 大演示浮点与定点矫正图 | `make_demo.py`生成，图像仍为RGB彩色 |
| `demo_preview.png` | 大演示输入/矫正并排图 | README首个视觉检查入口 |
| `demo_parameters.json` | 大演示源/目的尺寸、四角、H、误差和标记中心假设 | `make_demo.py`生成，不能代替摄像头实测 |
| `b_rectifier_instance.v` | 转发全部参数和具名端口的可综合接线模板 | A复制到真实工程；不实现DDR、HDMI、CDC或板级顶层 |
| `integration_files.f` | 9个RTL加接线模板的编译清单 | 可先用Icarus或ModelSim检查参数/端口一致 |
| `integration_config.json` | B默认参数、A/C待确认项、缓存/复位/数值合同和分项验证状态 | 记录用JSON；RTL不会读取；改最终配置须同步实例化和约束 |

小场景无黑正文干扰，可用默认四象限；大演示的黑文字是真实的检测干扰，因此必须配 `rois_demo.json`。四象限不会自动分离同一区内的多个黑物。

## results/：当前版本实跑产物

此目录在本次迁移前已清空旧产物并归档。下列文件在运行对应步骤后生成；未执行的检查不应凭空拥有通过证据。`verification.json` 是本次检查的汇总入口，日期与日志应一致。

| 文件或模式 | 说明 |
| --- | --- |
| `verification.json` | 本次状态、运行UTC、工具/测试列表、实际RTL比对统计、限制和可选v3兼容结果 |
| `backup_verification.json` | 本次再次逐文件核对完整备份与原工程，记录原目录未改及校验结果 |
| `quality_review.md` | 对黑检测、ROI、接口与文档的独立复查结论，以及仍需实测的使用限制 |
| `generation.log` | 小场景/向量生成的日志及数值摘要 |
| `python_tests.log` | Python模型回归原始输出 |
| `modelsim_script_tests.log` | Tcl命令替身脚本控制回归；不属于原生ModelSim |
| `rtl_syntax.log`、`syntax.vvp` | RTL顶层语法/编译输出与Icarus可执行中间件 |
| `example_syntax.log`、`example_syntax.vvp` | 完整接线模板的编译日志与中间件 |
| `tb_<名字>_compile.log` | 清单中每个testbench的编译输出；应检查报错/警告 |
| `tb_<名字>.vvp` | Icarus仿真中间件，`vvp`运行；可重建，不是FPGA位流 |
| `tb_<名字>.log` | 对应testbench实际自检查结果和成功标志 |
| `rtl_coord.csv` | 实际RTL导出的tag、UQ12.8 x/y和错误位；Python逐笔重算比对 |
| `rtl_solver.csv` | 实际RTL求解的拒绝位和H系数；与`solver.txt`比较 |
| `rtl_interp.csv` | 实际RTL输出tag与RGB；与`interp.txt`比较 |
| `rtl_video.csv` | 实际wrapper按阶段输出的phase/index/tag/RGB；与对应预期`.hex`比较 |
| `rtl_rectified0.png`、`rtl_rectified2.png` | 从RTL实际CSV重建的两张完整输出图；2表示wrapper测试阶段2，即场景1 |
| `demo_generation.log` | 运行演示生成时保存的摘要；是否保存取决于调用方式 |
| `cli_smoke/float.png`、`fixed.png`、`parameters.json` | 实际CLI演示输出，供检查入口和参数；由CLI输出位置决定 |
| `modelsim_full.log` | 原生ModelSim/Questa全套transcript，执行`run_modelsim.do`后才生成 |
| `integration_example.vvp`、`integration_override.vvp` | 按README/集成文档手动编译的示例中间件 |
| 波形文件（如`.vcd`） | 以`+wave`运行相应testbench时生成，供定位时序 |
| 用户另选的输出目录（如`my_photo/`） | CLI保存的浮点/定点图及参数；按该次命令辨认 |

生成的日志、CSV、PNG、`.vvp`可以重建；交付时保存它们是为了复核本次结果。PDS资源/时序、位流、DDR/HDMI日志应由真实板级工程另存并在验证记录里链接。

## docs/：设计说明与证据边界

| 文件 | 作用 |
| --- | --- |
| `file_guide.md` | 本页：目录、逐文件作用、生成关系和修改入口 |
| `black_markers.md` | 黑阈值、4 ROI定义、Python/RTL配置、干扰限制及旧四色迁移 |
| `algorithm.md` | 坐标/质心、独立浮点参考、FPGA闭式H、逐像素除法、采样和误差规则 |
| `interfaces.md` | 每个输入输出、位宽/RGB位序、缓存按序响应、复位、H换帧、数值/越界与延迟合同 |
| `integration_v1.md` | A/B/C默认/最终配置分工、黑阈值/ROI参数、编译覆写及帧管理步骤 |
| `validation_record.md` | 当前版验收方法、每个测试顶层、历史与当前结果区别、ModelSim/PDS/相机/整机待填表 |
| `changes_v1.md` | 2026-10-06接口补充的历史记录；不会作为本次黑检测的通过结论 |
| `changes_black_detection.md` | 2026-10-11黑标记改动范围、兼容变化、备份位置与回归入口 |
| `board_pds.md` | 原板卡材料核查、PDS仿真/综合/时序/上板步骤和资源资料疑点 |
| `timing_example.sdc` | 仅算法检查用50MHz时钟约束例子；实际系统时钟与IO/CDC约束仍须A/C确定 |
| `provenance.json` | 原v3/板卡资料哈希、历史来源与责任边界；字段描述原包形成时期的来源 |

## backups/：历史快照与旧结果

| 路径 | 保存内容 | 如何理解 |
| --- | --- | --- |
| `backups/README.md` | 两个归档目录及完整备份的区别 | 历史识别入口 |
| `2026-10-06_before_interface_v1_supplements/` | 原工程已有的局部备份：旧README、接口/板卡文档、2个检查脚本、ModelSim入口、旧结果和`install_manifest.json` | 补充v1接口前的部分文件，不是完整原工程，README里的四色/五项描述仅属于历史 |
| `2026-10-11_before_black_detection/` | 本次修改前旧`results/`、旧ModelSim `work/`和`modelsim.ini` | 避免旧日志/编译库和本次黑检测结果混淆；不是源码完整快照 |
| `2026-10-11_before_black_detection/results/history/2026-10-05/` | 原工程归档的早期五项验证输出、CSV、PNG、日志 | 只证明当时范围；不等于当前九项或黑标记通过 |

历史 `results/` 中的 `modelsim_user_coord.log`、`modelsim_native_evidence.json`、`modelsim_script_before_fix.log`、`modelsim_flag_before_fix.log` 分别是用户原生坐标日志、历史原生范围摘要、编译路径修正前问题、通过位读取修正前问题。它们说明旧ModelSim调试过程。其他日志/CSV/PNG/`.vvp`名称与上文results说明相同，但内容属于历史四色版本。旧`install_manifest.json`是当时交付安装记录，不是本次完整备份清单。

完整恢复应使用上一级 `member_b_perspective_original_2026-10-11.zip`，逐文件校验以 `source_backup_manifest.json` 为准。完整ZIP已包含原工程已有备份。

## ModelSim临时数据库

`work/` 是ModelSim/Questa编译、优化后的库，可由RTL/SV源码重建。不应手工修改其中内容，也不能当成当前源代码或硬件位流。

| 文件/子目录 | 用途 |
| --- | --- |
| `modelsim.ini` | ModelSim工作库/工具配置映射，可能依赖当时环境 |
| `work/_info`、`work/_vmake` | 编译库索引/生成信息 |
| `work/_lib.qdb`、`_lib1_0.qdb/.qpg/.qtl` | 编译库数据库及内部附属数据 |
| `work/@_opt/`、`@_opt1/`、`@_opt2/` | 不同优化仿真快照目录 |
| 上述目录中的`_lib*.qdb/.qpg/.qtl` | 优化库的专用数据库文件 |
| `@_opt*/_data/exempt*` | 优化过程中生成的工具内部数据 |

这些文件已作为源工程内容完整备份；本次运行需要从源码重新编译，以避免沿用旧四色优化模型。

## 从需求定位修改位置

| 需求 | 应改/检查的位置 |
| --- | --- |
| 换一组Python黑阈值 | 新建自己的阈值JSON，使用`--thresholds`；默认值在`golden.py` |
| 避免文字/阴影干扰 | 收窄自己的4 ROI JSON，使用`--rois`，检查每角计数/跨度；不调整透视采样 |
| FPGA更换阈值/ROI | A实例化中的`BLACK_*`、`P0..P3_*`参数，并同步`integration_config.json`，重新仿真/综合 |
| 更换输入/输出尺寸 | `SRC_W/H`、`OUT_W/H`，ROI范围、缓存行步长、目的坐标和显示窗口同步修改 |
| 修改H/定点数值或边界策略 | Python参考、RTL、生成向量、独立模型测试、接口/算法合同一起修改 |
| 接DDR和显示 | 先读`interfaces.md`与`integration_v1.md`，由A/C实现缓存、队列、帧锁定和CDC |
| 查本次是否通过 | `results/verification.json`和当次日志；硬件项目分别查`validation_record.md` |
