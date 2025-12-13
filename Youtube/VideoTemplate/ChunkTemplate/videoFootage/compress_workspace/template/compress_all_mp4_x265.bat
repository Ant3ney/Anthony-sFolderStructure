@echo off
setlocal enabledelayedexpansion

REM Create output folder if it doesn't exist
if not exist "compressed" (
    mkdir "compressed"
)

for %%F in (*.mp4 *.MP4) do (
    echo Processing: %%F
    ffmpeg -i "%%F" -vcodec libx265 -crf 28 "compressed\%%~nF.mp4"
)

echo.
echo All videos processed into .\compressed\
pause
