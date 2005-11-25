@REM Sample 'rdo' script
@REM
@IF "%SMELEM%"=="" %0\..\..\bin\smcmv.bat -k0 0 rdo %0
@IF NOT "%SMDIR%"=="" %SMDIR%\bin\smrmt.bat %SMELEM% rdo %0
@IF NOT "%SMDIR%"=="" ECHO Error: Execute this script on Agent! & EXIT 1
@REM
dir c:\
@IF ERRORLEVEL 1 EXIT %ERRORLEVEL%
