# CyberShake Data Access Tool - Quakeworx App                                      
                                                                                
https://github.com/SCECcode/cs-data-tools                                          
                                                                                   
Quakeworx batch application provides a form UI for executing the CyberShake     
Data Access Tool via a shell script wrapper to a Singularity container.         
                                                                                
Run `sbatch get_img.sh` once manually, Quakeworx jobs invoke `run.sh`.          
                                                                                   
- `get_img.sh` : Retrieves the `sceccode/cs_data_tutorial` Docker image and     
                 resolves a Singularity Image Format (SIF) file.                   
                                                                                   
- `osp_run.sh` : Parses and sanitizes Quakeworx input parameters and runs the tool 
                 via singularity in a single compute node.                         
                                                                                
- `run.sh` :     Hardcoded user input to validate workflow                      
                                                                                
- `debug.sh` :   Opens an interactive shell inside the container. Run it
                 directly from the login node (`./debug.sh`, do not `sbatch`) —
                 it requests a Slurm allocation via `salloc` and drops you into
                 `apptainer shell cs_data_tutorial.sif` on a compute node.
                 Exit twice to leave (container, then allocation).                
                                                                                
The final outputs are written into a temporary scratch directory which will     
eventually be purged. 
