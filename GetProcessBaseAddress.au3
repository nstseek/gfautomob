#include <WinAPI.au3>
Global $_COMMON_KERNEL32DLL=DllOpen("kernel32.dll")

Func GetProcessBaseAddress($PID)
	$OpenProcess = _ProcessOpen($PID,0x400)
	$pTemp=_ProcessGetModuleBaseAddress($PID ,$OpenProcess)
	$aTemp=_ProcessMemoryVirtualQuery($OpenProcess,$pTemp)

	Return $aTemp[1]
EndFunc



Func _ProcessOpen($vProcessID,$iAccess,$bInheritHandle=False)
Local $aRet
; Special 'Open THIS process' ID?  [returns pseudo-handle from Windows]
If $vProcessID=-1 Then
  $aRet=DllCall($_COMMON_KERNEL32DLL,"handle","GetCurrentProcess")
  If @error Then Return SetError(2,@error,0)
  Return $aRet[0]  ; usually the constant '-1', but we're keeping it future-OS compatible this way
ElseIf Not __PFEnforcePID($vProcessID) Then
  Return SetError(16,0,0)  ; Process does not exist or was invalid
EndIf
$aRet=DllCall($_COMMON_KERNEL32DLL,"handle","OpenProcess","dword",$iAccess,"bool",$bInheritHandle,"dword",$vProcessID)
If @error Then Return SetError(2,@error,0)
If Not $aRet[0] Then Return SetError(3,@error,0)
Return SetExtended($vProcessID,$aRet[0]) ; Return Process ID in @extended in case a process name was passed
EndFunc

Func _ProcessGetModuleBaseAddress($vProcessID,$sModuleName,$bList32bitMods=False,$bGetWow64Instance=False)
Local $i=0,$aModList
If Not $bList32bitMods Then $i=4 ; flag 4 = stop at 1st match (only if 32-bit modules aren't being listed)
$aModList=_ProcessListModules($vProcessID,$sModuleName,$i,$bList32bitMods)
If @error Then Return SetError(@error,@extended,-1)
If $aModList[0][0]=0 Then Return SetError(-1,0,-1)
; If a Wow64 Process (and $bList32bitMods=True), its possible more than one module name will match
If $aModList[0][0]>1 Then
  If $bList32bitMods And $bGetWow64Instance Then Return SetExtended($aModList[2][4],$aModList[2][3])
  SetError(-16) ; notify caller that >1 match was found, but returning 1st instance since $bGetWow64Instance=False
EndIf
Return SetError(@error,$aModList[1][4],$aModList[1][3]) ; SetExtended() actually clears @error, so we must use SetError()
EndFunc
Func _ProcessMemoryVirtualQuery($hProcess,$pAddress,$iInfo=-1)
If Not IsPtr($hProcess) Or Ptr($pAddress)=0 Or $iInfo>6 Then Return SetError(1,0,-1)
; MEMORY_BASIC_INFORMATION structure:  BaseAddress, AllocationBase, AllocationProtect, RegionSize, State, Protect, Type
Local $aRet,$stMemInfo=DllStructCreate("ptr;ptr;dword;ulong_ptr;dword;dword;dword"),$iStrSz=DllStructGetSize($stMemInfo)
$aRet=DllCall($_COMMON_KERNEL32DLL,"ulong_ptr","VirtualQueryEx","handle",$hProcess,"ptr",$pAddress,"ptr",DllStructGetPtr($stMemInfo),"ulong_ptr",$iStrSz)
If @error Then Return SetError(2,@error,-1)
If Not $aRet[0] Then Return SetError(3,@error,-1)
If $aRet[0]<>$iStrSz Then ConsoleWriteError("Size (in bytes) mismatch in VirtualQueryEx: Struct: "&$iStrSz&", Transferred: "&$aRet[0]&@LF)
; Return ALL?
If $iInfo<0 Then
  Dim $aMemInfo[7]
  For $i=0 To 6
   $aMemInfo[$i]=DllStructGetData($stMemInfo,$i+1)
  Next
  Return $aMemInfo
EndIf
Return DllStructGetData($stMemInfo,$iInfo+1)
EndFunc

Func _ProcessListModules($vProcessID,$sTitleFilter=0,$iTitleMatchMode=0,$bList32bitMods=False)
If Not __PFEnforcePID($vProcessID) Then Return SetError(1,0,"")
Local $hTlHlp,$aRet,$sTitle,$bMatchMade=1,$iTotal=0,$bMatch1=0,$iArrSz=40,$iNeg=0
If $sTitleFilter="" Then $sTitleFilter=0
If BitAND($iTitleMatchMode,8) Then
  $iNeg=-1
; 'Stop at first match' flag set?
ElseIf BitAND($iTitleMatchMode,4) And IsString($sTitleFilter) Then
  $iArrSz=1
  $bMatch1=1
EndIf
$iTitleMatchMode=BitAND($iTitleMatchMode,3)
Dim $aModules[$iArrSz+1][6]
; MAX_MODULE_NAME32 = 255  (+1 = 256), MAX_PATH = 260
; ModuleEntry32: Size, Module ID, Process ID, Global Usage Count, Process Usage Count, Base Address, Module Size, Module Handle, Module Name, Module Path
Local $stModEntry=DllStructCreate("dword;dword;dword;dword;dword;ptr;dword;handle;wchar[256];wchar[260]"),$pMEPointer=DllStructGetPtr($stModEntry)
DllStructSetData($stModEntry,1,DllStructGetSize($stModEntry))
If $bList32bitMods Then
  ; TH32CS_SNAPMODULE32 0x00000010  +  ; TH32CS_SNAPMODULE  0x00000008
  $hTlHlp=__PFCreateToolHelp32Snapshot($vProcessID,0x18)
Else
  ; TH32CS_SNAPMODULE  0x00000008
  $hTlHlp=__PFCreateToolHelp32Snapshot($vProcessID,8)
EndIf
If @error Then Return SetError(@error,@extended,"")
; Get first module
$aRet=DllCall($_COMMON_KERNEL32DLL,"bool","Module32FirstW","handle",$hTlHlp,"ptr",$pMEPointer)
While 1
  If @error Then
   Local $iErr=@error
   __PFCloseHandle($hTlHlp)
   Return SetError(2,$iErr,"")
  EndIf
  ; False returned? Likely no more modules found [LastError should equal ERROR_NO_MORE_FILES (18)]
  If Not $aRet[0] Then ExitLoop
  $sTitle=DllStructGetData($stModEntry,9)    ; file name
  If IsString($sTitleFilter) Then
   Switch $iTitleMatchMode
    Case 0
     If $sTitleFilter<>$sTitle Then $bMatchMade=0
    Case 1
     If StringInStr($sTitle,$sTitleFilter)=0 Then $bMatchMade=0
    Case Else
     If Not StringRegExp($sTitle,$sTitleFilter) Then $bMatchMade=0
   EndSwitch
   $bMatchMade+=$iNeg ; toggles match/no-match if 0x8 set
  EndIf
  If $bMatchMade Then
   $iTotal+=1
   If $iTotal>$iArrSz Then
    $iArrSz+=10
    ReDim $aModules[$iArrSz+1][6]
   EndIf
   $aModules[$iTotal][0]=$sTitle
   $aModules[$iTotal][1]=DllStructGetData($stModEntry,10) ; full path
   $aModules[$iTotal][2]=DllStructGetData($stModEntry,8) ; module handle/address (normally same as Base Address)
   $aModules[$iTotal][3]=DllStructGetData($stModEntry,6) ; module base address
   $aModules[$iTotal][4]=DllStructGetData($stModEntry,7) ; module size
   $aModules[$iTotal][5]=DllStructGetData($stModEntry,5) ; process usage count (same as Global usage count)
   ; Process ID is same as on entry, Module ID always = 1, Global Usage Count = Process Usage Count
   If $bMatch1 Then ExitLoop
  EndIf
  $bMatchMade=1
  ; Next module
  $aRet=DllCall($_COMMON_KERNEL32DLL,"bool","Module32NextW","handle",$hTlHlp,"ptr",$pMEPointer)
WEnd
__PFCloseHandle($hTlHlp)
ReDim $aModules[$iTotal+1][6]
$aModules[0][0]=$iTotal
Return $aModules
EndFunc

Func __PFCreateToolHelp32Snapshot($iProcessID,$iFlags)
; Parameter checking not done!! (INTERNAL only!)
Local $aRet
; Enter a loop in the case of a Module snapshot returning -1 and LastError=ERROR_BAD_LENGTH.  We'll try a max of 10 times
For $i=1 To 10
  $aRet=DllCall($_COMMON_KERNEL32DLL,"handle","CreateToolhelp32Snapshot","dword",$iFlags,"dword",$iProcessID)
  If @error Then Return SetError(2,@error,-1)
  ; INVALID_HANDLE_VALUE (-1) ?
  If $aRet[0]=-1 Then
   ; Heap (0x1) or Module (0x8 or 0x18) Snapshot?  MSDN recommends retrying the API call if LastError=ERROR_BAD_LENGTH (24)
   If BitAND($iFlags,0x19) And _WinAPI_GetLastError()=24 Then ContinueLoop
   ; Else - other error, invalid handle
   Return SetError(3,0,-1)
  EndIf
  Sleep(0) ; delay the next attempt
Next
If $aRet[0]=-1 Then Return SetError(4,0,-1)
Return $aRet[0]
EndFunc
Func __PFCloseHandle(ByRef $hHandle)
If Not IsPtr($hHandle) Or $hHandle=0 Then Return SetError(1,0,False)
Local $aRet=DllCall($_COMMON_KERNEL32DLL,"bool","CloseHandle","handle",$hHandle)
If @error Then Return SetError(2,@error,False)
If Not $aRet[0] Then Return SetError(3,@error,False)
; non-zero value for return means success
$hHandle=0 ; invalidate handle
Return True
EndFunc
Func __PFEnforcePID(ByRef $vPID)
If IsInt($vPID) Then Return True
$vPID=ProcessExists($vPID)
If $vPID Then Return True
Return SetError(1,0,False)
EndFunc