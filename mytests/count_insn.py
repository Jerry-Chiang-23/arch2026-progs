"""Count instructions retired by one rubik_solve call on an RV32 emulator.

Not rv32emu, and compiled with clang instead of the course's GCC, so the
numbers are an estimate. The stack is mapped at exactly 4 KiB, so a deeper
stack faults.

usage: python3 count_insn.py rubik.elf STATE [STATE...]
"""
import sys
from elftools.elf.elffile import ELFFile
from unicorn import Uc, UC_ARCH_RISCV, UC_MODE_RISCV32, UC_HOOK_BLOCK
from unicorn.riscv_const import (UC_RISCV_REG_SP, UC_RISCV_REG_RA,
                                 UC_RISCV_REG_A0, UC_RISCV_REG_A1,
                                 UC_RISCV_REG_A2)

STACK_TOP, STACK_SIZE = 0x80000, 0x1000
IO, SENTINEL = 0x90000, 0x0F000

def load(path):
    uc = Uc(UC_ARCH_RISCV, UC_MODE_RISCV32)
    with open(path, 'rb') as f:
        elf = ELFFile(f)
        entry = elf.header.e_entry
        segs = [s for s in elf.iter_segments() if s['p_type'] == 'PT_LOAD']
        lo = min(s['p_vaddr'] for s in segs) & ~0xfff
        hi = (max(s['p_vaddr'] + s['p_memsz'] for s in segs) + 0xfff) & ~0xfff
        uc.mem_map(lo, hi - lo)
        for seg in segs:
            uc.mem_write(seg['p_vaddr'], seg.data())
    uc.mem_map(STACK_TOP - STACK_SIZE, STACK_SIZE)
    uc.mem_map(IO, 0x1000)
    uc.mem_map(SENTINEL, 0x1000)
    return uc, entry

def run(uc, entry, state):
    count = [0]
    def blk(uc, addr, size, _):
        count[0] += size // 4
    h = uc.hook_add(UC_HOOK_BLOCK, blk, begin=0x10000, end=0x7ffff)
    uc.mem_write(IO, state.encode() + b'\0')
    uc.reg_write(UC_RISCV_REG_SP, STACK_TOP)
    uc.reg_write(UC_RISCV_REG_RA, SENTINEL)
    uc.reg_write(UC_RISCV_REG_A0, IO)
    uc.reg_write(UC_RISCV_REG_A1, IO + 0x100)
    uc.reg_write(UC_RISCV_REG_A2, 64)
    uc.emu_start(entry, SENTINEL)
    uc.hook_del(h)
    ret = uc.reg_read(UC_RISCV_REG_A0)
    ret = ret - (1 << 32) if ret & 0x80000000 else ret
    out = bytes(uc.mem_read(IO + 0x100, 64)).split(b'\0')[0].decode()
    return count[0], ret, out

if __name__ == '__main__':
    uc, entry = load(sys.argv[1])
    for s in sys.argv[2:]:
        n, ret, out = run(uc, entry, s)
        print(f'{n:>10} {s} {ret} {out}')
