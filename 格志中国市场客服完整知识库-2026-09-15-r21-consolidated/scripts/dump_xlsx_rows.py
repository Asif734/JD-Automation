import csv
import sys
import zipfile
from inspect_xlsx import read_shared_strings, read_sheets, cell_pos, cell_value, NS
from xml.etree import ElementTree as ET


def read_rows(zf, sheet_path, shared_strings):
    root = ET.fromstring(zf.read(sheet_path))
    rows = []
    for row in root.findall("main:sheetData/main:row", NS):
        values_by_col = {}
        for cell in row.findall("main:c", NS):
            _, col_num = cell_pos(cell.attrib.get("r"))
            value = cell_value(cell, shared_strings)
            if value != "":
                values_by_col[col_num] = value.replace("\r\n", "\n").replace("\r", "\n")
        if values_by_col:
            rows.append([values_by_col.get(col, "") for col in range(1, max(values_by_col) + 1)])
    return rows


def main():
    xlsx_path = sys.argv[1]
    start = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    end = int(sys.argv[3]) if len(sys.argv) > 3 else 999999
    with zipfile.ZipFile(xlsx_path) as zf:
        shared_strings = read_shared_strings(zf)
        sheet = read_sheets(zf)[0]
        rows = read_rows(zf, sheet["path"], shared_strings)
    writer = csv.writer(sys.stdout, delimiter="\t", lineterminator="\n")
    writer.writerow(["row", "date", "product", "type", "issue", "method", "note", "agent"])
    for idx, row in enumerate(rows, start=1):
        if idx < start or idx > end:
            continue
        padded = row + [""] * 9
        writer.writerow([idx, padded[0], padded[1], padded[2], padded[3], padded[5], padded[7], padded[8]])


if __name__ == "__main__":
    main()
