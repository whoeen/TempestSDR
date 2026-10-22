"""Index authored source/claim/reading notes in SQLite without copying full PDFs."""
import argparse
import hashlib
import json
import pathlib
import sqlite3
from datetime import datetime, timezone
ROOT = pathlib.Path(__file__).resolve().parents[1]
def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--query")
    args=parser.parse_args()
    db=sqlite3.connect(ROOT/"knowledge.sqlite")
    db.executescript("""
    CREATE TABLE IF NOT EXISTS entries (
      key TEXT PRIMARY KEY, area TEXT, file TEXT, line INTEGER,
      record_type TEXT, source_id TEXT, body TEXT, indexed_utc TEXT);
    CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(key UNINDEXED,body);
    """)
    if not args.query:
        rows=[]
        candidates=list((ROOT/"knowledge").rglob("*.jsonl"))
        candidates+=list((ROOT/"signal_processing"/"outputs").rglob("*.jsonl"))
        for path in sorted(candidates):
            if any(part in {"cache","extracted","raw"} for part in path.parts): continue
            relative=path.relative_to(ROOT).as_posix()
            for i,line in enumerate(path.read_text(encoding="utf-8-sig").splitlines(),1):
                if not line.strip(): continue
                data=json.loads(line)
                key=hashlib.sha256((relative+":"+str(i)+":"+line).encode()).hexdigest()
                source_id=data.get("source_id",data.get("claim_id",data.get("step","")))
                if not isinstance(source_id,str): source_id=json.dumps(source_id)
                rows.append((key,path.parent.name,relative,i,path.stem,source_id,
                             json.dumps(data,ensure_ascii=False),
                             datetime.now(timezone.utc).isoformat()))
        with db:
            db.execute("DELETE FROM entries")
            db.execute("DELETE FROM entries_fts")
            db.executemany("INSERT INTO entries VALUES (?,?,?,?,?,?,?,?)",rows)
            db.executemany("INSERT INTO entries_fts VALUES (?,?)",[(r[0],r[6]) for r in rows])
        summary={"indexed_utc":datetime.now(timezone.utc).isoformat(),
                 "entry_count":len(rows),"by_area":dict(db.execute(
                     "SELECT area,count(*) FROM entries GROUP BY area"))}
        (ROOT/"knowledge"/"index_summary.json").write_text(
            json.dumps(summary,ensure_ascii=False,indent=2),encoding="utf-8")
        print(json.dumps(summary,ensure_ascii=False))
    else:
        records=db.execute("""SELECT e.file,e.line,e.body FROM entries e
          JOIN entries_fts f ON e.key=f.key WHERE entries_fts MATCH ? LIMIT 20""",
          (args.query,)).fetchall()
        for file,line,body in records:
            print(json.dumps({"file":file,"line":line,"record":json.loads(body)},ensure_ascii=False))
    db.close()
if __name__=="__main__": main()
