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
import json, logging, math, sequtils
import conet

const
  LOG_LINES_MAX = 100
    ## max number of displayable log lines
  BUFFER_LINES_MAX = 30
    ## number of extra log lines used to buffer need to downsize 'guiLines'

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
  selectedLine = 0'i32
    ## index of user selected line

proc initNetworkLog*() =
  ## Initializes network log infrastructure. Call at app startup.
  var f: File
  if open(f, "net.log"):
    logPos = f.getFileSize()
    f.close()
  else:
    # log may not be initialized yet
    logPos = 0

proc checkNetworkLog*() =
  ## Updates contents of UI widget from notification of new log entries in
  ## network log.
  var f: File
  if not open(f, "net.log"):
    oplog.log(lvlError, "Unable to open net.log")
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
  # fill entire window
  igPushStyleVar(WindowPadding, ImVec2(x: 0, y: 0))
  igBegin("Network Log", isNetlogOpen.addr)
  igPopStyleVar()

  var winSize: ImVec2
  igGetWindowContentRegionMaxNonUDT(winSize.addr)
  igSetNextItemWidth(winSize.x)

  # Calculate height of listbox in units of items. Must truncate so listbox not
  # taller than containing window due to how igListBox() works. To get bottom
  # of list box flush with bottom of window, call igListBoxHeader(). In this
  # case must fill in listbox items manually here.
  var heightInItems = winSize.y / igGetTextLineHeightWithSpacing()
  heightInItems = trunc(heightInItems) - 2
  igListBox("##netlist", selectedLine.addr, guiLines[0].addr, guiLen.int32,
            heightInItems.int32)

  igEnd()
