# FPGA Musical Note Detector

**A real-time digital signal processing system that identifies musical notes from live audio using a custom-built FFT implementation on FPGA hardware.**

As a pianist and hardware enthusiast, I wanted to understand signal processing from the ground up—not just theoretically, but by building it in actual silicon. This project implements a complete audio processing pipeline on a Nexys A7-100T FPGA, from microphone input to note detection, with a Fast Fourier Transform core designed entirely from scratch.

![Demo](assets/demo.gif) *(Coming soon)*

---

## What It Does

This system captures audio through a PDM microphone, performs real-time frequency analysis using a 512-point FFT, and identifies which musical notes are being played. The detected notes (C4 through B4) are displayed on the board's seven-segment display.

**Key Capabilities:**
- **Real-time processing**: Analyzes audio with 0.25-second windows for responsive note detection
- **High frequency resolution**: 4 Hz bins enable accurate discrimination between semitones
- **Efficient hardware design**: Custom FFT implementation optimized for FPGA resources
- **Fully configurable**: Python script generates twiddle factors for any FFT size

**Try it yourself:** Play a note on a piano near the microphone, and watch the FPGA identify it in real-time.

---

## Architecture Overview

The design implements a complete DSP pipeline across three clock domains:

### Signal Processing Pipeline

```
PDM Microphone (2.083 MHz)
    ↓
PDM to PCM Converter (1024x decimation → 2.048 kHz)
    ↓
Clock Domain Crossing (sync to 25 MHz)
    ↓
512-Point FFT Engine (custom Cooley-Tukey radix-2)
    ↓
Note Detection Logic (frequency bin analysis)
    ↓
Seven-Segment Display (100 MHz refresh)
```

### Custom FFT Implementation

The heart of this project is a **fully custom FFT core** designed with careful attention to resource efficiency and timing:

- **Algorithm**: Cooley-Tukey decimation-in-time with bit-reversed input ordering
- **Stages**: log₂(512) = 9 pipeline stages
- **Memory Architecture**: Ping-pong BRAM buffers alternate each stage, enabling in-place computation without conflicts
- **Arithmetic**: 24-bit fixed-point datapath (16 integer + 8 fractional bits), Q15 twiddle factors
- **Resource Optimization**: Single pipelined complex multiplier reused across all butterflies

#### Key Optimization: Multiplier Reuse

Rather than instantiating hundreds of multipliers (one per butterfly operation), the design **completes one complex multiplication at a time** and sequences through all required operations. This approach:

- Reduces DSP slice usage by ~100x
- Enables the design to fit on a mid-range FPGA
- Still completes a full 512-point FFT in microseconds—fast enough for real-time audio

The complex multiplier itself is **2-stage pipelined** to meet timing at 25 MHz, computing `(a + jb) × (cos + j·sin)` with proper fixed-point scaling to prevent overflow.

### Memory Architecture

The design uses **two Block RAM (BRAM) instances** in a ping-pong configuration:

- **Data Buffers** (`data_buffer`): Two 512-word × 48-bit BRAMs store complex sample pairs
  - Buffer A: Active during odd-numbered FFT stages
  - Buffer B: Active during even-numbered FFT stages
  - Ping-pong pattern eliminates read-write conflicts during butterfly operations

- **Twiddle Factor ROM** (`twiddle_bits`): 256-word × 32-bit BRAM stores precomputed FFT coefficients
  - Format: `[cos(31:16), sin(15:0)]` in Q15 fixed-point
  - Indexed by `butterfly_index × (N/2) >> stage` for proper coefficient selection

This BRAM-centric approach freed up thousands of registers compared to earlier register-based designs.

---

## What I Learned

This project took me through five major design iterations over six months:

1. **Version 1**: All combinational logic—didn't fit on FPGA, would never meet timing
2. **Version 2**: Sequential multiplier with log₂(N) × N registers—better, but still too large
3. **Version 3**: Reduced to two N-length register arrays alternating each stage
4. **Version 4**: Replaced registers with BRAM—huge resource savings
5. **Version 5**: Pipelined the multiplier—**finally met timing** ✓

### Key Challenges & Solutions

**Challenge**: Initial synthesis runs would hang indefinitely.
**Root Cause**: Multiplier created a critical path too long for the tools to resolve.
**Solution**: Added 2-stage pipeline registers around complex multiplication unit.

**Challenge**: Running out of logic resources (LUTs, flip-flops).
**Root Cause**: Trying to store all intermediate FFT data in registers.
**Solution**: Migrated to BRAM with ping-pong buffering, reusing the same memory across stages.

**Challenge**: Validating a 512-point FFT without a golden reference.
**Solution**: Built an 8-point testbench where outputs can be hand-calculated, then verified that scaling up to 512 points (parameter change only) worked identically.

### Design Insights

- **Separate datapath from control**: Clean FSM controlling when/where data flows made debugging vastly easier
- **Critical path awareness**: Every design choice considered timing impact—pipelining isn't optional at high frequencies
- **Resource efficiency matters**: FPGAs are small; reusing hardware (multipliers, BRAM) is essential for complex algorithms

---

## Design Parameters & Tradeoffs

The system is optimized for **musical note detection** with these carefully chosen parameters:

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Sample Rate | 2.048 kHz | Power-of-2 for clean decimation; sufficient for musical frequencies |
| FFT Size | 512 points | Balances resolution and update rate |
| Window Duration | 0.25 seconds | Fast enough for real-time feel, long enough for 4 Hz resolution |
| Frequency Resolution | 4 Hz | Distinguishes semitones (e.g., C4 @ 262 Hz vs. C#4 @ 277 Hz) |
| Data Precision | 24-bit (8 frac.) | 8 extra bits accommodate 9 FFT stages without overflow |
| Twiddle Precision | Q15 (16-bit) | Fits in 2 bytes for BRAM; sufficient SNR for note detection |

### Why 512 Points?

Beyond 512 points, the FFT would analyze **higher frequencies outside the musical range** rather than improving resolution on musical notes. With 2.048 kHz sampling, 512 points gives bins up to 1.024 kHz—more than enough to cover the piano's fundamental frequencies.

**Resolution vs. Speed**: These are inversely related. A 1024-point FFT would halve the update rate (0.5s windows) without improving note discrimination, while 256 points would update faster but struggle to separate adjacent semitones.

### Configurability

To change the FFT size:

1. Update `WINDOW_SIZE` parameter in `mic_FFT.v`
2. Regenerate BRAM IP cores with new depths (N and N/2 words)
3. Generate new twiddle factors using the included Python script:

```bash
python3 twiddle_generator.py 1024 -o twiddle_factors.coe
```

4. Load the new `.coe` file into the `twiddle_bits` BRAM initialization

The design scales efficiently—doubling FFT size adds one pipeline stage and doubles BRAM usage, but timing remains achievable.

---

## Results

**It works!** The most satisfying moment was connecting a microphone, playing middle C on my piano, and watching the C4 bin light up on the LEDs while all other bins stayed dark.

### Accuracy

- ✅ **Reliably distinguishes adjacent semitones** (C4 vs. C#4, etc.)
- ✅ **Responsive**: 0.25s latency feels real-time when playing notes
- ✅ **Stable**: Magnitude threshold filtering prevents false triggers from background noise

### Current Scope

The current implementation detects notes in **octave 4** (C4 through B4, 262-494 Hz). The architecture supports extension to other octaves by:
- Adjusting frequency bin mapping in the note detection logic
- Potentially increasing sample rate for higher octaves
- Using multiple FFT windows for wider range

---

## Hardware & Tools

- **FPGA Board**: Digilent Nexys A7-100T (Artix-7 XC7A100T)
- **Development Tool**: Xilinx Vivado 2024.1
- **Microphone**: PDM MEMS microphone (on-board J_MIC connector)
- **Display**: On-board seven-segment displays and LEDs

**Resource Utilization**: *(TODO: add synthesis report numbers)*

---

## Running the Project

### Prerequisites
- Xilinx Vivado 2024.1 or later
- Nexys A7-100T board
- (Optional) Python 3 for regenerating twiddle factors

### Build & Program

1. Open `FFT.xpr` in Vivado
2. Run Synthesis → Implementation → Generate Bitstream
3. Connect the Nexys A7 board via USB
4. Open Hardware Manager → Auto Connect → Program Device with `FFT.runs/impl_1/mic_FFT.bit`

### Testing

Play musical notes near the microphone and observe:
- **LEDs [8:0]**: Show magnitude of C4 frequency bin (binary)
- **Seven-Segment Displays**: Show detected note names (C, C#, D, etc.)

### Simulation

Run the 8-point FFT testbench to verify core functionality:

```
Vivado → Flow Navigator → Simulation → Run Behavioral Simulation
```

The testbench (`FFT_tb.v`) runs five test cases (impulse, two-tone, complex sinusoid, etc.) with hand-calculated expected outputs.

---

## Project Structure

```
FFT/
├── FFT.srcs/sources_1/new/
│   ├── mic_FFT.v              # Top-level: PDM interface, note detection
│   ├── FFT.v                  # Core FFT engine with ping-pong buffers
│   └── SevSegTest.v           # Seven-segment display driver
├── FFT.srcs/sources_1/ip/
│   ├── twiddle_bits/          # BRAM for twiddle factors (256×32b)
│   └── data_buffer/           # BRAM for sample storage (512×48b)
├── FFT.srcs/sim_1/new/
│   └── FFT_tb.v               # 8-point FFT testbench
├── FFT.srcs/constrs_1/
│   └── Nexys-A7-100T-Master.xdc  # Pin constraints
├── twiddle_generator.py       # Generate .coe files for any FFT size
└── CLAUDE.md                  # Technical deep-dive documentation
```

---

## Future Enhancements

If I had more time, I would:

- **Increase precision**: Expand from 8 to 15 fractional bits for better SNR
- **Expand note range**: Detect multiple octaves (C2-C6) using intelligent bin selection
- **Add confidence metric**: Implement the commented-out confidence scoring logic
- **Precise frequency output**: Enable sub-bin frequency estimation for tuning applications
- **ASIC pathway**: This design is a step toward developing FFT IP cores for mixed-signal ASICs

---

## Skills Demonstrated

This project showcases:

- **Digital Signal Processing**: Understanding FFT theory and implementing it in hardware
- **RTL Design**: Verilog coding for complex stateful systems
- **Hardware Optimization**: Resource-constrained design with BRAM reuse and multiplier sharing
- **Timing Analysis**: Pipelining strategies to meet setup/hold constraints
- **Verification**: Testbench development and validation strategies
- **System Integration**: Multi-clock-domain design, PDM interfaces, display drivers
- **Follow-Through**: Six months from concept to working hardware

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Acknowledgments

Special thanks to the digital signal processing and FPGA communities for excellent educational resources that helped me understand butterfly operations and hardware optimization techniques.

---

**Questions or suggestions?** Feel free to open an issue or reach out!

*Built with passion at the intersection of music and hardware design.*
