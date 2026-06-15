#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: ./mth_c2hex_file.sh <source.c>"
    exit 1
fi

SOURCE=$1
BASE=$(basename "$SOURCE" .c)

# Compile
riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding \
    -Wl,--section-start=.text=0x0 -e main -o ${BASE}.elf ${SOURCE}

# Generate assembly with opcodes
riscv64-unknown-elf-objdump -d -M no-aliases ${BASE}.elf > ${BASE}.objdump

# Generate hex file for SystemVerilog
riscv64-unknown-elf-objcopy -O binary ${BASE}.elf ${BASE}.bin
hexdump -v -e '1/4 "%08x\n"' ${BASE}.bin > ${BASE}.hex

echo "Generated:"
echo "  ${BASE}.asm  - Assembly with hex opcodes"
echo "  ${BASE}.hex  - Hex file for SystemVerilog (32-bit per line)"

verilator --binary scrambler.sv  --top scrambler
./obj_dir/Vscrambler > _imem.hex
head -n -3 _imem.hex > imem.mem
rm _imem.hex