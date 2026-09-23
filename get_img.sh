#!/bin/bash                                                                        
# get-img.sh - Gets the sceccode/cs_data_tutorial Docker image as an SIF           
                                                                                   
#SBATCH -J get_cs_data_img     # Job name
#SBATCH -o job_out_%j.txt      # Name of stdout output file (%j expands to JobID)
#SBATCH -e job_err_%j.txt      # Name of stderr error file
#SBATCH -p skx-dev             # Queue (partition) name; 2 hour max
#SBATCH -N 1                   # Total # of nodes (must be 1 for serial)
#SBATCH -n 1                   # Total # of mpi tasks (should be 1 for serial)
#SBATCH -t 00:30:00            # Run time (hh:mm:ss)
#SBATCH -A TG-EES230082        # Allocation name

# Package is called `tacc-apptainer` on TACC systems (compute nodes only).
module load tacc-apptainer

# Download and convert the Docker image into a Singularity file (.sif)
apptainer pull cs_data_tutorial.sif docker://sceccode/cs_data_tutorial  
