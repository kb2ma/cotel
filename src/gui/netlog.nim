## View to show network log
##
## Shows up to 100 (LOG_LINES_MAX) lines at a time.
##
## Implementation Notes: ImGui's ListBox widget requires an array of C strings,
## provided by 'guiLines'. We cap the length of the array at LOG_LINES_MAX and
## store the current value in 'guiLen'. Internally gui_netlog maintains a Nim
## sequence of strings, 'logLines', that is the source for the C strings in
## guiLines. logLines includes an extra buffer of lines so it does not need
## to update the contents of guiLines with each new log entry.
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

import imgui
import json, logging, sequtils
import conet, gui/util

const
  LOG_LINES_MAX = 100
    ## max number of displayable log lines
  BUFFER_LINES_MAX = 30
    ## number of extra log lines used to buffer need to downsize 'guiLines'

let
  levelItems = ["DEBUG", "INFO", "WARN", "ERROR"]

var
  isNetlogOpen* = false
    ## Enclosing context sets this value to indicate log is visible
  logPos = 0'i64
    ## last position read in net.log
  logLines = newSeqOfCap[string](LOG_LINES_MAX + BUFFER_LINES_MAX)
    ## internal buffer of lines to feed guiLines
  guiLines: array[LOG_LINES_MAX, cstring]
    ## lines of C strings for ImGui, derived from logLInes
  guiLen = 0
    ## count of lines in guiLines; less than LOG_LINES_MAX until it fills up
  levelIndex = 0
    ## selected minimum log level
  filterChars = cast[seq[char]](@[])
    ## Characters to filter against when reading new lines in network log. For
    ## example, if filter includes 'D', debug log level messages will be
    ## excluded from display.
  isScrollToBottom = true
    ## For check box

proc initNetworkLog*(logFile: string) =
  ## Initializes network log infrastructure. Call at app startup.
  var f: File
  if open(f, logFile):
    logPos = f.getFileSize()
    f.close()
  else:
    # log may not be initialized yet
    logPos = 0

proc checkNetworkLog*(logFile: string) =
  ## Updates contents of UI widget from notification of new log entries in
  ## network log.
  var f: File
  if not open(f, logFile):
    oplog.log(lvlError, "Unable to open net log " & logFile)
    return

  try:
    let pos = f.getFileSize()
    if pos > logPos:
      # add new lines to logLines
      f.setFilePos(logPos)
      var lineText: string
      var startLen = logLines.len()
      while true:
        if not f.readLine(lineText):
          break
        # We expect a log line includes more than 12 characters, but include it
        # anyway if not to err on the verbose side.
        if (len(lineText) < 12) or not filterChars.contains(lineText[11]):
          logLines.add(lineText)
      logPos = pos

      # update guiLines with new lines
      var newLen = logLines.len()
      if newLen > startLen:
        # resize logLines if beyond line buffer limit
        if newLen >= (LOG_LINES_MAX + BUFFER_LINES_MAX):
          logLines.delete(0, newLen - LOG_LINES_MAX - 1)
          startLen = 0
          newLen = LOG_LINES_MAX
          oplog.log(lvlDebug, "Downsized line array")
        # only show most recent lines up to max
        let firstLine = max(newLen - LOG_LINES_MAX, 0).int32
        #echo(format("startLen $#, newLen $# (of $#), firstLine $#" % [fmt"{startLen}",
        #            fmt"{newLen}", fmt"{logLines.len()}", fmt"{firstLine}"]))

        guiLen = min(newLen, LOG_LINES_MAX)
        for i in 0 ..< guiLen:
          guiLines[i] = logLines[firstLine+i]
          #echo(format("guiLines $#: $#" % [fmt"{i}", fmt"{guiLines[i]}"]))
  finally:
    f.close()


proc showNetlogWindow*() =
  igSetNextWindowSize(ImVec2(x: 500, y: 300), FirstUseEver)
  igBegin("Network Log", isNetlogOpen.addr)

  # Header
  igPushStyleVar(ImGuiStyleVar.FramePadding, ImVec2(x: 4, y: 2))
  igAlignTextToFramePadding()
  igText("Log Level")
  igSameLine()
  igSetNextItemWidth(90)
  if igComboString("##level", levelIndex, levelItems):
    filterChars = @[]
    if levelIndex >= 1:
      filterChars.add('D')
    if levelIndex >= 2:
      filterChars.add('I')
    if levelIndex >= 3:
      filterChars.add('W')

  igSameLine(190)
  if igButton("Clear") or isEnterPressed():
    logLines = newSeqOfCap[string](LOG_LINES_MAX + BUFFER_LINES_MAX)
    for i in 0 ..< LOG_LINES_MAX:
      guiLines[i] = ""
  igSameLine(250)
  igText("Scroll to bottom")
  igSameLine()
  igCheckbox("##bottomCheckbox", isScrollToBottom.addr)
  igPopStyleVar()
  igSeparator()

  # List of log items
  var winSize: ImVec2
  igGetWindowContentRegionMaxNonUDT(winSize.addr)
  igItemSize(ImVec2(x:0,y:2))
  igBeginChild("NetlogChild", ImVec2(x:winSize.x, y:winSize.y - 80), false,
               HorizontalScrollbar)

  for i in 0 ..< guiLen:
    # Must use 'unformatted'. For igText() a '%' is interpreted ala 'printf'.
    igTextUnformatted(guiLines[i])
    if isScrollToBottom and i == (guiLen - 1):
      igSetScrollHereY(1f)
  igEndChild()
  igEnd()
