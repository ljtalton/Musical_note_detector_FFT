# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Xilinx Vivado FPGA project implementing a **real-time musical note detector** using Fast Fourier Transform (FFT) on a **Nexys A7-100T FPGA board**. The system captures audio from a PDM microphone, performs FFT analysis, and detects musical notes (C4-B4) displayed on seven-segment displays.

**Target Device**: Nexys A7-100T (xc7a100tcsg324-1)
**Tool**: Xilinx Vivado 2024.1

## Architecture

### System Pipeline

The design consists of three main processing stages:

1. **PDM to PCM Conversion** ([mic_FFT.v:123-153](FFT.srcs/sources_1/new/mic_FFT.v#L123-L153))
   - PDM microphone interface at 2.083 MHz (derived from 100 MHz system clock)
   - Decimation factor: 1024 (produces 2.048 kHz sample rate)
   - Output: 10-bit signed PCM samples

2. **Clock Domain Crossing** ([mic_FFT.v:155-178](FFT.srcs/sources_1/new/mic_FFT.v#L155-L178))
   - Two-stage synchronizer moves PCM data from mic_clk to 25 MHz domain
   - Edge detection on `pcm_valid` to trigger FFT input

3. **FFT Processing** ([FFT.v](FFT.srcs/sources_1/new/FFT.v))
   - Configurable N-point FFT (typically 512 points for 0.25s window)
   - Cooley-Tukey radix-2 decimation-in-time algorithm
   - Uses ping-pong BRAM buffers for in-place computation
   - Outputs frequency bins for note detection

4. **Note Detection** ([mic_FFT.v:226-288](FFT.srcs/sources_1/new/mic_FFT.v#L226-L288))
   - Compares magnitude at specific frequency bins (C4-B4)
   - Frequency resolution: 4 Hz (2048 Hz / 512 points)
   - Displays detected notes on seven-segment display via [SevSegTest.v](FFT.srcs/sources_1/imports/new/SevSegTest.v)

### FFT Core Implementation

The FFT module ([FFT.v](FFT.srcs/sources_1/new/FFT.v)) implements a **pipeline FFT** with these key features:

- **Bit-reversal input ordering**: Input samples are written to buffer using bit-reversed addresses ([FFT.v:403-411](FFT.srcs/sources_1/new/FFT.v#L403-L411))
- **Butterfly computation**: Uses complex multiplication with twiddle factors from BRAM ([FFT.v:138-151](FFT.srcs/sources_1/new/FFT.v#L138-L151))
- **Ping-pong buffering**: Two BRAM buffers alternate between read/write each stage to avoid conflicts
- **Fixed-point arithmetic**: 24-bit data path with 8 fractional bits; 16-bit Q15 twiddle factors
- **State machine**: 5-state FSM controls buffer filling, butterfly stages, and output ([FFT.v:178-401](FFT.srcs/sources_1/new/FFT.v#L178-L401))

### Xilinx IP Blocks

The project uses two Block Memory Generator IP cores:

1. **twiddle_bits** ([twiddle_bits.xci](FFT.srcs/sources_1/ip/twiddle_bits/twiddle_bits.xci))
   - Single-port RAM: 256 words × 32 bits
   - Stores FFT twiddle factors (cos + j·sin) in Q15 format
   - Initialized from COE file: `fft_twiddles.coe`
   - Read latency: 1 cycle (no output register)

2. **data_buffer** ([data_buffer.xci](FFT.srcs/sources_1/ip/data_buffer/data_buffer.xci))
   - Single-port RAM: 512 words × 48 bits
   - Stores complex data pairs (24-bit real + 24-bit imaginary)
   - Two instances used for ping-pong buffering
   - WRITE_FIRST mode

## Key Design Decisions

### Fixed-Point Precision
- **Data path**: 24 bits = 16 integer + 8 fractional bits
- **Twiddle factors**: 16 bits Q15 (1 sign + 15 fractional)
- **Complex multiplication** ([FFT.v:416-485](FFT.srcs/sources_1/new/FFT.v#L416-L485)): Handles scaling to prevent overflow after (a+jb)·(cos+j·sin)

### Frequency Mapping
Sample rate (2.048 kHz) with 512-point FFT yields 4 Hz resolution. Musical notes mapped to bins:
- `functional_window = 3.97364` Hz per bin ([mic_FFT.v:48](FFT.srcs/sources_1/new/mic_FFT.v#L48))
- Note frequencies divided by this value to get bin indices
- Example: C4 (261.63 Hz) → bin 66

### Clock Domains
- **100 MHz**: System clock, seven-segment display refresh
- **25 MHz**: FFT computation clock
- **~2.083 MHz**: PDM microphone clock (toggled every 24 cycles of 100 MHz)

## Building and Testing

### Vivado GUI Workflow

This project uses Vivado GUI (not TCL scripting). To build:

1. **Open Project**: Launch Vivado 2024.1 and open `FFT.xpr`
2. **Synthesis**: Click "Run Synthesis" or press F11
3. **Implementation**: Click "Run Implementation"
4. **Generate Bitstream**: Click "Generate Bitstream"
5. **Program Device**: Open Hardware Manager → Auto Connect → Program Device

**Output bitstream**: `FFT.runs/impl_1/mic_FFT.bit`

### Running Simulations

**Testbench**: [FFT_tb.v](FFT.srcs/sim_1/new/FFT_tb.v) - Tests 8-point FFT with various input signals

To run simulation in Vivado:
1. Open "Flow Navigator" → "Simulation" → "Run Simulation" → "Run Behavioral Simulation"
2. The testbench runs 5 test cases automatically (impulse, two-tone, complex sinusoid, etc.)
3. Waveform viewer opens automatically - look for `tb_FFT_8point` hierarchy

**Important**: The main 512-point FFT testbench may not exist; the 8-point version is for validation.

### Modifying IP Cores

To regenerate or modify IP (twiddle_bits, data_buffer):
1. In Vivado, open "IP Catalog"
2. Search for "Block Memory Generator"
3. Right-click on existing IP in "Sources" → "Re-customize IP"
4. After changes, click "Generate" to update HDL wrappers

**Twiddle factor initialization**: Edit [fft_twiddles.coe](FFT.ip_user_files/mem_init_files/fft_twiddles.coe) for different FFT sizes. Format is 32-bit hex: `[cos(31:16), sin(15:0)]` in Q15.

### Constraints

**Pin assignments**: [Nexys-A7-100T-Master.xdc](FFT.srcs/constrs_1/imports/digilent-xdc-master/Nexys-A7-100T-Master.xdc)

Critical pins:
- `clk_100mhz`: E3
- `CPU_RESETN`: Active-low reset button
- `mic_clk`, `mic_data`, `mic_lr_sel`: PDM microphone interface (J_MIC on schematic)
- `LED[8:0]`: Displays C4 bin magnitude
- `CA-CG`, `AN[7:0]`: Seven-segment display outputs

### Changing FFT Parameters

To change FFT size (e.g., from 512 to 1024 points):

1. Update `WINDOW_SIZE` parameter in [mic_FFT.v:12](FFT.srcs/sources_1/new/mic_FFT.v#L12)
2. Update `N_POINTS` in FFT module instantiation [mic_FFT.v:197](FFT.srcs/sources_1/new/mic_FFT.v#L197)
3. Regenerate `data_buffer` IP with new depth (N_POINTS words)
4. Regenerate `twiddle_bits` IP with new depth (N_POINTS/2 words)
5. Update twiddle factor COE file for new size (requires Python/MATLAB script)

## Common Issues

### Timing Violations
The complex multiplication ([FFT.v:138-151](FFT.srcs/sources_1/new/FFT.v#L138-L151)) has 2-cycle latency. If timing fails, consider:
- Adding pipeline registers in the butterfly datapath
- Reducing clock frequency (modify `clk_25mhz` divider in [mic_FFT.v:106-121](FFT.srcs/sources_1/new/mic_FFT.v#L106-L121))
- Using DSP48 slices for multiplication (Vivado should infer automatically)

### FFT Output Verification
- **Magnitude calculation**: [mic_FFT.v:291-321](FFT.srcs/sources_1/new/mic_FFT.v#L291-L321) uses alpha-max-plus-beta-min approximation
- **Scaling**: FFT output is scaled by N_POINTS; divide by 512 for normalized magnitude
- **Bin symmetry**: Real input produces conjugate-symmetric output; only bins 0 to N/2 are meaningful

### PDM Microphone Issues
- Ensure `mic_clk` frequency is within microphone spec (typically 1-3.2 MHz)
- Check `mic_lr_sel` is tied correctly (0 = left channel)
- PDM counter may saturate; ensure `pdm_counter` width matches decimation factor

## File Organization

**Source hierarchy**:
- `FFT.srcs/sources_1/new/`: RTL design files (FFT.v, mic_FFT.v)
- `FFT.srcs/sources_1/ip/`: Xilinx IP cores (data_buffer, twiddle_bits)
- `FFT.srcs/sim_1/new/`: Testbenches
- `FFT.srcs/constrs_1/`: Constraint files (.xdc)

**Generated files** (do not edit manually):
- `FFT.gen/sources_1/ip/`: Generated IP HDL wrappers
- `FFT.runs/synth_1/`: Synthesis outputs
- `FFT.runs/impl_1/`: Implementation outputs, including `.bit` file
- `FFT.cache/`: Vivado cache (can be safely deleted)

## Notes on Seven-Segment Display

The [SevSegConvert](FFT.srcs/sources_1/imports/new/SevSegTest.v#L23) module displays musical notes (C, C#, D, etc.) on the board's displays. The mapping in `BCDmatch` function ([SevSegTest.v:123-163](FFT.srcs/sources_1/imports/new/SevSegTest.v#L123-L163)) converts note numbers (1-12) to letter representations.

**Current behavior**: Displays up to 4 detected notes simultaneously on 4 digits.
