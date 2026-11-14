# my-powershell-scripts

A personal collection of PowerShell scripts I have written and saved over time. Whenever I need to automate something on Windows or get tired of doing a task manually, I throw a script together and drop it here so I do not lose it.

Everything is written for my own setup, so **read through the code and adjust any paths or variables** before running anything on your machine.

## Disclaimer

These scripts are tailored to my local environment and come with no guarantees. Test them before running them on anything important.

## Running Scripts

Downloaded scripts are blocked by default on Windows. To run a script in your current terminal session without permanently lowering your system's security, use the `Process` scope:

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
Note: If you choose to bypass the policy at the CurrentUser or LocalMachine level instead, make sure to switch it back (e.g., to RemoteSigned or Restricted) once you are done running the script.
