import unittest
import typestates

suite "typestates":
  test "hello returns expected greeting":
    check hello() == "hello from typestates"

  test "version present":
    check projectVersion == "0.0.1"
