#!/bin/sh
python3 -I - <<'XVEND_SETUP_PY'
#!/usr/bin/env python3
"""Generated private device-login launcher. Run as the normal setup user.

The builder replaces PIN with reviewed repo/tag/asset/SHA256 values.
Requires Ubuntu tools gh, ca-certificates, sudo, mount, umount, findmnt.
It refuses active swap and configured hibernation before any login.
"""
import os
from pathlib import Path
import resource
import shutil
import signal
import subprocess
import tempfile

PIN = ('WonderMakr/wonderwall-vending-prototype', 'setup-2026.10.05.2', 'xvend-setup.tar.gz', 'd67822109b87ee6cc5826ad21d6e83688931fa5985a10140845e0989d391db53')
ROOT_HANDOFF = '"""Reviewed root handoff, embedded by the builder in the pinned launcher.\n\nNever import or execute a user-owned file. Check a protected archive copy first.\n"""\nimport hashlib\nimport json\nimport os\nfrom pathlib import Path, PurePosixPath\nimport re\nimport shutil\nimport subprocess\nimport sys\nimport tarfile\nimport tempfile\n\n\ndef unique_object(pairs):\n    result = {}\n    for key, value in pairs:\n        if key in result:\n            raise ValueError("duplicate JSON field")\n        result[key] = value\n    return result\n\n\ndef safe_name(name):\n    return (bool(name) and "\\\\" not in name and ":" not in name and\n            "\\0" not in name and not PurePosixPath(name).is_absolute() and\n            all(part not in ("", ".", "..") for part in name.split("/")))\n\n\ndef handoff(archive, digest):\n    if os.geteuid() != 0:\n        raise ValueError("root staging requires sudo")\n    os.umask(0o077)\n    with tempfile.TemporaryDirectory(prefix="xvend-root-", dir="/var/tmp") as temporary:\n        root = Path(temporary)\n        # mkdtemp creates mode 0700 with this process as owner.\n        # Copy once, then check and use only this private copy.\n        protected = root / "setup.tar.gz"\n        with Path(archive).open("rb") as source, protected.open("xb") as target:\n            shutil.copyfileobj(source, target)\n        if hashlib.sha256(protected.read_bytes()).hexdigest() != digest:\n            raise ValueError("archive hash failed at root handoff; get the approved launcher and retry")\n        bundle = root / "bundle"\n        bundle.mkdir(mode=0o700)\n        with tarfile.open(protected, "r:gz") as tar:\n            members = tar.getmembers()\n            names = [member.name for member in members]\n            if len(names) != len(set(names)) or any(\n                    not safe_name(member.name) or not member.isfile() for member in members):\n                raise ValueError("unsafe archive paths or links; get a new approved bundle")\n            descriptor = json.load(tar.extractfile("bundle.json"), object_pairs_hook=unique_object)\n            if descriptor.get("format") != 1 or not isinstance(descriptor.get("files"), dict):\n                raise ValueError("unknown bundle format; get a new approved bundle")\n            if set(descriptor["files"]) != set(names) - {"bundle.json"}:\n                raise ValueError("bundle coverage failed; get a new approved bundle")\n            for member in members:\n                data = tar.extractfile(member).read()\n                if member.name != "bundle.json" and hashlib.sha256(data).hexdigest() != descriptor["files"][member.name]:\n                    raise ValueError("bundle file hash failed; get a new approved bundle")\n                if re.search(br"(?m)^-----BEGIN [A-Z ]*PRIVATE KEY-----\\r?$", data):\n                    raise ValueError("private key in bundle; ask the operator for a public-key-only bundle")\n            for member in members:\n                path = bundle / member.name\n                path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)\n                with path.open("xb") as target:\n                    target.write(tar.extractfile(member).read())\n                path.chmod(0o600)\n        with open("/dev/tty", "r") as terminal:\n            subprocess.run([sys.executable, "-I", str(bundle / "deploy/machine/setup.py"),\n                            "--bundle", str(bundle)], stdin=terminal, check=True,\n                           env={"PATH": "/usr/sbin:/usr/bin:/sbin:/bin", "LANG": "C.UTF-8"})\n\n\nif __name__ == "__main__":\n    try:\n        handoff(sys.argv[1], sys.argv[2])\n    except ValueError as error:\n        print("Setup stopped: " + str(error))\n        raise SystemExit(1)\n    except (OSError, KeyError, tarfile.TarError, subprocess.SubprocessError):\n        print("Root setup failed. Check disk space and the approved bundle. Retry setup.")\n        raise SystemExit(1)\n'


def run(command, **kwargs):
    kwargs.setdefault("env", {"PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                              "LANG": "C.UTF-8"})
    if command[:3] == ["gh", "auth", "login"]:
        cause = "GitHub sign-in failed. Check the code and repo access, then retry setup."
    elif command[:3] == ["gh", "release", "download"]:
        cause = "Bundle download failed. Check network and private repo access, then retry setup."
    elif command[:2] == ["sudo", "mount"]:
        cause = "The login memory mount failed. Check sudo access and noswap support, then retry setup."
    elif command[:2] == ["sudo", "umount"]:
        cause = "Login mount cleanup failed. Setup did not start. Reboot to clear the memory mount, then retry setup."
    elif command[:2] == ["sudo", "apt-get"]:
        cause = "Ubuntu tool install failed. Check network and package sources, then retry setup."
    else:
        cause = "Root setup failed. Check the cause above, then retry the approved launcher."
    try:
        subprocess.run(command, check=True, **kwargs)
    except (OSError, subprocess.CalledProcessError) as error:
        raise ValueError(cause) from error


def stop_signal(signum, frame):
    raise KeyboardInterrupt


def main():
    if PIN is None:
        raise ValueError("use a generated pinned launcher")
    if os.geteuid() == 0:
        raise ValueError("run as the setup user, without sudo")
    os.umask(0o077)
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    if len(Path("/proc/swaps").read_text().splitlines()) != 1:
        raise ValueError("Swap is active. It can save login data to disk. Run sudo swapoff -a, then retry setup. Ask the operator to keep swap off for this login.")
    # Raspberry Pi kernels have no hibernation, so no resume file: nothing to refuse.
    resume = Path("/sys/power/resume")
    if resume.exists() and resume.read_text().strip() != "0:0":
        raise ValueError("A hibernation resume device is set. It can save login data to disk. Ask the operator to remove the resume setting, reboot, then retry setup.")
    if shutil.which("gh") is None or not Path("/etc/ssl/certs/ca-certificates.crt").is_file():
        run(["sudo", "apt-get", "update"])
        run(["sudo", "apt-get", "install", "-y", "gh", "ca-certificates"])
    for signum in (signal.SIGINT, signal.SIGHUP, signal.SIGTERM):
        signal.signal(signum, stop_signal)
    repo, tag, asset, digest = PIN
    with tempfile.TemporaryDirectory(prefix="xvend-setup-") as scratch:
        root = Path(scratch)
        credentials = root / "credentials"
        credentials.mkdir(mode=0o700)
        mounted = False
        try:
            run(["sudo", "mount", "-t", "tmpfs", "-o",
                 "noswap,nodev,nosuid,noexec,mode=0700,uid=" + str(os.getuid()) +
                 ",gid=" + str(os.getgid()) + ",size=16m", "tmpfs", str(credentials)])
            mounted = True
            try:
                options = subprocess.check_output(
                    ["findmnt", "-n", "-T", str(credentials), "-o", "FSTYPE,OPTIONS"],
                    text=True, env={"PATH": os.environ.get("PATH", "/usr/bin:/bin")})
            except (OSError, subprocess.CalledProcessError) as error:
                raise ValueError("The login memory mount could not be checked. Check findmnt and sudo access, then retry setup.") from error
            words = options.strip().split()
            if len(words) != 2 or words[0] != "tmpfs" or "noswap" not in words[1].split(","):
                raise ValueError("The login memory mount failed its noswap check. Use the approved Ubuntu image with noswap support, then retry setup.")
            env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                   "HOME": str(credentials / "home"),
                   "GH_CONFIG_DIR": str(credentials / "gh"),
                   "XDG_CONFIG_HOME": str(credentials / "config"),
                   "XDG_CACHE_HOME": str(credentials / "cache"),
                   "XDG_DATA_HOME": str(credentials / "data"),
                   "TMPDIR": str(credentials / "tmp"),
                   "GH_PROMPT_DISABLED": "1", "GH_NO_UPDATE_NOTIFIER": "1",
                   "GH_NO_EXTENSION_UPDATE_NOTIFIER": "1",
                   "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
                   "BROWSER": "/bin/true", "LANG": "C.UTF-8"}
            for name in ("HOME", "GH_CONFIG_DIR", "XDG_CONFIG_HOME", "XDG_CACHE_HOME",
                         "XDG_DATA_HOME", "TMPDIR"):
                Path(env[name]).mkdir(mode=0o700)
            # subprocess.run waits for a killed child before cleanup on interruption.
            run(["gh", "auth", "login", "--hostname", "github.com",
                 "--git-protocol", "https", "--web", "--insecure-storage"], env=env)
            run(["gh", "release", "download", tag, "--repo", repo, "--pattern", asset,
                 "--dir", str(root)], env=env)
        finally:
            if mounted:
                # Remove all files while the nonpersistent mount remains in place.
                for path in credentials.iterdir():
                    if path.is_dir() and not path.is_symlink():
                        shutil.rmtree(path)
                    else:
                        path.unlink()
                run(["sudo", "umount", str(credentials)])
            credentials.rmdir()
        if credentials.exists():
            raise ValueError("credential cleanup did not finish")
        if ROOT_HANDOFF is None:
            raise ValueError("The reviewed root handoff is missing. Get the approved launcher.")
        # Only the reviewed embedded code enters root. Root copies, pins, and
        # extracts the archive into its own protected tree before source runs.
        run(["sudo", "/usr/bin/python3", "-I", "-c", ROOT_HANDOFF, str(root / asset), digest])


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        print("Setup stopped: " + str(error))
        raise SystemExit(1)
    except KeyboardInterrupt:
        print("Setup cancelled. Login files were cleared if cleanup completed. Retry setup when ready.")
        raise SystemExit(1)
    except OSError as error:
        # Name the cause from the error's type, reason and path only:
        # never echo command arguments or login values.
        cause = type(error).__name__ + ": " + (error.strerror or "no reason given")
        if error.filename is not None:
            cause += ": " + str(error.filename)
        print("Setup tool failed. " + cause + ". Retry the approved launcher after fixing it.")
        raise SystemExit(1)
    except subprocess.SubprocessError as error:
        print("Setup tool failed. " + type(error).__name__ + ". Check network access and sudo access. Retry the approved launcher.")
        raise SystemExit(1)

XVEND_SETUP_PY
