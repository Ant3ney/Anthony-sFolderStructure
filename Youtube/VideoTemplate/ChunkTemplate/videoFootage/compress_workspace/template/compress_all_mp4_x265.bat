@echo off
setlocal enabledelayedexpansion

for %%F in (*.mp4 *.MP4) do (
    echo Compressing: %%F
    ffmpeg -i "%%F" -vcodec libx265 -crf 28 "%%~nF_compressed_x265.mp4"
)

echo.
echo Done processing all MP4 files.
pause

