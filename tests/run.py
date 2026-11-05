#!/usr/bin/env python3
"""Prefer Lupa's Lua 5.1 runtime; no WoW client required. pip install lupa"""
from pathlib import Path
import os
os.chdir(Path(__file__).resolve().parent.parent)
from lupa.lua51 import LuaRuntime
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute(Path('tests/test.lua').read_text())
