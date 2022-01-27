

'
' to make available in an xml tied brs
' <script type="text/brightscript" uri="pkg:/source/utils/loggingUtils.brs" />
'

' TODO
'  * add a debug log config and UI for accessing it, for end users to access/send debug logs
'  * detect that we're running a dev version of the app and turn on debug anyway
'  * find a magic solution to detect either the file or sub/function that's calling us and inject that into the logs instead of taking the name arg


' we cannot name this "log" and get sane defaulting behaviors for parameters - there is some sort of reserved behavior for this undefined function name. - dsr
Sub dlog(message as String, name="" as String)
  ' TODO - add debug log on/off config and hook.
  if name <> "" then
   name = name + ": "
  end if
  print getLogDate() + " JF: " + name +  message.toStr()
End Sub

' Sub elog(message as String)
'   ' TODO - use debug log on/off config and hook?
'   print getLogDate() + " JF: ERROR: " + message.toStr()
' End Sub


' getLogDate pulled from rarflix.
function getLogDate(epoch=invalid) as string
        datetime = CreateObject( "roDateTime" )
        ' convert epoch if given - otherwise use the current time
        if epoch <> invalid then
            datetime.FromSeconds(epoch)
        end if
        datetime.ToLocalTime()
        date = datetime.AsDateString("short-date")
        hours = datetime.GetHours()
      if hours < 10 then
            hours = "0" + hours.toStr()
        else
            hours = hours.toStr()
        end if
        minutes = datetime.GetMinutes()
        if minutes < 10 then
            minutes = "0" + minutes.toStr()
        else
            minutes = minutes.toStr()
        end if
        seconds = datetime.GetSeconds()
        if seconds < 10 then
            seconds = "0" + seconds.toStr()
        else
            seconds = seconds.toStr()
        end if
  return date + " " + hours + ":" + minutes + ":" + seconds
end function
