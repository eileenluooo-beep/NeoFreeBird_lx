# NeoFreeBird 操作栏媒体下载快捷键

本项目是一个独立的配套动态库 `NFBActionBarDownload.dylib`，在帖子底部书签左侧增加下载按钮。普通图片由本库批量保存，视频/GIF 继续调用原 NeoFreeBird 下载模块。不包含 X 安装包，不替换 NeoFreeBird 主动态库。

目标组合：**NeoFreeBird 7.3.0 + X 12.38.1 + iOS 17.2.1，arm64 真机**。当前版本为**普通图片批量保存候选版 5**。

用户已确认紧凑布局版可以正常打开 X、下载视频/GIF，且右侧按钮布局正常。本版在它的基础上增加普通图片的一键批量保存；紧凑布局函数保持原样。本版尚未在 macOS 编译或手机上验证，上一版通过不代表新图片功能已经验收。

保留启动防护：动态库加载回调只安排主队列任务，注册按钮时只检查已注册父类的方法列表。新增加的布局 Hook 会先检查参数数量和类型，尤其是 CGPoint、CGFloat、block 和 BOOL；接口不匹配时跳过对应调整并输出状态日志。

## 行为

- 含普通图片、视频或 GIF，且 NeoFreeBird 的“下载媒体”开关开启时，显示原生下载图标。
- 位置优先为书签之前；书签被隐藏时放到分享之前。由 X 的原生操作栏重新排列，不覆盖按钮或使用固定屏幕坐标。
- 下载键按无计数的窄按钮参与原生布局，并取消它的额外宽度。包含下载键的操作栏将原生最小间距上限设为 4 点、最大间距上限设为 8 点；原本更小的间距继续沿用。
- 由原生布局继续计算图标、计数、方向和点击区域。不缩放整行，不隐藏书签、分享或统计数据；没有下载键的行沿用原布局。
- 纯图片帖子：点击一次保存该帖全部图片，含单图和多图，不逐张弹出保存菜单。视频/GIF 帖子仍调用原 `DownloadInlineButton` 的清晰度和保存选项。
- 图文与视频混合的帖子：提供“保存全部图片”和“下载视频 / GIF”两个入口，避免视频清晰度选择和照片授权同时弹出。
- 点击时读取按钮当前的 view model，不把旧帖子的媒体捕获在闭包里。
- 纯文字帖子不新增按钮。图片地址在点击时快照保存，滚动复用后不会改成另一条帖子的图片。
- 保留原“更多”菜单入口以及回复、转发、点赞、浏览量、书签、分享行为。
- 依赖原插件提供的类和方法；按钮注册检查发现接口缺失时不安装快捷键，输出不含用户内容的状态日志。这项检查不能保证捕获宿主内部的所有兼容问题。
- 使用 Objective-C runtime 连接原生按钮，不附带 Substrate、ElleKit 或其他 Hook 框架。

## 在 GitHub 构建

1. 将源码 ZIP **解压后的全部内容**上传到仓库根目录，覆盖旧版文件。必须包含新增的 `NFBPhotoSupport.h/.m`、`NFBPhotoDownloader.h/.m`、`tests/photo-support-smoke.m` 和更新后的构建脚本、工作流；不要只替换主 `.m` 或上传 ZIP。
2. 提交到默认分支，然后打开 **Actions → Build download shortcut dylib → Run workflow**。
3. 成功后会有两个产物：本次直接下载 **NFBActionBarDownload-arm64**。另一个 **NFBActionBarLoadProbe-arm64** 是空载对照，正常使用时无需添加。
4. 每个产物包含对应动态库、SHA-256、构建模式、系统依赖、源码提交和 Xcode 版本记录。

这个流程不要求 X 的 IPA，不需要上传 Apple ID、证书或私钥。它只构建动态库并上传本次运行产物，不创建 Release。产物经过临时签名；最终注入/安装仍由你的注入器或签名工具按实际设备要求处理。

## 普通图片的保存行为

- 普通图片始终直接保存到系统相册，不使用视频的 `direct_save` 菜单设置。首次需要允许 X 保存照片。优先申请“只添加”权限；安装包只有原有读写权限说明时，使用其声明的 Photos 权限级别。本功能不读取相册内容。
- Twitter 图片优先请求 `name=orig`，原图不可用时尝试帖子原有地址。其他 HTTPS 图片地址保持原样；图片文件按下载字节保存，不重新压缩。
- 顺序下载并导入帖子内所有图片，包括重复附图；同一时刻处理一条帖子，进行中再次点击不会追加重复任务。请保持 X 前台运行直到结果提示。
- 只有 PhotoKit 确认导入成功才计入“已保存”。地址缺失、网络错误或导入失败会计入失败数，不会少保存几张却提示全部成功。再次下载整条帖子会再次保存已经成功的图片。
- 网络请求使用独立临时会话，不使用 X 账号 Cookie、凭据或 token。下载临时文件保留到相册导入完成后再清理。
- 实际主包必须包含相册用途说明；缺失时显示错误并停止，不直接请求权限导致 X 退出。通常沿用 X 自身的用途说明和授权即可，无需修改插件配置。

## 更新与图片验收

保留原 NeoFreeBird 及其依赖，用本次构建的 `NFBActionBarDownload.dylib` 替换旧快捷键库，只启用一个快捷键库。空载库保持禁用。完全退出再打开 X，检查以下场景：

- 与问题截图相似、计数较大的视频帖子：回复、转发、点赞、浏览量、下载、书签和分享应全部在屏幕内，文字和图标没有重叠。
- 单张普通图片：按钮可见，点击后相册新增一张；2–4 张图片：点击一次保存全部，数量正确。
- 图片/视频混合帖：分别验证批量照片和原视频/GIF 清晰度菜单；拒绝相册权限时显示提示，X 继续可用。
- 图片原图地址失败时能回退，部分失败时显示实际数量；保存过程中连续点击不产生重复任务。
- 点击下载仍能打开下载选项并保存媒体；书签和分享仍可点击。
- 快速滚动后下载的媒体对应当前帖子；文字/纯图片帖子及关闭下载开关时，原操作栏保持原样。
- 帖子详情页、横竖屏和较大字体下没有新的截断。

本版只准备了这些验收场景，没有手机上的通过证据。需要 GitHub 的新编译产物和目标手机验证，才能确认此版本通过。

## 可选：启动问题的空载对照

1. 保持导致闪退的旧快捷键库禁用，确认 X 能打开；保留原 NeoFreeBird 及其依赖。
2. 解压 **NFBActionBarLoadProbe-arm64**，只添加里面的 `NFBActionBarLoadProbe.dylib`，使用同一注入器和相同注入方式。确认测试库已启用，旧快捷键库仍禁用；此时不要加入快捷键候选版。
3. 完全退出并重新打开 X，记录是否仍然点开就退出。空载版没有按钮，预期界面与未添加快捷键时相同。
4. 若空载版仍导致退出，优先核对注入/签名流程、依赖和加载结果；若空载版能打开且确认实际已加载，则下一步检查快捷键的宿主接口和按钮代码。单次不闪退不能证明库实际加载，未取得日志前也不能把对照结果当作最终根因。
5. 完成对照后禁用或移除空载库。需要验证快捷键候选版时，只添加 **NFBActionBarDownload-arm64** 中的 `NFBActionBarDownload.dylib`，不要同时启用多份旧/新快捷键库。

两个库由同一份源码和相同目标平台/链接/签名选项构建，并显式链接 Foundation、UIKit、CoreFoundation、CoreGraphics、Photos、ImageIO、UniformTypeIdentifiers、QuartzCore 和 libobjc。主 Hook 保留 MRC，异步照片模块在独立编译单元使用 ARC。空载版使用 `NFB_LOAD_ONLY=1`，加载回调直接返回，不执行 Hook 或照片任务；快捷键版使用 `NFB_LOAD_ONLY=0`。构建会比较两者链接的系统库并在不一致时停止。这些检查不模拟白魔注入器或真实手机签名环境。

本轮未操作白魔注入器，具体按钮名称和签名步骤请以你的版本为准。先确认 NeoFreeBird 设置中的下载媒体开关已打开，再在含视频/GIF 的帖子上检查下载图标。源代码 ZIP 不是可注入文件。

## 本机 Mac 构建

安装 Xcode 及 iPhoneOS SDK 后，在本目录执行：

```bash
bash test-runtime.sh
bash build.sh
```

输出：`build/load-test/NFBActionBarLoadProbe.dylib` 和 `build/shortcut/NFBActionBarDownload.dylib`。构建开启 `-Wall -Wextra -Werror`，失败会停止；检查签名、arm64 和 iOS 平台信息后生成 SHA-256。两者最低部署版本均为 iOS 15；仅有部署版本匹配不代表全部运行时接口兼容。原生 UIKit 按钮本身仍须在目标设备上验收。

## 验证边界

Windows 本轮可检查源码差异、Bash/YAML 语法、交付 ZIP 内容和 SHA-256。Actions 会执行已有的运行时签名检查，以及新增的图片地址、顺序、类型路由、无效图片计数和复用快照测试；这些 Foundation 测试不运行 X 或 PhotoKit。新图片下载、权限、导入和混合菜单需要真实手机验收。随包 `VALIDATION.json` 记录实际执行结果。

用户当前组合已通过上一版的一次启动和媒体下载验证；这不覆盖所有帖子类型、所有设置组合或 X 的其他版本。遇到新崩溃时可使用空载库对照；后续如出现崩溃报告，请保留 Termination Reason、Exception Type、Last Exception Backtrace 和触发线程。

待目标设备验证：正常视频、GIF、多个视频、文字/图片帖子、关闭下载开关、快速滚动复用、帖子详情、隐藏书签、深浅色、动态字体、旋转及原有按钮交互。本轮没有上述场景的通过证据。

## 接口依据与许可

- [NeoFreeBird 7.3.0 下载入口](https://github.com/NeoFreeBird/app/blob/v7.3.0/src/Hooks/MediaDownloads.x)：设置键、视频/GIF 类型和下载器调用。
- [媒体实体接口](https://github.com/NeoFreeBird/app/blob/v7.3.0/src/Headers/TFSHeaders.h)：普通图片 `mediaType=1`、GIF `2`、视频 `3` 以及 `mediaURL` 字段。
- [Apple PhotoKit 原文件导入](https://developer.apple.com/documentation/photos/phassetcreationrequest/addresource%28with%3Afileurl%3Aoptions%3A%29?language=objc)、[照片授权](https://developer.apple.com/documentation/Photos/PHPhotoLibrary/requestAuthorization%28for%3Ahandler%3A%29?language=objc)、[相册添加用途说明](https://developer.apple.com/documentation/bundleresources/information-property-list/nsphotolibraryaddusagedescription)：异步导入、权限和主包用途声明。
- [当前操作栏类接口](https://github.com/NeoFreeBird/app/blob/v7.3.0/src/Hooks/HideUI.x)：按钮类数组及书签/浏览量/分享类。
- [作者维护的原生按钮接口记录](https://github.com/NeoFreeBird/classdump/blob/72524d49d12bfa18278df85a995e1f9d65afa493/TwitterSPMAppMigration/TTAStatusInlineActionButton.h)：初始化、图片、状态、布局和点击接口；记录本身不能证明所有新版运行时都相同。
- [原生操作栏布局接口](https://github.com/NeoFreeBird/classdump/blob/72524d49d12bfa18278df85a995e1f9d65afa493/TwitterSPMAppMigration/TTAStatusInlineActionsView.h)：窄按钮分类、原生间距和布局参数。本版保留原生宽度、对齐计算器，不执行私有 block。
- [早期内联按钮](https://github.com/NeoFreeBird/tweak/blob/master/BHDownloadInlineButton.m)：原自定义下载动作编号。
- [Apple Objective-C runtime 实现](https://github.com/apple-oss-distributions/objc4/blob/main/runtime/objc-runtime-new.mm)：`class_getInstanceMethod` 可能尝试方法解析；元类关联查找失败会中止进程。

这是用户定制的配套项目，不是 NeoFreeBird 官方发布版本。沿用 GPL-3.0 许可，见 `LICENSE`。
