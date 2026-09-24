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
                 minimal container image lacks) inside the container, which
                 ships no OpenSSH client of its own.

The final outputs are written into a temporary scratch directory which will     
eventually be purged. 

## Debugging SCP/SSH inside the container

`osp_run.sh` retrieves Stampede3 seismograms via `scp` from
`login2.stampede3.tacc.utexas.edu:/corral/...` (`file_method = scp` in
`tacc.cfg`), run from inside the container using the host's bound-in `ssh`/
`scp` binaries. The production wrapper around `scp` passes `-F /dev/null`
(skip system ssh config), `-o BatchMode=yes` (fail fast instead of prompting),
`-o StrictHostKeyChecking=accept-new`, `-o UserKnownHostsFile=<temp
bind>/known_hosts`, and `-o ConnectTimeout=15`.

Before relying on this in a batch job, confirm which SSH auth method TACC
actually negotiates for a login→compute hop, and that the wrapper's flags
don't break it — in particular, `-F /dev/null` makes ssh ignore
`/etc/ssh/ssh_config` entirely, which may be where TACC enables
`HostbasedAuthentication`. Run this via `debug.sh` → `idev`, using a file you
already have legitimate access to (sidesteps any `/corral` ACL issue):

```bash
# 0. Baseline, bare compute node, no container.
ssh -v login2.stampede3.tacc.utexas.edu 'echo host-ssh-ok'
# Look for "Authentication succeeded (hostbased|publickey|gssapi-...)."

echo hello > /tmp/probe.txt
scp -v /tmp/probe.txt login2.stampede3.tacc.utexas.edu:/tmp/probe_${USER}.txt

# 1. Enter the container with the real production binds (debug.sh prints the
#    exact command - it sources lib_ssh_binds.sh).
module load tacc-apptainer
source lib_ssh_binds.sh && SSH_BINDS=$(ssh_binds cs_data_tutorial.sif)
apptainer shell $SSH_BINDS cs_data_tutorial.sif

# --- inside the container ---
echo "HOME=$HOME"; id; which ssh scp; ldd "$(which scp)"

# 2. Raw ssh/scp (host binaries + host /etc/ssh, no wrapper flags) - should
#    match step 0's auth method.
ssh -v login2.stampede3.tacc.utexas.edu 'echo container-ssh-ok'

# 3. Reproduce the production wrapper's exact flags - the real test.
ssh -v -F /dev/null -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
    login2.stampede3.tacc.utexas.edu 'echo wrapper-flags-ok'

scp -F /dev/null -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
    login2.stampede3.tacc.utexas.edu:/tmp/probe_${USER}.txt /tmp/probe_back.txt
cat /tmp/probe_back.txt
```

If step 3 fails or prompts where step 2 succeeded, `-F /dev/null` is
defeating the auth method step 0/2 rely on:

- **hostbased succeeded, then broke in step 3**: don't discard system config
  wholesale. Write a minimal container-writable config into `$TEMP_DIR`
  (avoids the "Bad owner or permissions" check, which is about file
  ownership/mode, not content) containing just the load-bearing directives
  from the host's `/etc/ssh/ssh_config` (`HostbasedAuthentication yes`,
  `EnableSSHKeysign yes`, any GSSAPI settings), and point `-F` at that file.
  Host-based auth also needs the `ssh-keysign` helper
  (`/usr/lib/openssh/ssh-keysign` or `/usr/libexec/openssh/ssh-keysign`)
  bound into the container - it isn't currently.
- **publickey succeeded**: the passwordless hop likely rides the user's own
  `~/.ssh` on the shared home filesystem, not host-based auth - bind the real
  host `$HOME/.ssh` into the container instead of `/etc/ssh` (note the
  container's `$HOME` is currently fixed to the image's baked-in
  `/home/cs_data_user`, so confirm/fix that too).
- **step 3 matches step 2**: no regression; the current wrapper is fine.
