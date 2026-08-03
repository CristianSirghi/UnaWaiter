@echo off
setlocal
rem ============================================================================
rem  UnaWaiter - verificare (READ-ONLY, nu schimba nimic)
rem ============================================================================
rem
rem   verify_front.bat "<sir_de_conectare>" <cod_univ>
rem
rem   TEST:
rem     verify_front.bat "foishor_riscani_unirest/foishor_riscani_unirest@una.md:4024/clouddev.world" 11
rem
rem   PRODUCTIE:
rem     verify_front.bat "unirest/unirest@93.116.209.117:1521/xe" 11
rem     verify_front.bat "unirest/unirest@185.247.159.33:1521/xe" 13
rem     verify_front.bat "unirest/unirest@95.65.21.122:1521/xe"  17
rem
rem Sirul de conectare e argument, nu construit din gazda, pentru ca testul are
rem alt utilizator, alt port si alt serviciu decat productia.
rem
rem Iese cu cod 0 daca totul e pe loc, altfel cu eroare.
rem ============================================================================

if "%~2"=="" (
  echo.
  echo   Folosire:  verify_front.bat "^<sir_de_conectare^>" ^<cod_univ^>
  echo.
  echo   ex:  verify_front.bat "unirest/unirest@93.116.209.117:1521/xe" 11
  echo.
  exit /b 2
)

set "CONECTARE=%~1"
set "COD_UNIV=%~2"
set "NLS_LANG=AMERICAN_AMERICA.AL32UTF8"

cd /d "%~dp0"

rem "echo exit |" e obligatoriu: 99_verify.sql n-are EXIT la final, fiindca e
rem inclus si de 00_install_front.sql (unde un EXIT ar taia mesajul final).
rem Fara asta, sqlplus ramane la prompt si comanda pare blocata.
echo exit | sqlplus -L -S "%CONECTARE%" @99_verify.sql %COD_UNIV%
exit /b %ERRORLEVEL%
