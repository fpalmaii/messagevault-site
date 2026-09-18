#!/bin/sh
# MessageVault 1.5 - migration test against the iOS Simulator.
#
# Run it, do what it says, run it again. It works out which stage it is in by
# looking at the database, so there is nothing to remember.
#
#   stage 0  app has never run       -> tells you to run it once
#   stage 1  fresh/new-schema DB     -> SEEDS a synthetic 1.0.2 vault, tells you to relaunch
#   stage 2  seeded, not migrated    -> tells you to relaunch the app
#   stage 3  migrated                -> VERIFIES and uploads the full log
#
# It never touches a physical device. It backs the database up before writing.

set -u
SQL=/usr/bin/sqlite3
LOG=/tmp/mv_migration_test.log
: > "$LOG"

say() { echo "$@" | tee -a "$LOG"; }

say "=== MessageVault 1.5 migration test ==="
say "date: $(date)"

# ---------------------------------------------------------------- locate the DB
DB=$(find "$HOME/Library/Developer/CoreSimulator/Devices" -name "messagevault.sqlite" 2>/dev/null \
     | head -1)

if [ -z "$DB" ]; then
    say ""
    say "No simulator database found yet."
    say ""
    say "DO THIS:  in Xcode, Product > Destination > iPhone 17 Pro"
    say "          then Product > Run, let the app open, then run this script again."
    exit 0
fi

DIR=$(dirname "$DB")
say "db: $DB"

VER=$($SQL "$DB" "PRAGMA user_version;" 2>/dev/null || echo "?")
TOK=$($SQL "$DB" "SELECT sql FROM sqlite_master WHERE name='search_index';" 2>/dev/null | tr -d '\n')
ITEMS=$($SQL "$DB" "SELECT COUNT(*) FROM content_items;" 2>/dev/null || echo 0)
say "user_version: $VER   items: $ITEMS"

case "$TOK" in
    *porter*)   TOKENIZER=porter ;;
    *unicode61*) TOKENIZER=unicode61 ;;
    *)          TOKENIZER=unknown ;;
esac
say "tokenizer: $TOKENIZER"

# ---------------------------------------------------------------- stage 2
if [ "$TOKENIZER" = "porter" ]; then
    say ""
    say "Seeded vault is present and NOT yet migrated. Good - that is the state we want."
    say ""
    say "DO THIS:  bring the Simulator to the front and launch MessageVault"
    say "          (tap its icon, or Product > Run in Xcode)."
    say "          Wait for it to finish opening, then run this script again."
    exit 0
fi

# ---------------------------------------------------------------- stage 3
if [ "$VER" = "4" ] && [ "$TOKENIZER" = "unicode61" ] && [ "$ITEMS" -gt 0 ]; then
    say ""
    say "############ VERIFYING ############"
    FAIL=0

    say ""
    say "-- schema --"
    say "$($SQL "$DB" "SELECT sql FROM sqlite_master WHERE name='search_index';")"
    case "$TOK" in
        *"prefix"*) say "PASS prefix index present" ;;
        *)          say "FAIL prefix index missing"; FAIL=1 ;;
    esac
    case "$TOK" in
        *porter*) say "FAIL porter still present"; FAIL=1 ;;
        *)        say "PASS porter gone" ;;
    esac

    say ""
    say "-- v3 item_tags --"
    TAGROWS=$($SQL "$DB" "SELECT COUNT(*) FROM item_tags;" 2>/dev/null || echo 0)
    TAGDIST=$($SQL "$DB" "SELECT COUNT(DISTINCT tag) FROM item_tags;" 2>/dev/null || echo 0)
    say "item_tags rows: $TAGROWS  distinct tags: $TAGDIST"
    [ "$TAGROWS" -gt 0 ] && say "PASS backfill populated" || { say "FAIL backfill empty"; FAIL=1; }
    say "top tags:"
    $SQL "$DB" "SELECT '   '||tag||'  '||COUNT(*) FROM item_tags GROUP BY tag ORDER BY COUNT(*) DESC LIMIT 8;" | tee -a "$LOG"
    say "orphans (should be 0): $($SQL "$DB" "SELECT COUNT(*) FROM item_tags it LEFT JOIN content_items ci ON ci.id=it.content_item_id WHERE ci.id IS NULL;")"

    say ""
    say "-- v4 retrieval counters --"
    COLS=$($SQL "$DB" "PRAGMA table_info(content_items);" | cut -d'|' -f2 | tr '\n' ' ')
    say "columns: $COLS"
    case "$COLS" in
        *last_opened_at*open_count*) say "PASS both columns present" ;;
        *) say "FAIL retrieval columns missing"; FAIL=1 ;;
    esac

    say ""
    say "-- data preserved --"
    say "content_items: $ITEMS (seeded 38)"
    say "search_index:  $($SQL "$DB" "SELECT COUNT(*) FROM search_index;")"
    [ "$ITEMS" = "38" ] && say "PASS no rows lost" || { say "FAIL item count changed"; FAIL=1; }

    say ""
    say "-- dead zones (the whole point) --"
    for W in animals running cooking swimming training happiness national; do
        LINE="   $W:"
        N=3
        while [ $N -le ${#W} ]; do
            P=$(echo "$W" | cut -c1-$N)
            C=$($SQL "$DB" "SELECT COUNT(*) FROM search_index WHERE search_index MATCH '$P*';" 2>/dev/null || echo E)
            LINE="$LINE $P=$C"
            N=$((N+1))
        done
        say "$LINE"
    done

    say ""
    say "-- prefix monotonicity across whole vocabulary --"
    $SQL "$DB" "CREATE VIRTUAL TABLE IF NOT EXISTS vocab_probe USING fts5vocab(search_index,'row');" 2>/dev/null
    TERMS=$($SQL "$DB" "SELECT term FROM vocab_probe WHERE length(term)>=5 AND term GLOB '[a-z]*' AND term NOT GLOB '*[^a-z]*';" 2>/dev/null)
    WIDENED=0; CHECKED=0
    for T in $TERMS; do
        PREV=""
        N=3
        while [ $N -le ${#T} ]; do
            P=$(echo "$T" | cut -c1-$N)
            C=$($SQL "$DB" "SELECT COUNT(*) FROM search_index WHERE search_index MATCH '$P*';" 2>/dev/null || echo 0)
            CHECKED=$((CHECKED+1))
            if [ -n "$PREV" ] && [ "$C" -gt "$PREV" ]; then
                say "   WIDENED $T at $P ($PREV -> $C)"
                WIDENED=$((WIDENED+1))
            fi
            PREV=$C
            N=$((N+1))
        done
    done
    say "terms: $(echo "$TERMS" | wc -w | tr -d ' ')  prefix queries: $CHECKED  widening steps: $WIDENED"
    [ "$WIDENED" -eq 0 ] && say "PASS monotonic" || { say "FAIL widening detected"; FAIL=1; }
    $SQL "$DB" "DROP TABLE IF EXISTS vocab_probe;" 2>/dev/null

    say ""
    say "-- controls (must stay empty) --"
    for W in xyzzy qqqq zzzzz; do
        say "   $W* -> $($SQL "$DB" "SELECT COUNT(*) FROM search_index WHERE search_index MATCH '$W*';")"
    done

    say ""
    if [ "$FAIL" -eq 0 ]; then say "############ RESULT: PASS ############"
    else say "############ RESULT: FAIL ############"; fi

    say ""
    say "uploading log..."
    URL=$(nc termbin.com 9999 < "$LOG" 2>/dev/null | tr -d '\0\r\n')
    echo ""
    echo "=========================================="
    echo " TELL CLAUDE THIS: $URL"
    echo "=========================================="
    exit 0
fi

# ---------------------------------------------------------------- stage 1: seed
say ""
say "############ SEEDING a synthetic 1.0.2 vault ############"
say "(this replaces the simulator database only - no physical device is touched)"

if [ -f "$DB" ]; then
    cp "$DB" "$DB.bak.$(date +%s)" 2>/dev/null && say "backup written next to the db"
fi
rm -f "$DB" "$DB-wal" "$DB-shm"

NOW=$(date +%s)
D=86400

{
  echo "PRAGMA journal_mode=WAL;"
  cat <<'SCHEMA'
CREATE TABLE IF NOT EXISTS content_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    captured_at INTEGER NOT NULL,
    raw_text TEXT NOT NULL,
    content_url TEXT,
    content_source TEXT,
    preview_image_path TEXT,
    preview_title TEXT,
    preview_domain TEXT,
    source_platform TEXT NOT NULL DEFAULT 'iOS',
    capture_method TEXT NOT NULL DEFAULT 'share_extension'
);
CREATE TABLE IF NOT EXISTS ai_enrichment (
    content_item_id INTEGER PRIMARY KEY,
    tags TEXT NOT NULL DEFAULT '',
    enrichment_source TEXT,
    enriched_at INTEGER,
    FOREIGN KEY (content_item_id) REFERENCES content_items(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS ad_signals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at INTEGER NOT NULL,
    signal_type TEXT NOT NULL,
    payload TEXT
);
CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5(
    content_item_id UNINDEXED, raw_text, preview_title, tags,
    tokenize = 'porter unicode61 remove_diacritics 1'
);
CREATE INDEX IF NOT EXISTS idx_content_items_captured_at ON content_items(captured_at DESC);
CREATE INDEX IF NOT EXISTS idx_content_items_source ON content_items(content_source);
CREATE INDEX IF NOT EXISTS idx_ai_enrichment_enriched_at ON ai_enrichment(enriched_at);
SCHEMA

  ins() {
    echo "INSERT INTO content_items (captured_at,raw_text,preview_title,content_source) VALUES ($((NOW-$1*D)),'$2','$3','$4');"
    echo "INSERT INTO ai_enrichment (content_item_id,tags,enrichment_source,enriched_at) VALUES (last_insert_rowid(),'$5','seed',$((NOW-$1*D)));"
  }

  for d in 2 3 5 6 8 11 14 17 20 22 25 27 29; do
    ins $d "Running through Bali beaches and animals" "Bali running" "instagram" "bali,travel,beach"
  done
  for d in 95 120; do ins $d "Bali travel notes" "Bali notes" "instagram" "bali,travel"; done
  for d in 4 18 40 70 100 130 160; do
    ins $d "Cooking a slow braise, national dish" "Cooking braise" "youtube" "recipes,cooking,food"
  done
  for d in 200 210 215 220 230 240; do
    ins $d "Woodworking bench build, training jigs" "Woodworking bench" "youtube" "woodworking,diy,tools"
  done
  for d in 30 45 60 75 90 110; do
    ins $d "Design systems and swimming pool architecture" "Design systems" "x" "design,architecture"
  done
  for d in 1 9 33 66; do
    ins $d "Happiness and relaxing travelling notes" "Happiness notes" "tiktok" "wellbeing,travel"
  done

  # A legacy April-era JSON tags row and a messy-whitespace row, to exercise the
  # backfill normaliser on the real device.
  echo "UPDATE ai_enrichment SET tags='[\"bali\",\"travel\",\"beach\"]' WHERE content_item_id=1;"
  echo "UPDATE ai_enrichment SET tags=' Bali , Travel ,beach' WHERE content_item_id=2;"

  cat <<'FILL'
INSERT INTO search_index (content_item_id, raw_text, preview_title, tags)
SELECT c.id, c.raw_text, COALESCE(c.preview_title,''), COALESCE(a.tags,'')
FROM content_items c LEFT JOIN ai_enrichment a ON a.content_item_id = c.id;
PRAGMA user_version = 0;
FILL
} | $SQL "$DB"

say "seeded items: $($SQL "$DB" "SELECT COUNT(*) FROM content_items;")"
say "user_version: $($SQL "$DB" "PRAGMA user_version;")  (0 = looks like 1.0.2)"
say "dead zone present before migration?  anim=$($SQL "$DB" "SELECT COUNT(*) FROM search_index WHERE search_index MATCH 'anim*';") anima=$($SQL "$DB" "SELECT COUNT(*) FROM search_index WHERE search_index MATCH 'anima*';") animal=$($SQL "$DB" "SELECT COUNT(*) FROM search_index WHERE search_index MATCH 'animal*';")"
say ""
say "That middle number should be 0 - that is the bug, reproduced on your Mac."
say ""
say "DO THIS:  bring the Simulator to the front and launch MessageVault"
say "          (tap its icon, or Product > Run in Xcode)."
say "          Then run this script again to verify."
