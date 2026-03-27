const holoReaderLineColumn* {.booldefine.} = true
  ## enables/disables line column tracking by default, has very little impact on performance

const holoReaderPeekStrCopyMem* {.booldefine.} = false
  ## possible minor optimization, seems slightly slower in practice 

type
  ReadState* = object
    pos*: int
    # XXX also total byte count #4
    doLineColumn*: bool = holoReaderLineColumn
    line*, column*: int

  SomeBuffer* = typed

{.push checks: off, stacktrace: off.}

proc initReadState*(doLineColumn = holoReaderLineColumn): ReadState {.inline.} =
  result = ReadState(doLineColumn: doLineColumn)

proc startRead*(state: var ReadState) {.inline.} =
  state.pos = -1
  state.line = 1
  state.column = 1

template doPeek*(data: SomeBuffer, dataLen: int, nextPos: int, c: var char, result: var bool) =
  if nextPos < dataLen:
    c = data[nextPos]
    result = true
  else:
    result = false

{.pop.}
