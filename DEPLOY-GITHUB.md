# IT Tools - GitHub hosting (gets past the FortiGate web filter)

Your FortiGate blocks `snapsbilling.com` as an **Unrated** site. GitHub is an
already-rated domain, so hosting `Tools.bat` there slips past the web filter.
Access is protected by a **password built into Tools.bat** (hashed), instead of
the PHP gate on your own server.

---

## 1. Set the password inside Tools.bat

1. Get the SHA-256 hash of the password you want (run once on any PC):

   ```powershell
   powershell -NoProfile -Command "[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes('YOUR-PASSWORD'))).Replace('-','')"
   ```

2. Open `Tools.bat`, find this line near the top:

   ```
   set "PWHASH="
   ```

   Paste the hash between the quotes, e.g.:

   ```
   set "PWHASH=ECD71870D1963316A97E3AC3408C9835AD8CF0F3C1BC703527C30265534F75AE"
   ```

   Leave it empty for no password. The password is asked once per run; tools you
   open from the window do not ask again.

---

## 2. Put Tools.bat on GitHub   (repo: aneesmug/DiagnosticTools)

> The repo MUST be **Public**. `raw.githubusercontent.com` cannot be downloaded
> by `irm` from a private repo, so a private repo breaks this.
> Make it public: repo -> Settings -> General -> Danger Zone -> "Change visibility" -> Public.

**Option A - web upload (no git needed):**
1. Open https://github.com/aneesmug/DiagnosticTools
2. "Add file" -> "Upload files" -> drag in `Tools.bat` -> "Commit changes".
3. Re-upload the same way whenever you update it.

**Option B - git (from a folder that has ONLY Tools.bat, NOT your web files):**
```powershell
mkdir $env:USERPROFILE\DiagnosticTools; cd $env:USERPROFILE\DiagnosticTools
git init
copy "D:\xampp\htdocs\almutlak\TroubleshooteTools\Tools.bat" .
git add Tools.bat
git commit -m "IT Tools"
git branch -M main
git remote add origin https://github.com/aneesmug/DiagnosticTools.git
git push -u origin main
```
> Do NOT push `config.php` / `index.php` - keep those on your server only.

Your raw URL (default branch `main`):
```
https://raw.githubusercontent.com/aneesmug/DiagnosticTools/main/Tools.bat
```

---

## 3. The command techs run

```powershell
$u='https://raw.githubusercontent.com/aneesmug/DiagnosticTools/main/Tools.bat'; $f="$env:TEMP\ITTools.bat"; irm $u -OutFile $f; Start-Process $f -Verb RunAs
```

- Downloads the file to disk and runs it elevated (one UAC prompt).
- Downloading a `.bat` to disk trips IPS far less than `irm ... | iex`.
- The password prompt appears, then the tool opens.

Tip: save that line as a desktop shortcut or a small `Run-ITTools.cmd` so techs
don't type it.

---

## Updating

- Push the new `Tools.bat` to the repo. `raw.githubusercontent.com` caches for a
  few minutes, so allow ~5 min, or use the jsDelivr CDN which you can purge:

  ```
  https://cdn.jsdelivr.net/gh/aneesmug/DiagnosticTools@main/Tools.bat
  ```

## Notes

- Your own server copy (`index.php` + `config.php` password gate) still works on
  networks where `snapsbilling.com` is allowed. The GitHub copy is for everywhere
  else. Keep the two `Tools.bat` files in sync (same file).
- The built-in password keeps casual/unauthorized users out. A determined person
  with the public `.bat` could read the hash and try to crack it, so use a long
  passphrase. For stronger control, keep the file on your own (allowed) server
  behind the PHP gate.
