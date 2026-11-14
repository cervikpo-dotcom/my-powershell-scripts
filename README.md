# my-powershell-scripts

A personal collection of PowerShell scripts I have written and saved over time. Whenever I need to automate something on Windows or get tired of doing a task manually, I throw a script together and drop it here so I do not lose it.

## Disclaimer

These scripts are tailored to my local environment and come with no guarantees. Test them before running them on anything important.

## Running Scripts

Downloaded scripts are blocked by default on Windows. To run a script in windows system's security you must run this code in powershell:

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass
```

**Note:** If you choose to bypass the policy **make sure to switch it back** (e.g., to `RemoteSigned` or `Restricted`) once you are done.
