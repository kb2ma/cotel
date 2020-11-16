## Conet provides CoAP networking via the [libcoap module](libcoap.html).
## An application runs Conet in a thread and communicates via the async
## channels in the [conet_ctx module](conet_ctx.html).
##
## Start Conet with a call to [netLoop()](conet.html#netLoop%2CConetState),
## which monitors network sockets as well as the channels to the enclosing
## application. Conet provides two services:
##
## * receive requests from a single server endpoint with either NoSec or PSK security
## * send requests to other servers, either with the secure coaps protocol or
##   with the insecure coap protocol
##
## As a CoAP server, Conet listens only for a GET request to th `/hi` resource.
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

const useWinVersion = defined(Windows) or defined(nimdoc)
when useWinVersion:
  import winlean
  # copy values from posix if not defined in winlean
  const posix_AF_UNSPEC = winlean.AF_UNSPEC
  const posix_SOCK_DGRAM = cint(2)
  const posix_AI_NUMERICHOST = cint(4)
  const posix_AF_INET = winlean.AF_INET
  const posix_AF_INET6 = winlean.AF_INET6
else:
  import posix
  const posix_AF_UNSPEC = posix.AF_UNSPEC
  const posix_SOCK_DGRAM = posix.SOCK_DGRAM
  const posix_AI_NUMERICHOST = posix.AI_NUMERICHOST
  const posix_AF_INET = posix.AF_INET
  const posix_AF_INET6 = posix.AF_INET6

import libcoap, nativesockets
import json, logging, parseutils, strformat, strutils
import conet_ctx
# Provides the core context data for conet module users to share
export conet_ctx

type
  ConetState* = ref object
    ## State for Conet; intended only for internal use
    securityMode*: SecurityMode
    listenAddr*: string
    serverPort*: int
    pskKey*: seq[char]
    pskClientId*: string

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
                    received: CPdu, id: CTxid)
                    {.exportc: "hnd_response", noconv.} =
  ## client response handler
  #oplog.log(lvlDebug, "Response received")
  var dataLen: csize_t
  var dataPtr: ptr uint8
  discard getData(received, addr dataLen, addr dataPtr)

  let codeStr = "[code $#.$#]\n" % [fmt"{received.code shr 5}",
                                    fmt"{received.code and 0x1F:>02}"]

  var dataStr = newString(dataLen)
  copyMem(addr dataStr[0], dataPtr, dataLen)
  netChan.send( CoMsg(req: "response.payload", payload: codeStr & dataStr) )

proc handleCoapLog(level: CLogLevel, message: cstring)
                   {.exportc: "hnd_log", noconv.} =
  var lvl: Level
  case level
  of LOG_EMERG, LOG_ALERT, LOG_CRIT, LOG_ERR:
    lvl = lvlError
  of LOG_WARNING:
    lvl = lvlWarn
  of LOG_NOTICE:
    lvl = lvlNotice
  of LOG_INFO:
    lvl = lvlInfo
  of LOG_DEBUG, COAP_LOG_CIPHERS:
    lvl = lvlDebug

  # strip trailing whitespace to avoid extra newline
  oplog.log(lvl, strip($message, false))

proc resolveAddress(ctx: CContext, host: string, port: string,
                    sockAddr: ptr CSockAddr) =
  ## Looks up network address info. Initializes and updates 'sockAddr'.
  ## Prefers IPv6 address, although the format of the host address should
  ## suggest the IP version.

  var hints: AddrInfo
  hints.ai_family = posix_AF_UNSPEC
  hints.ai_socktype = posix_SOCK_DGRAM
  hints.ai_flags = posix_AI_NUMERICHOST
  # Use 'info' to iterate linked list, and retain first element in 'firstInfo'.
  var info, firstInfo: ptr AddrInfo

  initAddress(sockAddr)
  let res = getaddrinfo(host, port, addr hints, firstInfo)
  info = firstInfo

  while info != nil:
    case info.ai_family
    of posix_AF_INET6:
      sockAddr.size = sizeof(SockAddr_in6).SockLen
      copyMem(addr sockAddr.`addr`.sin6, info.ai_addr, sockAddr.size)
      break
    of posix_AF_INET:
      sockAddr.size = sizeof(SockAddr_in).SockLen
      copyMem(addr sockAddr.`addr`.sin, info.ai_addr, sockAddr.size)
    else:
      discard
    info = info.ai_next

  freeaddrinfo(firstInfo)

proc sendMessage(ctx: CContext, state: ConetState, jsonStr: string) =
  ## Send a message to exercise client flow with a server.
  let reqJson = parseJson(jsonStr)

  # init server address/port
  let address = create(CSockAddr)
  let host = reqJson["remHost"].getStr()
  let port = reqJson["remPort"].getInt()
  resolveAddress(ctx, host, $port, address)

  #init session
  var session: CSession
  if getStr(reqJson["proto"]) == "coaps":
    # Assume libcoap retains PSK session, so look for it. Also assume use of
    # local interface 0.
    session = findSession(ctx, address, 0)
    if session == nil:
      session = newClientSessionPsk(ctx, nil, address, COAP_PROTO_DTLS,
                                    state.pskClientId,
                                    cast[ptr uint8](addr state.pskKey[0]),
                                    state.pskKey.len.uint)
  else:
    # proto must be 'coap'
    session = newClientSession(ctx, nil, address, COAP_PROTO_UDP)
  if session == nil:
    oplog.log(lvlError, "Can't create client session")
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
    oplog.log(lvlError, "Can't create client PDU")
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
        oplog.log(lvlError, "Can't create option list")
        return
      if insertOptlist(addr chain, optlist) == 0:
        oplog.log(lvlError, "Can't add to option chain")
        return
    pos = pos + plen + 1

  # Path may just be "/". No PDU option in that case.
  if chain == nil and uriPath != "/":
    oplog.log(lvlError, "Can't create option list")
    return
  if chain != nil and addOptlistPdu(pdu, addr chain) == 0:
    oplog.log(lvlError, "Can't create option list")
    deleteOptlist(chain)
    deletePdu(pdu)
    releaseSession(session)
    return
  deleteOptlist(chain)

  # send
  if send(session, pdu) == COAP_INVALID_TXID:
    deletePdu(pdu)


proc netLoop*(state: ConetState) =
  ## Setup server and run event loop
  oplog = newFileLogger("net.log", fmtStr="[$time] $levelname: ", bufSize=0)
  open(netChan)
  open(ctxChan)
  setLogLevel(LOG_DEBUG)
  setLogHandler(handleCoapLog)

  # init context, listen port/endpoint
  var ctx = newContext(nil)

  # CoAP server setup
  var address = create(CSockAddr)
  resolveAddress(ctx, state.listenAddr, $state.serverPort, address)

  var proto: CProto
  var secMode: string
  case state.securityMode
  of SECURITY_MODE_PSK:
    if setContextPsk(ctx, "", cast[ptr uint8](addr state.pskKey[0]),
                     state.pskKey.len.csize_t) == 0:
      oplog.log(lvlError, "Can't set context PSK")
      return
    proto = COAP_PROTO_DTLS
    secMode = "PSK"
  of SECURITY_MODE_NOSEC:
    proto = COAP_PROTO_UDP
    secMode = "NoSec"

  discard newEndpoint(ctx, address, proto)

  oplog.log(lvlInfo, "Cotel networking ", secMode, " listening on ",
            state.listenAddr, ":", $state.serverPort)

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
        send_message(ctx, state, msgTuple.msg.payload)
      of "quit":
        break
      else:
        oplog.log(lvlError, "msg not understood: " & msgTuple.msg.req)

  if ctx != nil:
    freeContext(ctx)
  oplog.log(lvlInfo, "Exiting net gracefully")
