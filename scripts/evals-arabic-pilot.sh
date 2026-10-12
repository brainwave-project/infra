#!/bin/sh
set -eu

experiment_dir="/workspace/docs/experiment-3"
diagnostic_dir="$experiment_dir/data/diagnostic"
pilot_dir="$experiment_dir/work/miracl-ar-train-pilot-100-s42"
full_dir="$experiment_dir/work/miracl-ar-full-dev"
state_dir="$experiment_dir/work/.evals-arabic-state"
normalization_root="/workspace/agent-hub/src/agent_hub/eval/lab_store/normalization"

run_normalization() {
  python -m agent_hub.eval.normalization "$@"
}

json_value() {
  python -c 'import json, sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"
}

import_dataset() {
  dataset_name="$1"
  dataset_dir="$2"
  import_json="$(run_normalization --root "$normalization_root" import \
    --name "$dataset_name" \
    --corpus "$dataset_dir/corpus.jsonl" \
    --queries "$dataset_dir/queries.jsonl" \
    --qrels "$dataset_dir/qrels.tsv" \
    --provenance "$dataset_dir/provenance.json")"
  printf '%s\n' "$import_json" >&2
  printf '%s' "$import_json" | json_value dataset_id
}

save_run() {
  state_prefix="$1"
  run_json="$2"
  mkdir -p "$state_dir"
  printf '%s' "$run_json" | json_value run_id > "$state_dir/$state_prefix-run-id"
  printf '%s' "$run_json" | json_value report_path > "$state_dir/$state_prefix-report-path"
  printf '%s\n' "$run_json"
}

read_state() {
  state_name="$1"
  state_path="$state_dir/$state_name"
  if [ ! -s "$state_path" ]; then
    echo "Missing saved state: $state_name. Complete the earlier guide step first." >&2
    exit 2
  fi
  tr -d '\r\n' < "$state_path"
}

ensure_diagnostic_dataset() {
  diagnostic_state="$state_dir/diagnostic-dataset-id"
  if [ -s "$diagnostic_state" ]; then
    tr -d '\r\n' < "$diagnostic_state"
    return
  fi

  mkdir -p "$state_dir"
  ensured_dataset_id="$(import_dataset \
    "Arabic normalization diagnostic CLI" "$diagnostic_dir")"
  printf '%s' "$ensured_dataset_id" > "$diagnostic_state"
  printf '%s' "$ensured_dataset_id"
}

install_dense_dependencies() {
  if ! python -m pip --version >/dev/null 2>&1; then
    python -m ensurepip --upgrade
  fi
  python -m pip install --quiet 'sentence-transformers>=3.3'
}

action="${1:-}"
case "$action" in
  list)
    run_normalization --root "$normalization_root" list
    ;;
  diagnostic)
    mkdir -p "$state_dir"
    run_normalization options
    diagnostic_dataset_id="$(ensure_diagnostic_dataset)"
    diagnostic_run_json="$(run_normalization --root "$normalization_root" run \
      --dataset "$diagnostic_dataset_id" \
      --retrievers bm25 \
      --presets raw diacritics tatweel alef conservative aggressive \
      --normalization-side both \
      --bootstrap-samples 1000 \
      --seed 42)"
    save_run diagnostic-bm25 "$diagnostic_run_json"
    ;;
  prepare)
    run_normalization prepare-miracl \
      --output "$pilot_dir" \
      --mode pilot \
      --split train \
      --query-limit 100 \
      --distractors 1000 \
      --seed 42 \
      --dataset-revision 5be20db9509754dadad47689368639fcec739c00 \
      --corpus-revision d921ec7e349ce0d28daf30b2da9da5ee698bef0d
    ;;
  run)
    mkdir -p "$state_dir"
    pilot_dataset_id="$(import_dataset \
      "MIRACL Arabic train pilot 100 queries seed 42" "$pilot_dir")"
    printf '%s' "$pilot_dataset_id" > "$state_dir/pilot-dataset-id"
    pilot_run_json="$(run_normalization --root "$normalization_root" run \
      --dataset "$pilot_dataset_id" \
      --retrievers bm25 \
      --presets raw diacritics tatweel alef conservative aggressive \
      --normalization-side both \
      --bootstrap-samples 1000 \
      --seed 42)"
    save_run pilot-bm25 "$pilot_run_json"
    ;;
  dense-diagnostic)
    diagnostic_dataset_id="$(ensure_diagnostic_dataset)"
    install_dense_dependencies
    dense_diagnostic_json="$(run_normalization --root "$normalization_root" run \
      --dataset "$diagnostic_dataset_id" \
      --retrievers dense \
      --presets raw conservative aggressive \
      --normalization-side both \
      --dense-model facebook/mcontriever-msmarco \
      --dense-revision 9ff6abed2c2fdf32bbbd8b4e98fb10160e317375 \
      --dense-max-seq-length 256 \
      --dense-batch-size 32 \
      --bootstrap-samples 1000 \
      --seed 42)"
    save_run diagnostic-dense "$dense_diagnostic_json"
    ;;
  dense-pilot)
    pilot_dataset_id="$(read_state pilot-dataset-id)"
    install_dense_dependencies
    dense_pilot_json="$(run_normalization --root "$normalization_root" run \
      --dataset "$pilot_dataset_id" \
      --retrievers dense \
      --presets raw diacritics tatweel alef conservative aggressive \
      --normalization-side both \
      --dense-model facebook/mcontriever-msmarco \
      --dense-revision 9ff6abed2c2fdf32bbbd8b4e98fb10160e317375 \
      --dense-max-seq-length 256 \
      --dense-batch-size 32 \
      --bootstrap-samples 1000 \
      --seed 42)"
    save_run pilot-dense "$dense_pilot_json"
    ;;
  full-prepare)
    mkdir -p "$state_dir"
    full_query_limit="${2:-}"
    if [ -n "$full_query_limit" ]; then
      case "$full_query_limit" in
        *[!0-9]*|0) echo "query_limit must be a positive integer" >&2; exit 2 ;;
      esac
      full_dir="$experiment_dir/work/miracl-ar-full-dev-q${full_query_limit}-s42"
      full_dataset_name="MIRACL Arabic full corpus dev query sample $full_query_limit seed 42"
      run_normalization prepare-miracl \
        --output "$full_dir" \
        --mode full \
        --split dev \
        --query-limit "$full_query_limit" \
        --seed 42 \
        --dataset-revision 5be20db9509754dadad47689368639fcec739c00 \
        --corpus-revision d921ec7e349ce0d28daf30b2da9da5ee698bef0d
    else
      full_dataset_name="MIRACL Arabic full corpus all dev queries"
      run_normalization prepare-miracl \
        --output "$full_dir" \
        --mode full \
        --split dev \
        --seed 42 \
        --dataset-revision 5be20db9509754dadad47689368639fcec739c00 \
        --corpus-revision d921ec7e349ce0d28daf30b2da9da5ee698bef0d
    fi
    full_dataset_id="$(import_dataset \
      "$full_dataset_name" "$full_dir")"
    printf '%s' "$full_dataset_id" > "$state_dir/full-dataset-id"
    echo "Saved full dataset ID: $full_dataset_id"
    ;;
  full-bm25)
    full_dataset_id="$(read_state full-dataset-id)"
    main_bm25_json="$(run_normalization --root "$normalization_root" run \
      --dataset "$full_dataset_id" \
      --retrievers bm25 \
      --presets raw diacritics tatweel alef conservative aggressive \
      --normalization-side both \
      --bootstrap-samples 10000 \
      --seed 42)"
    save_run main-bm25 "$main_bm25_json"
    ;;
  full-dense)
    full_dataset_id="$(read_state full-dataset-id)"
    install_dense_dependencies
    main_dense_json="$(run_normalization --root "$normalization_root" run \
      --dataset "$full_dataset_id" \
      --retrievers dense \
      --presets raw diacritics tatweel alef conservative aggressive \
      --normalization-side both \
      --bootstrap-samples 10000 \
      --seed 42 \
      --dense-model facebook/mcontriever-msmarco \
      --dense-revision 9ff6abed2c2fdf32bbbd8b4e98fb10160e317375 \
      --dense-max-seq-length 256 \
      --dense-batch-size 32)"
    save_run main-dense "$main_dense_json"
    ;;
  main-analyze)
    main_report_path="$(read_state main-bm25-report-path)"
    python /workspace/infra/scripts/analyze-arabic-normalization.py "$main_report_path"
    ;;
  main-export)
    main_run_id="$(read_state main-bm25-run-id)"
    run_normalization --root "$normalization_root" export \
      --run "$main_run_id" \
      --output "$experiment_dir/work/main-bm25-trec"
    ;;
  *)
    echo "Usage: $0 {list|diagnostic|prepare|run|dense-diagnostic|dense-pilot|full-prepare [query-limit]|full-bm25|full-dense|main-analyze|main-export}" >&2
    exit 2
    ;;
esac
