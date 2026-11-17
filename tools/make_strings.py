#!/usr/bin/env python3
"""生成界面文字的 String Catalog（Localizable.xcstrings / InfoPlist.xcstrings）。
源语言为简体中文（代码中的字符串即 key）；繁体中文由 OpenCC 自动转换。
用法: python3 tools/make_strings.py
"""
import json
import os

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
    "注意": ("Notes", "주의", "Notas", "Lưu ý"),
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

INFO = {
    "CFBundleDisplayName": ("语法扫描", ("Grammar Scan", "문법 스캔", "Gramática JP", "Ngữ Pháp JP")),
    "NSCameraUsageDescription": ("需要使用相机扫描书本上的日文，以识别其中的语法点。", (
        "The camera is used to scan Japanese text in books and identify grammar points. Images are processed on your device only.",
        "책의 일본어를 스캔해 문법을 인식하기 위해 카메라를 사용합니다. 이미지는 기기 안에서만 처리됩니다.",
        "La cámara se usa para escanear texto japonés de libros e identificar puntos gramaticales. Las imágenes se procesan solo en tu dispositivo.",
        "Ứng dụng dùng camera để quét chữ tiếng Nhật trong sách và nhận diện ngữ pháp. Hình ảnh chỉ được xử lý trên thiết bị.",
    )),
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


def main():
    strings = {}
    for key, vals in S.items():
        l = {lang: loc(v) for lang, v in zip(LANGS, vals)}
        l["zh-Hans"] = unit(key)
        l["zh-Hant"] = unit(cc.convert(key))
        strings[key] = {"extractionState": "manual", "localizations": l}
    with open(os.path.join(APP, "Localizable.xcstrings"), "w", encoding="utf-8") as f:
        json.dump(catalog(strings), f, ensure_ascii=False, indent=2, sort_keys=True)

    info = {}
    for key, (zh, vals) in INFO.items():
        l = {lang: unit(v) for lang, v in zip(LANGS, vals)}
        l["zh-Hans"] = unit(zh)
        l["zh-Hant"] = unit(cc.convert(zh))
        info[key] = {"extractionState": "manual", "localizations": l}
    with open(os.path.join(APP, "InfoPlist.xcstrings"), "w", encoding="utf-8") as f:
        json.dump(catalog(info), f, ensure_ascii=False, indent=2, sort_keys=True)
    print(f"Localizable: {len(strings)} keys, InfoPlist: {len(info)} keys")


if __name__ == "__main__":
    main()
