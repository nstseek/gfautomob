#include "NomadMemory.au3"
#include "GetProcessBaseAddress.au3"
SetPrivilege("SeDebugPrivilege", 1)

Func Terminate()
	Exit 0
EndFunc

;set hotkey to quit
HotKeySet("{ESC}", "Terminate")

MsgBox(4096, "GF | Warning", "This script only works if GF resolution is set to windowed 1600x900 in a 1080p screen and if GF screen is perfectly centered! (you just need to set GF to full screen and then set it to windowed 1600x900, it will came out perfectly centered)")

;==== OPEN MEMORY=====
$ProcessID = WinGetProcess("Grand Fantasia")
If $ProcessID == 0 Then
	MsgBox(4096, "GF | ERROR", "Failed to get process ID.")
	Exit 1
EndIf

$baseAddress = GetProcessBaseAddress($ProcessID) ; "GrandFantasia.exe+96C56C" - Gets what "GrandFantasia.exe" equals.
If @Error Then
	MsgBox(4096, "ERROR", "Failed to get process base address")
	Exit 1
EndIf

$procHandle = _MemoryOpen($ProcessID)
If @Error Then
	MsgBox(4096, "GF | ERROR", "Failed to open memory.")
	Exit 1
EndIf

;enemy id memory address - need to find a static address
Const $enemyIdAddress = 0x0B0D63D0

;target exists memory address
Const $targetExistsOffset = 0x96C56C
Const $targetExistsAddress = Int($baseAddress + $targetExistsOffset)

;delay to start script (in seconds)
Const $startDelay = 3

MsgBox(4096, "GF Auto Kill Random Mobs", "GF PID is " & $ProcessID & " The script will start in " & $startDelay & " seconds - open your game!")

;declaring constants to be used
;=====================

;tooltip coordinates
Const $xTooltip = 1288
Const $yTooltip = 102

;the enemy id you want to focus on (set to -1 if you don't have a specific enemy to focus)
Const $correctEnemyId = -1

;default delay after doing an in-game action
Const $defaultDelay = 500

;max attacks on the same enemy before resetting position and starting again
Const $maxAttacksOnSameEnemy = 50

;declaring variables that will be read from memory
;=====================

;focused enemy id (-1 in runtime means this is not being used/updated)
$focusedEnemyId = -1

;target state
$targetExists = false

Func readTargetId()
    Return _MemoryRead($enemyIdAddress, $procHandle); THIS IS CHEAT ENGINE RAW OFFSET - THAT YOU CAN SEE IN CHEAT ENGINE GUI
EndFunc

Func readTargetExists()
    $targetExistsRaw = _MemoryRead($targetExistsAddress, $procHandle); THIS IS CHEAT ENGINE RAW OFFSET - THAT YOU CAN SEE IN CHEAT ENGINE GUI

	If $targetExistsRaw == 0 Then
		Return false
	Else
		Return true
	EndIf
EndFunc

Func updateMemoryValues($fetchFocusedEnemyId = false)
		$targetExists = readTargetExists()
		If $fetchFocusedEnemyId And $targetExists Then
			$focusedEnemyId = readTargetExists()
		EndIf
	EndFunc
	
Func displayTooltip($message)
	ToolTip($message, $xTooltip, $yTooltip, 'GF Auto Mob', 1)
EndFunc

; IT DOES WORK - WTFFFFFFFFFF
updateMemoryValues()
If @Error Then
	MsgBox(4096, "ERROR", "Failed to read memory.")
	Exit 1
EndIf

;in-game procedures
;=====================


Func moveCamera()
	MouseClickDrag("right", 960, 520, 962, 520)
	sleep($defaultDelay)
EndFunc

Func moveCharacter()
	MouseClick("left", 960, 820)
	sleep($defaultDelay)
EndFunc

Func changeTarget()
	Send("{TAB}")
	sleep($defaultDelay)
EndFunc

Func resetCharacterPosition($reason)
	;map button coordinates
	$mapButtonX = 1668
	$mapButtonY = 226

	;map reset coordinates
	$mapResetX = 958
	$mapResetY = 521

	;delay to wait for character to get to correct coordinates
	$navigationDelay = 90
	
	;unlock character - character can get locked after chasing an enemy that can not be reached
	For $i = 10 To 1 Step -1
		moveCharacter()
	Next

	;click to open map
	MouseClick("left", $mapButtonX, $mapButtonY)
	sleep($defaultDelay)

	;click to navigate to map coordinates
	MouseClick("left", $mapResetX, $mapResetY)
	sleep($defaultDelay)
	
	;click to close map
	MouseClick("left", $mapButtonX, $mapButtonY)
	sleep($defaultDelay)
	
	For $i = $navigationDelay To 1 Step -1
		$secondsWord = ' seconds'
		If $i == 1 Then
			$secondsWord = ' second'
		EndIf
		
		displayTooltip($i & $secondsWord & ' | ' & $reason)
		sleep(1000)
	Next

	;ideally, this would read x and y character coordinates, but this can be done later
EndFunc

Func attack()
	;attack skill coordinates in screen
	$mouseAttackX = 603
	$mouseAttackY = 953

	MouseClick("right", $mouseAttackX, $mouseAttackY)
	sleep($defaultDelay)
EndFunc

;main loop
;=====================

For $i = $startDelay To 1 Step -1
	$secondsWord = ' seconds'
	If $i == 1 Then
		$secondsWord = ' second'
	EndIf
	
	displayTooltip('Waiting ' & $i & $secondsWord & '...')
	sleep(1000)
Next

displayTooltip('Script has started')

While 1 <> 0
	updateMemoryValues()
	$tabCount = 0
	While ($focusedEnemyId <> $correctEnemyId And $correctEnemyId <> -1) Or $targetExists == false
		If Mod($tabCount, 5) == 0 And $tabCount > 0 Then
			displayTooltip($tabCount & ' | Moving camera and character to find an enemy...')
			moveCamera()
			moveCharacter()
			$tabCount = 0
		EndIf
		If $tabCount == 50 Then
			displayTooltip('Resetting character position due to not being able to find an enemy...')
			resetCharacterPosition('Resetting character position due to not being able to find an enemy...')
			$tabCount = 0
		EndIf
		displayTooltip($tabCount & ' | Looking for an enemy...')
		changeTarget()
		$tabCount = $tabCount + 1
		updateMemoryValues()
	WEnd
	; check if the target is still alive
	$attackCount = 0
	While $targetExists
		displayTooltip($attackCount & ' | Attacking target...')
		attack()
		$attackCount = $attackCount + 1
		updateMemoryValues()
		If $attackCount == $maxAttacksOnSameEnemy And $targetExists Then
			displayTooltip('Resetting character position due to not being able to kill enemy...')
			resetCharacterPosition('Resetting character position due to not being able to kill enemy...')
			$targetExists = false
		EndIf
	WEnd
WEnd
