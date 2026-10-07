# xVend setup

Start xVend setup on a fresh Ubuntu Server 24.04 machine.

Run this one command in the Ubuntu terminal as your normal user:

```sh
curl -fsS https://raw.githubusercontent.com/WonderMakr/xVend-setup/main/xvend-setup.sh -o ~/xvend-setup.sh && sh ~/xvend-setup.sh
```

The script shows a GitHub sign-in code.
Use an approved account with access to the private xVend project.
Public access to this script does not grant access to the installer.

Setup asks for the Machine name, Fleet address, Tech PIN and Staff PIN.
Use Up and Down to select the Machine type. Press Enter to confirm.
It installs the selected Core and its default settings.
Local setup can finish before Fleet approval.
A Fleet admin matches the Machine name, type and code on the Machines page.

Current installer: `setup-2026.10.07.1`.
Its exact archive hash is pinned in the script.
The installer and signed Core packages stay in the private project.

The script checks swap and the login memory store before GitHub sign-in.
If a check fails, follow its message and run the same command again.
A retry keeps the saved setup settings.

Fresh Raspberry Pi arm64 installation still needs proof.
Keep motor power off during setup.
Complete hardware checks before live use.
