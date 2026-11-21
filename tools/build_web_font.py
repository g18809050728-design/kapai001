"""Build the Web shell font from the project's Noto Sans CJK font.

Run from the repository root with fonttools and brotli installed.
"""

from pathlib import Path

from fontTools import subset

source = "assets/fonts/NotoSansCJKsc-Regular.otf"
copy = "".join(Path(path).read_text() for path in ["web/game-shell.js", "web/accounts.js"])
common_hanzi = []
for row in range(0xB0, 0xD8):
    for column in range(0xA1, 0xFF):
        common_hanzi.append(bytes([row, column]).decode("gb2312", errors="ignore"))

options = subset.Options()
options.flavor = "woff2"
font = subset.load_font(source, options)
subsetter = subset.Subsetter(options=options)
subsetter.populate(text=copy + "".join(common_hanzi))
subsetter.subset(font)
subset.save_font(font, "web/game-shell.woff2", options)
