#!/bin/bash
# run.sh - Hardcoded input variables for testing the workflow

#SBATCH -J cs_data_access      # Job name
#SBATCH -o job_out_%j.txt      # Name of stdout output file (%j expands to JobID)
#SBATCH -e job_err_%j.txt      # Name of stderr error file
#SBATCH -p skx-dev             # Queue (partition) name; 2 hour max
#SBATCH -N 1                   # Total # of nodes (must be 1 for serial)
#SBATCH -n 1                   # Total # of mpi tasks (should be 1 for serial)
#SBATCH -t 00:30:00            # Run time (hh:mm:ss)
#SBATCH -A TG-EES230082        # Allocation name

# Stampede3 SKX nodes: 48 cores/node, charged per node-hour, so a partial-node
# request (-c N) schedules the same full node without using the rest. If more
# parallelism is ever needed, set OMP_NUM_THREADS (1 thread/core; max 48).

# osp_run.sh loads apptainer itself and forwards our arguments verbatim to
# the container pipeline (input_gen -> retrieve_cs_data), writing to ./outputs.
./osp_run.sh -m "Study 22.12 LF" -p "Site Info" --filter SITE_NAME=USC