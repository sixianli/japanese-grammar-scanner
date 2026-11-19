# Task: transcribe the printed Japanese text in textbook photos (ground truth for OCR evaluation)

Photos are in /home/user/japanese-grammar-scanner/tests/ocr/samples/. For each file you are given, view the image (Read tool) and write
/tmp/claude-0/-home-user-japanese-grammar-scanner/3d2b5cc4-dca9-58d6-99f4-60394745a9d0/scratchpad/ocr_gt/<IMG_xxxx>.txt

This text is the reference that an OCR system will be compared against, so be exact.

## Include
- All **printed Japanese** text on the **main page** (the page the photo is centred on): headings, body text, dialogue bubbles,
  exercise questions and answer choices, notes, word lists (the Japanese part only).
- Text exactly as printed (do not fix or normalise it). Keep the blanks in exercises as printed, e.g. 「（　）」 or 「___」.

## Exclude
- Furigana (the small kana readings printed above or beside kanji) — write only the base text.
- Handwriting of any kind (pencil/pen notes, circles, ticks, answers written in, red Chinese notes).
- Text showing through from the back of the page, and text on other pages or books partly visible at the edges of the photo.
- Non-Japanese text: English, Chinese, Korean, Vietnamese glosses (e.g. in 「夜市：night market／夜市／야시장」 keep only 「夜市：」).
- Page numbers, decorative running heads like "29回目 News 3".

## Format
- Reading order: for horizontal text, top to bottom; within a two-column layout, finish the left column first unless the layout clearly reads otherwise. Vertical text: right to left.
- Join a sentence that wraps across printed lines into one line. Start a new line after each sentence, heading, bubble, list item or answer choice.
- Write 〓 for a character you cannot read; if a whole region is unreadable (blur, glare), skip it and add a final line starting with `#` describing what was skipped.
- UTF-8 plain text, nothing else in the file.

When all your files are written, reply with one line per file: the file name and the number of characters written.
