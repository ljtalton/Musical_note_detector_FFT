`timescale 1ns / 1ps

// Musical Note Detector with optimal parameters for semitone discrimination:
// - Sample Rate: 2.048kHz (clean power-of-2)
// - Window Size: 512 samples (0.25s window)  
// - Resolution: 4Hz (excellent for musical notes)
// - Update Rate: 4Hz (new result every 0.25s)
module mic_FFT #(
    parameter PDM_CLK_FREQ = 2097152,         // 2.097152MHz PDM clock
    parameter SAMPLE_RATE = 2048,             // 2.048kHz sample rate
    parameter DECIMATION_FACTOR = 1024,       // ~2.097152MHz / 2.048kHz (rounded)
    parameter WINDOW_SIZE = 512,              // 0.25s window (512 samples at 2.048kHz)
    parameter HALF_SIZE = WINDOW_SIZE >> 1,
    parameter NUM_NOTES = 12,                 // 12 semitones in octave
    parameter AMPLITUDE_BITS = 7,             // 7-bit amplitude precision
    parameter NOTE_OUTPUT_BITS = 4            // 4-bit note output (0-11 for C-B)
)(
    input wire clk_100mhz,               // 100MHz system clock
    input wire CPU_RESETN,
    
    // Microphone PDM interface
    output wire mic_clk,                 // 2.4MHz to microphone
    output wire mic_lr_sel,              // L/R select (tie to GND for left)
    input wire mic_data,                 // PDM data from microphone
    
    // Musical note detection outputs
    //output reg [NOTE_OUTPUT_BITS-1:0] detected_note,    // 0=C, 1=C#, 2=D, ... 11=B
    //output reg [AMPLITUDE_BITS-1:0] amplitude,          // Signal amplitude
    //output reg note_valid,                               // New note detection (every 0.25s)
    //output reg [15:0] precise_freq_x100,                // Precise frequency × 100 (4Hz resolution)
    //output reg [3:0] note_confidence,                     // Confidence level 0-15
    
    output wire [8:0] LED,
    
    output wire CA,
    output wire CB,
    output wire CC,
    output wire CD,
    output wire CE,
    output wire CF,
    output wire CG,
    output wire [7:0] AN
);

    wire rst = ~CPU_RESETN;
    
    localparam threshold = 5;
    localparam real functional_window = 3.97364;
    localparam C4 = $rtoi(261.63 / functional_window + 0.5);  // Rounds to nearest: 66
    localparam Cs4 = $rtoi(277.18 / functional_window + 0.5);
    localparam D4 = $rtoi(293.66 / functional_window + 0.5);
    localparam Ds4 = $rtoi(311.13 / functional_window + 0.5);
    localparam E4 = $rtoi(329.63 / functional_window + 0.5);
    localparam F4 = $rtoi(349.23 / functional_window + 0.5);
    localparam Fs4 = $rtoi(369.99 / functional_window + 0.5);
    localparam G4 = $rtoi(392.00 / functional_window + 0.5);
    localparam Gs4 = $rtoi(415.30 / functional_window + 0.5);
    localparam A4 = $rtoi(440.00 / functional_window + 0.5);
    localparam As4 = $rtoi(466.16 / functional_window + 0.5);
    localparam B4 = $rtoi(493.88 / functional_window + 0.5);
    
    /*
    // Note frequencies × 100 (for fixed-point arithmetic)
    localparam [15:0] NOTE_FREQS [0:NUM_NOTES-1] = '{
        26163,  // C4:  261.63Hz × 100
        27718,  // C#4: 277.18Hz × 100  
        29366,  // D4:  293.66Hz × 100
        31113,  // D#4: 311.13Hz × 100
        32963,  // E4:  329.63Hz × 100
        34923,  // F4:  349.23Hz × 100
        36999,  // F#4: 369.99Hz × 100
        39200,  // G4:  392.00Hz × 100
        41530,  // G#4: 415.30Hz × 100
        44000,  // A4:  440.00Hz × 100
        46616,  // A#4: 466.16Hz × 100
        49388   // B4:  493.88Hz × 100
    };

    // Note names for debugging (not synthesized)
    localparam string NOTE_NAMES [0:NUM_NOTES-1] = '{
        "C4", "C#4", "D4", "D#4", "E4", "F4", 
        "F#4", "G4", "G#4", "A4", "A#4", "B4"
    };
    */
    // Clock generation for 2.097152MHz microphone clock
    reg [5:0] clk_div_counter;
    reg mic_clk_reg;
    
    always @(posedge clk_100mhz or posedge rst) begin
        if (rst) begin
            clk_div_counter <= 0;
            mic_clk_reg <= 0;
        end else begin
            if (clk_div_counter >= 23) begin // ~2.083MHz
                clk_div_counter <= 0;
                mic_clk_reg <= ~mic_clk_reg;
            end else begin
                clk_div_counter <= clk_div_counter + 1;
            end
        end
    end
    
    assign mic_clk = mic_clk_reg;
    assign mic_lr_sel = 1'b0;
    
    reg [5:0] clk_div_counter_25;
    reg clk_25mhz;
    
    always @(posedge clk_100mhz or posedge rst) begin
        if (rst) begin
            clk_div_counter_25 <= 0;
            clk_25mhz <= 0;
        end else begin
            if (clk_div_counter_25 >= 1) begin // ~25MHz
                clk_div_counter_25 <= 0;
                clk_25mhz <= ~clk_25mhz;
            end else begin
                clk_div_counter_25 <= clk_div_counter_25 + 1;
            end
        end
    end

    // PDM to PCM conversion at 2.048kHz
    reg [9:0] pdm_counter;              // Count '1's in PDM stream (up to 1024)
    reg [$clog2(DECIMATION_FACTOR)-1:0] decimation_counter;
    reg signed [9:0] pcm_sample;         // 8-bit PCM output
    reg pcm_valid;
    
    always @(posedge mic_clk or posedge rst) begin
        if (rst) begin
            pdm_counter <= 0;
            decimation_counter <= 0;
            pcm_sample <= 0;
            pcm_valid <= 0;
        end else begin
            if (mic_data) begin
                pdm_counter <= pdm_counter + 1;
            end
            
            decimation_counter <= decimation_counter + 1;
            
            if (decimation_counter == DECIMATION_FACTOR - 1) begin
                decimation_counter <= 0;
                // Convert PDM count to signed PCM: avoid overflow
                // Map 0-1024 to approximately -128 to +128 (safe range)
                pcm_sample <= pdm_counter - 10'd512 + 10'd17;  // Divide by 4, then center
                pdm_counter <= 0;
                pcm_valid <= 1;
            end else begin
                pcm_valid <= 0;
            end
        end
    end
    
reg pcm_valid_sync1, pcm_valid_sync2, pcm_valid_prev;
reg signed [9:0] pcm_sample_sync;

// clock-data synchronizer
always @(posedge clk_25mhz or posedge rst) begin
    if (rst) begin
        {pcm_valid_sync2, pcm_valid_sync1} <= 2'b0;
        pcm_valid_prev <= 0;
        pcm_sample_sync <= 0;
    end else begin
        // Two-FF synchronizer for pcm_valid
        {pcm_valid_sync2, pcm_valid_sync1} <= {pcm_valid_sync1, pcm_valid};
        pcm_valid_prev <= pcm_valid_sync2;
        
        // Capture data when valid edge detected
        if (pcm_valid_sync1 && !pcm_valid_sync2) begin
            pcm_sample_sync <= pcm_sample;
        end
    end
end

// Use synchronized signals
wire pcm_valid_edge = pcm_valid_sync2 && !pcm_valid_prev;


// FFT transformation section
reg data_in_valid;
wire [31:0] complex_pair; // [x, y]
wire [7:0] data_out_real; // output data
wire [7:0] data_out_imag; // outupt data
reg [7:0] data_out_real_reg;
reg [7:0] data_out_imag_reg;
wire output_ready_flag; 
wire output_start;
reg [$clog2(WINDOW_SIZE)-1:0] out_count;
reg [1:0] output_fsm;
wire [8:0] magnitude_out;
reg [8:0] C4_out;
reg [2:0] note_count;
reg [3:0] notes_out [0:3];

FFT #(
    .N_POINTS(WINDOW_SIZE),
    .INPUT_WIDTH(8),
    .OUTPUT_WIDTH(8)
) f0 (
    .clk(clk_25mhz),
    .rst(rst),
       
    .data_in_valid(pcm_valid_edge),
    .data_in_real(pcm_sample_sync[7:0]),
    .data_in_imag(0), // flattened array
    .data_out_real(data_out_real),
    .data_out_imag(data_out_imag),
    .output_ready_flag(output_ready_flag),
    .output_start(output_start)
);

SevSegConvert S0 (
    .clk(clk_100mhz),
    .SW({notes_out[0], notes_out[1], notes_out[2], notes_out[3]}),
    .CA(CA),
    .CB(CB),
    .CC(CC),
    .CD(CD),
    .CE(CE),
    .CF(CF),
    .CG(CG),
    .AN(AN)
);

integer i;
always@(posedge clk_100mhz) begin
    if (rst) begin
        out_count <= 0;
        output_fsm <= 0;
        C4_out <= 0;
    end else begin
        if (output_start) begin
            out_count <= 0;
            output_fsm <= 0;
            note_count <= 0;
            
            for (i = 0; i < 4; i = i + 1) begin
                notes_out[i] <= 0;
            end
        end else begin
            case (output_fsm) 
                0: begin
                    if (out_count == WINDOW_SIZE-1) begin
                        output_fsm <= 2;
                    end
                    else if (output_ready_flag) begin
                        output_fsm <= 1;
                        out_count <= out_count + 1;
                        if ((magnitude_out > 3) && (note_count < 4)) begin
                            // Check all 12 note bins
                            case (out_count)
                                C4:  begin notes_out[note_count] <= 1;  note_count <= note_count + 1; end
                                Cs4: begin notes_out[note_count] <= 2;  note_count <= note_count + 1; end
                                D4:  begin notes_out[note_count] <= 3;  note_count <= note_count + 1; end
                                Ds4: begin notes_out[note_count] <= 4;  note_count <= note_count + 1; end
                                E4:  begin notes_out[note_count] <= 5;  note_count <= note_count + 1; end
                                F4:  begin notes_out[note_count] <= 6;  note_count <= note_count + 1; end
                                Fs4: begin notes_out[note_count] <= 7;  note_count <= note_count + 1; end
                                G4:  begin notes_out[note_count] <= 8;  note_count <= note_count + 1; end
                                Gs4: begin notes_out[note_count] <= 9;  note_count <= note_count + 1; end
                                A4:  begin notes_out[note_count] <= 10; note_count <= note_count + 1; end
                                As4: begin notes_out[note_count] <= 11; note_count <= note_count + 1; end
                                B4:  begin notes_out[note_count] <= 12; note_count <= note_count + 1; end
                                // No default - other bins are ignored
                            endcase
                        end
                                               
                        case (out_count) 
                            C4: begin 
                                C4_out <= magnitude_out;
                            end
                        endcase
                    end
                end
                1: begin
                    if (!output_ready_flag) begin
                        output_fsm <= 0;
                    end
                end
                2: begin
                    // Idle
                end
                default: output_fsm <= 0;
            endcase
        end
    end
end

// Fixed-width function version for use in testbenches or other modules
function [8:0] magnitude_fixed;  // 17-bit output for 16-bit inputs
    input signed [7:0] real_part;
    input signed [7:0] imag_part;
    
    // Local variables - all fixed width
    reg [7:0] abs_real, abs_imag;
    reg [7:0] max_val, min_val;
    reg [11:0] min_scaled;  // 8 + 4 extra bits for multiplication
    reg [8:0] result;
    
    begin
        // Absolute values
        abs_real = (real_part[7]) ? -real_part : real_part;
        abs_imag = (imag_part[7]) ? -imag_part : imag_part;
        
        // Max and min
        max_val = (abs_real > abs_imag) ? abs_real : abs_imag;
        min_val = (abs_real < abs_imag) ? abs_real : abs_imag;
        
        // Scale min_val by 13/32 ≈ 0.4
        min_scaled = (min_val * 13) >> 5;
        
        // Calculate final result
        result = max_val + min_scaled[7:0];
        
        // Return with overflow protection
        magnitude_fixed = (result > 9'h1FF) ? 9'h1FF : result;
    end
endfunction

assign magnitude_out = magnitude_fixed(data_out_real, data_out_imag);

assign LED[8:0] = C4_out;
//assign LED[0] = (data_out_real[C4] > THRESHOLD);

endmodule