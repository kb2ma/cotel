## Cotel CLI
##
## Command line interface for libcoap server and client
##
## Copyright 2020 Ken Bannister
## SPDX-License-Identifier: Apache-2.0

import os, parseOpt, threadpool, times
import conet, gui_util

proc onChanMsg(msg: CoMsg) =
  case msg.req
  of "response.payload":
    echo("response: ", msg.payload)
  of "request.log":
    # Don't echo; too disruptive to CLI
    #echo("request: ", msg.payload)
  else:
    echo("chan msg not understood: ", msg.req)
  stdout.write("cli> ")

proc cliLoop(conf: CotelConf) =
  # Start network I/O (see conet.nim)
  spawn netLoop(conf.serverPort)

  # wait asynchronously for user input
  setStdIoUnbuffered()
  stdout.write("cli> ")
  var messageFlowVar = spawn stdin.readLine()

  # Serve resources until quit
  while true:
    if messageFlowVar.isReady():
      case ^messageFlowVar
      of "s":
        ctxChan.send( CoMsg(req: "send_msg") )
      of "q":
        ctxChan.send( CoMsg(req: "quit") )
        threadpool.sync()
        break
      stdout.write("cli> ")
      messageFlowVar = spawn stdin.readLine()
    else:
      # Handle any incoming message from the conet channel
      var msgTuple = netChan.tryRecv()
      if msgTuple.dataAvailable:
        onChanMsg(msgTuple.msg)
      # wait a bit before checking again
      sleep(500)


# Parse command line options, read conf file, and start app
var confName = ""
var p = initOptParser()
while true:
  p.next()
  case p.kind
  of cmdEnd: break
  of cmdShortOption, cmdLongOption:
    if p.key == "c":
      if p.val == "":
        echo("Expected conf file name")
      else:
        confName = p.val
    else:
      echo("Option ", p.key, " not understood")
  of cmdArgument:
    echo("Argument ", p.key, " not understood")

var conf = readConfFile(confName)

cliLoop(conf)
