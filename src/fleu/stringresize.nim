import std/strbasics

when not declared(capacity):
  template capacity(s: string): int {.used.} = high(int)

{.push checks: off, stacktrace: off.}

proc smartResizeAdd*(s: var string, a: openArray[char], freeBefore: int): bool {.inline.} =
  ## adds `a` to `s`; if operation would result in resize, deletes characters
  ## before `freeBefore` and returns `true`, otherwise returns `false`
  when nimvm:
    s.add(a)
    result = false
  else:
    when not defined(nimscript) and not defined(js):
      if freeBefore != 0 and s.len + a.len > s.capacity:
        let realSLen = s.len - freeBefore
        for i in 0 ..< realSLen:
          s[i] = s[i + freeBefore]
        s.setLen(realSLen + a.len)
        for i in 0 ..< a.len:
          s[i + realSLen] = a[i]
        result = true
      else:
        s.add(a)
        result = false
    else:
      s.add(a)
      result = false

proc smartResizeAdd*(s: var string, a: char, freeBefore: int): bool {.inline.} =
  ## adds `a` to `s`; if operation would result in resize, deletes characters
  ## before `freeBefore` and returns `true`, otherwise returns `false`
  when nimvm:
    s.add(a)
    result = false
  else:
    when not defined(nimscript) and not defined(js):
      if freeBefore != 0 and s.len + 1 > s.capacity:
        let realSLen = s.len - freeBefore
        for i in 0 ..< realSLen:
          s[i] = s[i + freeBefore]
        s.setLen(realSLen + 1)
        s[realSLen] = a
        result = true
      else:
        s.add(a)
        result = false
    else:
      s.add(a)
      result = false

{.pop.}
