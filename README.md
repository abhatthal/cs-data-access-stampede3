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
container anyway), `-o BatchMode=yes` (fail fast instead of prompting),
`-o StrictHostKeyChecking=yes` (the bound-in known_hosts already trusts
login2), and `-o ConnectTimeout=15`.

**Confirmed** (manual debug session, bare compute node, `qwxdev`): TACC's
login←compute SSH is **not** host-based auth. `ssh -v` shows the server only
ever offers `publickey,keyboard-interactive`; the client's own
`~/.ssh/id_ed25519` is accepted for the publickey step ("partial success"),
then a `keyboard-interactive` round trip completes with **no prompt shown and
no input typed** - TACC auto-satisfies it from the compute node. Both a plain
`ssh` command and an `scp` of an arbitrary file succeeded this way.

The one open question this doesn't yet answer: whether `-o BatchMode=yes`
(which disables interactive querying) also blocks that zero-prompt
`keyboard-interactive` completion, since the production wrapper relies on
`BatchMode=yes` to fail fast rather than hang. Test that specifically, on the
bare compute node (no container needed for this one), via `debug.sh` → `idev`:

```bash
# Already confirmed to work without BatchMode:
ssh -v login2.stampede3.tacc.utexas.edu 'echo ok'

# The open question: does BatchMode=yes still let the keyboard-interactive
# step complete, or does it block the method outright?
ssh -v -o BatchMode=yes login2.stampede3.tacc.utexas.edu 'echo ok'
scp -v -o BatchMode=yes /tmp/probe.txt login2.stampede3.tacc.utexas.edu:/tmp/probe_${USER}.txt
```

- **Succeeds identically**: the wrapper's `BatchMode=yes` is fine as-is.
- **Fails/hangs**: `BatchMode=yes` is blocking `keyboard-interactive` outright.
  Drop it from the wrapper and rely on `-o ConnectTimeout=15` (bounds network
  hangs) plus wrapping the `exec` in `timeout <N>` (bounds an auth hang too,
  since there's no prompt to fail on but the process could still stall) to
  keep the fail-fast behavior `BatchMode=yes` was providing.

Once that's settled, repeat the same commands inside the container (binds
from `debug.sh`'s printed instructions) to confirm the bound-in `~/.ssh` and
pinned `$HOME` reproduce the same result there, then retry the full
production wrapper (`$TEMP_DIR/bin/scp`, or just its `exec` line) directly
against a real `/corral` path once the ACL grant is confirmed.
