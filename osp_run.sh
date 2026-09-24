#!/bin/bash
# osp_run.sh - Script executed by Quakeworx app, processes user input and runs app

# Tapis/Quakeworx provides the job environment; tolerate local testing without it.
if [ -f ./tapisjob.env ]; then
    source ./tapisjob.env
fi

# Package is called `tacc-apptainer` on TACC systems (compute nodes only).
module load tacc-apptainer

# Fail the job if any stage fails (input_gen or retrieve_cs_data).
set -euo pipefail

# --- Parse and sanitize the Quakeworx parameters ---------------------------
# The form emits every template field, even empty ones, repeats flags, and
# splits multi-word values by unquoted spaces ("Study 24.8 BB" arrives as
# three separate arguments). Rebuild a clean input_gen argument set here:
# join split values back together, drop empty-valued flags, and keep the
# last non-empty value for repeated flags.

MODEL=""
PRODUCT=""
EVENT_FILE=""
SORT_BY=""
SORT_ORDER=""
FILTER_ARGS=()    # "NAME=VALUE" entries; a non-empty value replaces an earlier one

is_known_flag() {
    case "$1" in
        -m|--model|-p|--product|-e|--input-event-filename|\
        --filter|--sort-by|--sort-order|--)
            return 0 ;;
        *)  return 1 ;;
    esac
}

# Split any combined "--flag=value" into two tokens so the main loop sees
# flags and values uniformly (only leading known flags are split, so filter
# values containing '=' pass through untouched).
PREP=()
for a in "$@"; do
    case "$a" in
        --filter=*|--model=*|--product=*|--sort-by=*|--sort-order=*|\
        --input-event-filename=*|-e=*)
            PREP+=("${a%%=*}" "${a#*=}") ;;
        *)
            PREP+=("$a") ;;
    esac
done
set -- "${PREP[@]}"

add_filter() {
    fv="$1"
    name="${fv%%=*}"
    k=0
    if [ ${#FILTER_ARGS[@]} -gt 0 ]; then
        for existing in "${FILTER_ARGS[@]}"; do
            if [ "${existing%%=*}" = "$name" ]; then
                FILTER_ARGS[$k]="$fv"
                return
            fi
            k=$((k + 1))
        done
    fi
    FILTER_ARGS+=("$fv")
}

while [ $# -gt 0 ]; do
    flag="$1"
    shift
    # Join consecutive non-flag tokens: recovers values the form left unquoted
    val=""
    while [ $# -gt 0 ] && ! is_known_flag "$1"; do
        val="${val:+$val }$1"
        shift
    done
    case "$flag" in
        -m|--model)
            if [ -n "$val" ]; then MODEL="$val"; fi ;;
        -p|--product)
            if [ -n "$val" ]; then PRODUCT="$val"; fi ;;
        -e|--input-event-filename)
            if [ -n "$val" ]; then EVENT_FILE="$val"; fi ;;
        --sort-by)
            if [ -n "$val" ]; then SORT_BY="$val"; fi ;;
        --sort-order)
            if [ -n "$val" ]; then SORT_ORDER="$val"; fi ;;
        --filter)
            # Only keep NAME=VALUE with a non-empty value; empty filters are
            # the form's unused template fields.
            case "$val" in
                *=*)
                    if [ -n "${val#*=}" ]; then add_filter "$val"; fi ;;
            esac ;;
        -)
            ;;  # literal '-' argument, ignore
        *)
            ;;  # unexpected bare token; skip
    esac
done

FORWARDED=()
if [ -n "$MODEL" ]; then FORWARDED+=(--model "$MODEL"); fi
if [ -n "$PRODUCT" ]; then FORWARDED+=(--product "$PRODUCT"); fi
if [ ${#FILTER_ARGS[@]} -gt 0 ]; then
    for f in "${FILTER_ARGS[@]}"; do
        FORWARDED+=(--filter "$f")
    done
fi
if [ -n "$EVENT_FILE" ]; then FORWARDED+=(-e "$EVENT_FILE"); fi
if [ -n "$SORT_BY" ]; then FORWARDED+=(--sort-by "$SORT_BY"); fi
if [ -n "$SORT_ORDER" ]; then FORWARDED+=(--sort-order "$SORT_ORDER"); fi
# ------------------------------------------------------------------------------

echo "Running request with parameters: ${FORWARDED[*]:-}"

IMAGE="/work2/11814/qwxdev/stampede3/qwxdev/apps/stampede3/rocky9.7/cs-data-access/cs_data_tutorial.sif"
CONTAINER_HOME="/home/cs_data_user"
OUTPUT_DIR="./outputs"                          # persistent results (job dir)
# Node-local scratch for the job, purged at job end (TACC sets $TMPDIR per job).
# Overridable via the environment, e.g. for local testing without a SLURM allocation.
TEMP_DIR="${TEMP_DIR:-${TMPDIR:-$SCRATCH}/tmp}"

mkdir -p "$OUTPUT_DIR" "$TEMP_DIR"

# Output/temp paths are bind-mounted into the container (the image FS is
# read-only under singularity); the bind target is named "outputs" to match
# the host directory name.
HOST_BINDS="--bind $PWD/$OUTPUT_DIR:$CONTAINER_HOME/outputs --bind $TEMP_DIR:$CONTAINER_HOME/tmp"

# The event file (-e) lives in the job directory, but the pipeline runs from
# the container home, so a relative -e path would not resolve. Bind the file
# into the container home and rewrite the -e argument to its container path.
if [ -n "$EVENT_FILE" ]; then
    case "$EVENT_FILE" in
        /*) HOST_EVENT="$EVENT_FILE" ;;
        *)  HOST_EVENT="$PWD/$EVENT_FILE" ;;
    esac
    if [ ! -f "$HOST_EVENT" ]; then
        echo "ERROR: event file not found: $HOST_EVENT" >&2
        exit 1
    fi
    EVENT_CONTAINER_PATH="$CONTAINER_HOME/$(basename "$EVENT_FILE")"
    HOST_BINDS="$HOST_BINDS --bind $HOST_EVENT:$EVENT_CONTAINER_PATH"
    idx=0
    for i in "${!FORWARDED[@]}"; do
        if [ "${FORWARDED[$i]}" = "-e" ]; then
            FORWARDED[$((idx + 1))]="$EVENT_CONTAINER_PATH"
        fi
        idx=$((idx + 1))
    done
fi

# Quote each sanitized argument with printf %q so values with spaces survive
# the nested bash -c inside the container.
INPUT_GEN_ARGS=$(printf '%q ' "${FORWARDED[@]:-}")

# Single container: the pipe between input_gen and retrieve_cs_data lives inside
# the one invocation. The nested bash -c needs its own pipefail (the outer
# 'set -euo pipefail' does not propagate into it); input_gen writes the request
# JSON to stdout (summary to stderr) and retrieve_cs_data reads it from stdin
# via '-i -', per the cs-data-tools docs.
#
# The pipeline runs from the temp bind, not the container home: the image FS is
# read-only under singularity, and the scp-based seismogram download writes its
# file_transfer.log relative to the cwd (src/data_collector/run_data_collector.py),
# which would fail with EROFS. Scripts and config are referenced by absolute
# path so the cwd change doesn't break imports or the -c lookup. All other
# stages take absolute -o/-t paths, so nothing else depends on the cwd.
apptainer exec $HOST_BINDS "$IMAGE" bash -c "set -o pipefail; cd $CONTAINER_HOME/tmp && python3 $CONTAINER_HOME/cs-data-tools/src/input_gen/run_input_gen.py $INPUT_GEN_ARGS | python3 $CONTAINER_HOME/cs-data-tools/src/retrieve_cs_data.py -i - -o $CONTAINER_HOME/outputs -t $CONTAINER_HOME/tmp -c $CONTAINER_HOME/cs-data-tools/src/db_wrapper/tacc.cfg"

echo "Done. Results are in $OUTPUT_DIR"
