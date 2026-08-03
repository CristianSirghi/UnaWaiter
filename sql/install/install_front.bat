@echo off
setlocal
rem ============================================================================
rem  UnaWaiter - instalare pe frontul unui restaurant
rem ============================================================================
rem
rem   install_front.bat <gazda> <cod_univ>
rem
rem   install_front.bat 93.116.209.117 11     MIRON COSTIN (Riscani)
rem   install_front.bat 185.247.159.33 13     COLUMNA
rem   install_front.bat 95.65.21.122  17      MIRCEA cel BATRIN
rem
rem Utilizatorul si parola sunt conventia UAMenu: unirest/unirest pe toate
rem fronturile de productie. Daca vreun restaurant iese din conventie, dai
rem parola ca al treilea argument.
rem
rem Scrie un log complet in log\install_<cod_univ>_<data>.log si se opreste la
rem prima eroare (WHENEVER SQLERROR EXIT FAILURE din 00_install_front.sql).
rem ============================================================================

if "%~2"=="" (
  echo.
  echo   Folosire:  install_front.bat ^<gazda^> ^<cod_univ^> [parola]
  echo.
  echo   ex:  install_front.bat 93.116.209.117 11
  echo.
  exit /b 2
)

set "GAZDA=%~1"
set "COD_UNIV=%~2"
set "PAROLA=%~3"
if "%PAROLA%"=="" set "PAROLA=unirest"

rem Sursa: fara asta, textul romanesc din scripturi ajunge stricat in baza.
rem Bazele sunt CL8MSWIN1251, dar clientul trebuie sa declare ce trimite EL.
set "NLS_LANG=AMERICAN_AMERICA.AL32UTF8"

cd /d "%~dp0"
if not exist log mkdir log

for /f "tokens=1-3 delims=/.- " %%a in ("%DATE%") do set "AZI=%%c%%b%%a"
set "AZI=%AZI: =%"
set "LOG=log\install_%COD_UNIV%_%AZI%_%RANDOM%.log"

echo.
echo ============================================================
echo   UnaWaiter — instalare
echo   gazda    : %GAZDA%
echo   filiala  : %COD_UNIV%
echo   log      : %LOG%
echo ============================================================
echo.
echo   ATENTIE: se scrie intr-o baza de PRODUCTIE.
echo   Verifica gazda si filiala de mai sus.
echo.
set /p RASPUNS=  Continui? (scrie DA)
if /i not "%RASPUNS%"=="DA" (
  echo   Anulat.
  exit /b 1
)

echo.
echo   Rulez...

sqlplus -L -S "unirest/%PAROLA%@%GAZDA%:1521/xe" @00_install_front.sql %COD_UNIV% > "%LOG%" 2>&1
set "REZULTAT=%ERRORLEVEL%"

type "%LOG%"

echo.
if "%REZULTAT%"=="0" (
  echo ============================================================
  echo   GATA. Filiala %COD_UNIV% instalata.  Log: %LOG%
  echo ============================================================
) else (
  echo ============================================================
  echo   ESUAT ^(cod %REZULTAT%^). Nimic mai departe nu s-a rulat.
  echo   Vezi %LOG% — instalarea se opreste la PRIMA eroare,
  echo   deci ultima linie din log arata exact unde a crapat.
  echo ============================================================
)

exit /b %REZULTAT%
