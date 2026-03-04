# Security Hardening TODO

Findings from container escape analysis (2026-03-04).

> **Note:** VS Code IPC escape vectors are not applicable when running via `docker run` (standalone mode). These items focus on remaining attack surface.

## High Priority

- [ ] Add custom seccomp profile restricting dangerous syscalls (`mount`, `ptrace`, `unshare`, `clone` with `CLONE_NEWUSER`/`CLONE_NEWNET`)
- [ ] Verify `chattr +i` success and hard-fail if unsupported (overlay2 often doesn't support extended attributes)
- [ ] Drop `NET_ADMIN`/`NET_RAW` capabilities after firewall init completes (only needed during setup)

## Medium Priority

- [ ] Add `--read-only` rootfs with tmpfs for `/tmp`
- [ ] Mount `/proc` and `/sys` as read-only
- [ ] Add `--security-opt=no-new-privileges` to prevent privilege escalation

## Low Priority

- [ ] Periodically re-resolve allowlisted domain IPs (currently point-in-time at startup)
- [ ] Consider AppArmor profile for additional confinement

## Not Applicable (Standalone Mode)

The following are mitigated by running outside VS Code Dev Containers:

- VS Code IPC socket escape (no sockets created)
- Race window on attach (no attach phase)
- `remoteEnv` variable injection (no VS Code server)
