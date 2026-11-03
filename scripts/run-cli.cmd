@echo off
setlocal

if defined REOLINK_CLI_BIN goto override
if defined REOLINK_CONTAINER goto container

where reolink-cli >nul 2>&1
if errorlevel 1 goto missing
reolink-cli %*
exit /b %ERRORLEVEL%

:override
"%REOLINK_CLI_BIN%" %*
exit /b %ERRORLEVEL%

:container
if defined REOLINK_DOCKER_CONTEXT goto container_context
docker exec -i "%REOLINK_CONTAINER%" reolink-cli %*
exit /b %ERRORLEVEL%

:container_context
docker --context "%REOLINK_DOCKER_CONTEXT%" exec -i "%REOLINK_CONTAINER%" reolink-cli %*
exit /b %ERRORLEVEL%

:missing
echo reolink-cli is not installed. Install the CLI and gateway from https://github.com/reolink/reolink-cli and add them to PATH, or set REOLINK_CONTAINER to a running container. 1>&2
exit /b 127
