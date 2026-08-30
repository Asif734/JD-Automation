import json
import re
import sys
import zipfile
from pathlib import PurePosixPath
from xml.etree import ElementTree as ET


NS = {
    "main": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
    "rel": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
    "pkgrel": "http://schemas.openxmlformats.org/package/2006/relationships",
}


def col_to_num(col):
    total = 0
    for ch in col:
        total = total * 26 + ord(ch.upper()) - 64
    return total


def cell_pos(ref):
    match = re.match(r"([A-Z]+)([0-9]+)", ref or "")
    if not match:
        return None, None
    return int(match.group(2)), col_to_num(match.group(1))


def read_shared_strings(zf):
    if "xl/sharedStrings.xml" not in zf.namelist():
        return []
    root = ET.fromstring(zf.read("xl/sharedStrings.xml"))
    strings = []
    for si in root.findall("main:si", NS):
        parts = []
        for t in si.findall(".//main:t", NS):
            parts.append(t.text or "")
        strings.append("".join(parts))
    return strings


def read_sheets(zf):
    workbook = ET.fromstring(zf.read("xl/workbook.xml"))
    rels = ET.fromstring(zf.read("xl/_rels/workbook.xml.rels"))
    rel_map = {rel.attrib["Id"]: rel.attrib["Target"] for rel in rels}
    sheets = []
    for sheet in workbook.findall("main:sheets/main:sheet", NS):
        rid = sheet.attrib.get(f"{{{NS['rel']}}}id")
        target = rel_map[rid]
        path = str(PurePosixPath("xl") / target)
        sheets.append(
            {
                "name": sheet.attrib["name"],
                "sheet_id": sheet.attrib.get("sheetId"),
                "path": path,
            }
        )
    return sheets


def cell_value(cell, shared_strings):
    ctype = cell.attrib.get("t")
    if ctype == "inlineStr":
        return "".join(t.text or "" for t in cell.findall(".//main:t", NS)).strip()
    value = cell.find("main:v", NS)
    if value is None:
        return ""
    raw = value.text or ""
    if ctype == "s":
        try:
            return shared_strings[int(raw)].strip()
        except (ValueError, IndexError):
            return raw
    return raw.strip()


def summarize_sheet(zf, sheet, shared_strings, max_rows=40):
    root = ET.fromstring(zf.read(sheet["path"]))
    dim = root.find("main:dimension", NS)
    rows_out = []
    nonempty_rows = 0
    max_col = 0
    for row in root.findall("main:sheetData/main:row", NS):
        values_by_col = {}
        for cell in row.findall("main:c", NS):
            row_num, col_num = cell_pos(cell.attrib.get("r"))
            value = cell_value(cell, shared_strings)
            if value != "":
                values_by_col[col_num] = value
                max_col = max(max_col, col_num or 0)
        if values_by_col:
            nonempty_rows += 1
            if len(rows_out) < max_rows:
                row_values = []
                for col in range(1, max(values_by_col) + 1):
                    row_values.append(values_by_col.get(col, ""))
                rows_out.append(row_values)
    return {
        "name": sheet["name"],
        "dimension": dim.attrib.get("ref") if dim is not None else "",
        "nonempty_rows": nonempty_rows,
        "max_col": max_col,
        "sample_rows": rows_out,
    }


def main():
    xlsx_path = sys.argv[1]
    max_rows = int(sys.argv[2]) if len(sys.argv) > 2 else 40
    with zipfile.ZipFile(xlsx_path) as zf:
        shared_strings = read_shared_strings(zf)
        sheets = read_sheets(zf)
        summary = [summarize_sheet(zf, sheet, shared_strings, max_rows=max_rows) for sheet in sheets]
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
