## Cotel CLI
##
## Command line interface for libcoap server and client
##
## Copyright 2020 Ken Bannister
## SPDX-License-Identifier: Apache-2.0

import json, logging, os, parseOpt, threadpool
import conet, gui_util

proc onChanMsg(msg: CoMsg) =
  case msg.req
  of "response.payload":
    echo("response: ", msg.payload)
  of "request.log":
    # Don't echo; too disruptive to CLI
    #echo("request: ", msg.payload)
    discard
  else:
    echo("chan msg not understood: ", msg.req)
  stdout.write("cli> ")

proc sendMsg() =
  var jNode = %*
    { "msgType": "NON", "uriPath": "/time",
      "proto": "coap", "remHost": "::1",
      "remPort": 5685 }
  ctxChan.send( CoMsg(req: "send_msg", payload: $jNode) )

proc main(conf: CotelConf) =
  # Configure CoAP networking and spawn in a new thread
  let conetState = ConetState(listenAddr: conf.serverAddr,
                              serverPort: conf.serverPort,
                              securityMode: conf.securityMode,
                              pskKey: conf.pskKey, pskClientId: conf.pskClientId)
  # Start network I/O (see conet.nim)
  spawn netLoop(conetState)

  # wait asynchronously for user input
  setStdIoUnbuffered()
  stdout.write("cli> ")
  var messageFlowVar = spawn stdin.readLine()

  # Serve resources until quit
  while true:
    if messageFlowVar.isReady():
      case ^messageFlowVar
      of "s":
        sendMsg()
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


# Parse command line options.
var confName = ""
var p = initOptParser()
while true:
  p.next()
  case p.kind
  of cmdEnd: break
  of cmdShortOption, cmdLongOption:
    if p.key == "c":
      if p.val == "":
        echo("Expected configuration file name")
      else:
        confName = p.val
    else:
      echo("Option ", p.key, " not understood")
  of cmdArgument:
    echo("Argument ", p.key, " not understood")

if confName == "":
  echo("Must provide configuration file")
  quit(QuitFailure)

oplog = newFileLogger("gui.log", fmtStr="[$time] $levelname: ", bufSize=0)
try:
  main(readConfFile(confName))
except:
  oplog.log(lvlError, "App failure: ", getCurrentExceptionMsg())
  quit(QuitFailure)
