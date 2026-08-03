@echo off
setlocal
rem ============================================================================
rem  REPETITIA INSTALARII, pe baza de TEST (clouddev)
rem ============================================================================
rem  Dublu-click pe fisier, sau ruleaza-l din cmd. Se opreste dupa fiecare pas
rem  ca sa poti citi ce a iesit.
rem
rem  NU ATINGE PRODUCTIA. Conexiunea de mai jos e testul, se vede dupa
rem  "clouddev" - productia ar fi "unirest@93.116.209.117".
rem ============================================================================

set "CONN=foishor_riscani_unirest/foishor_riscani_unirest@una.md:4024/clouddev.world"
set "NLS_LANG=AMERICAN_AMERICA.AL32UTF8"
cd /d "%~dp0"

cls
echo ============================================================
echo   REPETITIA INSTALARII UnaWaiter  --  baza de TEST
echo ============================================================
echo.
echo   Ce se va intampla, in ordine:
echo.
echo     1. se sterg cele 9 obiecte UnaWaiter  (tabele, view-uri, pachet)
echo     2. se instaleaza totul de la zero, din scripturi
echo     3. se verifica automat ca totul e pe loc
echo     4. se pun inapoi datele vechi (chelneri cu PIN, mese, bonuri)
echo.
echo   Comenzile din UAMenu si restul bazei NU se ating.
echo   Backup: sql\backup\restore_test_20260803.sql
echo.
set /p GO=  Continui? (scrie DA si Enter):
if /i not "%GO%"=="DA" (
  echo.
  echo   Anulat. Nu s-a schimbat nimic.
  pause
  exit /b 1
)

echo.
echo ============================================================
echo   PASUL 1 - stergerea obiectelor
echo ============================================================
echo.
sqlplus -L -S "%CONN%" @98_dezinstalare.sql DA-STERG
if errorlevel 1 goto :eroare
echo.
echo   ^>^> Trebuie sa vezi 9 linii "sters".
pause

echo.
echo ============================================================
echo   PASUL 2 - instalarea de la zero
echo ============================================================
echo.
sqlplus -L -S "%CONN%" @00_install_front.sql 11
if errorlevel 1 goto :eroare
echo.
echo   ^>^> Trebuie sa se termine cu "REZULTAT: TOTUL E PE LOC"
echo      si "Instalare incheiata cu succes".
pause

echo.
echo ============================================================
echo   PASUL 3 - punem datele vechi inapoi
echo ============================================================
echo.
echo   Acum baza are mesele NOI (35, ca la Riscani), dar chelnerii
echo   sunt fara PIN si bonurile lipsesc.
echo.
echo   DA  = revii exact la starea de dinainte (24 mese, 4 PIN-uri, 44 bonuri)
echo   NU  = lasi mesele noi, dar chelnerii trebuie sa-si puna iar PIN-ul
echo.
set /p REST=  Pun datele vechi inapoi? (DA / NU):
if /i "%REST%"=="DA" (
  sqlplus -L -S "%CONN%" @..\backup\restore_test_20260803.sql
  if errorlevel 1 goto :eroare
  echo.
  echo   ^>^> Date restaurate.
) else (
  echo.
  echo   ^>^> Sarit. Baza ramane cu seed-ul nou.
)
pause

echo.
echo ============================================================
echo   PASUL 4 - verificarea finala
echo ============================================================
echo.
rem 99_verify.sql n-are EXIT (e inclus si de 00_install_front.sql, unde un EXIT
rem ar taia mesajul final). Rulat singur, sqlplus ar ramane la prompt si ar parea
rem blocat - de aceea ii dam noi "exit" pe intrare.
echo exit | sqlplus -L -S "%CONN%" @99_verify.sql 11
echo.
echo ============================================================
echo   GATA. Daca ultima linie zice "TOTUL E PE LOC", a mers tot.
echo ============================================================
pause
exit /b 0

:eroare
echo.
echo ============================================================
echo   S-A OPRIT DIN CAUZA UNEI ERORI
echo.
echo   Scripturile se opresc la PRIMA eroare, deci ultimele linii
echo   de mai sus arata exact unde. Copiaza-le si arata-le.
echo.
echo   Nimic nu e pierdut: datele sunt in
echo   sql\backup\restore_test_20260803.sql
echo ============================================================
pause
exit /b 1
