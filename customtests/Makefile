# Makefile for the Apple IIgs core's custom diagnostic tests (Merlin32 65816 asm).
#
#   make                 build every test disk
#   make mmu_test        build just one (see TESTS below for the list)
#   make download-tools  fetch Merlin32 + CiderPress2 without building
#   make clean           remove built .SYSTEM files and disk images
#
# Merlin32 and CiderPress2 are downloaded on demand; they are not committed.
# blank.2mg is the bootable ProDOS template every test disk is built from.
#
# Every test here prints a PASS/FAIL verdict on screen. Tests that merely dumped
# register values for a human to eyeball were removed -- they were one-off probes
# from bug hunts (SCC read timing, DBR/PLB corruption, Y-register race) that have
# since been closed.

.DEFAULT_GOAL := all

# ============================================================================
# Toolchain
# ============================================================================
UNAME_S := $(shell uname -s)

MERLIN_ZIP = Merlin32_v1.2.zip
MERLIN_DIR = Merlin32_v1.2_b2
MERLIN_URL = https://brutaldeluxe.fr/products/crossdevtools/merlin/Merlin32_v1.2.zip

CP2_VERSION = 1.1.1

ifeq ($(UNAME_S),Darwin)
    ASM = ./$(MERLIN_DIR)/MacOS/Merlin32
    CP2_DIR = cp2_$(CP2_VERSION)_osx-x64_sc
else ifeq ($(UNAME_S),Linux)
    ASM = ./$(MERLIN_DIR)/Linux/Merlin32
    CP2_DIR = cp2_$(CP2_VERSION)_linux-x64_sc
else
    $(error Unsupported OS: $(UNAME_S). Only Darwin (macOS) and Linux are supported.)
endif

CP2_ZIP = $(CP2_DIR).zip
CP2_URL = https://github.com/fadden/CiderPress2/releases/download/v$(CP2_VERSION)/$(CP2_ZIP)
CP2 = ./$(CP2_DIR)/cp2

$(MERLIN_DIR):
	@echo "Merlin32 not found. Downloading from $(MERLIN_URL)..."
	@curl -L -o $(MERLIN_ZIP) $(MERLIN_URL)
	@unzip -q $(MERLIN_ZIP)
	@rm -f $(MERLIN_ZIP)
	@chmod +x $(ASM)
	@echo "Merlin32 installed."

$(CP2_DIR):
	@echo "CiderPress2 not found. Downloading from $(CP2_URL)..."
	@curl -L -o $(CP2_ZIP) $(CP2_URL)
	@mkdir -p $(CP2_DIR)
	@unzip -q $(CP2_ZIP) -d $(CP2_DIR)
	@rm -f $(CP2_ZIP)
	@chmod +x $(CP2)
	@echo "CiderPress2 installed."

download-merlin:
	@rm -rf $(MERLIN_DIR)
	@$(MAKE) $(MERLIN_DIR)

download-cp2:
	@rm -rf $(CP2_DIR)
	@$(MAKE) $(CP2_DIR)

download-tools: $(MERLIN_DIR) $(CP2_DIR)
	@echo "All tools downloaded."

# ============================================================================
# Test list:  <target>:<source.S>:<PRODOS.SYSTEM name>
#
#   mmu_test         MMU/shadow/language-card decode. Used by vsim/regression.sh.
#   gsqmmu_test      Shadowing/RAMWRT/aux-bank cases ported from the GSquared
#                    emulator's MMU suite -- an independent cross-check of mmu_test.
#   selftest01..0c   Launch one ROM selftest directly (01=ROM, 02=RAM, ... 0c=Sound).
#   scc_selftest     SCC register-level replica of ROM selftest 06-01.
#   scc_crosschan    SCC A-TX->B-RX / B-TX->A-RX through the real UART serializers.
#   scc_both         3-deep RX FIFO on both SCC channels.
#   adb_device_enum  ADB GLU FLUSH/TALK handshake against an absent device.
#   adb_rom_checksum ADB microcontroller ROM checksum. NOTE: the expected values
#                    are pinned to the ROM3 ADB uC ROM; this fails under ROM1.
#   floppy_rw_test   Block-level write/read/verify on 5.25" + 3.5" WOZ media.
#   time             ProDOS GET_TIME smoke check for the RTC clock driver.
# ============================================================================
TESTS = \
    mmu_test:MMU_TEST.S:MMUTEST.SYSTEM \
    gsqmmu_test:GSQMMU.S:GSQMMU.SYSTEM \
    scc_selftest:SELFTEST_SCC.S:SCCSLF.SYSTEM \
    scc_crosschan:SCC_CROSSCHAN_TEST.S:SCCCROSS.SYSTEM \
    scc_both:SCC_BOTH_CHANNELS.S:SCCBOTH.SYSTEM \
    adb_device_enum:ADB_DEVICE_ENUM.S:ADBENUM.SYSTEM \
    adb_rom_checksum:ADB_ROM_CHECKSUM.S:ADBROMCK.SYSTEM \
    floppy_rw_test:FLOPPY_RW_TEST.S:FLPTEST.SYSTEM \
    time:TIME.S:TIME.SYSTEM \
    selftest01:SELFTEST01.S:TEST01.SYSTEM \
    selftest02:SELFTEST02.S:TEST02.SYSTEM \
    selftest03:SELFTEST03.S:TEST03.SYSTEM \
    selftest04:SELFTEST04.S:TEST04.SYSTEM \
    selftest05:SELFTEST05.S:TEST05.SYSTEM \
    selftest06:SELFTEST06.S:TEST06.SYSTEM \
    selftest07:SELFTEST07.S:TEST07.SYSTEM \
    selftest08:SELFTEST08.S:TEST08.SYSTEM \
    selftest09:SELFTEST09.S:TEST09.SYSTEM \
    selftest0a:SELFTEST0A.S:TEST0A.SYSTEM \
    selftest0b:SELFTEST0B.S:TEST0B.SYSTEM \
    selftest0c:SELFTEST0C.S:TEST0C.SYSTEM

TARGETS = $(foreach t,$(TESTS),$(word 1,$(subst :, ,$(t))))
DISKS   = $(foreach t,$(TESTS),$(word 1,$(subst :, ,$(t))).2mg)
SYSTEMS = $(foreach t,$(TESTS),$(word 3,$(subst :, ,$(t))))

# ============================================================================
# Rule template: assemble the .S, then drop the .SYSTEM onto a copy of blank.2mg
#   $(1) target/disk stem   $(2) source .S   $(3) ProDOS SYSTEM filename
# ============================================================================
define TEST_RULE
$(1): $(1).2mg

$(3): $(2) | $$(MERLIN_DIR)
	$$(ASM) -V $$(MERLIN_DIR)/Library/ $$<

$(1).2mg: $(3) blank.2mg | $$(CP2_DIR)
	@echo "Building $(1).2mg..."
	@cp blank.2mg $(1).2mg
	@$$(CP2) rm $(1).2mg "BASIC.SYSTEM" 2>/dev/null || true
	@$$(CP2) add $(1).2mg "$(3)"
	@$$(CP2) sa $(1).2mg type=SYS "$(3)"
	@echo "  ready: $(1).2mg"
endef

$(foreach t,$(TESTS),$(eval $(call TEST_RULE,$(word 1,$(subst :, ,$(t))),$(word 2,$(subst :, ,$(t))),$(word 3,$(subst :, ,$(t))))))

# floppy_rw_test also needs blank WOZ media to write to (created by cp2).
floppy_rw_test: floppy_rw_525.woz floppy_rw_35.woz

floppy_rw_525.woz: | $(CP2_DIR)
	$(CP2) cdi $@ 140k prodos

floppy_rw_35.woz: | $(CP2_DIR)
	$(CP2) cdi $@ 800k prodos

# ============================================================================
all: $(TARGETS)
	@echo ""
	@echo "Built $(words $(TARGETS)) test disks."

clean:
	rm -f $(SYSTEMS) $(DISKS)
	rm -f floppy_rw_525.woz floppy_rw_35.woz
	rm -f *_Output.txt *_Symbols.txt *_FileInformation.txt

.PHONY: all clean download-merlin download-cp2 download-tools $(TARGETS)
