#!/bin/bash
# debug.sh - Opens an interactive shell inside the cs_data_tutorial container
#
# Run this script directly from the login node:  ./debug.sh
# Do NOT submit it with sbatch - an interactive session cannot run as a batch
# job. Stampede3 also rejects plain `salloc` for interactive development; the
# supported way is the `idev` command, which requests the allocation and drops
# you into a shell on a compute node.
#
# `apptainer shell` is the Apptainer equivalent of `docker run -it`: it gives
# an interactive session where you can navigate inside the container.
# Type `exit` to leave the container, then `exit` again to end the idev session.

IMAGE="cs_data_tutorial.sif"    # Pulled by get_img.sh (sceccode/cs_data_tutorial)

echo "Requesting interactive session. Once you land on the compute node, run:"
echo "  module load tacc-apptainer"
echo "  apptainer shell $IMAGE"

idev \
    -A TG-EES230082 \
    -p skx-dev \
    -N 1 \
    -n 1 \
    -t 00:30:00