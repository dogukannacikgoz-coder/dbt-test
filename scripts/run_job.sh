#!/usr/bin/env bash
# ============================================================================
#  UC4 / OpenShift job giriş noktası — 1 UC4 job = 1 tag
#  Kullanım:
#    scripts/run_job.sh <tag> [load_date] [--retry]
#    scripts/run_job.sh cust_fin_daily 2026-10-02
#    scripts/run_job.sh cust_fin_daily 2026-10-02 --retry   # son run'da fail/skip olanlardan devam
#  load_date verilmezse dün. Exit code dbt'ninkidir (UC4 başarı/hata buna bakar).
# ============================================================================
set -uo pipefail
TAG="${1:?tag gerekli}"
LOAD_DATE="${2:-$(date -d yesterday +%F)}"
MODE="${3:-}"
cd "$(dirname "$0")/.."
export DBT_PROFILES_DIR="${DBT_PROFILES_DIR:-$PWD}"

# her job kendi target klasörünü kullanır -> paralel job'lar run_results'ını ezmez, retry doğru çalışır
STATE_DIR="target/jobs/${TAG}"
VARS="{load_date: '${LOAD_DATE}'}"

if [[ "$MODE" == "--retry" ]]; then
  dbt retry --target-path "$STATE_DIR" --vars "$VARS"
else
  dbt build -s "tag:${TAG}" --target-path "$STATE_DIR" --vars "$VARS"
fi
RC=$?
echo "job=${TAG} load_date=${LOAD_DATE} rc=${RC}"
exit $RC
