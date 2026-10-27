# 앱 아이콘(A2 시안: 겹친 두 패드)을 Icon Composer 문서로 만든다. 사용법: make_icon_composer.py <AppIcon.icon 경로>
# .icon 캔버스(1024)는 아이콘 몸체 전체라서, 시안의 몸체(100~924, 824)를 0~1024로 키워 옮긴다.
import json, pathlib, shutil, sys

out = pathlib.Path(sys.argv[1])  # 만들 .icon 폴더 경로
shutil.rmtree(out, ignore_errors=True)
(out / "Assets").mkdir(parents=True)

K = 1024 / 824          # 시안 좌표 → .icon 좌표
def m(v): return (v - 100) * K
def size(v): return v * K

def pad_svg(name, x, y, w, h, rx, angle, cx, cy, top, bottom):
    svg = (
        '<svg width="1024" height="1024" viewBox="0 0 1024 1024" fill="none" xmlns="http://www.w3.org/2000/svg">'
        f'<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">'
        f'<stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient></defs>'
        f'<rect x="{m(x):.1f}" y="{m(y):.1f}" width="{size(w):.1f}" height="{size(h):.1f}" rx="{size(rx):.1f}" fill="url(#g)"'
        + (f' transform="rotate({angle} {m(cx):.1f} {m(cy):.1f})"' if angle else '')
        + '/></svg>\n'
    )
    (out / "Assets" / name).write_text(svg, encoding="utf-8")

# 뒤: 내장 트랙패드(파랑), 앞: 매직 트랙패드(보라, -18° 회전) — make_icons.py의 A2와 같은 자리
pad_svg("internal.svg", 200, 290, 470, 320, 58, 0, 0, 0, "#6BB4FF", "#1F6FE5")
pad_svg("magic.svg", 355, 445, 470, 320, 58, -18, 590, 605, "#D08BFF", "#7B2FF0")

doc = {
    "fill": {"automatic-gradient": "extended-srgb:0.93333,0.94510,0.97255,1.00000"},
    "groups": [
        {"name": "Magic", "layers": [{"image-name": "magic.svg", "name": "magic"}]},
        {"name": "Internal", "layers": [{"image-name": "internal.svg", "name": "internal"}]},
    ],
    "supported-platforms": {"squares": ["macOS"]},
}
(out / "icon.json").write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
print(out)
