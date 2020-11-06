## Cotel networking
##
## Runs libcoap server and client
##
## Copyright 2020 Ken Bannister
## SPDX-License-Identifier: Apache-2.0

import libcoap, posix, nativesockets
import json, logging, parseutils

type
  CoMsg* = object
    ## A REST-like message for use in a channel with the enclosing context
    req*: string
    payload*: string

var
  netChan*: Channel[CoMsg]
  ## Communication channel from conet to enclosing context
  ctxChan*: Channel[CoMsg]
  ## Communication channel from enclosing context to conet
  log {.threadvar.}: FileLogger

proc handleHi(context: CContext, resource: CResource, session: CSession,
              req: CPdu, token: CCoapString, query: CCoapString, resp: CPdu)
              {.exportc: "hnd_hi", noconv.} =
  ## server /hi GET handler; greeting
  resp.`type` = COAP_MESSAGE_ACK
  resp.code = COAP_RESPONSE_CODE_205
  discard addData(resp, 5, "Howdy")
  let remote = getAddrString(addr session.addr_info.remote.`addr`.sa)
  netChan.send( CoMsg(req: "request.log", payload: remote & " GET /hi") )

proc handleResponse(context: CContext, session: CSession, sent: CPdu,
                    received: CPdu, id: CTxid) {.exportc: "hnd_response",
                    noconv.} =
  ## client response handler
  #log.log(lvlDebug, "Response received")
  var dataLen: csize_t
  var dataPtr: ptr uint8
  discard getData(received, addr dataLen, addr dataPtr)

  var dataStr = newString(dataLen)
  copyMem(addr dataStr[0], dataPtr, dataLen)
  netChan.send( CoMsg(req: "response.payload", payload: dataStr) )


proc sendMessage(ctx: CContext, jsonStr: string) =
  ## Send a message to exercise client flow with a server
  let reqJson = parseJson(jsonStr)

  # init server address/port
  let address = create(CSockAddr)
  initAddress(address)
  try:
    let info = getAddrInfo("127.0.0.1", 5685.Port, Domain.AF_INET,
                           SockType.SOCK_DGRAM, Protocol.IPPROTO_UDP)
    address.`addr`.sin = cast[SockAddr_in](info.ai_addr[])
    freeaddrinfo(info)
  except OSError:
    log.log(lvlError, "Can't resolve server address")
    return

  #init session
  var session = newClientSession(ctx, nil, address, COAP_PROTO_UDP)
  if session == nil:
    log.log(lvlError, "Can't create client session")
    return

  # init PDU, including type and code
  var msgType: uint8
  if reqJson["msgType"].getStr() == "CON":
    msgType = COAP_MESSAGE_CON
  else:
    msgType = COAP_MESSAGE_NON

  var pdu = initPdu(msgType, COAP_REQUEST_GET.uint8, 1000'u16,
                    maxSessionPduSize(session))
  if pdu == nil:
    log.log(lvlError, "Can't create client PDU")
    releaseSession(session)
    return

  # add Uri-Path options
  let uriPath = reqJson["uriPath"].getStr()
  var pos = 0
  var chain: COptlist

  while pos < uriPath.len:
    var token: string
    let plen = parseUntil(uriPath, token, '/', pos)
    #echo("start pos: ", pos, ", token: ", token, " of len ", plen)
    if plen > 0:
      let optlist = newOptlist(COAP_OPTION_URI_PATH, token.len.csize_t,
                               cast[ptr uint8](token.cstring))
      if optlist == nil:
        log.log(lvlError, "Can't create option list")
        return
      if insertOptlist(addr chain, optlist) == 0:
        log.log(lvlError, "Can't add to option chain")
        return
    pos = pos + plen + 1

  # Path may just be "/". No PDU option in that case.
  if chain == nil and uriPath != "/":
    log.log(lvlError, "Can't create option list")
    return
  if chain != nil and addOptlistPdu(pdu, addr chain) == 0:
    log.log(lvlError, "Can't create option list")
    deleteOptlist(chain)
    deletePdu(pdu)
    releaseSession(session)
    return
  deleteOptlist(chain)

  # send
  if send(session, pdu) == COAP_INVALID_TXID:
    deletePdu(pdu)


proc netLoop*(serverPort: int) =
  ## Setup server and run event loop
  log = newFileLogger("net.log", fmtStr="[$time] $levelname: ", bufSize=0)
  open(netChan)
  open(ctxChan)

  # init context, listen port/endpoint
  var ctx = newContext(nil)

  # CoAP server setup
  var address = create(CSockAddr)
  initAddress(address)
  address.`addr`.sin.sin_family = Domain.AF_INET.cushort
  address.`addr`.sin.sin_port = posix.htons(serverPort.uint16)

  discard newEndpoint(ctx, address, COAP_PROTO_UDP)

  log.log(lvlInfo, "Cotel networking started on port ",
          posix.ntohs(address.`addr`.sin.sin_port))

  # Establish server resources and request handlers, and also the client
  # response handler.
  var r = initResource(makeStringConst("hi"), 0)
  registerHandler(r, COAP_REQUEST_GET, handleHi)
  addResource(ctx, r)
  registerResponseHandler(ctx, handleResponse)

  # Serve resources until quit
  while true:
    discard processIo(ctx, 500'u32)

    var msgTuple = ctxChan.tryRecv()
    if msgTuple.dataAvailable:
      case msgTuple.msg.req
      of "send_msg":
        send_message(ctx, msgTuple.msg.payload)
      of "quit":
        break
      else:
        log.log(lvlError, "msg not understood: " & msgTuple.msg.req)

  if ctx != nil:
    freeContext(ctx)
  log.log(lvlInfo, "Exiting net gracefully")
