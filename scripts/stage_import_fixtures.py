#!/usr/bin/env python3
"""Stage fictional history and October examples in Simulator Files for native QA."""
import argparse
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--device", default="booted", help="Booted simulator UUID or 'booted'")
parser.add_argument("--app", type=Path, help="Optional built Harbor.app to install first")
args = parser.parse_args()
if args.app:
    subprocess.run(["xcrun", "simctl", "install", args.device, str(args.app.resolve())], check=True)
container = Path(subprocess.check_output(
    ["xcrun", "simctl", "get_app_container", args.device, "com.josh.harbor", "data"], text=True
).strip())
# Only stage synthetic source documents; never reset or modify any ledger or Keychain item.
documents = container / "Documents"
documents.mkdir(exist_ok=True)
fixtures = Path(__file__).resolve().parent.parent / "HarborTests" / "Fixtures"
for source, target in [("Transactions.csv", "Harbor-test-transactions.csv"), ("Statement.pdf", "Harbor-test-statement.pdf"),
                       # A single named subscription exercises the focused billing-schedule prompt.
                       ("ICloudSubscription.csv", "Harbor-test-icloud-single.csv"),
                       # Additional fictional exports exercise CAD-suffixed headers and wrapped PDF table cells.
                       ("ExpandedTransactions.csv", "Harbor-expanded-transactions.csv"), ("ExpandedStatement.pdf", "Harbor-expanded-statement.pdf"),
                       ("USDSavings.csv", "Harbor-USD-savings.csv"), ("VisionGBPStatement.pdf", "Harbor-GBP-vision.pdf")]:
    shutil.copyfile(fixtures / source, documents / target)
# This balanced fictional statement supports exact monthly reconciliation and duplicate-only receipts.
shutil.copyfile(fixtures / "MonthlyReconciliation.csv", documents / "Harbor-monthly-reconciliation.csv")
shutil.copyfile(Path(__file__).resolve().parent.parent / "samples" / "October-2026-examples.csv", documents / "Harbor-October-examples.csv")
print("Staged the nine fictional files in Simulator: Files → On My iPhone → Harbor")
