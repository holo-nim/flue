import std/unicode

const holoReaderLineColumn* {.booldefine.} = true
  ## enables/disables line column tracking by default for tracked state, has very little impact on performance

const holoReaderPeekStrCopyMem* {.booldefine.} = false
  ## possible minor optimization, can be faster on reduced instruction sets

const holoReaderMatchStrEqualMem* {.booldefine.} = false
  ## possible minor optimization, can be faster on reduced instruction sets

const experimentalViewsAvailable = compiles do:
  var x: int
  let y: var int = y

const holoReaderUseViews* {.booldefine.} = experimentalViewsAvailable

type
  ReadState* = object
    pos*: int
  
  TrackedReadState* = object
    pos*: int
    doLineColumn*: bool = holoReaderLineColumn
    line*, column*: int
    # XXX also total byte count #4

  SomeReader* = typed
  SomeBuffer* = typed

{.push checks: off, stacktrace: off.}

template doLineColumn*(state: ReadState): bool = false
template line*(state: ReadState): int = -1
template column*(state: ReadState): int = -1

proc initReadState*(): ReadState {.inline.} =
  result = ReadState()

proc initReadState*(doLineColumn: bool): ReadState {.inline, deprecated: "line column option is ignored, use tracked read state".} =
  result = initReadState()

proc initTrackedReadState*(doLineColumn = holoReaderLineColumn): TrackedReadState {.inline.} =
  result = TrackedReadState()
  result.doLineColumn = doLineColumn

proc startRead*(state: var ReadState) {.inline.} =
  state.pos = -1

proc startRead*(state: var TrackedReadState) {.inline.} =
  state.pos = -1
  state.line = 1
  state.column = 1

template advance*(reader: SomeReader, state: var ReadState) =
  inc state.pos

template advance*(reader: SomeReader, state: var ReadState, last: char) =
  inc state.pos

template advance*(reader: SomeReader, state: var ReadState, last: Rune, lastSize: int) =
  inc state.pos, lastSize

template advanceBy*(reader: SomeReader, state: var ReadState, n: int) =
  inc state.pos, n

template advance*(reader: SomeReader, state: var TrackedReadState) =
  inc state.pos
  if state.doLineColumn:
    let c = reader.currentBuffer[state.pos] # or unsafePeek
    if c == '\n' or (c == '\r' and peekOrZero(reader) != '\n'):
      inc state.line
      state.column = 1
    else:
      inc state.column

template advance*(reader: SomeReader, state: var TrackedReadState, last: char) =
  inc state.pos
  if state.doLineColumn:
    if last == '\n' or (last == '\r' and peekOrZero(reader) != '\n'):
      inc state.line
      state.column = 1
    else:
      inc state.column

template advance*(reader: SomeReader, state: var TrackedReadState, last: Rune, lastSize: int) =
  inc state.pos, lastSize
  if state.doLineColumn:
    if last == Rune('\n') or (last == Rune('\r') and peekOrZero(reader) != '\n'):
      inc state.line
      state.column = 1
    else:
      inc state.column

template advanceBy*(reader: SomeReader, state: var TrackedReadState, n: int) =
  inc state.pos, n
  if state.doLineColumn:
    let newPos = state.pos
    for i in newPos - n + 1 ..< newPos:
      let c = reader.currentBuffer[i]
      if c == '\n' or (c == '\r' and reader.currentBuffer[i + 1] != '\n'):
        inc state.line
        state.column = 1
      else:
        inc state.column
    let cf = reader.currentBuffer[newPos] # or unsafePeek
    if cf == '\n' or (cf == '\r' and peekOrZero(reader) != '\n'):
      inc state.line
      state.column = 1
    else:
      inc state.column

template doPeek*(data: SomeBuffer, dataLen: int, nextPos: int, c: var char, result: var bool) =
  if nextPos < dataLen:
    c = data[nextPos]
    result = true
  else:
    result = false

{.pop.}
