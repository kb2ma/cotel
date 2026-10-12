## Straightforward wrapper module for libcoap. Click on the `{...}` for a proc
## to see the corresponding libcoap function name. libcoap provides
## [online documentation](https://libcoap.net/doc/reference/4.3.x/), or you
## may build it yourself from [source](https://github.com/obgm/libcoap).
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

const useWinVersion = defined(Windows) or defined(nimdoc)
when useWinVersion:
  import winlean
else:
  import posix
import nativesockets

when defined(windows):
  # vcpkg's libcoap port only builds a static library on Windows ("dllexport
  # is not supported"), so link coap-3.lib directly rather than loading a DLL.
  # The install prefix (containing include/ and lib/) is taken from
  # -d:libcoapRoot=<dir>, or else from the VCPKG_INSTALLED environment variable.
  import std/os
  const libcoapRoot {.strdefine.} = getEnv("VCPKG_INSTALLED")
  when libcoapRoot.len > 0:
    {.passC: "-I" & quoteShell(libcoapRoot / "include").}
  when defined(vcc):
    when libcoapRoot.len > 0:
      {.passL: "/LIBPATH:" & quoteShell(libcoapRoot / "lib").}
    {.passL: "coap-3.lib ws2_32.lib iphlpapi.lib".}
  else:
    when libcoapRoot.len > 0:
      {.passL: "-L" & quoteShell(libcoapRoot / "lib").}
    {.passL: "-lcoap-3 -lws2_32 -liphlpapi".}
elif defined(macosx):
  # Homebrew's libcoap. Its prefix is not on the default include or dlopen()
  # search paths, so add it explicitly; take it from -d:libcoapRoot=<dir>, or
  # else from the LIBCOAP_BREW_PREFIX/HOMEBREW_PREFIX environment variables.
  # At runtime prefer a copy bundled in Cotel.app/Contents/Frameworks.
  import std/os
  const libcoapRoot {.strdefine.} =
    if existsEnv("LIBCOAP_BREW_PREFIX"): getEnv("LIBCOAP_BREW_PREFIX")
    elif existsEnv("HOMEBREW_PREFIX"): getEnv("HOMEBREW_PREFIX")
    elif defined(arm64): "/opt/homebrew"
    else: "/usr/local"
  {.passC: "-I" & quoteShell(libcoapRoot / "include").}
  const libName = "(@executable_path/../Frameworks/|" & libcoapRoot &
                  "/lib/|)libcoap-3-openssl(.3|).dylib"
else:
  const libName = "libcoap-3-openssl.so(|.3)"

type
  CProto* = cint
  ## coap_proto_t
  COpt = uint8

  CTxid* = cint
  ## coap_mid_t

  CPduType* = cint
  ## coap_pdu_type_t

  CPduCode* = cint
  ## coap_pdu_code_t

const
  COAP_PROTO_NONE* = 0.CProto
  COAP_PROTO_UDP* = 1.CProto
  COAP_PROTO_DTLS* = 2.CProto
  COAP_PROTO_TCP* = 3.CProto
  COAP_PROTO_TLS* = 4.CProto

  # Message types
  COAP_MESSAGE_CON* = 0.CPduType
  COAP_MESSAGE_NON* = 1.CPduType
  COAP_MESSAGE_ACK* = 2.CPduType
  COAP_MESSAGE_RST* = 3.CPduType

  COAP_RESPONSE_CODE_201* = ((2 shl 5) or 1).CPduCode
  COAP_RESPONSE_CODE_202* = ((2 shl 5) or 2).CPduCode
  COAP_RESPONSE_CODE_203* = ((2 shl 5) or 3).CPduCode
  COAP_RESPONSE_CODE_204* = ((2 shl 5) or 4).CPduCode
  COAP_RESPONSE_CODE_205* = ((2 shl 5) or 5).CPduCode
  COAP_RESPONSE_CODE_400* = ((4 shl 5) or 0).CPduCode
  COAP_RESPONSE_CODE_404* = ((4 shl 5) or 4).CPduCode

  # CoAP options. Considered use of an enum, but the conet module provides a
  # table of OptionType tuples, which is a better match for application use.
  COAP_OPTION_IF_MATCH* =        1   # opaque 0-8 B
  COAP_OPTION_URI_HOST* =        3   # String 1-255 B
  COAP_OPTION_ETAG* =            4   # opaque 1-8 B
  COAP_OPTION_IF_NONE_MATCH* =   5   # empty  0 B
  COAP_OPTION_OBSERVE* =         6   # empty/uint 0 B/0-3 B
  COAP_OPTION_URI_PORT* =        7   # uint 0-2 B
  COAP_OPTION_LOCATION_PATH* =   8   # String 0-255 B
  COAP_OPTION_URI_PATH* =       11   # String 0-255 B
  COAP_OPTION_CONTENT_FORMAT* = 12   # uint 0-2 B
  COAP_OPTION_MAXAGE* =         14   # uint 0-4 B default 60 Seconds
  COAP_OPTION_URI_QUERY* =      15   # String 1-255 B
  COAP_OPTION_ACCEPT* =         17   # uint 0-2 B
  COAP_OPTION_LOCATION_QUERY* = 20   # String 0-255 B
  COAP_OPTION_BLOCK2* =         23   # uint 0-3 B
  COAP_OPTION_BLOCK1* =         27   # uint 0-3 B
  COAP_OPTION_SIZE2* =          28   # uint 0-4 B
  COAP_OPTION_PROXY_URI* =      35   # String 1-1034 B
  COAP_OPTION_PROXY_SCHEME* =   39   # String 1-255 B
  COAP_OPTION_SIZE1* =          60   # uint 0-4 B
  COAP_OPTION_NORESPONSE* =    258   # uint 0-1 B

  COAP_INVALID_TXID* = -1.CTxid
  COAP_IO_WAIT* = 0

type
  CRequestCode* = enum
    ## coap_request_t, and value is 'detail' portion of request method code
    COAP_REQUEST_GET = 1,
    COAP_REQUEST_POST,
    COAP_REQUEST_PUT,
    COAP_REQUEST_DELETE,
    COAP_REQUEST_FETCH,
    COAP_REQUEST_PATCH,
    COAP_REQUEST_IPATCH

  CResponseResult* = enum
    ## coap_response_t, returned by a CResponseHandler
    COAP_RESPONSE_FAIL,
    COAP_RESPONSE_OK

  CLogLevel* = enum
    ## coap_log_t logging levels
    LOG_EMERG,
    LOG_ALERT,
    LOG_CRIT,
    LOG_ERR,
    LOG_WARNING,
    LOG_NOTICE,
    LOG_INFO,
    LOG_DEBUG,
    COAP_LOG_CIPHERS

  CSockAddrUnion* {.union} = object
    ## Used only by CSockAddr
    sa*: SockAddr
    sin*: Sockaddr_in
    sin6*: Sockaddr_in6

  CSockAddr* {.importc: "struct coap_address_t",
              header: "<coap3/coap.h>".} = object
    ## libcoap internal socket address
    size*: SockLen
    `addr`*: CSockAddrUnion

  CStringConst* {.importc: "struct coap_str_const_t",
                 header: "<coap3/coap.h>"} = ptr object

  CBinConst* {.importc: "struct coap_bin_const_t",
              header: "<coap3/coap.h>"} = object
    ## Returned by getToken(); holds a PDU's token
    length*: csize_t
    s*: ptr uint8

  CContext* {.importc: "struct coap_context_t",
                 header: "<coap3/coap.h>"} = ptr object
    ## libcoap top-level data object; libcoap always manages heap memory

  CEndpoint* = ptr object
    ## libcoap coap_endpoint_t
    proto*: CProto

  CResource* {.importc: "struct coap_resource_t",
                 header: "<coap3/coap.h>"} = ptr object

  CSession* {.importc: "struct coap_session_t",
                 header: "<coap3/coap.h>"} = ptr object
    ## Opaque as of libcoap 3.x; use the getXxx() accessors below rather than
    ## reading fields directly.

  CPdu* {.importc: "struct coap_pdu_t",
             header: "<coap3/coap.h>"} = ptr object
    ## Opaque as of libcoap 3.x; use the getXxx()/setXxx() accessors below
    ## rather than reading/writing fields directly.

  COptlist* = ptr object

  COptFilter* {.importc: "struct coap_opt_filter_t",
               header: "<coap3/coap.h>".} = object

  COptIterator* {.importc: "coap_opt_iterator_t",
                  header: "<coap3/coap.h>".} = object
    ## Only the field the app actually reads is declared; the C header owns
    ## the rest of the (otherwise transparent) layout.
    optType* {.importc: "number".}: uint16

  CCoapBinary* = ptr object

  CCoapString* {.importc: "struct coap_string_t",
                 header: "<coap3/coap.h>"} = ptr object
    length*: csize_t
    s*: ptr uint8

  CRequestHandler* = proc (resource: CResource, session: CSession, req: CPdu,
                           query: CCoapString, resp: CPdu) {.noconv.}

  CResponseHandler* = proc (session: CSession, sent: CPdu, received: CPdu,
                            id: CTxid): CResponseResult {.noconv.}

  CLogHandler* = proc (level: CLogLevel, message: cstring) {.noconv.}

const
  COAP_OPT_ALL* = cast[ptr COptFilter](nil)

when defined(windows):
  {.push cdecl.}
else:
  {.push dynlib: libName.}
# net.h
proc freeContext*(context: CContext) {.importc: "coap_free_context".}

proc newContext*(listen_addr: ptr CSockAddr): CContext
                {.importc: "coap_new_context".}

proc newMessageId*(session: CSession): uint16
                  {.importc: "coap_new_message_id".}

proc registerResponseHandler*(context: CContext, handler: CResponseHandler)
                             {.importc: "coap_register_response_handler".}

proc send*(session: CSession, pdu: CPdu): CTxid {.importc: "coap_send".}

proc setContextPsk*(context: CContext, hint: cstring, key: ptr uint8,
                    key_len: csize_t): cint {.importc: "coap_context_set_psk".}

# coap_session.h
proc findSession*(context: CContext, remote: ptr CSockAddr,
                  if_index: cint): CSession
                 {.importc: "coap_session_get_by_peer".}

proc freeEndpoint*(ep: CEndpoint) {.importc: "coap_free_endpoint".}

proc getAddrRemote*(session: CSession): ptr CSockAddr
                   {.importc: "coap_session_get_addr_remote".}

proc getProto*(session: CSession): CProto
              {.importc: "coap_session_get_proto".}

proc maxSessionPduSize*(session: CSession): csize_t
                       {.importc: "coap_session_max_pdu_size".}

proc newClientSession*(context: CContext, local_addr: ptr CSockAddr,
                       server_addr: ptr CSockAddr, proto: CProto): CSession
                      {.importc: "coap_new_client_session".}

proc newClientSessionPsk*(context: CContext, local_addr: ptr CSockAddr,
                          server_addr: ptr CSockAddr, proto: CProto,
                          identity: cstring, key: ptr uint8,
                          key_len: uint): CSession
                         {.importc: "coap_new_client_session_psk".}

proc newEndpoint*(context: CContext, listen_addr: ptr CSockAddr,
                 proto: CProto): CEndpoint {.importc: "coap_new_endpoint".}

proc releaseSession*(session: CSession) {.importc: "coap_session_release".}

# resource.h
proc addResource*(context: CContext, resource: CResource)
                 {.importc: "coap_add_resource".}

proc initResource*(uri_path: CStringConst, flags: cint): CResource
                  {.importc: "coap_resource_init".}

proc registerHandler*(resource: CResource, `method`: CRequestCode,
                      handler: CRequestHandler)
                     {.importc: "coap_register_handler".}

# pdu.h
proc addData*(pdu: CPdu, len: csize_t, data: cstring): cint
             {.importc: "coap_add_data".}

proc addToken*(pdu: CPdu, len: csize_t, data: cstring): cint
              {.importc: "coap_add_token".}

proc deletePdu*(pdu: CPdu) {.importc: "coap_delete_pdu".}

proc getData*(pdu: CPdu, len: ptr csize_t, data: ptr ptr uint8): cint
             {.importc: "coap_get_data".}

proc initPdu*(`type`: CPduType, code: CPduCode, txid: CTxid = 0.CTxid,
             size: csize_t): CPdu
             {.importc: "coap_pdu_init".}
  ## 'type' is one of the COAP_MESSAGE... constants
  ## 'code' param value is CRequestCode for a request

proc getType*(pdu: CPdu): CPduType {.importc: "coap_pdu_get_type".}

proc setType*(pdu: CPdu, `type`: CPduType) {.importc: "coap_pdu_set_type".}

proc getCode*(pdu: CPdu): CPduCode {.importc: "coap_pdu_get_code".}

proc setCode*(pdu: CPdu, code: CPduCode) {.importc: "coap_pdu_set_code".}

proc getMid*(pdu: CPdu): CTxid {.importc: "coap_pdu_get_mid".}

proc getToken*(pdu: CPdu): CBinConst {.importc: "coap_pdu_get_token".}

# option.h
proc addOptlistPdu*(pdu: CPdu, chain: ptr COptlist): cint
                   {.importc: "coap_add_optlist_pdu".}

proc deleteOptlist*(list: COptlist) {.importc: "coap_delete_optlist".}
  ## Must delete optlist created by newOptlist

proc insertOptlist*(chain: ptr COptlist, optlist: COptlist): cint
                   {.importc: "coap_insert_optlist".}

proc newOptlist*(number: uint16, length: csize_t, data: ptr uint8): COptlist
                {.importc: "coap_new_optlist".}

proc setOptFilterSet*(filter: ptr COptFilter, number: uint16): cint
                     {.importc: "coap_option_filter_set".}

# Must set filter type as below, rather than the filter itself. The empty
# filter is defined as NULL; i.e., it treats the pointer as absent.
proc initOptIterator*(pdu: CPdu, oi: ptr COptIterator,
                      filter: ptr COptFilter): ptr COptIterator
                     {.importc: "coap_option_iterator_init".}

proc nextOption*(oi: ptr COptIterator): ptr COpt {.importc: "coap_option_next".}

proc optLength*(opt: ptr COpt): uint32 {.importc: "coap_opt_length".}

proc optValue*(opt: ptr COpt): ptr uint8 {.importc: "coap_opt_value".}

# coap_io.h
proc processIo*(context: CContext, timeout: uint32): cint
               {.importc: "coap_io_process".}

# coap_dtls.h
proc setDtlsLogLevel*(level: CLogLevel) {.importc: "coap_dtls_set_log_level".}

# address.h
proc initAddress*(address: ptr CSockAddr) {.importc: "coap_address_init".}

# str.h
proc makeStringConst*(str: cstring): CStringConst
                     {.importc: "coap_make_str_const".}

# coap_internal.h
proc encodeVarSafe*(buf: ptr uint8, length: csize_t, value: uint): cuint
                   {.importc: "coap_encode_var_safe".}

# coap_debug.h
proc setLogHandler*(handler: CLogHandler) {.importc: "coap_set_log_handler".}

proc setLogLevel*(level: CLogLevel) {.importc: "coap_set_log_level".}
{.pop.}
