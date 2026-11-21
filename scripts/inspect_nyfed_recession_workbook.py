#!/usr/bin/env python3
"""Inspect NY Fed's published recession model workbook, without estimating values.

Diagnostic-only. Official workbook layout and publication timestamp must be
verified before making this a production data source.
"""
import io
import urllib.request

URL="https://www.newyorkfed.org/medialibrary/media/research/capital_markets/allmonth.xls"

def describe():
    try:
        import xlrd
    except ImportError:
        print("NYFED_RECESSION_PENDING: xlrd dependency not installed")
        return False
    try:
        request=urllib.request.Request(URL,headers={"User-Agent":"Mozilla/5.0 OoglexResearch/1.0"})
        with urllib.request.urlopen(request,timeout=20) as resp:
            data=resp.read(4000000)
        book=xlrd.open_workbook(file_contents=data)
        print("NYFED_OFFICIAL_WORKBOOK_SHEETS:",book.sheet_names())
        for sheet in book.sheets():
            print("SHEET:",sheet.name,"rows",sheet.nrows,"cols",sheet.ncols)
            for idx in list(range(min(sheet.nrows,6)))+list(range(max(6,sheet.nrows-3),sheet.nrows)):
                values=[str(sheet.cell_value(idx,j))[:35] for j in range(min(sheet.ncols,10))]
                print("ROW",idx,values)
        return True
    except (OSError,ValueError,ImportError,Exception) as exc:
        print("NYFED_RECESSION_PENDING:",type(exc).__name__,str(exc)[:150])
        return False
if __name__=="__main__":describe()
