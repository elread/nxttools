'# start.vbs, osm, 2014
'# NRS Start, Stop, Auto update with saving your settings, no console.
'# 
'# If you find this service useful, please consider making a donation NXT: 10260372437324455574
'# 
Option Explicit

const AutoUpdate          = true  ' download & update actual version: true - yes; false - no
const SilentMode          = false ' true: nonstop; false: with stops
const UseUAC              = false ' use administrator mode: true - yes; false - no
const MemAlocated         = ""    ' java memory configuration, e.g. "-Xms448 -Xmx480"
const DefaultTimeout      = 30    ' sec.
const JavaEXE             = "javaw.exe"
const DefaultURL          = "http://localhost:7874/nxt?requestType="
dim   StopPort : StopPort = 28282
dim   StopKey  : StopKey  = 12345

on error resume next
Dim Args   : Set Args   = WScript.Arguments
Dim oShell : Set oShell = CreateObject ("WScript.Shell")
if UseUAC then dim uac : uac = "runas" 
If WScript.Arguments(0) <> "uac" then
    Dim objShell : Set objShell = CreateObject("Shell.Application")
    Dim WinVer   :     WinVer   = CSng(Replace(oShell.RegRead("HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\CurrentVersion"),".",","))
    if WinVer < 6 then
        objShell.ShellExecute "cscript.exe", Chr(34) & WScript.ScriptFullName & Chr(34) & " uac //nologo", "", "", 1
    else
        objShell.ShellExecute "cscript.exe", Chr(34) & WScript.ScriptFullName & Chr(34) & " uac //nologo", "", uac, 1
    end if
Else
    err.Clear
    on error goto 0
    WScript.Echo "NRS Start/Stop; Version: 0.1.1;"&VbCrLf
    

    ' Check path
    dim fso : Set fso = CreateObject ("Scripting.FileSystemObject")
    dim ScriptFullPath :ScriptFullPath  = fso.GetParentFolderName(fso.GetAbsolutePathName(WScript.ScriptFullName))&"\"
    if not fso.FileExists(ScriptFullPath&"start.jar") then
        toLog("NXT file 'start.jar' not found")
        PressAnyKey(1)
    end if
    dim pathJava : pathJava  = checkJava()
        
    ' Main
    dim ActualVersion
    dim PIDJava : PIDJava = isProcess(JavaEXE,"start.jar")

    if  PIDJava > 0 then
        if CheckUpdate then
            call UpdateVersion
        else 
            call StopServer
        end if
    else
        call StartServer
        if CheckUpdate then
            call UpdateVersion
            call StartServer
        end if
    end if
    PressAnyKey(1)
end if

sub StartServer
    toLog("Starting NXT...")
    on error resume next
    oShell.Run "cmd /C "&fso.GetDriveName(ScriptFullPath)&_
        " && CD "&""""&ScriptFullPath&""""&" && start /MIN "&""""&"NXT"&""""&" "&_
        """"&pathJava&""""&" -jar start.jar "&MemAlocated&" STOP.PORT="&StopPort&" STOP.KEY="&StopKey, 2, false
    if Err.Number <> 0 then DisplayErrorInfo
    on error goto 0
    
    dim cnt : cnt = 0
    do 
        Wscript.Sleep 1000
        cnt = cnt + 1
        if cnt > 60 then ' 1 minute
            toLog("Warning! Can't start the server.")
            PressAnyKey(1)
        end if
        PIDJava = isProcess (JavaEXE, "start.jar")
    loop until PIDJava > 0
    toLog("Waiting for server response...")

    dim oXMLHTTP : Set oXMLHTTP = CreateObject("Microsoft.XMLHTTP")
    cnt = 0
    on error resume next
    do
        Wscript.Sleep 2000
        cnt = cnt + 1
        if cnt > 30 then ' 1 minute
            oXMLHTTP = nothing
            toLog("Warning! Server response timeout.")
            PressAnyKey(2)
        end if
        Err.Clear
        oXMLHTTP.Open "GET", DefaultURL + "getState", false
        oXMLHTTP.Send
    loop until oXMLHTTP.readyState = 4 and oXMLHTTP.Status = 200
    if Err.Number <> 0 then DisplayErrorInfo
    on error goto 0
    toLog("NXT Started")
end sub

function CheckUpdate
    dim response, CurrentVersion
    response      = SendRequestHttp("getAliasURI&alias=nrsversion")
    if not response = "" then ActualVersion = split(stunParser(response,"uri")," ")(0)
    toLog("Actual version:    "&ActualVersion)

    response      = SendRequestHttp("getState")
    if not response = "" then CurrentVersion = stunParser(response,"version")
    toLog("Current version:   "&CurrentVersion)
    toLog("Last block number: "&stunParser(response,"numberOfBlocks"))
    if StrToInt(ActualVersion) > StrToInt(CurrentVersion) and AutoUpdate then CheckUpdate = true else CheckUpdate = false
end function

function StrToInt (ByVal str)
    StrToInt = 0
    if TypeName(str) = "String" then
        StrToInt  = mid(Replace(trim(str), ".", "")+String(9, "0"),1,9)
        on error resume next
        StrToInt = CLng(StrToInt)
        if Err.Number <> 0 then
            StrToInt = 0
            err.clear
            on error goto 0
        end if
    end if
end function

sub UpdateVersion
    toLog("Prepare to update")
    call Download("http://download.nxtcrypto.org/nxt-client-"&ActualVersion&".zip","nxt-client-"&ActualVersion&".zip")

    if MakeDirectory(ScriptFullPath&"tmp") then
        call Extract( ScriptFullPath&"nxt-client-"&ActualVersion&".zip", ScriptFullPath&"tmp\" )
    else
        toLog("Warning! Can't create folder 'tmp'.") 
        PressAnyKey(6)
    end if
    
    dim web_xmlPath : web_xmlPath = "webapps\root\WEB-INF\web.xml"
    call xmlWorker(ScriptFullPath&"tmp\nxt\"&web_xmlPath, ScriptFullPath&web_xmlPath)
    call StopServer
    call MoveSource(ScriptFullPath&"tmp\nxt", ScriptFullPath) 'fso.GetParentFolderName(ScriptFullPath)
    call DelDirectory (ScriptFullPath&"tmp\")

end sub

sub DelDirectory (ByVal pathDirectory)
    if fso.FolderExists(pathDirectory) then fso.GetFolder(pathDirectory).Delete
end sub 

sub MoveSource (ByVal PathSource, ByVal PathTarget)
    dim objShell  : set objShell  = CreateObject("shell.application")
    dim objTarget : set objTarget = objShell.NameSpace(PathTarget)
    dim objSource : set objSource = objShell.NameSpace(PathSource)
    dim objFso    : set objFso    = CreateObject("Scripting.FileSystemObject")

    dim objFolder : set objFolder = objFso.GetFolder(PathSource)
    dim objSubF   : set objSubF   = objFolder.SubFolders
    dim objFiles  : set objFiles  = objFolder.Files


    on error resume next
    if (not objTarget is nothing) then
        dim File, SubF, saveCnt
        saveCnt = objSource.Items.Count
        For Each SubF In objSubF
            objTarget.MoveHere SubF.path, 4+16+512
        next    
        for Each File  In objFiles
            objTarget.MoveHere File.path, 4+16+512
        next    
    end if
    if Err.Number <> 0 then DisplayErrorInfo
    toLog("Moved "&saveCnt-objSource.Items.Count&" objects")
    on error goto 0

    set objFso     = nothing
    set objFolder  = nothing
    set objFiles   = nothing
    set objSubF    = nothing
    set objTarget  = nothing
    set objSource  = nothing
    set objShell   = nothing
end sub

sub StopServer
    toLog("Try to stop server...")

    on error resume next
    oShell.Run """"&pathJava&""""&" -jar "&""""&ScriptFullPath&"start.jar"&""""&" STOP.PORT="&StopPort&" STOP.KEY="&StopKey&" --stop", 0, false
    if Err.Number <> 0 then DisplayErrorInfo
    on error goto 0

    dim cnt : cnt = 0
    do 
        Wscript.Sleep 1000
        cnt = cnt + 1
        if cnt > 60 then ' 1 minute
            ' NEED BKP! Broken Blockchain!
            toLog("Warning! Can't correctly stop the server.")
            if foundProcess(PIDJava, true) then
                toLog("Java proccess killed.")
                exit sub
            else
                toLog("Can't kill java proccess.")
                PressAnyKey(1)
            end if
        end if
    loop until not foundProcess(PIDJava, false)
    toLog("Java stoped")
end sub

function checkJava
    dim JavaVersion, JavaRegPath32, JavaRegPath64, JavaRegPathS1, JavaRegPathS2
    JavaRegPathS1 = "c:\Windows\System32\"&JavaEXE
    JavaRegPathS2 = "c:\Windows\SysWOW64\"&JavaEXE
    if fso.FileExists(JavaRegPathS1) then checkJava = JavaRegPathS1 : exit function : end if
    if fso.FileExists(JavaRegPathS2) then checkJava = JavaRegPathS2 : exit function : end if
    
    on error resume next
    JavaRegPath32 = "HKEY_LOCAL_MACHINE\SOFTWARE\JavaSoft\Java Runtime Environment\"
    JavaVersion = oShell.RegRead(JavaRegPath32+"CurrentVersion")
    checkJava   = oShell.RegRead(JavaRegPath32+JavaVersion&"\JavaHome")&"\bin\"&JavaEXE
    if Err.Number = 0 and fso.FileExists(checkJava) then exit function

    JavaRegPath64 = "HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\JavaSoft\Java Runtime Environment\"
    JavaVersion = oShell.RegRead(JavaRegPath64+"CurrentVersion")
    checkJava   = oShell.RegRead(JavaRegPath64+JavaVersion&"\JavaHome")&"\bin\"&JavaEXE
    if Err.Number = 0 and fso.FileExists(checkJava) then exit function
    err.Clear
    on error goto 0
    
    checkJava   = ""
    toLog("'"&JavaEXE&"' not found")
    PressAnyKey(1)
end function

function toLog (ByVal str)
    WScript.echo "["&time&"] "&str
End function

function isProcess (ByVal ProcessName, StartFileName)
    dim objWMIService, objProc, posSP, posSK, strCL
    Set objWMIService = GetObject ("winmgmts:{impersonationLevel=impersonate}!\\.\root\cimv2")
    isProcess = 0
    For Each objProc In objWMIService.ExecQuery ("Select * from Win32_Process Where Name = '"&ProcessName&"'")
        strCL = ucase(trim(objProc.CommandLine))+" "
        if InStr(strCL, ucase(StartFileName) ) > 0 then
            'toLog("is:"&objProc.CommandLine)
            'toLog("is:"&objProc.ExecutablePath)
            isProcess = objProc.ProcessId
            posSP = InStr(strCL, "STOP.PORT=")
            posSK = InStr(strCL, "STOP.KEY=")
            toLog("Java working")
            if posSP+posSK > 0 then
                StopPort = mid(strCL,posSP+10,InStr(posSP, strCL, " ")-posSP-10)
                StopKey  = mid(strCL,posSK+9,InStr(posSK, strCL, " ")-posSK-9)
                toLog("Found STOP.PORT="&StopPort&" and STOP.KEY="&StopKey&"")
            else
              toLog("Warning! STOP.PORT and STOP.KEY not found")
            end if
            exit function
        end if
    Next
End function

function foundProcess (ByVal PID, ByVal Destroy)
    dim objWMIService, objProc, objTerm
    Set objWMIService = GetObject ("winmgmts:{impersonationLevel=impersonate}!\\.\root\cimv2")
    foundProcess = false
    For Each objProc In objWMIService.ExecQuery("SELECT * FROM Win32_Process WHERE ProcessId = "&PID)
        if Destroy then 
            objTerm = objProc.Terminate()
            if objTerm = 0 then foundProcess = true else foundProcess = false
        else
            foundProcess = true
        end if
        exit function
    Next
end function

sub xmlWorker (ByVal xmlFile, old_xmlFile)
    toLog("Compare web.xml...")
    
    dim xmlOld      : Set xmlOld   = CreateObject("Microsoft.XMLDOM")
    xmlOld.Async = "False"
    if not xmlOld.Load(old_xmlFile) then
        toLog("Warning! Current 'web.xml' not saved.") 
        PressAnyKey(5)
    end if
    
    if not fso.FileExists(xmlFile) then
        toLog("File " +xmlFile+" not found")
        call PressAnyKey(5)
    end if
    
    dim newNode, newNodes, pathNode, newParam, newValue, oldValue
    dim xmlNew : Set xmlNew   = CreateObject("Microsoft.XMLDOM")
    xmlNew.Async = "False"
    xmlNew.Load(xmlFile)

    dim chngValue : chngValue = 0
    pathNode = "/web-app/servlet/init-param"
    Set newNodes = xmlNew.selectNodes (pathNode)

    For Each newNode in newNodes
        set newParam = newNode.childNodes(0)
        set newValue = newNode.childNodes(1)
        Set oldValue = xmlOld.selectNodes (pathNode + " [" + newParam.nodeName+"='" + newParam.text + "']/"+newValue.nodeName)(0)
        if newValue.text <> oldValue.text then
            newValue.text = oldValue.text
            chngValue     = chngValue + 1
        end if
    Next

    if chngValue > 0 then xmlNew.Save xmlFile
    toLog("Changes saved: "&chngValue)
    set xmlNew   = nothing
    set xmlOld   = nothing
    set newNodes = nothing
end sub

function stunParser(ByVal strJSON, ByVal srchArg)
    dim iJSON, arrJSON, posArg, posQuote, posValue
    strJSON = trim(strJSON)
    stunParser = strJSON
    if strJSON = "" then
        exit function
    else
        arrJSON = Split(strJSON,",")
        For Each iJSON In arrJSON 'if UBound(arrJSON)>0 then
            posArg = InStr(1,ucase(iJSON), """"&ucase(srchArg)&""":")
            if posArg > 0 then
                posValue   = posArg + len(srchArg) + 3

                posQuote   = InStr(posValue,iJSON, ",")
                if posQuote = 0 then posQuote = len(iJSON)
                stunParser = Replace(Replace(mid(iJSON, posValue), "}", ""),"""", "")
                Exit For
            end if
        Next
    end if
end function

function SendRequestHttp(ByVal request)
    dim http
    Set http = CreateObject("Microsoft.XmlHttp")
    http.open "GET", DefaultURL + request, FALSE
    
    on error resume next
    http.send ""
    if http.Status <> 200 then
        toLog("Server not responding")
        call PressAnyKey(6)
    end if
    if Err.Number <> 0 then DisplayErrorInfo
    on error goto 0
    
    SendRequestHttp = http.responseText
    set http = nothing
end function

sub Download(ByVal url, ByVal filename)

    dim oXMLHTTP, oADOStream, Tick
    Set oXMLHTTP = CreateObject("Microsoft.XMLHTTP")
    oXMLHTTP.Open "GET", url, true
    oXMLHTTP.Send
    toLog("Download "&filename)
    do
        Wscript.Sleep 100
        Tick = Tick +1
        if Tick > DefaultTimeout*10 then 
            WScript.Echo "  Timeout "&DefaultTimeout&" sec."
            set oXMLHTTP = Nothing
            call PressAnyKey(2)
        end if
    loop until oXMLHTTP.readyState = 4

    If oXMLHTTP.Status=200 Then
        Set oADOStream = CreateObject("ADODB.Stream")
        oADOStream.Mode = 3 ' permission: read/write
        oADOStream.Type = 1 ' data type: Binary
        oADOStream.Open
        oADOStream.Write oXMLHTTP.responseBody
        oADOStream.SaveToFile ScriptFullPath&filename, 2 ' force rewrite
        oADOStream.Close
        toLog("Saved to  "&ScriptFullPath)
    else
        toLog("Download error N "&oXMLHTTP.Status&" - "&oXMLHTTP.StatusText)
        set oXMLHTTP   = Nothing
        set oADOStream = Nothing
        call PressAnyKey(3)
    end if
    set oXMLHTTP   = Nothing
    set oADOStream = Nothing
end sub

sub Extract( ByVal myZipFile, ByVal myTargetDir )
' Based on an article by Gerald Gibson Jr.: http://www.codeproject.com/csharp/decompresswinshellapics.asp
' Written by Rob van der Woude: http://www.robvanderwoude.com
    toLog("Unzip...")
    Dim objShell, objSource, objTarget, objSubF
    Set objShell = CreateObject( "Shell.Application" )
    Set objSource = objShell.NameSpace( myZipFile ).Items( )
    Set objTarget = objShell.NameSpace( myTargetDir )

    On Error Resume Next
    objTarget.CopyHere objSource, 4+16+1024 '256

    do 
        Wscript.Sleep 100
    loop until objTarget.Items.Count > 0

    Set objSubF   = objShell.NameSpace( myTargetDir +"nxt\")

    if Err.Number = 0 then toLog("Unzip "&objSubF.Items.Count&" objects")
    Set objSubF   = Nothing
    Set objTarget = Nothing
    Set objSource = Nothing
    Set objShell  = Nothing    
    if Err.Number <> 0 then
        call DisplayErrorInfo
        call PressAnyKey(4)
    end if
    err.clear
    on error goto 0
End sub

Function MakeDirectory(ByVal dirPath)
  Dim dirFSO, dir
  Set dirFSO = CreateObject("Scripting.FileSystemObject")
  With dirFSO
    If .FolderExists( .GetDriveName(dirPath)) Then
      dir = dirPath
      Dim rdirs(): ReDim rdirs(-1)
      Do While Not .FolderExists(dir) And Not _
        .GetDriveName(dir) = dir
        ReDim Preserve rdirs(ubound(rdirs) + 1)
        rdirs(ubound(rdirs)) = .GetFileName(dir)
        dir = .GetParentFolderName(dir)
      Loop
      Do While ubound(rdirs) > -1
        dir = .BuildPath(dir, rdirs(ubound(rdirs)) )
        .CreateFolder dir
        Redim Preserve rdirs(ubound(rdirs) - 1)
      Loop
      MakeDirectory = True
    Else
      MakeDirectory = False
    End If
  End With
  set dirFSO = nothing
End Function

sub DisplayErrorInfo
    WScript.Echo "Error "&Err.Number&" ("&trim(Err.description)&")"
    Err.Clear
end sub

sub PressAnyKey(ByVal ErrNumber)
    dim sKey
    WScript.Echo ""
    if not SilentMode then 
        if ErrNumber <> 1 then 
            WScript.Echo("Script halted ("&ErrNumber&").")
        end if
        WScript.Echo("Press ENTER to exit. ")
        Do While Not WScript.StdIn.AtEndOfLine
            sKey = WScript.StdIn.Read(1)
            Loop
    end if
    Set objShell = nothing
    WScript.Quit(ErrNumber)
end sub
