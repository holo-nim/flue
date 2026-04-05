## included in view_reader module with `ViewReaderType` defined as template

when not declared(ViewReaderType):
  {.fatal: "this is an include in the view_reader module".}

when defined(js):
  template jsRawSet(a, b) =
    {.emit: [a, " = ", b, ";"].}

  template `buffer=`*(reader: ViewReaderType, s: string) =
    jsRawSet(reader.bufferView, s)

  template viewed(orig): untyped {.redefine.} =
    type State = orig
    State
  template state*(reader: ViewReaderType): var ViewStateType =
    reader.statePtr[]
  template `stateSource=`*(reader: ViewReaderType, s: viewed(ViewStateType)) =
    jsRawSet(reader.statePtr, s)
  template `state=`*(reader: ViewReaderType, s: viewed(ViewStateType)) =
    reader.statePtr[] = s
else:
  template `buffer=`*(reader: ViewReaderType, s: string) =
    reader.bufferView = BufferView(data: cast[ptr UncheckedArray[char]](cstring(s)), len: s.len)

  template viewed(orig): untyped {.redefine.} =
    type State = var orig
    State

  when StateView is ptr:
    template state*(reader: ViewReaderType): var ViewStateType =
      reader.statePtr[]
    template `stateSource=`*(reader: var ViewReaderType, s: viewed(ViewStateType)) =
      reader.statePtr = addr s
    template `state=`*(reader: ViewReaderType, s: viewed(ViewStateType)) =
      reader.statePtr[] = s
  elif holoReaderUseViews:
    template state*(reader: ViewReaderType): var ViewStateType =
      reader.statePtr
    template `stateSource=`*(reader: var ViewReaderType, s: viewed(ViewStateType)) =
      reader.statePtr = s
    template `state=`*(reader: ViewReaderType, s: viewed(ViewStateType)) =
      reader.statePtr = s
  else:
    {.error: "unknown way to handle state type: " & $ReaderState.}

template bufferPos*(reader: ViewReaderType): int = reader.state.pos
template currentBuffer*(reader: ViewReaderType): untyped =
  reader.bufferView

proc startRead*(reader: var ViewReaderType, str: string) {.inline.} =
  reader.buffer = str
  startRead(reader.state)

proc peek*(reader: ViewReaderType, c: var char): bool {.inline.} =
  let nextPos = reader.bufferPos + 1
  doPeek(reader.bufferView, reader.bufferView.len, nextPos, c, result)

proc unsafePeek*(reader: ViewReaderType): char {.inline.} =
  # this is extra unsafe
  result = reader.bufferView[reader.bufferPos + 1]

proc peek*(reader: ViewReaderType, c: var char, offset: int): bool {.inline.} =
  let nextPos = reader.bufferPos + 1 + offset
  doPeek(reader.bufferView, reader.bufferView.len, nextPos, c, result)

proc unsafePeek*(reader: ViewReaderType, offset: int): char {.inline.} =
  # this is extra unsafe
  result = reader.bufferView[reader.bufferPos + 1 + offset]

proc peekCount*(reader: ViewReaderType, rune: var Rune): int {.inline.} =
  ## returns rune size if rune is peeked
  let bpos = reader.bufferPos
  if bpos + 1 < reader.bufferView.len:
    let start = reader.bufferView[bpos + 1]
    result = 0
    let b = start.byte
    var n = 0
    if b shr 5 == 0b110:
      n = 1
    elif b shr 4 == 0b1110:
      n = 2
    elif b shr 3 == 0b11110:
      n = 3
    elif b shr 2 == 0b111110:
      n = 4
    elif b shr 1 == 0b1111110:
      n = 5
    else:
      return
    if bpos + 1 + n < reader.bufferView.len:
      result = n
      fastRuneAt(reader.bufferView.toOpenArray(0, reader.bufferView.len - 1), bpos + 1, rune, doInc = false)

proc peek*(reader: ViewReaderType, rune: var Rune): bool {.inline.} =
  result = peekCount(reader, rune) != 0

template peekStrImpl(reader: ViewReaderType, cs) =
  result = false
  let n = cs.len
  let bpos = reader.bufferPos
  if bpos + n < reader.bufferView.len:
    result = true
    when nimvm:
      for i in 0 ..< n:
        cs[i] = reader.bufferView[bpos + 1 + i]
    else:
      when not holoReaderPeekStrCopyMem or defined(js) or defined(nimscript):
        for i in 0 ..< n:
          cs[i] = reader.bufferView[bpos + 1 + i]
      else:
        copyMem(addr cs[0], addr reader.bufferView[bpos + 1], n)

proc peek*(reader: ViewReaderType, cs: var openArray[char]): bool {.inline.} =
  peekStrImpl(reader, cs)

proc peek*[I](reader: ViewReaderType, cs: var array[I, char]): bool {.inline.} =
  peekStrImpl(reader, cs)

proc peekOrZero*(reader: ViewReaderType): char {.inline.} =
  if not peek(reader, result):
    result = '\0'

proc hasNext*(reader: ViewReaderType): bool {.inline.} =
  var dummy: char
  result = peek(reader, dummy)

proc hasNext*(reader: ViewReaderType, offset: int): bool {.inline.} =
  var dummy: char
  result = peek(reader, dummy, offset)

template lockBuffer*(reader: ViewReaderType) = discard

template unlockBuffer*(reader: ViewReaderType) = discard

proc unsafeNext*(reader: ViewReaderType) {.inline.} =
  reader.advance(reader.state)

proc unsafeNextBy*(reader: ViewReaderType, n: int) {.inline.} =
  reader.advanceBy(reader.state, n)

proc next*(reader: ViewReaderType, c: var char): bool {.inline.} =
  if not peek(reader, c):
    return false
  result = true
  reader.unsafeNext()

proc next*(reader: ViewReaderType, rune: var Rune): bool {.inline.} =
  let size = peekCount(reader, rune)
  if size == 0:
    return false
  result = true
  reader.unsafeNextBy(size)

proc next*(reader: ViewReaderType): bool {.inline.} =
  var dummy: char
  result = next(reader, dummy)

iterator chars*(reader: ViewReaderType): char =
  var c: char
  while reader.peek(c):
    yield c
    reader.unsafeNext()

iterator peekNext*(reader: ViewReaderType): char {.deprecated.} =
  ## deprecated alias for `chars`
  for c in chars(reader):
    yield c

proc peekMatch*(reader: ViewReaderType, c: char): bool {.inline.} =
  var c2: char
  if reader.peek(c2) and c2 == c:
    result = true
  else:
    result = false

proc nextMatch*(reader: ViewReaderType, c: char): bool {.inline.} =
  result = peekMatch(reader, c)
  if result:
    reader.unsafeNext()

proc peekMatch*(reader: ViewReaderType, c: char, offset: int): bool {.inline.} =
  let bpos = reader.bufferPos
  if bpos + 1 + offset < reader.bufferView.len:
    if c != reader.bufferView[bpos + 1 + offset]:
      return false
    result = true
  else:
    result = false

proc peekMatch*(reader: ViewReaderType, rune: Rune): bool {.inline.} =
  var rune2: Rune
  if reader.peek(rune2) and rune2 == rune:
    result = true
  else:
    result = false

proc nextMatch*(reader: ViewReaderType, rune: Rune): bool {.inline.} =
  result = peekMatch(reader, rune)
  if result:
    reader.unsafeNextBy(size(rune))

proc peekMatch*(reader: ViewReaderType, cs: set[char], c: var char): bool {.inline.} =
  if reader.peek(c) and c in cs:
    result = true
  else:
    result = false

proc nextMatch*(reader: ViewReaderType, cs: set[char], c: var char): bool {.inline.} =
  result = peekMatch(reader, cs, c)
  if result:
    reader.unsafeNext()

proc peekMatch*(reader: ViewReaderType, cs: set[char]): bool {.inline.} =
  var dummy: char
  result = reader.peekMatch(cs, dummy)

proc nextMatch*(reader: ViewReaderType, cs: set[char]): bool {.inline.} =
  var dummy: char
  result = reader.nextMatch(cs, dummy)

proc peekMatch*(reader: ViewReaderType, cs: set[char], offset: int, c: var char): bool {.inline.} =
  let bpos = reader.bufferPos
  if bpos + 1 + offset < reader.bufferView.len:
    let c2 = reader.bufferView[bpos + 1 + offset]
    if c2 in cs:
      c = c2
      return true
    result = false
  else:
    result = false

proc peekMatch*(reader: ViewReaderType, cs: set[char], offset: int): bool {.inline.} =
  var dummy: char
  result = reader.peekMatch(cs, offset, dummy)

template peekMatchStrImpl(reader: ViewReaderType, str: untyped, isStatic: bool = false) =
  let bpos = reader.bufferPos
  if bpos + str.len < reader.bufferView.len:
    when nimvm:
      for i in 0 ..< str.len:
        if str[i] != reader.bufferView[bpos + 1 + i]:
          return false
      result = true
    else:
      when not holoReaderMatchStrEqualMem or isStatic or defined(js) or defined(nimscript):
        for i in 0 ..< str.len:
          if str[i] != reader.bufferView[bpos + 1 + i]:
            return false
        result = true
      else:
        when isStatic:
          let str = str
        result = equalMem(unsafeAddr str[0], addr reader.bufferView[bpos + 1], str.len)
  else:
    result = false

proc peekMatch*(reader: ViewReaderType, str: openArray[char]): bool {.inline.} =
  peekMatchStrImpl(reader, str)

proc peekMatch*[I](reader: ViewReaderType, str: array[I, char]): bool {.inline.} =
  peekMatchStrImpl(reader, str)

proc peekMatch*(reader: ViewReaderType, str: static string): bool {.inline.} =
  # maybe make a const array
  peekMatchStrImpl(reader, str, isStatic = true)

proc nextMatch*(reader: ViewReaderType, str: openArray[char]): bool {.inline.} =
  result = peekMatch(reader, str)
  if result:
    reader.unsafeNextBy(str.len)

proc nextMatch*[I](reader: ViewReaderType, str: array[I, char]): bool {.inline.} =
  result = peekMatch(reader, str)
  if result:
    reader.unsafeNextBy(str.len)

proc nextMatch*(reader: ViewReaderType, str: static string): bool {.inline.} =
  result = peekMatch(reader, str)
  if result:
    reader.unsafeNextBy(str.len)
