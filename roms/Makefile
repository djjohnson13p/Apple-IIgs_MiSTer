# Builds the ROM images the core needs from a MAME apple2gs.zip.
#
#   1. Drop a MAME apple2gs.zip (0.286 or compatible) into this folder.
#   2. make
#
# Produces (all git-ignored -- we cannot redistribute Apple ROM content):
#   ../vsim/boot.rom   ROM3, 256K -- MiSTer loads as ioctl_index[15:6]==0
#   ../vsim/boot1.rom  ROM1, 128K -- MiSTer loads as ioctl_index[15:6]==1
#   ../chr.mem         character ROM, read by rtl/vgc.v at elaboration
#   ../vsim/chr.mem    same file; Verilator resolves it relative to vsim/

all: roms

apple2gs.zip:
	@echo "ERROR: apple2gs.zip not found."
	@echo ""
	@echo "Place a MAME apple2gs.zip (0.286 or compatible) in this folder, then re-run make."
	@echo "We cannot redistribute Apple's ROM -- you must supply your own."
	@false

342-0077-b: apple2gs.zip
	unzip -o -j apple2gs.zip apple2gsr1/342-0077-b

341-0728: apple2gs.zip
	unzip -o -j apple2gs.zip 341-0728

341-0748: apple2gs.zip
	unzip -o -j apple2gs.zip 341-0748

# ROM3 binary (256KB): banks FC-FD (341-0728) + FE (341-0748 second half) + FF (341-0748 first half)
../vsim/boot.rom: 341-0728 341-0748
	cat 341-0728 > $@
	dd if=341-0748 bs=65536 skip=1 count=1 >> $@ 2>/dev/null
	dd if=341-0748 bs=65536 count=1 >> $@ 2>/dev/null

# ROM1 binary (128KB): banks FE-FF (342-0077-b)
../vsim/boot1.rom: 342-0077-b
	cp 342-0077-b $@

# Character ROM. gen_chr.py is self-contained (the font table is embedded in the
# script), so this needs no external emulator source. Quartus resolves vgc.v's
# "chr.mem" against the repo root and Verilator against vsim/, so we need both.
../chr.mem: ../vsim/gen_chr.py
	cd ../vsim && python3 gen_chr.py
	mv ../vsim/chr_iigs.mem $@

../vsim/chr.mem: ../chr.mem
	cp $< $@

roms: ../vsim/boot.rom ../vsim/boot1.rom ../chr.mem ../vsim/chr.mem

clean:
	rm -f 342-0077-b 341-0728 341-0748
	rm -f ../vsim/boot.rom ../vsim/boot1.rom
	rm -f ../chr.mem ../vsim/chr.mem ../vsim/chr_iigs.mem

.PHONY: all roms clean
