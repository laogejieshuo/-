@echo off
setlocal enabledelayedexpansion

:: 检查 FFmpeg 是否可用
where ffmpeg >nul 2>&1
if %errorlevel% neq 0 (
    echo [错误] 请先安装 FFmpeg 并添加到系统 PATH
    pause
    exit /b
)

:: 设置输出文件夹
set "OUTPUT_FOLDER=cleaned_videos"
if not exist "%OUTPUT_FOLDER%" mkdir "%OUTPUT_FOLDER%"

:: 支持的视频扩展名
set "EXTENSIONS=mp4 mov mkv avi m4v"

:: 根据 GPU 自动选择编码器（NVIDIA/AMD/Intel）
:: 检测 NVIDIA
ffmpeg -encoders | findstr nvenc >nul 2>&1
if %errorlevel% == 0 (
    set "GPU_ENCODER=h264_nvenc"
    set "PRESET=fast"
) else (
    :: 检测 AMD
    ffmpeg -encoders | findstr amf >nul 2>&1
    if %errorlevel% == 0 (
        set "GPU_ENCODER=h264_amf"
        set "PRESET=fast"
    ) else (
        :: 检测 Intel
        ffmpeg -encoders | findstr qsv >nul 2>&1
        if %errorlevel% == 0 (
            set "GPU_ENCODER=h264_qsv"
            set "PRESET=fast"
        ) else (
            echo [警告] 未检测到 GPU 编码器，将使用 CPU 编码（libx264）
            set "GPU_ENCODER=libx264"
            set "PRESET=medium"
        )
    )
)

:: 遍历当前目录下的所有视频文件
for %%f in (*.*) do (
    for %%e in (%EXTENSIONS%) do (
        if /i "%%~xf" == ".%%e" (
            echo 正在处理: "%%f"

            :: 提取原视频的 CRF 值（如果存在）
            for /f "delims=" %%i in ('ffprobe -v error -select_streams v:0 -show_entries stream^=codec_name,bit_rate -of default^=noprint_wrappers^=1:nokey^=1 "%%f" 2^>^&1') do (
                set "CODEC=%%i"
            )
            for /f "delims=" %%j in ('ffprobe -v error -select_streams v:0 -show_entries format^=bit_rate -of default^=noprint_wrappers^=1:nokey^=1 "%%f" 2^>^&1') do (
                set "BITRATE=%%j"
            )

            :: 提取原音频编码格式
            for /f "delims=" %%k in ('ffprobe -v error -select_streams a:0 -show_entries stream^=codec_name -of default^=noprint_wrappers^=1:nokey^=1 "%%f" 2^>^&1') do (
                set "AUDIO_CODEC=%%k"
            )

            :: 如果原视频是 H.265，则使用对应的 GPU 编码器
            if "!CODEC!" == "hevc" (
                if "!GPU_ENCODER!" == "h264_nvenc" set "GPU_ENCODER=hevc_nvenc"
                if "!GPU_ENCODER!" == "h264_amf" set "GPU_ENCODER=hevc_amf"
                if "!GPU_ENCODER!" == "h264_qsv" set "GPU_ENCODER=hevc_qsv"
            )

            :: 构建 FFmpeg 命令
            ffmpeg -i "%%f" ^
                -map_metadata -1 -map_chapters -1 ^
                -c:v !GPU_ENCODER! -preset !PRESET! ^
                -crf 23 -b:v !BITRATE! ^
                -c:a !AUDIO_CODEC! -b:a 192k ^
                -y "%OUTPUT_FOLDER%\%%~nf_cleaned.%%e"
        )
    )
)

echo 处理完成！文件已保存到: "%OUTPUT_FOLDER%"

:: 再次用 exiftool 彻底清理元数据（确保无残留）
where exiftool >nul 2>&1
if %errorlevel% == 0 (
    echo 正在用 exiftool 二次清理元数据...
    exiftool -all= -r "%OUTPUT_FOLDER%"
    del "%OUTPUT_FOLDER%\*_original" 2>nul
) else (
    echo [提示] 未安装 exiftool，跳过二次元数据清理。
)

pause