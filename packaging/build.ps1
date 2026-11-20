# Builds 死ねアップル: the app folder, the portable (travel) zip, and the installer.
# Everything the app needs is bundled; people never download anything else.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$name = "死ねアップル"
$py = Join-Path $root ".venv\Scripts\python.exe"
$out = Join-Path $root "release"

Push-Location $root
try {
    # The GUI uses gamdl from the project virtual environment. Keep the auth
    # parser in that installed package in sync with the checked-out source so
    # the frozen app includes fixes made under src/gamdl.
    $authSource = Join-Path $root "src\gamdl\api\auth.py"
    $authInstalled = Join-Path $root ".venv\Lib\site-packages\gamdl\api\auth.py"
    if ((Test-Path $authSource) -and (Test-Path $authInstalled)) {
        Copy-Item -LiteralPath $authSource -Destination $authInstalled -Force
    }

    # One version number, from gui\gamdl_gui\__init__.py, stamped into the
    # exe's file details, the installer and the About screen.
    $version = [regex]::Match((Get-Content -Raw "$root\gui\gamdl_gui\__init__.py"), '__version__\s*=\s*"([0-9.]+)"').Groups[1].Value
    if (-not $version) { throw "Couldn't read __version__ from gui\gamdl_gui\__init__.py" }
    $parts = (($version.Split(".") + @("0", "0", "0"))[0..3]) -join ", "
    New-Item -ItemType Directory -Force "$root\build" | Out-Null
    $versionFile = "$root\build\version_info.txt"
    (Get-Content -Raw -Encoding UTF8 "$root\packaging\version_info.txt") -replace "1, 0, 0, 0", $parts -replace "u'1\.0\.0'", "u'$version'" |
        Set-Content -Encoding UTF8 $versionFile
    Write-Host "Building version $version"

    # Build in a staging folder, so a copy of the app that's open from dist\
    # (or anywhere else) is never touched.
    $app = "$root\build\app"
    Get-Process | Where-Object { $_.Path -like "$app\*" -or $_.Path -like "$root\build\portable\*" } | Stop-Process -Force

    # 1. The app folder (build\app\死ねアップル)
    & $py -m PyInstaller --clean --noconfirm --windowed --name $name `
        --icon "$root\gui\app.ico" --version-file "$versionFile" `
        --distpath "$app" --workpath "$root\build" --specpath "$root\build" `
        --paths "$root\gui" `
        --add-data "$root\gui\gamdl_gui\qml;ui" `
        --collect-binaries gamdl --collect-submodules gamdl --collect-data pywidevine --collect-submodules pywidevine `
        --hidden-import mutagen.mp4 `
        --hidden-import PySide6.QtQuick --hidden-import PySide6.QtQml --hidden-import PySide6.QtQuickControls2 `
        --hidden-import PySide6.QtMultimedia --hidden-import PySide6.QtWebEngineWidgets --hidden-import PySide6.QtWebEngineCore `
        --hidden-import PySide6.QtWebEngineQuick --hidden-import PySide6.QtSvg --hidden-import PySide6.QtNetwork `
        --exclude-module tkinter --exclude-module PyQt5 --exclude-module PyQt6 `
        --exclude-module pycparser.lextab --exclude-module pycparser.yacctab `
        "$root\gui\launcher.py"
    if ($LASTEXITCODE -ne 0) { throw "PyInstaller failed" }

    # Keep the engine's name out of the program folder: its compiled core
    # becomes engine.pyd (loaded by launcher.py) and its metadata is dropped.
    $internal = "$app\$name\_internal"
    # PyInstaller finds Poppler's ICU 78 through PATH. It exports suffixed
    # symbols such as ucnv_open_78, which is incompatible with Qt6Core's
    # Windows ICU import. The launcher loads the compatible system ICU first.
    Get-ChildItem -LiteralPath $internal -Recurse -File -Filter "icu*.dll" | Remove-Item -Force
    Move-Item -Force "$internal\gamdl\_native.pyd" "$internal\engine.pyd"
    # The multi-size icon next to the exe: used for the window, taskbar and Alt+Tab.
    Copy-Item -Force "$root\gui\app.ico" "$app\$name\app.ico"
    # The licenses travel with the app (GPL-3.0, gamdl's MIT, third-party notices).
    Copy-Item -Force "$root\LICENSE", "$root\THIRD_PARTY_NOTICES.md" "$app\$name\"
    Copy-Item -Force -Recurse "$root\LICENSES" "$app\$name\"
    Remove-Item -Recurse -Force "$internal\gamdl"
    Get-ChildItem $internal -Directory -Filter "gamdl-*.dist-info" | Remove-Item -Recurse -Force

    New-Item -ItemType Directory -Force $out | Out-Null

    # 2. Portable (travel) version: same files plus portable.ini, which keeps
    #    all settings, sign-in and caches in a Data folder next to the app.
    $stage = Join-Path $root "build\portable\$name Portable"
    if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
    New-Item -ItemType Directory -Force $stage | Out-Null
    Copy-Item -Recurse "$app\$name\*" $stage
    Set-Content -Encoding UTF8 (Join-Path $stage "portable.ini") "[$name]`r`nportable=true`r`n; Settings, sign-in and caches are stored in the Data folder beside the app."
    $zip = Join-Path $out "$name-Portable.zip"
    if (Test-Path $zip) { Remove-Item -Force $zip }
    & $py -c "import shutil, sys; shutil.make_archive(sys.argv[1], 'zip', sys.argv[2], sys.argv[3])" `
        ($zip -replace '\.zip$', '') (Split-Path $stage) (Split-Path $stage -Leaf)
    if ($LASTEXITCODE -ne 0) { throw "Zip failed" }

    # 3. Installer
    $iscc = @("$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe", "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe") |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $iscc) { throw "Inno Setup 6 is required to build the installer" }
    & $iscc "/O$out" "/DAppVersion=$version" "$root\packaging\installer.iss"
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed" }

    Get-ChildItem $out | Select-Object Name, @{n = "MB"; e = { [math]::Round($_.Length / 1MB) } }
}
finally { Pop-Location }
