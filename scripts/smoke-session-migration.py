#!/usr/bin/env python3
"""Smoke test the SQLite migration contract used by SessionStore 0.9.6."""
import sqlite3
import tempfile
import os
from pathlib import Path

fd, temp_path = tempfile.mkstemp(prefix="morixtrem-migration-", suffix=".db")
os.close(fd)
p = Path(temp_path)
try:
    db = sqlite3.connect(p)
    q = db.cursor()
    q.execute("PRAGMA foreign_keys=ON")
    q.execute("CREATE TABLE session_folders(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)")
    q.execute("INSERT INTO session_folders(name) VALUES('Test')")
    q.execute("""
      CREATE TABLE sessions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        kind TEXT NOT NULL CHECK(kind IN ('ssh','rdp')),
        host TEXT NOT NULL,
        user_name TEXT NOT NULL DEFAULT '',
        port INTEGER NOT NULL,
        domain_name TEXT NOT NULL DEFAULT '',
        rdp_width INTEGER NOT NULL DEFAULT 1440,
        rdp_height INTEGER NOT NULL DEFAULT 900,
        rdp_scale INTEGER NOT NULL DEFAULT 100,
        fullscreen INTEGER NOT NULL DEFAULT 0,
        ignore_certificate INTEGER NOT NULL DEFAULT 0,
        folder_id INTEGER REFERENCES session_folders(id) ON DELETE SET NULL,
        security_profile TEXT NOT NULL DEFAULT 'modern',
        key_file TEXT NOT NULL DEFAULT '',
        ftp_tls INTEGER NOT NULL DEFAULT 1,
        ftp_passive INTEGER NOT NULL DEFAULT 1,
        overwrite_existing INTEGER NOT NULL DEFAULT 1,
        max_parallel INTEGER NOT NULL DEFAULT 4,
        credential_saved INTEGER NOT NULL DEFAULT 0,
        last_used_at TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT
      )
    """)
    q.execute("INSERT INTO sessions(name,kind,host,user_name,port) VALUES('Legacy SSH','ssh','127.0.0.1','tester',22)")
    db.commit()

    q.execute("PRAGMA foreign_keys=OFF")
    q.execute("BEGIN IMMEDIATE")
    q.execute("DROP TABLE IF EXISTS sessions_morixtrem_legacy_096")
    q.execute("ALTER TABLE sessions RENAME TO sessions_morixtrem_legacy_096")
    q.execute("""
      CREATE TABLE sessions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        host TEXT NOT NULL,
        user_name TEXT NOT NULL DEFAULT '',
        port INTEGER NOT NULL,
        domain_name TEXT NOT NULL DEFAULT '',
        rdp_width INTEGER NOT NULL DEFAULT 1440,
        rdp_height INTEGER NOT NULL DEFAULT 900,
        rdp_scale INTEGER NOT NULL DEFAULT 100,
        fullscreen INTEGER NOT NULL DEFAULT 0,
        ignore_certificate INTEGER NOT NULL DEFAULT 0,
        folder_id INTEGER REFERENCES session_folders(id) ON DELETE SET NULL,
        security_profile TEXT NOT NULL DEFAULT 'modern',
        key_file TEXT NOT NULL DEFAULT '',
        ftp_tls INTEGER NOT NULL DEFAULT 1,
        ftp_passive INTEGER NOT NULL DEFAULT 1,
        overwrite_existing INTEGER NOT NULL DEFAULT 1,
        max_parallel INTEGER NOT NULL DEFAULT 4,
        credential_saved INTEGER NOT NULL DEFAULT 0,
        last_used_at TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT
      )
    """)
    cols = "id,name,kind,host,user_name,port,domain_name,rdp_width,rdp_height,rdp_scale,fullscreen,ignore_certificate,folder_id,security_profile,key_file,ftp_tls,ftp_passive,overwrite_existing,max_parallel,credential_saved,last_used_at,created_at,updated_at"
    q.execute(f"INSERT INTO sessions({cols}) SELECT {cols} FROM sessions_morixtrem_legacy_096")
    q.execute("DROP TABLE sessions_morixtrem_legacy_096")
    q.execute("PRAGMA user_version=906")
    q.execute("COMMIT")
    q.execute("PRAGMA foreign_keys=ON")

    sql = q.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='sessions'").fetchone()[0].lower()
    assert "check" not in sql or "kind" not in sql, sql
    q.execute("INSERT INTO sessions(name,kind,host,user_name,port) VALUES('FTP','ftp','127.0.0.1','tester',21)")
    ftp_id = q.lastrowid
    q.execute("UPDATE sessions SET folder_id=1 WHERE id=?", (ftp_id,))
    db.commit()
    assert q.execute("SELECT kind,folder_id FROM sessions WHERE id=?", (ftp_id,)).fetchone() == ("ftp", 1)
    assert q.execute("SELECT rdp_scale FROM sessions WHERE id=?", (ftp_id,)).fetchone() == (100,)
    assert q.execute("PRAGMA user_version").fetchone()[0] == 906
    print("Session migration smoke test passed")
finally:
    try:
        db.close()
    except Exception:
        pass
    p.unlink(missing_ok=True)
