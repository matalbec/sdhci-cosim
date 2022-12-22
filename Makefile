all:
	ghdl -a --std=08 sdhci.vhdl sdhci_test.vhdl
	ghdl -e --std=08 sdhci_test

all_cosim:
	ghdl -a --std=08 sdhci.vhdl sdhci_cosim.vhdl
	ghdl -e --std=08 sdhci_cosim
	ghdl --vpi-compile gcc -c cosim.c -o cosim.o
	ghdl --vpi-link gcc cosim.o -o cosim.vpi

run_test: all
	ghdl -r sdhci_test --stop-time=40ns --vcd=sdhci_test.vcd

run_test_visual: run_test
	gtkwave sdhci_test.vcd

run_cosim: all_cosim
	ghdl -r sdhci_cosim --stop-time=10us --vpi=./cosim.vpi --vcd=sdhci_cosim.vcd

clean:
	rm *.o *.vpi *.cf *.vcd sdhci_test sdhci_cosim
