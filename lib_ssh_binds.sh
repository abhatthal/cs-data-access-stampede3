#!/bin/bash
# lib_ssh_binds.sh - Compute apptainer --bind flags that expose the host's
# ssh client (scp, ssh) and the invoking user's own SSH trust material inside
# the container image, which ships no OpenSSH client. Sourced by osp_run.sh
# (production) and, per debug.sh's printed instructions, interactively on the
# compute node - both build the container's SSH environment identically, so
# manual testing via debug.sh is representative of what a batch job runs.
#
# Confirmed via manual debug session (see README.md's SSH/SCP diagnostic
# recipe): TACC's login<->compute passwordless SSH is NOT host-based auth -
# it's the invoking user's own key under ~/.ssh plus a keyboard-interactive
# step TACC auto-satisfies with no prompt. So the container needs the user's
# real ~/.ssh (ssh_home_binds), not /etc/ssh.
#
# Usage: source lib_ssh_binds.sh
#        SSH_BINDS=$(ssh_binds "$IMAGE")       # host scp/ssh binaries + libs
#        SSH_HOME_BINDS=$(ssh_home_binds)      # host ~/.ssh (identity, known_hosts)
# Each echoes bind flags to stdout (empty string if not applicable).

ssh_binds() {
    local image="$1"
    local host_scp host_ssh libdir libs missing name src
    host_scp=$(command -v scp || true)
    host_ssh=$(command -v ssh || true)
    if [ -z "$host_scp" ] || [ -z "$host_ssh" ]; then
        return 0
    fi

    local binds="--bind $host_scp:/usr/bin/scp --bind $host_ssh:/usr/bin/ssh"

    # The host client binaries may need libraries the minimal container image
    # lacks (observed: libcrypt.so.2). The image's library layout may differ
    # from the host's (Debian-style images use /lib/x86_64-linux-gnu, EL-style
    # /lib64), so first find the directory the container's own loader uses
    # (the one holding libc), then check each library scp/ssh link against by
    # basename and bind the missing ones into that directory. Checking by
    # basename keeps glibc core libs (which the container has) unshadowed.
    libdir=$(apptainer exec "$image" bash -c 'for d in /lib/x86_64-linux-gnu /usr/lib/x86_64-linux-gnu /lib64 /usr/lib64; do if [ -e "$d/libc.so.6" ]; then echo "$d"; exit; fi; done')
    libs=$(ldd "$host_scp" "$host_ssh" 2>/dev/null | awk '$3 ~ /^\// {print $3}' | sort -u)
    missing=$(apptainer exec "$image" bash -c 'libdir=$1; shift; for f in "$@"; do [ -e "$libdir/$(basename "$f")" ] || basename "$f"; done' _ "$libdir" $libs | sort -u) || true
    for name in $missing; do
        src=$(echo "$libs" | grep "/$name\$")
        echo "Binding missing library into container: $src -> $libdir/$name" >&2
        binds="$binds --bind $src:$libdir/$name"
    done

    echo "$binds"
}

ssh_home_binds() {
    # Bind only ~/.ssh (not the whole home dir) read-only, at the identical
    # host path, so ssh's normal identity/known_hosts lookup finds it as long
    # as $HOME is also pointed at this same path when ssh actually runs (the
    # scp wrapper in osp_run.sh does this with `export HOME=...`, baked in at
    # generation time on the host, where $HOME already resolves correctly).
    if [ -d "$HOME/.ssh" ]; then
        echo "--bind $HOME/.ssh:$HOME/.ssh"
    fi
}
