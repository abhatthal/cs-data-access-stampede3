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
                 is rejected), so it starts an `idev` session; then follow its
                 printed instructions (`module load tacc-apptainer`, then
                 source `lib_ssh_binds.sh` and `apptainer shell`) on the
                 compute node. Exit twice to leave (container, then idev
                 session).

- `lib_ssh_binds.sh` : Shared helper, sourced by both `osp_run.sh` and (per
                 `debug.sh`'s printed instructions) interactively, that
                 computes the `apptainer --bind` flags exposing the host's
                 `ssh`/`scp` client (and any libraries they need that the
                 minimal container image lacks), plus the invoking user's own
                 `~/.ssh` (identity + known_hosts), inside the container,
                 which ships no OpenSSH client of its own.

The final outputs are written into a temporary scratch directory which will     
eventually be purged. 

## Debugging SCP/SSH inside the container

`osp_run.sh` retrieves Stampede3 seismograms via `scp` from
`login2.stampede3.tacc.utexas.edu:/corral/...` (`file_method = scp` in
`tacc.cfg`), run from inside the container using the host's bound-in `ssh`/
`scp` binaries. The production wrapper around `scp` sets `HOME` to the real
invoking user's home (so ssh's default identity/known_hosts lookup finds the
bound-in `~/.ssh`), then passes `-F /dev/null` (no ssh_config ships in the
container anyway), `-o StrictHostKeyChecking=yes` (the bound-in known_hosts
already trusts login2), `-o ConnectTimeout=15` (bounds the initial network
connection), and runs the whole thing under `timeout 60` (bounds the entire
auth + transfer, adjust based on observed seismogram file sizes/transfer
speed once real data is flowing).

**Confirmed** (manual debug session, `qwxdev`, bare compute node): TACC's
login←compute SSH is **not** host-based auth. `ssh -v` shows the server only
ever offers `publickey,keyboard-interactive`; the client's own
`~/.ssh/id_ed25519` is accepted for the publickey step ("partial success"),
then a `keyboard-interactive` round trip completes with **no prompt shown and
no input typed** - TACC auto-satisfies it from a compute node. Both `ssh` and
`scp` of an arbitrary file succeeded this way.

**Also confirmed - and this is why the wrapper no longer uses it**: inside
the container (`lib_ssh_binds.sh`'s binds, `$HOME` pinned to the real value),
`-o BatchMode=yes` breaks this. With it set, the exact same key is still
accepted for the publickey step, but the server then reports "No more
authentication methods to try" and denies the connection
(`Permission denied (keyboard-interactive)`) - `BatchMode=yes` disables the
`keyboard-interactive` method outright, and that's the method TACC's
zero-prompt second factor rides on. `timeout 60` around the whole `scp`
invocation replaces `BatchMode`'s fail-fast role without touching which auth
methods ssh is allowed to attempt.

Not yet directly tested: the same command *inside* the container *without*
`BatchMode=yes` (i.e. exactly what the production wrapper now runs) - worth
one more quick check to close the loop:

```bash
ssh -v login2.stampede3.tacc.utexas.edu 'echo ok'   # inside the container, no BatchMode
```

Remaining verification once the `/corral` ACL grant is confirmed: run the
production wrapper (`$TEMP_DIR/bin/scp`, or just its final `exec` line, e.g.
`timeout 60 scp -F /dev/null -o StrictHostKeyChecking=yes -o ConnectTimeout=15
login2.stampede3.tacc.utexas.edu:/corral/projects/DS-Cybershake/Study_22.12_LF/<a
real file> /tmp/`) against a real `/corral` path from inside the container,
then run `sbatch run.sh` end to end and confirm `./outputs` contains the
expected `Seismogram_*.grm` files with no
`seismogram_transfer_failure.log` written.
