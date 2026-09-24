#!/bin/bash
# lib_ssh_binds.sh - Compute apptainer --bind flags that expose the host's
# ssh client (scp, ssh) inside the container image, which ships no OpenSSH
# client. Sourced by osp_run.sh (production) and, per debug.sh's printed
# instructions, interactively on the compute node - both build the
# container's SSH environment identically, so manual testing via debug.sh is
# representative of what a batch job actually runs.
#
# Usage: source lib_ssh_binds.sh; SSH_BINDS=$(ssh_binds "$IMAGE")
# Echoes bind flags to stdout (empty string if the host has no ssh/scp).

ssh_binds() {
    local image="$1"
    local host_scp host_ssh libdir libs missing name src
    host_scp=$(command -v scp || true)
    host_ssh=$(command -v ssh || true)
    if [ -z "$host_scp" ] || [ -z "$host_ssh" ]; then
        return 0
    fi

    local binds="--bind /etc/ssh:/etc/ssh --bind $host_scp:/usr/bin/scp --bind $host_ssh:/usr/bin/ssh"

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
