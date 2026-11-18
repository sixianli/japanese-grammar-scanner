#!/usr/bin/env python3
"""生成界面文字的 String Catalog（Localizable.xcstrings / InfoPlist.xcstrings）。
源语言为简体中文（代码中的字符串即 key）；繁体中文由 OpenCC 自动转换。
用法: python3 tools/make_strings.py
"""
import json
import os
import re

from opencc import OpenCC

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "JapaneseGrammarScanner")
cc = OpenCC("s2twp")

# key(简体中文) : (en, ko, es, vi)
S = {
    "扫描": ("Scan", "스캔", "Escanear", "Quét"),
    "语法库": ("Grammar", "문법 사전", "Gramática", "Ngữ pháp"),
    "收藏": ("Favorites", "즐겨찾기", "Favoritos", "Yêu thích"),
    "取消收藏": ("Remove from Favorites", "즐겨찾기 해제", "Quitar de favoritos", "Bỏ yêu thích"),
    "意思": ("Meaning", "의미", "Significado", "Ý nghĩa"),
    "用法": ("Usage", "용법", "Uso", "Cách dùng"),
    "接续": ("Formation", "접속", "Formación", "Cách kết hợp"),
    "使用场景": ("When to Use", "사용 장면", "Cuándo se usa", "Tình huống sử dụng"),
    "词源": ("Origin", "어원", "Origen", "Nguồn gốc"),
    "例句": ("Examples", "예문", "Ejemplos", "Ví dụ"),
    "关闭": ("Close", "닫기", "Cerrar", "Đóng"),
    "购买失败": ("Purchase Failed", "구매 실패", "Error en la compra", "Mua thất bại"),
    "好": ("OK", "확인", "Aceptar", "OK"),
    "解锁完整讲解": ("Unlock Full Explanations", "전체 설명 잠금 해제", "Desbloquear explicaciones completas", "Mở khóa toàn bộ giải thích"),
    "扫到不懂的语法，马上看懂。": ("Scan a grammar point you don't know — understand it instantly.", "모르는 문법을 스캔하면 바로 이해됩니다.", "Escanea la gramática que no entiendes y compréndela al instante.", "Quét mẫu ngữ pháp chưa hiểu, hiểu ngay lập tức."),
    "全部 N5–N1 语法点的完整讲解": ("Full explanations for every N5–N1 grammar point", "N5–N1 모든 문법의 전체 설명", "Explicaciones completas de toda la gramática N5–N1", "Giải thích đầy đủ mọi mẫu ngữ pháp N5–N1"),
    "按义项分段的用法、接续与例句": ("Usage by meaning, with formation and examples", "의미별 용법·접속·예문", "Usos por significado, con formación y ejemplos", "Cách dùng theo từng nghĩa, kèm cách kết hợp và ví dụ"),
    "日常生活与职场的使用场景": ("Real situations from daily life and work", "일상생활과 직장의 사용 장면", "Situaciones reales de la vida diaria y el trabajo", "Tình huống thực tế trong đời sống và công việc"),
    "词源与相近语法对比": ("Origins and comparisons with similar grammar", "어원과 비슷한 문법 비교", "Origen y comparación con gramática similar", "Nguồn gốc và so sánh ngữ pháp tương tự"),
    "例句汉字全部标注假名": ("Furigana on every kanji in examples", "예문의 모든 한자에 후리가나 표기", "Furigana en todos los kanji de los ejemplos", "Furigana cho mọi chữ Hán trong ví dụ"),
    "完全离线，无广告，无追踪": ("Fully offline. No ads, no tracking.", "완전 오프라인 · 광고 없음 · 추적 없음", "Totalmente sin conexión. Sin anuncios ni rastreo.", "Hoàn toàn ngoại tuyến, không quảng cáo, không theo dõi"),
    "免费试用中，还剩 %lld 天": ({"one": "Free trial: %lld day left", "other": "Free trial: %lld days left"}, "무료 체험 중 · %lld일 남음", {"one": "Prueba gratis: queda %lld día", "other": "Prueba gratis: quedan %lld días"}, "Đang dùng thử miễn phí, còn %lld ngày"),
    "免费试用已结束": ("Free trial has ended", "무료 체험이 끝났습니다", "La prueba gratis ha terminado", "Thời gian dùng thử đã kết thúc"),
    "开始 %lld 天免费试用": ("Start %lld-Day Free Trial", "%lld일 무료 체험 시작", "Empezar prueba gratis de %lld días", "Bắt đầu dùng thử miễn phí %lld ngày"),
    "免费开始使用": ("Start Free", "무료로 시작하기", "Empezar gratis", "Bắt đầu miễn phí"),
    "前 %lld 天免费使用全部功能。之后可一次性 %@ 永久解锁完整讲解，不订阅、不自动扣费。": (
        "All features free for the first %lld days. After that, unlock full explanations forever with a one-time %@ purchase. No subscription, no automatic charges.",
        "처음 %lld일 동안 모든 기능 무료. 이후 %@ 한 번 구매로 전체 설명을 영구 잠금 해제할 수 있습니다. 구독 없음, 자동 결제 없음.",
        "Todas las funciones gratis durante los primeros %lld días. Después, desbloquea las explicaciones completas para siempre con una compra única de %@. Sin suscripción ni cargos automáticos.",
        "Miễn phí mọi tính năng trong %lld ngày đầu. Sau đó, mua một lần %@ để mở khóa vĩnh viễn toàn bộ giải thích. Không đăng ký, không tự động trừ tiền.",
    ),
    "前 %lld 天免费使用全部功能。之后可一次性购买永久解锁完整讲解，不订阅、不自动扣费。": (
        "All features free for the first %lld days. After that, unlock full explanations forever with a one-time purchase. No subscription, no automatic charges.",
        "처음 %lld일 동안 모든 기능 무료. 이후 한 번 구매로 전체 설명을 영구 잠금 해제할 수 있습니다. 구독 없음, 자동 결제 없음.",
        "Todas las funciones gratis durante los primeros %lld días. Después, desbloquea las explicaciones completas para siempre con una compra única. Sin suscripción ni cargos automáticos.",
        "Miễn phí mọi tính năng trong %lld ngày đầu. Sau đó, mua một lần để mở khóa vĩnh viễn toàn bộ giải thích. Không đăng ký, không tự động trừ tiền.",
    ),
    "免费试用还剩 %lld 天": ({"one": "%lld day left in your free trial", "other": "%lld days left in your free trial"}, "무료 체험 %lld일 남음", {"one": "Te queda %lld día de prueba gratis", "other": "Te quedan %lld días de prueba gratis"}, "Còn %lld ngày dùng thử miễn phí"),
    "一次性 %@ 永久解锁，不订阅": ("Unlock forever for a one-time %@. No subscription.", "%@ 한 번 구매로 영구 잠금 해제 · 구독 없음", "Desbloqueo para siempre por un pago único de %@. Sin suscripción.", "Mua một lần %@ để mở khóa vĩnh viễn, không đăng ký"),
    "一次性购买永久解锁，不订阅": ("Unlock forever with a one-time purchase. No subscription.", "한 번 구매로 영구 잠금 해제 · 구독 없음", "Desbloqueo para siempre con un pago único. Sin suscripción.", "Mua một lần để mở khóa vĩnh viễn, không đăng ký"),
    "免费 · 到期后不会自动扣费": ("Free · No automatic charge afterwards", "무료 · 종료 후 자동 결제 없음", "Gratis · Sin cargos automáticos después", "Miễn phí · Không tự động trừ tiền"),
    "一次性购买 %@": ("One-Time Purchase %@", "한 번 구매 %@", "Compra única %@", "Mua một lần %@"),
    "永久解锁 · 无需订阅": ("Unlock forever · No subscription", "영구 잠금 해제 · 구독 없음", "Desbloqueo para siempre · Sin suscripción", "Mở khóa vĩnh viễn · Không cần đăng ký"),
    "恢复购买": ("Restore Purchases", "구매 복원", "Restaurar compras", "Khôi phục giao dịch"),
    "免费试用期为 %lld 天，期间可使用全部内容。试用结束后不会自动收费；如需继续查看完整讲解，可一次性购买永久解锁。扫描识别与语法高亮始终免费。": (
        "The free trial lasts %lld days and includes all content. You won't be charged automatically when it ends; to keep reading full explanations, make a one-time purchase to unlock them forever. Scanning and grammar highlighting are always free.",
        "무료 체험은 %lld일이며 모든 콘텐츠를 이용할 수 있습니다. 체험이 끝나도 자동으로 결제되지 않습니다. 전체 설명을 계속 보려면 한 번 구매로 영구 잠금 해제하세요. 스캔과 문법 하이라이트는 항상 무료입니다.",
        "La prueba gratis dura %lld días e incluye todo el contenido. No se te cobrará automáticamente al terminar; para seguir leyendo las explicaciones completas, haz una compra única y desbloquéalas para siempre. El escaneo y el resaltado de gramática son siempre gratis.",
        "Dùng thử miễn phí %lld ngày với toàn bộ nội dung. Khi hết hạn sẽ không tự động trừ tiền; để tiếp tục xem giải thích đầy đủ, hãy mua một lần để mở khóa vĩnh viễn. Quét và tô sáng ngữ pháp luôn miễn phí.",
    ),
    "隐私政策": ("Privacy Policy", "개인정보 처리방침", "Política de privacidad", "Chính sách quyền riêng tư"),
    "使用条款": ("Terms of Use", "이용 약관", "Términos de uso", "Điều khoản sử dụng"),
    "用法、例句、使用场景、词源、相近语法对比": ("Usage, examples, situations, origin and similar grammar", "용법·예문·사용 장면·어원·비슷한 문법", "Uso, ejemplos, situaciones, origen y gramática similar", "Cách dùng, ví dụ, tình huống, nguồn gốc và ngữ pháp tương tự"),
    "查看解锁方式": ("See Unlock Options", "잠금 해제 방법 보기", "Ver opciones de desbloqueo", "Xem cách mở khóa"),
    "设置": ("Settings", "설정", "Ajustes", "Cài đặt"),
    "购买": ("Purchase", "구매", "Compra", "Mua"),
    "状态": ("Status", "상태", "Estado", "Trạng thái"),
    "关于": ("About", "정보", "Acerca de", "Giới thiệu"),
    "支持与反馈": ("Support & Feedback", "지원 및 피드백", "Soporte y comentarios", "Hỗ trợ & phản hồi"),
    "开源许可": ("Open-Source Licenses", "오픈소스 라이선스", "Licencias de código abierto", "Giấy phép mã nguồn mở"),
    "版本": ("Version", "버전", "Versión", "Phiên bản"),
    "已永久解锁": ("Unlocked forever", "영구 잠금 해제됨", "Desbloqueado para siempre", "Đã mở khóa vĩnh viễn"),
    "未开始试用": ("Trial not started", "체험 시작 전", "Prueba no iniciada", "Chưa bắt đầu dùng thử"),
    "用于离线生成例句的假名注音数据": ("Used offline to generate furigana for example sentences", "예문 후리가나 데이터를 오프라인으로 생성하는 데 사용", "Se usa sin conexión para generar el furigana de los ejemplos", "Dùng ngoại tuyến để tạo furigana cho câu ví dụ"),
    "用于把讲解转换为繁体中文": ("Used to convert explanations to Traditional Chinese", "설명을 번체 중국어로 변환하는 데 사용", "Se usa para convertir las explicaciones al chino tradicional", "Dùng để chuyển giải thích sang tiếng Trung phồn thể"),
    "用于绘制 App 图标": ("Used to draw the app icon", "앱 아이콘 제작에 사용", "Se usa para dibujar el icono de la app", "Dùng để vẽ biểu tượng ứng dụng"),
    "用于绘制示例书页图片": ("Used to draw the sample page image", "예시 페이지 이미지 제작에 사용", "Se usa para dibujar la página de ejemplo", "Dùng để vẽ trang sách mẫu"),
    "本 App 的语法讲解为原创内容。文字识别使用 Apple Vision 框架在设备上完成。以下第三方开源组件仅在构建阶段用于生成 App 内的静态数据或图片：": (
        "All grammar explanations are original content. Text recognition runs on-device with Apple's Vision framework. The open-source components below were used only at build time to generate static data or images:",
        "이 앱의 문법 설명은 모두 독자적으로 작성되었습니다. 문자 인식은 Apple Vision 프레임워크로 기기에서 처리됩니다. 아래 오픈소스 구성 요소는 빌드 단계에서 정적 데이터나 이미지를 만드는 데만 사용되었습니다:",
        "Todas las explicaciones son contenido original. El reconocimiento de texto se realiza en el dispositivo con el framework Vision de Apple. Los siguientes componentes de código abierto solo se usaron al compilar, para generar datos estáticos o imágenes:",
        "Toàn bộ giải thích ngữ pháp là nội dung gốc. Nhận dạng chữ chạy trên thiết bị bằng Apple Vision. Các thành phần mã nguồn mở dưới đây chỉ được dùng khi build để tạo dữ liệu tĩnh hoặc hình ảnh:",
    ),
    "跳过": ("Skip", "건너뛰기", "Omitir", "Bỏ qua"),
    "下一步": ("Next", "다음", "Siguiente", "Tiếp"),
    "开始使用": ("Get Started", "시작하기", "Empezar", "Bắt đầu"),
    "先用示例书页试试": ("Try the Sample Page First", "예시 페이지로 먼저 체험하기", "Probar primero la página de ejemplo", "Thử trước với trang mẫu"),
    "对准日文，语法一目了然": ("Point at Japanese, See the Grammar", "일본어에 대면 문법이 한눈에", "Apunta al japonés y verás la gramática", "Hướng vào tiếng Nhật, ngữ pháp hiện ra ngay"),
    "读日语书遇到看不懂的句子？用相机扫一下，文中的语法点会自动找出来并高亮。": (
        "Stuck on a sentence in a Japanese book? Scan it with the camera and every grammar point is found and highlighted.",
        "일본어 책에서 모르는 문장이 나왔나요? 카메라로 스캔하면 문법이 자동으로 찾아져 하이라이트됩니다.",
        "¿Te atascas con una frase en un libro japonés? Escanéala con la cámara y cada punto gramatical se detecta y resalta.",
        "Gặp câu khó trong sách tiếng Nhật? Quét bằng camera, mọi mẫu ngữ pháp sẽ được tìm và tô sáng."),
    "扫描书本或截图": ("Scan Books or Screenshots", "책이나 스크린샷 스캔", "Escanea libros o capturas", "Quét sách hoặc ảnh chụp màn hình"),
    "把相机对准书页，语法会实时高亮，颜色代表 JLPT 等级。按中间的快门定格画面做精细识别，也可以从相册选择截图。": (
        "Point the camera at a page and grammar lights up in real time, colored by JLPT level. Tap the shutter for a detailed analysis, or pick a screenshot from Photos.",
        "카메라를 페이지에 대면 문법이 실시간으로 하이라이트되며 색상은 JLPT 레벨을 나타냅니다. 셔터를 누르면 정밀 분석을, 사진에서 스크린샷을 고를 수도 있습니다.",
        "Apunta la cámara a una página y la gramática se resalta al instante, con colores según el nivel JLPT. Pulsa el obturador para un análisis detallado o elige una captura de Fotos.",
        "Hướng camera vào trang sách, ngữ pháp được tô sáng theo thời gian thực với màu theo cấp JLPT. Nhấn nút chụp để phân tích chi tiết, hoặc chọn ảnh chụp màn hình từ thư viện."),
    "点击高亮，查看讲解": ("Tap a Highlight to Learn", "하이라이트를 눌러 설명 보기", "Toca un resaltado para aprender", "Nhấn vào phần tô sáng để xem giải thích"),
    "每个语法点都有意思、用法、例句、使用场景、词源和相近语法对比。例句里的汉字都标注了假名。": (
        "Every grammar point comes with meaning, usage, examples, real situations, origin and similar grammar. Kanji in examples have furigana.",
        "모든 문법에 의미·용법·예문·사용 장면·어원·비슷한 문법 비교가 있습니다. 예문의 한자에는 후리가나가 붙어 있습니다.",
        "Cada punto gramatical incluye significado, uso, ejemplos, situaciones reales, origen y gramática similar. Los kanji de los ejemplos llevan furigana.",
        "Mỗi mẫu ngữ pháp đều có ý nghĩa, cách dùng, ví dụ, tình huống, nguồn gốc và so sánh ngữ pháp tương tự. Chữ Hán trong ví dụ đều có furigana."),
    "语法库与收藏": ("Library & Favorites", "문법 사전과 즐겨찾기", "Biblioteca y favoritos", "Thư viện và yêu thích"),
    "在「语法库」按等级浏览或搜索全部语法，点 ☆ 收藏需要复习的语法。讲解会跟随手机语言显示。": (
        "Browse or search all grammar by level in Grammar, and tap ☆ to save points to review. Explanations follow your device language.",
        "「문법 사전」에서 레벨별로 모든 문법을 보거나 검색하고, ☆를 눌러 복습할 문법을 저장하세요. 설명은 기기 언어로 표시됩니다.",
        "Explora o busca toda la gramática por nivel en Gramática y toca ☆ para guardar lo que quieras repasar. Las explicaciones siguen el idioma del dispositivo.",
        "Xem hoặc tìm toàn bộ ngữ pháp theo cấp độ trong mục Ngữ pháp, nhấn ☆ để lưu mẫu cần ôn. Giải thích hiển thị theo ngôn ngữ của máy."),
    "准备好了": ("You're All Set", "준비 완료", "Todo listo", "Sẵn sàng rồi"),
    "手边没有日语书也没关系，可以先用内置的示例书页体验一下。": (
        "No Japanese book at hand? Try the built-in sample page first.",
        "일본어 책이 없어도 괜찮아요. 내장된 예시 페이지로 먼저 체험해 보세요.",
        "¿No tienes un libro en japonés a mano? Prueba primero la página de ejemplo incluida.",
        "Không có sách tiếng Nhật bên cạnh? Hãy thử trước với trang mẫu có sẵn."),
    "帮助": ("Help", "도움말", "Ayuda", "Trợ giúp"),
    "使用引导": ("How to Use", "사용 안내", "Cómo usar", "Hướng dẫn sử dụng"),
    "今天没有需要复习的语法。看过的语法会按遗忘曲线，在快要忘记时提醒你复习。": ("Nothing to review today. Grammar you've read comes back right before you're likely to forget it.", "오늘 복습할 문법이 없습니다. 본 문법은 망각 곡선에 따라 잊기 직전에 복습하도록 알려 드립니다.", "Hoy no hay nada que repasar. La gramática que leas volverá justo antes de que la olvides.", "Hôm nay không có mẫu cần ôn. Ngữ pháp đã xem sẽ được nhắc ôn ngay trước khi bạn sắp quên."),
    "按遗忘曲线排序：最快要忘记的排在最前面。点开回顾一遍即完成复习。": ("Ordered by the forgetting curve: what you're closest to forgetting comes first. Open one to review it.", "망각 곡선 순서: 가장 먼저 잊을 문법이 맨 위에 있습니다. 열어서 한 번 보면 복습 완료.", "Ordenado por la curva del olvido: lo que estás más cerca de olvidar va primero. Ábrelo para repasarlo.", "Sắp xếp theo đường cong lãng quên: mẫu sắp quên nhất ở trên cùng. Mở ra xem lại là hoàn thành."),
    "记忆约 %lld%%": ("~%lld%% recall", "기억 약 %lld%%", "~%lld%% recuerdo", "Nhớ ~%lld%%"),
    "出题频率": ("Exam Frequency", "출제 빈도", "Frecuencia en el examen", "Tần suất ra đề"),
    "常考": ("Often Tested", "자주 출제", "Muy frecuente", "Hay thi"),
    "考过": ("Has Appeared", "출제된 적 있음", "Ha salido", "Đã từng thi"),
    "根据公开的考试复原资料与教材整理，仅供参考。": ("Compiled from publicly available exam recollections and textbooks. For reference only.", "공개된 시험 복원 자료와 교재를 바탕으로 정리한 참고용 정보입니다.", "Recopilado de reconstrucciones públicas del examen y libros de texto. Solo como referencia.", "Tổng hợp từ tài liệu phục dựng đề thi công khai và giáo trình, chỉ mang tính tham khảo."),
    "继续上次": ("Pick Up Where You Left Off", "이어서 보기", "Continuar donde lo dejaste", "Tiếp tục lần trước"),
    "全部扫描记录": ("All Scans", "전체 스캔 기록", "Todos los escaneos", "Tất cả lần quét"),
    "还有 %lld 个没看过": ({"one": "%lld not viewed yet", "other": "%lld not viewed yet"}, "아직 안 본 문법 %lld개", {"one": "%lld sin ver", "other": "%lld sin ver"}, "Còn %lld mẫu chưa xem"),
    "全部看过了": ("All viewed", "모두 확인함", "Todo visto", "Đã xem hết"),
    "今日复习": ("Review Today", "오늘의 복습", "Repaso de hoy", "Ôn tập hôm nay"),
    "今天没有需要复习的语法。看过的语法会按 1、3、7、14、30 天的间隔提醒你复习。": ("Nothing to review today. Grammar you've read comes back for review after 1, 3, 7, 14 and 30 days.", "오늘 복습할 문법이 없습니다. 본 문법은 1·3·7·14·30일 간격으로 복습 알림이 표시됩니다.", "Hoy no hay nada que repasar. La gramática que leas volverá a repaso a los 1, 3, 7, 14 y 30 días.", "Hôm nay không có mẫu cần ôn. Ngữ pháp đã xem sẽ được nhắc ôn sau 1, 3, 7, 14 và 30 ngày."),
    "按遗忘曲线安排，点开回顾一遍即完成复习。": ("Spaced by the forgetting curve. Open one to review it.", "망각 곡선에 맞춰 배치했습니다. 열어서 한 번 보면 복습 완료.", "Organizado según la curva del olvido. Ábrelo para repasarlo.", "Sắp xếp theo đường cong lãng quên. Mở ra xem lại là hoàn thành."),
    "常出现但还没学": ("Common in Your Reading", "자주 나오지만 아직 안 배운 문법", "Frecuente en tus lecturas", "Hay gặp nhưng chưa học"),
    "你扫描的材料里经常出现、但还没看过讲解的语法。": ("Grammar that shows up often in what you scan but you haven't read yet.", "스캔한 자료에 자주 나오지만 아직 설명을 보지 않은 문법입니다.", "Gramática que aparece a menudo en lo que escaneas y que aún no has leído.", "Ngữ pháp xuất hiện nhiều trong tài liệu bạn quét nhưng bạn chưa xem."),
    "%lld 次扫描": ({"one": "in %lld scan", "other": "in %lld scans"}, "스캔 %lld회", {"one": "en %lld escaneo", "other": "en %lld escaneos"}, "%lld lần quét"),
    "学习进度": ("Progress", "학습 진도", "Progreso", "Tiến độ"),
    "看过讲解的语法计为“已学”。": ("A grammar point counts as learned once you've read its explanation.", "설명을 본 문법은 '학습 완료'로 집계됩니다.", "Un punto cuenta como aprendido cuando lees su explicación.", "Mẫu ngữ pháp được tính là đã học khi bạn xem giải thích."),
    "从 N5 开始": ("Start with N5", "N5부터 시작", "Empieza por N5", "Bắt đầu từ N5"),
    "首页": ("Home", "홈", "Inicio", "Trang chủ"),
    "扫描日文，找出语法": ("Scan Japanese, Find the Grammar", "일본어를 스캔해 문법 찾기", "Escanea japonés y encuentra la gramática", "Quét tiếng Nhật, tìm ngữ pháp"),
    "对准书页或选择截图，所有语法点都会被高亮出来。": ("Point at a page or pick a screenshot — every grammar point gets highlighted.", "책 페이지를 비추거나 스크린샷을 고르면 모든 문법이 하이라이트됩니다.", "Apunta a una página o elige una captura: se resaltará cada punto gramatical.", "Hướng vào trang sách hoặc chọn ảnh chụp màn hình, mọi mẫu ngữ pháp sẽ được tô sáng."),
    "相机扫描": ("Scan with Camera", "카메라로 스캔", "Escanear con la cámara", "Quét bằng camera"),
    "从相册识别": ("From Photos", "사진에서 인식", "Desde Fotos", "Từ thư viện ảnh"),
    "今日语法": ("Grammar of the Day", "오늘의 문법", "Gramática del día", "Ngữ pháp hôm nay"),
    "最近扫描": ("Recent Scans", "최근 스캔", "Escaneos recientes", "Quét gần đây"),
    "最近查看": ("Recently Viewed", "최근 본 문법", "Vistos recientemente", "Xem gần đây"),
    "清除": ("Clear", "지우기", "Borrar", "Xóa"),
    "确定要清除吗？": ("Clear this history?", "기록을 지울까요?", "¿Borrar este historial?", "Xóa lịch sử này?"),
    "扫描过的书页会保存在这里，方便回看。": ("Pages you scan are saved here so you can revisit them.", "스캔한 페이지가 여기에 저장되어 다시 볼 수 있습니다.", "Las páginas que escanees se guardan aquí para volver a verlas.", "Các trang đã quét sẽ được lưu ở đây để xem lại."),
    "看过的语法讲解会出现在这里。": ("Grammar points you've read will appear here.", "읽은 문법 설명이 여기에 표시됩니다.", "Aquí aparecerán los puntos gramaticales que hayas leído.", "Các mẫu ngữ pháp bạn đã xem sẽ hiện ở đây."),
    "组词逻辑": ("How It's Built", "구성 원리", "Cómo se forma", "Logic cấu tạo"),
    "出现 %lld 次": ({"one": "%lld time", "other": "%lld times"}, "%lld회", {"one": "%lld vez", "other": "%lld veces"}, "%lld lần"),
    "双指缩放查看原文，点击高亮查看讲解": ("Pinch to zoom into the text. Tap a highlight to see its explanation.", "두 손가락으로 확대해 원문을 보고, 하이라이트를 눌러 설명을 보세요", "Pellizca para ampliar el texto y toca un resaltado para ver la explicación", "Dùng hai ngón tay để phóng to, nhấn vào phần tô sáng để xem giải thích"),
    "点击高亮或下方列表查看讲解；点击图片可放大查看原文。": ("Tap a highlight or an item below for the explanation. Tap the photo to zoom in.", "하이라이트나 아래 목록을 눌러 설명을 보세요. 사진을 누르면 확대할 수 있습니다.", "Toca un resaltado o un elemento para ver la explicación. Toca la foto para ampliarla.", "Nhấn vào phần tô sáng hoặc danh sách để xem giải thích. Nhấn vào ảnh để phóng to."),
    "注意": ("Watch Out", "주의", "Atención", "Lưu ý"),
    "日常生活": ("Daily Life", "일상생활", "Vida diaria", "Đời sống hằng ngày"),
    "职场": ("At Work", "직장", "En el trabajo", "Nơi làm việc"),
    "相似・相近语法": ("Similar Grammar", "비슷한 문법", "Gramática similar", "Ngữ pháp tương tự"),
    "查看讲解": ("View", "설명 보기", "Ver", "Xem giải thích"),
    "找不到该语法点": ("Grammar point not found", "문법 항목을 찾을 수 없습니다", "No se encontró el punto gramatical", "Không tìm thấy mẫu ngữ pháp"),
    "等级": ("Level", "레벨", "Nivel", "Cấp độ"),
    "全部": ("All", "전체", "Todos", "Tất cả"),
    "搜索语法、意思或例句": ("Search grammar, meanings or examples", "문법, 의미, 예문 검색", "Buscar gramática, significados o ejemplos", "Tìm ngữ pháp, ý nghĩa hoặc ví dụ"),
    "还没有收藏": ("No Favorites Yet", "즐겨찾기가 없습니다", "Aún no hay favoritos", "Chưa có mục yêu thích"),
    "在语法讲解页或列表中点击 ☆ 即可收藏。": ("Tap ☆ on a grammar page or in a list to save it here.", "문법 설명 화면이나 목록에서 ☆를 누르면 즐겨찾기에 추가됩니다.", "Toca ☆ en una explicación o en la lista para guardarla aquí.", "Nhấn ☆ trong trang giải thích hoặc danh sách để lưu vào đây."),
    "将相机对准书本上的日文": ("Point the camera at Japanese text", "카메라를 책의 일본어에 맞춰 주세요", "Apunta la cámara a un texto en japonés", "Hướng camera vào chữ tiếng Nhật trong sách"),
    "识别到 %lld 个语法点，点击高亮或下方标签查看": (
        {"one": "%lld grammar point found — tap a highlight or tag", "other": "%lld grammar points found — tap a highlight or tag"},
        "문법 %lld개 인식됨 — 하이라이트나 태그를 누르세요",
        {"one": "%lld punto gramatical — toca un resaltado o etiqueta", "other": "%lld puntos gramaticales — toca un resaltado o etiqueta"},
        "Tìm thấy %lld mẫu ngữ pháp — nhấn vào phần tô sáng hoặc thẻ",
    ),
    "识别到 %lld 个语法点": (
        {"one": "%lld Grammar Point Found", "other": "%lld Grammar Points Found"},
        "문법 %lld개 인식됨",
        {"one": "%lld punto gramatical encontrado", "other": "%lld puntos gramaticales encontrados"},
        "Tìm thấy %lld mẫu ngữ pháp",
    ),
    "试试示例": ("Try Sample", "예시 보기", "Probar ejemplo", "Thử mẫu"),
    "试试示例书页": ("Try a Sample Page", "예시 페이지로 체험하기", "Probar una página de ejemplo", "Thử với trang mẫu"),
    "打开设置": ("Open Settings", "설정 열기", "Abrir Ajustes", "Mở Cài đặt"),
    "没有相机权限。\n请在「设置」中允许访问相机，或从相册选择图片。": (
        "No camera access.\nAllow camera access in Settings, or choose a photo instead.",
        "카메라 권한이 없습니다.\n설정에서 카메라 접근을 허용하거나 사진을 선택하세요.",
        "Sin acceso a la cámara.\nPermite el acceso en Ajustes o elige una foto.",
        "Chưa có quyền dùng camera.\nHãy cho phép trong Cài đặt hoặc chọn ảnh từ thư viện.",
    ),
    "此设备无法使用相机。\n可以从相册选择图片进行识别。": (
        "The camera isn't available on this device.\nYou can choose a photo instead.",
        "이 기기에서는 카메라를 사용할 수 없습니다.\n사진을 선택해 인식할 수 있습니다.",
        "La cámara no está disponible en este dispositivo.\nPuedes elegir una foto.",
        "Thiết bị này không dùng được camera.\nBạn có thể chọn ảnh từ thư viện.",
    ),
    "相册": ("Photos", "사진", "Fotos", "Ảnh"),
    "补光": ("Light", "조명", "Luz", "Đèn"),
    "定格并精细识别": ("Capture and analyze", "촬영해서 정밀 분석", "Capturar y analizar", "Chụp và phân tích"),
    "识别结果": ("Results", "인식 결과", "Resultados", "Kết quả"),
    "编辑文本": ("Edit Text", "텍스트 편집", "Editar texto", "Sửa văn bản"),
    "正在识别文字和语法点…": ("Recognizing text and grammar…", "텍스트와 문법을 인식하는 중…", "Reconociendo texto y gramática…", "Đang nhận dạng chữ và ngữ pháp…"),
    "识别失败": ("Recognition Failed", "인식 실패", "Error de reconocimiento", "Nhận dạng thất bại"),
    "无法读取图片": ("Couldn't read the image.", "이미지를 읽을 수 없습니다.", "No se pudo leer la imagen.", "Không đọc được ảnh."),
    "没有识别到日文": ("No Japanese Text Found", "일본어를 인식하지 못했습니다", "No se encontró texto en japonés", "Không nhận dạng được tiếng Nhật"),
    "请让文字清晰、光线充足，尽量正对书页拍摄。": (
        "Make sure the text is sharp and well lit, and hold the camera parallel to the page.",
        "글자가 선명하고 밝게 보이도록 하고, 페이지를 정면에서 촬영하세요.",
        "Asegúrate de que el texto sea nítido y esté bien iluminado, y fotografía la página de frente.",
        "Hãy để chữ rõ nét, đủ sáng và chụp thẳng vào trang sách.",
    ),
    "没有识别到收录的语法点": ("No Grammar Points Found", "수록된 문법을 찾지 못했습니다", "No se encontraron puntos gramaticales", "Không tìm thấy mẫu ngữ pháp nào"),
    "点击图片或文本中的高亮，或下方列表，查看详细讲解。": (
        "Tap a highlight in the image or text, or an item below, to see the explanation.",
        "이미지나 텍스트의 하이라이트, 또는 아래 목록을 눌러 자세한 설명을 보세요.",
        "Toca un resaltado en la imagen o el texto, o un elemento de la lista, para ver la explicación.",
        "Nhấn vào phần tô sáng trong ảnh, văn bản hoặc danh sách bên dưới để xem giải thích.",
    ),
    "识别文本": ("Recognized Text", "인식된 텍스트", "Texto reconocido", "Văn bản nhận dạng"),
    "文本已手动修改，图片上的高亮已隐藏。": (
        "The text was edited, so highlights on the image are hidden.",
        "텍스트를 수정해서 이미지의 하이라이트는 숨겨졌습니다.",
        "El texto se editó, así que los resaltados de la imagen están ocultos.",
        "Văn bản đã được sửa nên phần tô sáng trên ảnh đã bị ẩn.",
    ),
    "修正识别文本": ("Correct Text", "텍스트 수정", "Corregir texto", "Sửa văn bản"),
    "取消": ("Cancel", "취소", "Cancelar", "Hủy"),
    "重新识别": ("Analyze", "다시 분석", "Analizar", "Phân tích lại"),
    "这里有多个语法点，请选择": ("Several grammar points overlap here. Choose one:", "여러 문법이 겹쳐 있습니다. 선택하세요", "Aquí se superponen varios puntos gramaticales. Elige uno:", "Có nhiều mẫu ngữ pháp ở đây, hãy chọn một:"),
}

# 缅甸语（my，Myanmar Unicode）。缅甸语没有复数变化，统一用普通字符串。
MY = {
    "扫描": "စကင်ဖတ်",
    "语法库": "သဒ္ဒါ",
    "收藏": "အကြိုက်ဆုံး",
    "取消收藏": "အကြိုက်ဆုံးမှ ဖယ်ရန်",
    "意思": "အဓိပ္ပာယ်",
    "用法": "အသုံးပြုပုံ",
    "接续": "တွဲဆက်ပုံ",
    "使用场景": "သုံးရမည့် အခြေအနေ",
    "词源": "ဇစ်မြစ်",
    "例句": "ဥပမာများ",
    "关闭": "ပိတ်ရန်",
    "购买失败": "ဝယ်ယူမှု မအောင်မြင်ပါ",
    "好": "OK",
    "解锁完整讲解": "ရှင်းလင်းချက် အပြည့်အစုံ ဖွင့်ရန်",
    "扫到不懂的语法，马上看懂。": "နားမလည်တဲ့ သဒ္ဒါကို စကင်ဖတ်လိုက်ရုံနဲ့ ချက်ချင်း နားလည်ပါမယ်။",
    "全部 N5–N1 语法点的完整讲解": "N5–N1 သဒ္ဒါအားလုံးအတွက် ရှင်းလင်းချက် အပြည့်အစုံ",
    "按义项分段的用法、接续与例句": "အဓိပ္ပာယ်အလိုက် အသုံးပြုပုံ၊ တွဲဆက်ပုံနှင့် ဥပမာများ",
    "日常生活与职场的使用场景": "နေ့စဉ်ဘဝနှင့် အလုပ်ခွင်မှ လက်တွေ့ အခြေအနေများ",
    "词源与相近语法对比": "ဇစ်မြစ်နှင့် ဆင်တူသဒ္ဒါများ နှိုင်းယှဉ်ချက်",
    "例句汉字全部标注假名": "ဥပမာများထဲရှိ ခန်ဂျီတိုင်းတွင် ဖူရီဂါနာ ပါဝင်",
    "完全离线，无广告，无追踪": "အော့ဖ်လိုင်း အပြည့်အဝ။ ကြော်ငြာ မရှိ၊ ခြေရာခံခြင်း မရှိ။",
    "免费试用中，还剩 %lld 天": "အခမဲ့ အစမ်းသုံးကာလ - %lld ရက် ကျန်သေးသည်",
    "免费试用已结束": "အခမဲ့ အစမ်းသုံးကာလ ပြီးဆုံးပါပြီ",
    "开始 %lld 天免费试用": "%lld ရက် အခမဲ့ အစမ်းသုံးမှု စတင်ရန်",
    "免费开始使用": "အခမဲ့ စတင်ရန်",
    "前 %lld 天免费使用全部功能。之后可一次性 %@ 永久解锁完整讲解，不订阅、不自动扣费。": "ပထမ %lld ရက်အတွင်း လုပ်ဆောင်ချက်အားလုံးကို အခမဲ့ သုံးနိုင်ပါသည်။ ထို့နောက် %@ ဖြင့် တစ်ကြိမ်တည်း ဝယ်ယူ၍ ရှင်းလင်းချက် အပြည့်အစုံကို အမြဲတမ်း ဖွင့်နိုင်ပါသည်။ လစဉ်ကြေး မရှိ၊ အလိုအလျောက် ငွေဖြတ်ခြင်း မရှိပါ။",
    "前 %lld 天免费使用全部功能。之后可一次性购买永久解锁完整讲解，不订阅、不自动扣费。": "ပထမ %lld ရက်အတွင်း လုပ်ဆောင်ချက်အားလုံးကို အခမဲ့ သုံးနိုင်ပါသည်။ ထို့နောက် တစ်ကြိမ်တည်း ဝယ်ယူ၍ ရှင်းလင်းချက် အပြည့်အစုံကို အမြဲတမ်း ဖွင့်နိုင်ပါသည်။ လစဉ်ကြေး မရှိ၊ အလိုအလျောက် ငွေဖြတ်ခြင်း မရှိပါ။",
    "免费试用还剩 %lld 天": "အခမဲ့ အစမ်းသုံးရန် %lld ရက် ကျန်သေးသည်",
    "一次性 %@ 永久解锁，不订阅": "%@ ဖြင့် တစ်ကြိမ်ဝယ်ပြီး အမြဲတမ်း ဖွင့်ပါ။ လစဉ်ကြေး မရှိပါ။",
    "一次性购买永久解锁，不订阅": "တစ်ကြိမ်ဝယ်ယူရုံဖြင့် အမြဲတမ်း ဖွင့်ပါ။ လစဉ်ကြေး မရှိပါ။",
    "免费 · 到期后不会自动扣费": "အခမဲ့ · ပြီးဆုံးပါက အလိုအလျောက် ငွေမဖြတ်ပါ",
    "一次性购买 %@": "တစ်ကြိမ်တည်း ဝယ်ယူရန် %@",
    "永久解锁 · 无需订阅": "အမြဲတမ်း ဖွင့်ထားမည် · လစဉ်ကြေး မလိုပါ",
    "恢复购买": "ဝယ်ယူမှုများ ပြန်ယူရန်",
    "免费试用期为 %lld 天，期间可使用全部内容。试用结束后不会自动收费；如需继续查看完整讲解，可一次性购买永久解锁。扫描识别与语法高亮始终免费。": "အခမဲ့ အစမ်းသုံးကာလသည် %lld ရက် ဖြစ်ပြီး အကြောင်းအရာအားလုံးကို သုံးနိုင်ပါသည်။ အစမ်းသုံးကာလ ပြီးဆုံးချိန်တွင် အလိုအလျောက် ငွေမဖြတ်ပါ။ ရှင်းလင်းချက် အပြည့်အစုံကို ဆက်ဖတ်လိုပါက တစ်ကြိမ်တည်း ဝယ်ယူ၍ အမြဲတမ်း ဖွင့်နိုင်ပါသည်။ စကင်ဖတ်ခြင်းနှင့် သဒ္ဒါ အရောင်ခြယ်ပြခြင်းမှာ အမြဲ အခမဲ့ ဖြစ်ပါသည်။",
    "隐私政策": "ကိုယ်ရေးအချက်အလက် မူဝါဒ",
    "使用条款": "အသုံးပြုမှု စည်းမျဉ်းများ",
    "用法、例句、使用场景、词源、相近语法对比": "အသုံးပြုပုံ၊ ဥပမာ၊ အခြေအနေ၊ ဇစ်မြစ်နှင့် ဆင်တူသဒ္ဒါ",
    "查看解锁方式": "ဖွင့်ရန် နည်းလမ်းများ ကြည့်ရန်",
    "设置": "ဆက်တင်များ",
    "购买": "ဝယ်ယူမှု",
    "状态": "အခြေအနေ",
    "关于": "အကြောင်း",
    "支持与反馈": "အကူအညီနှင့် အကြံပြုချက်",
    "开源许可": "Open Source လိုင်စင်များ",
    "版本": "ဗားရှင်း",
    "已永久解锁": "အမြဲတမ်း ဖွင့်ပြီးပါပြီ",
    "未开始试用": "အစမ်းသုံးမှု မစတင်ရသေးပါ",
    "用于离线生成例句的假名注音数据": "ဥပမာဝါကျများအတွက် ဖူရီဂါနာကို အော့ဖ်လိုင်းဖြင့် ထုတ်ရန် အသုံးပြုသည်",
    "用于把讲解转换为繁体中文": "ရှင်းလင်းချက်များကို ရိုးရာ တရုတ်စာ (Traditional Chinese) သို့ ပြောင်းရန် အသုံးပြုသည်",
    "用于绘制 App 图标": "အက်ပ် အိုင်ကွန်ကို ဆွဲရန် အသုံးပြုသည်",
    "用于绘制示例书页图片": "နမူနာ စာမျက်နှာပုံကို ဆွဲရန် အသုံးပြုသည်",
    "本 App 的语法讲解为原创内容。文字识别使用 Apple Vision 框架在设备上完成。以下第三方开源组件仅在构建阶段用于生成 App 内的静态数据或图片：": "သဒ္ဒါ ရှင်းလင်းချက်အားလုံးသည် မူရင်း ရေးသားထားသော အကြောင်းအရာများ ဖြစ်ပါသည်။ စာသား ဖတ်ယူခြင်းကို Apple ၏ Vision framework ဖြင့် စက်ပေါ်တွင်သာ လုပ်ဆောင်ပါသည်။ အောက်ပါ Open Source အစိတ်အပိုင်းများကို အက်ပ်ထဲရှိ ဒေတာ သို့မဟုတ် ပုံများ ထုတ်ရန် build လုပ်ချိန်တွင်သာ အသုံးပြုခဲ့ပါသည်:",
    "跳过": "ကျော်ရန်",
    "下一步": "ရှေ့ဆက်ရန်",
    "开始使用": "စတင်ရန်",
    "先用示例书页试试": "နမူနာ စာမျက်နှာဖြင့် အရင် စမ်းကြည့်ရန်",
    "对准日文，语法一目了然": "ဂျပန်စာကို ချိန်လိုက်ရုံနဲ့ သဒ္ဒါကို မြင်ရမယ်",
    "读日语书遇到看不懂的句子？用相机扫一下，文中的语法点会自动找出来并高亮。": "ဂျပန်စာအုပ် ဖတ်ရင်း နားမလည်တဲ့ ဝါကျ တွေ့နေသလား။ ကင်မရာနဲ့ စကင်ဖတ်လိုက်ရုံနဲ့ သဒ္ဒါအားလုံးကို အလိုအလျောက် ရှာပြီး အရောင်ခြယ်ပြပေးပါမယ်။",
    "扫描书本或截图": "စာအုပ် သို့မဟုတ် စခရင်ရှော့ကို စကင်ဖတ်ပါ",
    "把相机对准书页，语法会实时高亮，颜色代表 JLPT 等级。按中间的快门定格画面做精细识别，也可以从相册选择截图。": "ကင်မရာကို စာမျက်နှာဆီ ချိန်လိုက်ရင် သဒ္ဒါတွေကို ချက်ချင်း အရောင်ခြယ်ပြပြီး အရောင်က JLPT အဆင့်ကို ပြပါတယ်။ အသေးစိတ် ခွဲခြမ်းဖို့ ရိုက်ခလုတ်ကို နှိပ်ပါ၊ ဒါမှမဟုတ် ဓာတ်ပုံများထဲက စခရင်ရှော့ကို ရွေးနိုင်ပါတယ်။",
    "点击高亮，查看讲解": "အရောင်ခြယ်ထားတာကို နှိပ်ပြီး ရှင်းလင်းချက် ကြည့်ပါ",
    "每个语法点都有意思、用法、例句、使用场景、词源和相近语法对比。例句里的汉字都标注了假名。": "သဒ္ဒါတိုင်းမှာ အဓိပ္ပာယ်၊ အသုံးပြုပုံ၊ ဥပမာ၊ လက်တွေ့ အခြေအနေ၊ ဇစ်မြစ်နှင့် ဆင်တူသဒ္ဒါ နှိုင်းယှဉ်ချက်တွေ ပါဝင်ပါတယ်။ ဥပမာထဲက ခန်ဂျီတွေမှာ ဖူရီဂါနာ ပါပါတယ်။",
    "语法库与收藏": "သဒ္ဒါနှင့် အကြိုက်ဆုံး",
    "在「语法库」按等级浏览或搜索全部语法，点 ☆ 收藏需要复习的语法。讲解会跟随手机语言显示。": "「သဒ္ဒါ」 မှာ အဆင့်အလိုက် သဒ္ဒါအားလုံးကို ကြည့်ရှု သို့မဟုတ် ရှာဖွေနိုင်ပြီး ပြန်လေ့လာချင်တာကို ☆ နှိပ်ပြီး သိမ်းထားနိုင်ပါတယ်။ ရှင်းလင်းချက်တွေကို ဖုန်းရဲ့ ဘာသာစကားအတိုင်း ပြပါမယ်။",
    "准备好了": "အဆင်သင့်ပါပြီ",
    "手边没有日语书也没关系，可以先用内置的示例书页体验一下。": "လက်ထဲမှာ ဂျပန်စာအုပ် မရှိလည်း ရပါတယ်။ ပါဝင်ပြီးသား နမူနာ စာမျက်နှာနဲ့ အရင် စမ်းကြည့်ပါ။",
    "帮助": "အကူအညီ",
    "使用引导": "အသုံးပြုနည်း",
    "今天没有需要复习的语法。看过的语法会按遗忘曲线，在快要忘记时提醒你复习。": "ဒီနေ့ ပြန်လေ့လာစရာ သဒ္ဒါ မရှိပါ။ ဖတ်ပြီးသား သဒ္ဒါတွေကို မေ့လျော့မှုမျဉ်းကွေးအရ မေ့ခါနီးချိန်မှာ ပြန်လေ့လာဖို့ သတိပေးပါမယ်။",
    "按遗忘曲线排序：最快要忘记的排在最前面。点开回顾一遍即完成复习。": "မေ့လျော့မှုမျဉ်းကွေးအလိုက် စီထားပါတယ်- အမေ့နီးဆုံး သဒ္ဒါက ထိပ်ဆုံးမှာ ရှိပါတယ်။ ဖွင့်ပြီး တစ်ခေါက် ပြန်ကြည့်ရင် ပြန်လေ့လာမှု ပြီးပါပြီ။",
    "记忆约 %lld%%": "မှတ်မိနှုန်း ~%lld%%",
    "出题频率": "စာမေးပွဲ ထွက်နှုန်း",
    "常考": "မကြာခဏ ထွက်",
    "考过": "ထွက်ဖူးသည်",
    "根据公开的考试复原资料与教材整理，仅供参考。": "အများသိ စာမေးပွဲ ပြန်လည်မှတ်တမ်းများနှင့် ဖတ်စာအုပ်များမှ စုစည်းထားခြင်း ဖြစ်ပါသည်။ ကိုးကားရန်သာ ဖြစ်ပါသည်။",
    "继续上次": "ရပ်ခဲ့သည့်နေရာမှ ဆက်ရန်",
    "全部扫描记录": "စကင်ဖတ်မှု အားလုံး",
    "还有 %lld 个没看过": "မကြည့်ရသေးသော %lld ခု",
    "全部看过了": "အားလုံး ကြည့်ပြီးပါပြီ",
    "今日复习": "ယနေ့ ပြန်လေ့လာရန်",
    "今天没有需要复习的语法。看过的语法会按 1、3、7、14、30 天的间隔提醒你复习。": "ဒီနေ့ ပြန်လေ့လာစရာ သဒ္ဒါ မရှိပါ။ ဖတ်ပြီးသား သဒ္ဒါတွေကို 1၊ 3၊ 7၊ 14 နှင့် 30 ရက် ကြာတိုင်း ပြန်လေ့လာဖို့ သတိပေးပါမယ်။",
    "按遗忘曲线安排，点开回顾一遍即完成复习。": "မေ့လျော့မှုမျဉ်းကွေးအလိုက် စီစဉ်ထားပါတယ်။ ဖွင့်ပြီး တစ်ခေါက် ပြန်ကြည့်ရင် ပြီးပါပြီ။",
    "常出现但还没学": "မကြာခဏ တွေ့ရပေမယ့် မလေ့လာရသေး",
    "你扫描的材料里经常出现、但还没看过讲解的语法。": "သင် စကင်ဖတ်တဲ့ စာတွေထဲမှာ မကြာခဏ ပါပေမယ့် ရှင်းလင်းချက် မဖတ်ရသေးတဲ့ သဒ္ဒါများ။",
    "%lld 次扫描": "စကင်ဖတ်မှု %lld ကြိမ်",
    "学习进度": "လေ့လာမှု တိုးတက်မှု",
    "看过讲解的语法计为“已学”。": "ရှင်းလင်းချက် ဖတ်ပြီးသော သဒ္ဒါကို “လေ့လာပြီး” ဟု သတ်မှတ်ပါသည်။",
    "从 N5 开始": "N5 မှ စတင်ရန်",
    "首页": "ပင်မ",
    "扫描日文，找出语法": "ဂျပန်စာကို စကင်ဖတ်ပြီး သဒ္ဒါ ရှာပါ",
    "对准书页或选择截图，所有语法点都会被高亮出来。": "စာမျက်နှာကို ချိန်ပါ သို့မဟုတ် စခရင်ရှော့ ရွေးပါ — သဒ္ဒါအားလုံးကို အရောင်ခြယ်ပြပေးပါမယ်။",
    "相机扫描": "ကင်မရာဖြင့် စကင်ဖတ်ရန်",
    "从相册识别": "ဓာတ်ပုံများမှ",
    "今日语法": "ယနေ့ သဒ္ဒါ",
    "最近扫描": "မကြာသေးမီ စကင်ဖတ်မှုများ",
    "最近查看": "မကြာသေးမီက ကြည့်ခဲ့သည်များ",
    "清除": "ရှင်းရန်",
    "确定要清除吗？": "ဤမှတ်တမ်းကို ရှင်းမလား။",
    "扫描过的书页会保存在这里，方便回看。": "စကင်ဖတ်ထားသော စာမျက်နှာများကို ပြန်ကြည့်နိုင်ရန် ဤနေရာတွင် သိမ်းထားပါမည်။",
    "看过的语法讲解会出现在这里。": "ဖတ်ပြီးသော သဒ္ဒါများ ဤနေရာတွင် ပေါ်လာပါမည်။",
    "组词逻辑": "ဖွဲ့စည်းပုံ",
    "出现 %lld 次": "%lld ကြိမ်",
    "双指缩放查看原文，点击高亮查看讲解": "လက်နှစ်ချောင်းဖြင့် ချဲ့ကြည့်ပါ။ ရှင်းလင်းချက် ကြည့်ရန် အရောင်ခြယ်ထားသည်ကို နှိပ်ပါ။",
    "点击高亮或下方列表查看讲解；点击图片可放大查看原文。": "ရှင်းလင်းချက် ကြည့်ရန် အရောင်ခြယ်ထားသည် သို့မဟုတ် အောက်ပါစာရင်းကို နှိပ်ပါ။ ပုံကို နှိပ်၍ ချဲ့ကြည့်နိုင်သည်။",
    "注意": "သတိပြုရန်",
    "日常生活": "နေ့စဉ်ဘဝ",
    "职场": "အလုပ်ခွင်",
    "相似・相近语法": "ဆင်တူသဒ္ဒါ",
    "查看讲解": "ကြည့်ရန်",
    "找不到该语法点": "ဤသဒ္ဒါကို ရှာမတွေ့ပါ",
    "等级": "အဆင့်",
    "全部": "အားလုံး",
    "搜索语法、意思或例句": "သဒ္ဒါ၊ အဓိပ္ပာယ် သို့မဟုတ် ဥပမာ ရှာရန်",
    "还没有收藏": "အကြိုက်ဆုံး မရှိသေးပါ",
    "在语法讲解页或列表中点击 ☆ 即可收藏。": "သဒ္ဒါ စာမျက်နှာ သို့မဟုတ် စာရင်းတွင် ☆ ကို နှိပ်၍ ဤနေရာတွင် သိမ်းနိုင်ပါသည်။",
    "将相机对准书本上的日文": "ကင်မရာကို ဂျပန်စာသားဆီ ချိန်ပါ",
    "识别到 %lld 个语法点，点击高亮或下方标签查看": "သဒ္ဒါ %lld ခု တွေ့ရှိ — အရောင်ခြယ်ထားသည် သို့မဟုတ် အညွှန်းကို နှိပ်ပါ",
    "识别到 %lld 个语法点": "သဒ္ဒါ %lld ခု တွေ့ရှိသည်",
    "试试示例": "နမူနာ စမ်းရန်",
    "试试示例书页": "နမူနာ စာမျက်နှာ စမ်းကြည့်ရန်",
    "打开设置": "ဆက်တင်များ ဖွင့်ရန်",
    "没有相机权限。\n请在「设置」中允许访问相机，或从相册选择图片。": "ကင်မရာ သုံးခွင့် မရှိပါ။\nဆက်တင်များတွင် ကင်မရာ သုံးခွင့်ပေးပါ သို့မဟုတ် ဓာတ်ပုံတစ်ပုံ ရွေးပါ။",
    "此设备无法使用相机。\n可以从相册选择图片进行识别。": "ဤစက်တွင် ကင်မရာ သုံး၍ မရပါ။\nဓာတ်ပုံတစ်ပုံကို ရွေး၍ ဖတ်ယူနိုင်ပါသည်။",
    "相册": "ဓာတ်ပုံများ",
    "补光": "ဓာတ်မီး",
    "定格并精细识别": "ရိုက်ယူပြီး အသေးစိတ် ခွဲခြမ်းရန်",
    "识别结果": "ရလဒ်များ",
    "编辑文本": "စာသား ပြင်ရန်",
    "正在识别文字和语法点…": "စာသားနှင့် သဒ္ဒါကို ဖတ်ယူနေသည်…",
    "识别失败": "ဖတ်ယူ၍ မရပါ",
    "无法读取图片": "ပုံကို ဖတ်၍ မရပါ။",
    "没有识别到日文": "ဂျပန်စာ မတွေ့ပါ",
    "请让文字清晰、光线充足，尽量正对书页拍摄。": "စာသား ကြည်လင်ပြီး အလင်း လုံလောက်ပါစေ၊ စာမျက်နှာကို တည့်တည့် ရိုက်ပါ။",
    "没有识别到收录的语法点": "သဒ္ဒါ မတွေ့ပါ",
    "点击图片或文本中的高亮，或下方列表，查看详细讲解。": "ရှင်းလင်းချက် ကြည့်ရန် ပုံ သို့မဟုတ် စာသားထဲရှိ အရောင်ခြယ်ထားသည်ကို၊ သို့မဟုတ် အောက်ပါစာရင်းကို နှိပ်ပါ။",
    "识别文本": "ဖတ်ယူထားသော စာသား",
    "文本已手动修改，图片上的高亮已隐藏。": "စာသားကို ပြင်ထားသဖြင့် ပုံပေါ်ရှိ အရောင်ခြယ်မှုများကို ဖျောက်ထားပါသည်။",
    "修正识别文本": "စာသား ပြင်ဆင်ရန်",
    "取消": "ပယ်ဖျက်ရန်",
    "重新识别": "ပြန်ခွဲခြမ်းရန်",
    "这里有多个语法点，请选择": "ဤနေရာတွင် သဒ္ဒါ အများအပြား ထပ်နေပါသည်။ တစ်ခု ရွေးပါ:",
}

INFO = {
    "CFBundleDisplayName": ("语法扫描", ("Grammar Scan", "문법 스캔", "Gramática JP", "Ngữ Pháp JP")),
    "NSCameraUsageDescription": ("需要使用相机扫描书本上的日文，以识别其中的语法点。", (
        "The camera is used to scan Japanese text in books and identify grammar points. Images are processed on your device only.",
        "책의 일본어를 스캔해 문법을 인식하기 위해 카메라를 사용합니다. 이미지는 기기 안에서만 처리됩니다.",
        "La cámara se usa para escanear texto japonés de libros e identificar puntos gramaticales. Las imágenes se procesan solo en tu dispositivo.",
        "Ứng dụng dùng camera để quét chữ tiếng Nhật trong sách và nhận diện ngữ pháp. Hình ảnh chỉ được xử lý trên thiết bị.",
    )),
}

MY_INFO = {
    "CFBundleDisplayName": "သဒ္ဒါစကင်",
    "NSCameraUsageDescription": "စာအုပ်ထဲရှိ ဂျပန်စာကို စကင်ဖတ်ပြီး သဒ္ဒါများကို ရှာဖွေရန် ကင်မရာကို အသုံးပြုပါသည်။ ပုံများကို သင့်စက်ပေါ်တွင်သာ လုပ်ဆောင်ပါသည်။",
}

LANGS = ["en", "ko", "es", "vi"]


def unit(v):
    return {"stringUnit": {"state": "translated", "value": v}}


def loc(v):
    if isinstance(v, dict):
        return {"variations": {"plural": {k: unit(x) for k, x in v.items()}}}
    return unit(v)


def catalog(entries):
    return {"sourceLanguage": "zh-Hans", "strings": entries, "version": "1.0"}


def check_my():
    missing = [k for k in S if k not in MY]
    extra = [k for k in MY if k not in S]
    assert not missing and not extra, f"MY 缺少 {missing} / 多余 {extra}"
    missing = [k for k in INFO if k not in MY_INFO]
    extra = [k for k in MY_INFO if k not in INFO]
    assert not missing and not extra, f"MY_INFO 缺少 {missing} / 多余 {extra}"
    for k, v in MY.items():
        assert isinstance(v, str), f"MY[{k!r}] 必须是字符串"
        assert re.findall(r"%(?:\d+\$)?(?:lld|@|%)", k) == re.findall(r"%(?:\d+\$)?(?:lld|@|%)", v), f"MY[{k!r}] 格式符不一致"


def main():
    check_my()
    strings = {}
    for key, vals in S.items():
        l = {lang: loc(v) for lang, v in zip(LANGS, vals)}
        l["my"] = unit(MY[key])
        l["zh-Hans"] = unit(key)
        l["zh-Hant"] = unit(cc.convert(key))
        strings[key] = {"extractionState": "manual", "localizations": l}
    with open(os.path.join(APP, "Localizable.xcstrings"), "w", encoding="utf-8") as f:
        json.dump(catalog(strings), f, ensure_ascii=False, indent=2, sort_keys=True)

    info = {}
    for key, (zh, vals) in INFO.items():
        l = {lang: unit(v) for lang, v in zip(LANGS, vals)}
        l["my"] = unit(MY_INFO[key])
        l["zh-Hans"] = unit(zh)
        l["zh-Hant"] = unit(cc.convert(zh))
        info[key] = {"extractionState": "manual", "localizations": l}
    with open(os.path.join(APP, "InfoPlist.xcstrings"), "w", encoding="utf-8") as f:
        json.dump(catalog(info), f, ensure_ascii=False, indent=2, sort_keys=True)
    print(f"Localizable: {len(strings)} keys, InfoPlist: {len(info)} keys")


if __name__ == "__main__":
    main()
