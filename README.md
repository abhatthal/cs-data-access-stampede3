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
                 Stampede3 requires `idev` for interactive sessions (`salloc`
                 is rejected), so it starts an `idev` session; then run
                 `module load tacc-apptainer` and
                 `apptainer shell cs_data_tutorial.sif` on the compute node.
                 Exit twice to leave (container, then idev session).                
                                                                                
The final outputs are written into a temporary scratch directory which will     
eventually be purged. 
