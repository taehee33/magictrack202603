# 앱에서 쓰는 문구를 뽑아 Localizable.xcstrings에 영어 번역을 채운다.
# 사용법: python3 -I tools/localization/update_catalog.py  (프로젝트 폴더에서)
# 번역표(en.py)에 없는 문구가 있으면 목록을 보여주고 실패한다
import json, pathlib, subprocess, sys, tempfile, xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[2]
CATALOG = ROOT / "MagicTrack/Resources/Localizable.xcstrings"
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from en import EN  # noqa: E402

# 번역이 필요 없는 문구 (기호·숫자만)
SKIP = {"", "%lld", "·", "%@ · %@", "VID %@ · PID %@"}

# 코드에서 더 이상 쓰지 않는 문구가 남지 않도록 빈 카탈로그에서 다시 뽑는다
CATALOG.write_text(json.dumps({"sourceLanguage": "ko", "strings": {}, "version": "1.0"}, indent=2) + "\n", encoding="utf-8")

with tempfile.TemporaryDirectory() as tmp:
    subprocess.run(["xcodebuild", "-exportLocalizations", "-project", str(ROOT / "MagicTrack.xcodeproj"),
                    "-localizationPath", tmp, "-exportLanguage", "en"], check=True, capture_output=True)
    xliff = pathlib.Path(tmp) / "en.xcloc/Localized Contents/en.xliff"
    ns = {"x": "urn:oasis:names:tc:xliff:document:1.2"}
    keys = []
    for f in ET.parse(xliff).getroot().findall("x:file", ns):
        if f.get("original", "").endswith("Localizable.xcstrings"):
            keys += [u.get("id") for u in f.findall(".//x:trans-unit", ns)]

missing = [k for k in keys if k not in SKIP and k not in EN]
if missing:
    print("번역표(en.py)에 없는 문구:")
    for k in missing:
        print("  ", repr(k))
    sys.exit(1)

strings = {}
for key in sorted(keys):
    if key in SKIP:
        strings[key] = {"shouldTranslate": False}
        continue
    strings[key] = {"localizations": {"en": {"stringUnit": {"state": "translated", "value": EN[key]}}}}

CATALOG.write_text(json.dumps({"sourceLanguage": "ko", "strings": strings, "version": "1.0"},
                              ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(f"{len(strings)}개 문구, 번역 누락 없음 → {CATALOG.relative_to(ROOT)}")
