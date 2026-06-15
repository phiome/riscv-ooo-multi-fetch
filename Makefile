PKG_FILES = $(wildcard ./src/pkg/*.sv)
SV_FILES = ${wildcard ./src/*.sv}
TB_FILES = ${wildcard ./tb/*.sv}
ALL_FILES = ${PKG_FILES} ${SV_FILES} ${TB_FILES}

all: clean
	@cp ./tests/$(FLAG)/imem.mem ./imem.mem
	@export TK_TEST=$(FLAG) 
	@make run
	@python3 check_result.py model.log tests/$(FLAG)/test.log

lint:
	@echo "Running lint checks..."
	verilator --lint-only -Wall --timing -Wno-UNUSED -Wno-MULTIDRIVEN -Wno-CASEINCOMPLETE ${ALL_FILES}

build: lint
	verilator --binary ${ALL_FILES} --top tb -j 0 --trace -Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN

run: build
	obj_dir/Vtb

build_without_konata:
	verilator --binary ${ALL_FILES} ./tb/tb.sv --top tb -j 0 --trace -Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN --trace-structs -DRUN_WITHOUT_KONATA=1

run_without_konata: build_without_konata
	obj_dir/Vtb

wave: run
	gtkwave --dark dump.vcd

check: 
	@python3 check_result.py model.log tests/$(TK_TEST)/test.log

# --- Coverage ----------------------------------------------------------------
build-cov:
	@mkdir -p logs
	verilator --binary ${SV_FILES} ./tb/tb.sv --top tb \
	    -j 0 --coverage \
	    -Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN

cov: build-cov
	cp model.log model_run.log 2>/dev/null || true
	obj_dir/Vtb +verilator+coverage+file+logs/coverage.dat
	mv model_run.log model.log 2>/dev/null || true
	verilator_coverage --write-info logs/coverage.info logs/coverage.dat
	genhtml logs/coverage.info --output-directory logs/html
	@echo "----------------------------------------------------------------"
	@echo "Coverage report generated:"
	@echo "logs/html/index.html"
	@echo "Please open the corresponding file to review the report."
	@echo "----------------------------------------------------------------"


clean:
	@echo "Cleaning temp files..."
	rm -f dump.vcd model.log konata.log
	rm -f coverage.dat
	rm -f logs/coverage.dat logs/coverage.info
	rm -rf logs/html obj_dir

.PHONY: lint build run wave check build-cov cov clean
