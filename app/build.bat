@echo off
rem Builds sample\dist\hello.exe with PyInstaller. Usage: build.bat [version]
rem Run it from anywhere; needs Python 3 on PATH.
setlocal
cd /d "%~dp0"

set VERSION=%~1
if "%VERSION%"=="" set VERSION=local

python -m venv .venv || exit /b 1
call .venv\Scripts\activate.bat || exit /b 1
python -m pip install --quiet -r requirements.txt || exit /b 1

rem Stamp the version into a copy so the source stays untouched.
powershell -NoProfile -Command "(Get-Content hello.py) -replace '__VERSION__','%VERSION%' | Set-Content build_hello.py" || exit /b 1

pyinstaller --noconfirm --onefile --name hello build_hello.py || exit /b 1
del build_hello.py

echo built %cd%\dist\hello.exe
endlocal
