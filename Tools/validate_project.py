"""K-LINGUA 專案完整性檢查（可在 Windows / macOS 執行，不需 Xcode）。

檢查項目：
1. project.pbxproj：大括號/小括號平衡、所有被引用的物件 ID 都有定義、rootObject 存在。
2. 所有 .xcassets 內的 Contents.json 為合法 JSON。
3. Swift 原始碼：括號平衡（排除字串與註解）、不含疑似硬編碼 API Key。
4. 資料夾同步群組 KLingua/ 與本機套件 Packages/KLinguaCore 存在。

用法：python Tools/validate_project.py
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
errors: list[str] = []
notes: list[str] = []


def check_pbxproj() -> None:
    path = ROOT / "KLingua.xcodeproj" / "project.pbxproj"
    text = path.read_text(encoding="utf-8")
    body = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    body = re.sub(r'"(?:[^"\\]|\\.)*"', '""', body)
    for open_c, close_c in ("{}", "()"):
        if body.count(open_c) != body.count(close_c):
            errors.append(f"pbxproj: {open_c}{close_c} 不平衡")
    defined = set(re.findall(r"^\s*([0-9A-F]{24})\s*(?:/\*.*?\*/)?\s*=", text, flags=re.M))
    referenced = set(re.findall(r"\b([0-9A-F]{24})\b", body))
    missing = referenced - defined
    if missing:
        errors.append(f"pbxproj: 引用但未定義的 ID：{sorted(missing)}")
    unused = defined - referenced_outside_definitions(body)
    if unused:
        notes.append(f"pbxproj: 已定義但未被引用（通常是根群組或 rootObject 以外的情況）：{sorted(unused)}")
    root = re.search(r"rootObject\s*=\s*([0-9A-F]{24})", body)
    if not root or root.group(1) not in defined:
        errors.append("pbxproj: rootObject 缺失或未定義")
    if "objectVersion = 77" not in text:
        errors.append("pbxproj: objectVersion 應為 77（Xcode 16 資料夾同步格式）")
    notes.append(f"pbxproj: {len(defined)} 個物件，引用完整")


def referenced_outside_definitions(body: str) -> set[str]:
    refs: set[str] = set()
    for line in body.splitlines():
        m = re.match(r"^\s*([0-9A-F]{24})\s*=", line)
        rest = line[m.end():] if m else line
        refs.update(re.findall(r"\b([0-9A-F]{24})\b", rest))
    return refs


def check_assets() -> None:
    for f in (ROOT / "KLingua").rglob("Contents.json"):
        try:
            json.loads(f.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            errors.append(f"JSON 錯誤 {f.relative_to(ROOT)}: {e}")


KEY_PATTERNS = [r"sk-ant-[A-Za-z0-9_-]{10,}", r"sk-[A-Za-z0-9]{20,}", r"AIza[0-9A-Za-z_-]{30,}"]


def strip_swift(src: str) -> str:
    src = re.sub(r'"""(.*?)"""', '""', src, flags=re.S)
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    src = re.sub(r"//[^\n]*", "", src)
    src = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', src)
    return src


def check_swift() -> None:
    files = list(ROOT.rglob("*.swift"))
    files = [f for f in files if ".build" not in f.parts]
    for f in files:
        src = f.read_text(encoding="utf-8")
        code = strip_swift(src)
        for o, c in ("{}", "()", "[]"):
            if code.count(o) != code.count(c):
                errors.append(f"{f.relative_to(ROOT)}: {o}{c} 不平衡")
        for pat in KEY_PATTERNS:
            if re.search(pat, src):
                errors.append(f"{f.relative_to(ROOT)}: 疑似硬編碼 API Key")
    notes.append(f"Swift: 檢查 {len(files)} 個檔案")


def check_layout() -> None:
    for p in ["KLingua", "Packages/KLinguaCore/Package.swift", "Packages/KLinguaCore/Sources/KLinguaCore",
              "Packages/KLinguaCore/Tests/KLinguaCoreTests"]:
        if not (ROOT / p).exists():
            errors.append(f"缺少 {p}")
    if not list((ROOT / "KLingua").rglob("*App.swift")):
        errors.append("找不到 @main App 進入點")


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    check_layout()
    check_pbxproj()
    check_assets()
    check_swift()
    for n in notes:
        print("  ·", n)
    if errors:
        print("\n❌ 發現問題：")
        for e in errors:
            print("  -", e)
        return 1
    print("\n✅ 專案結構檢查通過（注意：這不等於 Swift 編譯通過，編譯需在 macOS/Xcode 進行）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
