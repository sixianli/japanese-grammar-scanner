# 端到端测试覆盖清单

端到端测试（`JapaneseGrammarScannerUITests/`）在每次提交时由 CI（iOS Build & Test → **e2e**）在 iPhone 模拟器上运行：
像用户一样点击、输入、滑动、返回，检查每一步到达的页面。任何一条失败，版本都不会上传 TestFlight。
失败时自动保存截图（Actions 页面的 `e2e` 附件）。

启动状态：`-e2e` 清空本地数据并放入固定数据（4 条扫描记录、10 条浏览记录，其中 5 条是 10 天前看的），
`-e2eFresh` 为全新安装状态（会显示引导页，没有任何记录）。

## 功能路径 → 测试

| 区域 | 功能路径 | 测试 |
|---|---|---|
| 引导 | 首次启动 → 逐页「下一步」→「开始使用」→ 新用户首页 → 入门语法 → 讲解 | `FreshInstallTests.testOnboardingNextThroughThenStart` |
| 引导 | 「跳过」→「先用示例书页试试」→ 识别结果 | `FreshInstallTests.testOnboardingSkipThenTrySample` |
| 空状态 | 收藏为空、搜索页没有浏览记录 | `FreshInstallTests.testEmptyStates` |
| 首页 | 相机扫描 → 扫描标签 | `HomeTests.testCameraButtonOpensScanTab` |
| 首页 | 没有大标题，相机按钮里一行说明；扫描过以后不显示「试试示例」 | `HomeTests.testHomeHasNoHeadlineAndHidesSampleLinkAfterScanning` |
| 首页（新用户） | 还没扫描过时显示「试试示例」小链接 → 识别结果 | `FreshInstallTests.testNewUserHomeShowsSmallSampleLink` |
| 首页 | 从相册识别 → 选照片 → 识别结果 | `HomeTests.testPhotoPickerOpensResult` |
| 首页 | 底部反馈入口 → 反馈页 → 取消 | `HomeTests.testFeedbackLinkOpensFeedback` |
| 首页 | 搜索框 → 搜索标签并获得焦点 | `EndToEndTests.testHomeSearchEntryOpensSearchTab` |
| 首页 | 继续上次 → 识别结果 → 语法点 → 讲解 → 点首页标签回到顶部 | `EndToEndTests.testContinueScanThenGrammarThenHomeTab` |
| 首页 | 全部扫描记录 → 依次打开多条记录 → 返回列表 → 返回首页 | `EndToEndTests.testAllScansOpensEveryRecord` |
| 首页 | 全部扫描记录 → 清除 → 确认 → 首页不再有「继续上次」 | `HomeTests.testClearAllScans` |
| 首页 | 最近查看 / 快要忘了 → 查看全部 → 讲解 → 返回 | `EndToEndTests.testSeeAllRecentAndForgetting` |
| 首页 | 最近查看 → 清除 → 确认 → 首页不再显示 | `HomeTests.testClearRecentViewed` |
| 首页 | 列表里的语法点 → 讲解 → 收藏 → 收藏标签 → 打开 | `EndToEndTests.testHomeGrammarRowOpensDetailAndFavorite` |
| 扫描 | 扫描标签 → 试试示例 → 结果 → 放大 / 关闭 → 讲解 → 切标签再切回 → 再点扫描回到首页 | `EndToEndTests.testSampleScanResultZoomAndTabs` |
| 扫描 | 扫描标签 → 相册 → 选照片 → 识别结果 | `ScanResultTests.testScanTabPhotoPicker` |
| 扫描 | 取景时只提示拍照，画面上没有语法框 | `LineSelectFlowTests.testScanTabOnlyFramesWithoutRecognizing` |
| 选行 | 拍完先显示照片和认出的行，没有语法框、没有语法列表 | `LineSelectFlowTests.testPhotoShowsLinesWithoutGrammarBoxesBeforeAnalyzing` |
| 选行 | 点一行 →「分析这 1 行」→ 只列这一行的语法（反向：别的行的「らしい」「たことがある」不出现） | `LineSelectFlowTests.testTapOneLineShowsOnlyThatLinesGrammar` |
| 选行 | 按住从一行拖到下面第二行 → 正好选中 3 行 → 只列这 3 行的语法（反向：「ながら」不出现） | `LineSelectFlowTests.testDragSelectsSeveralWholeLines` |
| 选行 | 再点已选的行取消选择 | `LineSelectFlowTests.testTapSelectedLineAgainDeselectsIt` |
| 选行 | 分析整页 → 重新选行 → 只看一行，语法点比整页少 | `LineSelectFlowTests.testAnalyzeWholePageThenReselectOneLine` |
| 选行 | 选了行后改为分析整页 | `LineSelectFlowTests.testSwitchToWholePageAfterSelecting` |
| 识别结果 | 点高亮框 → 讲解（多个语法点时先选择） | `ScanResultTests.testHighlightBoxOpensGrammarOrChooser` |
| 识别结果 | 列表中每个语法点 → 讲解 → 返回 | `ScanResultTests.testResultRowsAllOpenDetail` |
| 识别结果 | 进入讲解后顶部显示「你扫到的：…」，对应用法高亮，点横幅跳到该用法；从搜索进入不显示 | `ScanResultTests.testScannedMatchBannerOnDetail` / `testNoScannedBannerFromSearch` |
| 识别结果 | 一个框里有多个语法点时，选项附上各自命中的原文 | `ScanResultTests.testChooserOptionsShowMatchedText` |
| 识别结果 | 放大按钮 → 全屏 → 双击放大 / 还原 → 关闭 | `ScanResultTests.testZoomButtonDoubleTapAndClose` |
| 识别结果 | 双指放大进入全屏 → 双指缩小退出 | `ScanResultTests.testPinchOpensZoomAndPinchInCloses` |
| 识别结果 | 全屏时向下滑退出 | `ScanResultTests.testSwipeDownClosesZoom` |
| 识别结果 | 手动修正文字 → 输入 → 重新识别 | `ScanResultTests.testEditTextAndReanalyze` |
| 识别结果 | 手动修正文字 → 取消 | `ScanResultTests.testEditTextCancel` |
| 讲解 | 点义项 → 页内跳转 | `DetailTests.testSenseRowsJumpWithinPage` |
| 讲解 | 相近语法 → 另一个讲解 → 返回原讲解 → 返回搜索 | `DetailTests.testSimilarGrammarPushesAndBackReturns` |
| 讲解 | 底部「讲解有误？告诉我们」→ 反馈页 → 取消 | `DetailTests.testDetailFeedbackLink` |
| 讲解 | 收藏后右上角按钮消失、标题下出现「已收藏」→ 收藏页左滑「取消收藏」→ 回讲解页按钮重新出现 | `DetailTests.testFavoriteHidesButtonAndUnfavoriteBySwipeInList` |
| 讲解 | 点「已收藏」→「取消收藏」→ 按钮重新出现、收藏页为空 | `DetailTests.testUnfavoriteFromFavoritedTagOnDetail` |
| 讲解（反向） | 没收藏时按钮一直在、没有「已收藏」 | `DetailTests.testUnfavoritedGrammarKeepsButtonAndHasNoTag` |
| 讲解 | 往上滑时大标题跟着移进顶栏正中并缩小、标题下出现一行缩小的标签（等级、必考），没收藏的没有「已收藏」；回到顶部复原 | `DetailTests.testTitleFollowsScrollIntoCenteredBar` |
| 讲解 | 最长的几个标题（〜ままに・〜られるままに・〜がままに、〜いかんで（は）／〜いかんによっては、〜んです・〜のです・〜んだ）展开和收起两种状态都只占一行、在返回键和收藏键之间居中、不压按钮、不超出屏幕 | `DetailTests.testLongTitleMamaniStaysOneLineCenteredInBothStates`、`testLongTitleIkanDeWaStaysOneLineCenteredInBothStates`、`testLongTitleNdesuStaysOneLineCenteredInBothStates` |
| 讲解 | 收藏过的语法，顶栏标签行里「已收藏」和等级排在同一行 | `DetailTests.testFavoritedTagJoinsBarRow` |
| 复习 | 复习页收藏 → 顶部提示「已收进收藏」→ 按钮消失、出现「已收藏」 | `ReviewTests.testFavoriteDuringReviewHidesButtonAndConfirms` |
| 动效 | 樱花落进袋子、标签图标变粉时仍能点「收藏」标签 | `SakuraAnimationTests.testFavoritesTabReachableWhenPouchTurnsPink` |
| 语法库 | 列表 → 讲解 → 返回 | `EndToEndTests.testLibraryOpensDetail` |
| 语法库 | N5–N1、全部 等级筛选 | `LibraryTests.testLevelFilters` |
| 语法库 | 往上滑后搜索框和等级筛选固定在顶部，仍能点 N3 筛选 | `LibraryTests.testLevelFilterStaysPinnedWhenScrolling` |
| 语法库 | 搜索 → 讲解；无结果 | `LibraryTests.testLibrarySearchOpensDetail` / `testLibrarySearchNoResults` |
| 语法库 | 讲解 → 切首页 → 切回仍在讲解 → 再点回到列表 | `LibraryTests.testTabKeepsItsOwnPage` |
| 收藏 | 语法库点星号收藏 3 个 → 三种排序 | `FavoritesTests.testSortMenuAllOptions` |
| 收藏 | 左滑「取消收藏」 | `FavoritesTests.testSwipeToUnfavorite` |
| 收藏 | 打开讲解 → 再点收藏标签回到列表 | `FavoritesTests.testOpenDetailAndRetapTab` |
| 搜索 | 点搜索标签自动获得焦点；从讲解页切走再回来，回到搜索页并获得焦点 | `EndToEndTests.testSearchTabFocusesFieldEveryTime` |
| 搜索 | 未输入时显示最近查看 → 打开 | `SearchTests.testRecentViewsShownWhenEmpty` |
| 搜索 | 无结果；只在例句中出现；按中文意思搜索 | `SearchTests.testNoResults` / `testFoundOnlyInExamples` / `testChineseMeaningSearch` |
| 搜索 | 输入后点空白处收起键盘、文字保留；拖动结果列表收起键盘 | `SearchTests.testTapOutsideDismissesKeyboard` |
| 设置 | 打开 / 关闭设置面板 | `SettingsTests.*` |
| 设置 | 外观：逐个点所有主题色和背景色 | `SettingsTests.testAppearanceAllSwatches` |
| 设置 | 语言：逐个切换 8 种语言，界面立即变化 | `SettingsTests.testEveryLanguage` / `EndToEndTests.testSettingsSheetAndLanguageSwitch` |
| 设置 | 切换到英文后讲解内容也变成英文 | `SettingsTests.testLanguageAppliesToContent` |
| 设置 | 三种反馈 → 填写 → 发送 → 弹出分享面板 | `SettingsTests.testFeedbackAllKindsSendOpensShareSheet` |
| 设置 | 反馈添加截图 → 删除截图 | `SettingsTests.testFeedbackAddScreenshot` |
| 设置 | 反馈输入后点键盘上方「完成」收起键盘 | `SettingsTests.testFeedbackKeyboardDone` |
| 设置 | 匿名使用统计开关：默认打开，关闭后保存 | `SettingsTests.testUsageStatsToggle` |
| 设置 | 使用引导 → 跳过 → 开始使用 | `SettingsTests.testOnboardingFromSettings` |
| 设置 | 隐私政策、使用条款、开源许可、版本 | `SettingsTests.testAboutPages` |

## 模拟器上测不了的（及替代验证方式）

| 功能 | 原因 | 替代验证 |
|---|---|---|
| 相机取景、快门拍照、补光 | 模拟器没有相机 | 拍照之后的选行、分析流程用示例书页覆盖（`LineSelectFlowTests`）；取景和快门由测试人员在 TestFlight 版本上验证 |
| 双指缩放的跟手程度、滑动流畅度 | 属于主观手感，UI 测试只能验证功能是否正确 | TestFlight 真机体验 |
| App 内一键提交反馈（CloudKit） | 需要开发者账号开通 iCloud 容器和 iCloud 登录 | 开通后用 TestFlight 版本实际提交一次，并确认邮件转发 |
| 付费（试用、购买、恢复购买） | 当前版本已关闭收费（`Features.paymentsEnabled = false`） | 重新开启收费时补充 StoreKit 测试 |
