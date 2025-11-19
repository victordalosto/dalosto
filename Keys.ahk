#Requires AutoHotkey v2.0
#SingleInstance Force


; Used to move the cursor to the beginning of the line
RShift::Home

; Left Alt + Q types a backslash
<!q::Send "\"

; Left Alt + Z types a vertical bar (OR operator)
<!z::Send "|"

; Page Down moves cursor to the end of the line
PgDn::End