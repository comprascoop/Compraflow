#!/usr/bin/env bash
# Gera um único arquivo SQL com todas as migrations, para colar no SQL Editor do Supabase.
set -e
out="supabase/_TUDO_EM_UM.sql"
echo "-- CompraFlow — todas as migrations em ordem. Gerado em $(date)" > "$out"
for f in supabase/migrations/*.sql; do
  echo -e "\n\n-- ============ $(basename "$f") ============" >> "$out"
  cat "$f" >> "$out"
done
echo "Gerado: $out"
