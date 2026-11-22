#!/usr/bin/env python3
"""Prefer direct official Treasury history; FRED H.15 is labelled fallback only."""
import argparse
from datetime import date
from pathlib import Path

from scripts.build_asset_compass_history import build as treasury_build
from scripts.build_asset_compass_history_fred_v42 import build as fred_build
from scripts.validate_asset_compass_treasury_trends_v42 import validate

def build_prefer_treasury(output,*,today=None,start_year=None,direct=None,fallback=None):
    today=today or date.today()
    direct=direct or treasury_build
    fallback=fallback or fred_build
    start_year=start_year if start_year is not None else today.year-5
    if start_year<1997 or start_year>today.year or today.year-start_year>15:
        raise ValueError('Invalid historical year range')
    try:
        result=direct(range(start_year,today.year+1),output)
        if result.get("source")!="U.S. Department of the Treasury":
            raise ValueError("Direct Treasury builder returned unexpected source")
        validate(result)
        print("V42 historical yields: verified direct U.S. Treasury CSV")
        return result
    except (OSError,ValueError,TimeoutError) as error:
        print("Direct Treasury historical CSV failed:",type(error).__name__,
              "— trying distinctly labeled official Federal Reserve H.15 via FRED")
    result=fallback(start_year=max(start_year,today.year-2),output=output,today=today)
    if result.get("source")!="Federal Reserve Board H.15 via FRED":
        raise ValueError("H.15 fallback returned unexpected source")
    validate(result)
    print("V42 historical yields: verified Federal Reserve H.15 via FRED fallback")
    return result

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--output",type=Path,default=Path("data/asset-compass-treasury-history.json"))
    p.add_argument("--start-year",type=int)
    args=p.parse_args()
    d=build_prefer_treasury(args.output,start_year=args.start_year)
    print(d["source"],d["observation_count"],d["start_date"],d["end_date"])

if __name__=="__main__":
    main()
