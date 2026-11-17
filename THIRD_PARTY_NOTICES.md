# Third-Party Notices / 第三方组件声明

The app ships with no third-party runtime libraries. It uses only Apple frameworks (SwiftUI, Vision, AVFoundation, StoreKit).
The following open-source components are used at build time to generate static data or images bundled in the app.

本 App 不包含任何第三方运行时库，只使用 Apple 系统框架。以下开源组件仅在构建阶段用于生成 App 内的静态数据或图片。

| Component | Used for | License |
| --- | --- | --- |
| [SudachiPy](https://github.com/WorksApplications/sudachi.rs) / [SudachiDict](https://github.com/WorksApplications/SudachiDict) | Furigana data (`Resources/Grammar/furigana.json`, `tools/make_furigana.py`) | Apache License 2.0, © Works Applications Co., Ltd. |
| [OpenCC](https://github.com/BYVoid/OpenCC) (opencc-python-reimplemented) | Traditional Chinese text (`tools/make_zh_hant.py`) | Apache License 2.0 |
| [Noto Serif JP](https://fonts.google.com/noto/specimen/Noto+Serif+JP) | App icon (`tools/make_icon.py`) | SIL Open Font License 1.1 |
| [IPA Font](https://moji.or.jp/ipafont/) | Sample page image (`tools/make_sample_page.py`) | IPA Font License Agreement v1.0 |
| [Pillow](https://python-pillow.org) | Image generation scripts (not shipped) | MIT-CMU |

Apache License 2.0: http://www.apache.org/licenses/LICENSE-2.0 — SIL OFL 1.1: https://openfontlicense.org
