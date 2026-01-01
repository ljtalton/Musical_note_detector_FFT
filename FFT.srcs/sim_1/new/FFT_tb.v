`timescale 1ns / 1ps

module tb_FFT_8point();

    // Test parameters for 8-point FFT
    localparam N_POINTS = 8;
    localparam HALF_POINTS = N_POINTS >> 1;
    localparam DATA_WIDTH = 24;
    localparam DATA_FRAC_BITS = 8;
    localparam INPUT_WIDTH = 8;
    localparam OUTPUT_WIDTH = 16;
    localparam TWIDDLE_WIDTH = 16;
    localparam PIPELINE_STAGES = $clog2(N_POINTS);
    
    // Testbench signals
    reg clk;
    reg rst;
    reg data_in_valid;
    reg [N_POINTS * INPUT_WIDTH-1:0] data_in_real;
    reg [N_POINTS * INPUT_WIDTH-1:0] data_in_imag;
    reg [HALF_POINTS * TWIDDLE_WIDTH-1:0] twiddle_real;
    reg [HALF_POINTS * TWIDDLE_WIDTH-1:0] twiddle_imag;
    wire [N_POINTS * OUTPUT_WIDTH-1:0] data_out_real;
    wire [N_POINTS * OUTPUT_WIDTH-1:0] data_out_imag;
    wire output_ready_flag;
    
    // Test data arrays (easier to work with)
    reg signed [INPUT_WIDTH-1:0] test_input_real [0:N_POINTS-1];
    reg signed [INPUT_WIDTH-1:0] test_input_imag [0:N_POINTS-1];
    wire signed [OUTPUT_WIDTH-1:0] test_output_real [0:N_POINTS-1];
    wire signed [OUTPUT_WIDTH-1:0] test_output_imag [0:N_POINTS-1];
    
    // Twiddle factor arrays (Q15 format: 1 sign + 15 fractional bits)
    reg signed [TWIDDLE_WIDTH-1:0] twiddle_cos [0:HALF_POINTS-1];
    reg signed [TWIDDLE_WIDTH-1:0] twiddle_sin [0:HALF_POINTS-1];
    
    integer i;
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 100MHz clock
    end
    
    // Connect flattened arrays to test arrays
    generate
        genvar k;
        for (k = 0; k < N_POINTS; k = k + 1) begin : array_connect
            assign test_output_real[k] = data_out_real[(k+1)*OUTPUT_WIDTH-1:k*OUTPUT_WIDTH];
            assign test_output_imag[k] = data_out_imag[(k+1)*OUTPUT_WIDTH-1:k*OUTPUT_WIDTH];
        end
    endgenerate
    
    // Flatten input arrays
    always @(*) begin
        for (i = 0; i < N_POINTS; i = i + 1) begin
            data_in_real[i*INPUT_WIDTH +: INPUT_WIDTH] = test_input_real[i];
            data_in_imag[i*INPUT_WIDTH +: INPUT_WIDTH] = test_input_imag[i];
        end
        
        for (i = 0; i < HALF_POINTS; i = i + 1) begin
            twiddle_real[i*TWIDDLE_WIDTH +: TWIDDLE_WIDTH] = twiddle_cos[i];
            twiddle_imag[i*TWIDDLE_WIDTH +: TWIDDLE_WIDTH] = twiddle_sin[i];
        end
    end
    
    // Initialize twiddle factors for 8-point FFT
    // W_8^k = cos(-2πk/8) + j*sin(-2πk/8), k = 0,1,2,3
    initial begin
        // k=0: W_8^0 = 1 + 0j
        twiddle_cos[0] = 16'h7FFF;  // cos(0) = 1.0 in Q15
        twiddle_sin[0] = 16'h0000;  // sin(0) = 0.0 in Q15
        
        // k=1: W_8^1 = cos(-π/4) + j*sin(-π/4) = 0.707 - 0.707j  
        twiddle_cos[1] = 16'h5A82;  // cos(-π/4) ≈ 0.707 in Q15
        twiddle_sin[1] = 16'hA57E;  // sin(-π/4) ≈ -0.707 in Q15
        
        // k=2: W_8^2 = cos(-π/2) + j*sin(-π/2) = 0 - 1j
        twiddle_cos[2] = 16'h0000;  // cos(-π/2) = 0.0 in Q15  
        twiddle_sin[2] = 16'h8001;  // sin(-π/2) = -1.0 in Q15
        
        // k=3: W_8^3 = cos(-3π/4) + j*sin(-3π/4) = -0.707 - 0.707j
        twiddle_cos[3] = 16'hA57E;  // cos(-3π/4) ≈ -0.707 in Q15
        twiddle_sin[3] = 16'hA57E;  // sin(-3π/4) ≈ -0.707 in Q15
    end
    
    // DUT instantiation
    FFT #(
        .N_POINTS(N_POINTS),
        .HALF_POINTS(HALF_POINTS),
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_FRAC_BITS(DATA_FRAC_BITS),
        .INPUT_WIDTH(INPUT_WIDTH),
        .OUTPUT_WIDTH(OUTPUT_WIDTH),
        .TWIDDLE_WIDTH(TWIDDLE_WIDTH),
        .PIPELINE_STAGES(PIPELINE_STAGES)
    ) dut (
        .clk(clk),
        .rst(rst),
        .data_in_valid(data_in_valid),
        .data_in_real(data_in_real),
        .data_in_imag(data_in_imag),
        //.twiddle_real(twiddle_real),
        //.twiddle_imag(twiddle_imag),
        .data_out_real(data_out_real),
        .data_out_imag(data_out_imag),
        .output_ready_flag(output_ready_flag)
    );
    
    // Test stimulus
    initial begin
        $display("8-Point FFT Testbench Starting...");
        $display("PIPELINE_STAGES = %d", PIPELINE_STAGES);
        
        // Initialize
        rst = 1;
        data_in_valid = 0;
        
        // Clear input arrays
        for (i = 0; i < N_POINTS; i = i + 1) begin
            test_input_real[i] = 0;
            test_input_imag[i] = 0;
        end
        
        // Release reset
        #50;
        rst = 0;
        #20;
        
        // Debug: Check if input data is being flattened correctly
        $display("\n=== Debug: Input Array Flattening ===");
        test_input_real[0] = 8'd32;
        for (i = 1; i < N_POINTS; i = i + 1) begin
            test_input_real[i] = 0;
            test_input_imag[i] = 0;
        end
        #1; // Wait for combinational logic
        $display("test_input_real[0] = %d", test_input_real[0]);
        $display("data_in_real[7:0] = %d", data_in_real[7:0]);
        $display("data_in_real full = %h", data_in_real);
        
        // Test Case 1: Impulse input [1,0,0,0,0,0,0,0]
        // Expected output: [1,1,1,1,1,1,1,1] (all bins have magnitude 1)
        $display("\n=== Test Case 1: Impulse Input ===");
        run_fft_test("Impulse");
        
        // Test Case 2: Two-tone signal (Bin 1 + Bin 2 frequencies)
        // Bin 1: sin(2π*1*n/8) = sin(π*n/4) - one cycle over 8 samples
        // Bin 2: sin(2π*2*n/8) = sin(π*n/2) - two cycles over 8 samples
        $display("\n=== Test Case 2: Two-Tone Signal (Bins 1+2) ===");
        test_input_real[0] = 8'd0;   // sin(0) + sin(0) = 0
        test_input_real[1] = 8'd22;  // sin(π/4) + sin(π/2) ≈ 0.707 + 1 = 1.707 * 13 ≈ 22
        test_input_real[2] = 8'd13;  // sin(π/2) + sin(π) ≈ 1 + 0 = 1 * 13 ≈ 13  
        test_input_real[3] = -8'd4;  // sin(3π/4) + sin(3π/2) ≈ 0.707 + (-1) = -0.293 * 13 ≈ -4
        test_input_real[4] = 8'd0;   // sin(π) + sin(2π) = 0
        test_input_real[5] = 8'd4;   // sin(5π/4) + sin(5π/2) ≈ -0.707 + 1 = 0.293 * 13 ≈ 4
        test_input_real[6] = -8'd13; // sin(3π/2) + sin(3π) ≈ -1 + 0 = -1 * 13 ≈ -13
        test_input_real[7] = -8'd22; // sin(7π/4) + sin(7π/2) ≈ -0.707 + (-1) = -1.707 * 13 ≈ -22
        for (i = 0; i < N_POINTS; i = i + 1) test_input_imag[i] = 0;
        run_fft_test("Two-Tone");
        
        // Test Case 3: Complex sinusoid at bin 1 (real + imaginary)
        // Real part: cos(π*n/4), Imaginary part: sin(π*n/4) 
        $display("\n=== Test Case 3: Complex Sinusoid (Bin 1) ===");
        test_input_real[0] = 8'd16;  // cos(0) = 1 * 16
        test_input_real[1] = 8'd11;  // cos(π/4) ≈ 0.707 * 16 ≈ 11
        test_input_real[2] = 8'd0;   // cos(π/2) = 0
        test_input_real[3] = -8'd11; // cos(3π/4) ≈ -0.707 * 16 ≈ -11
        test_input_real[4] = -8'd16; // cos(π) = -1 * 16
        test_input_real[5] = -8'd11; // cos(5π/4) ≈ -0.707 * 16 ≈ -11
        test_input_real[6] = 8'd0;   // cos(3π/2) = 0
        test_input_real[7] = 8'd11;  // cos(7π/4) ≈ 0.707 * 16 ≈ 11
        
        test_input_imag[0] = 8'd0;   // sin(0) = 0
        test_input_imag[1] = 8'd11;  // sin(π/4) ≈ 0.707 * 16 ≈ 11
        test_input_imag[2] = 8'd16;  // sin(π/2) = 1 * 16
        test_input_imag[3] = 8'd11;  // sin(3π/4) ≈ 0.707 * 16 ≈ 11
        test_input_imag[4] = 8'd0;   // sin(π) = 0
        test_input_imag[5] = -8'd11; // sin(5π/4) ≈ -0.707 * 16 ≈ -11
        test_input_imag[6] = -8'd16; // sin(3π/2) = -1 * 16
        test_input_imag[7] = -8'd11; // sin(7π/4) ≈ -0.707 * 16 ≈ -11
        run_fft_test("Complex Sinusoid");
        
        // Test Case 4: Three-tone complex signal  
        // Mix of DC + Bin 1 + Bin 3 with phase shifts
        $display("\n=== Test Case 4: Three-Tone Complex ===");
        test_input_real[0] = 8'd20;  // DC(8) + cos(0)(8) + cos(0)(4) = 8+8+4
        test_input_real[1] = 8'd8;   // DC(8) + cos(π/4)(8) + cos(3π/4)(4) ≈ 8+6-3 ≈ 11
        test_input_real[2] = 8'd5;   // DC(8) + cos(π/2)(8) + cos(3π/2)(4) = 8+0-4 = 4
        test_input_real[3] = 8'd2;   // DC(8) + cos(3π/4)(8) + cos(9π/4)(4) ≈ 8-6+3 ≈ 5
        test_input_real[4] = 8'd0;   // DC(8) + cos(π)(8) + cos(3π)(4) = 8-8+4 = 4
        test_input_real[5] = -8'd6;  // DC(8) + cos(5π/4)(8) + cos(15π/4)(4) ≈ 8-6-3 ≈ -1
        test_input_real[6] = -8'd4;  // DC(8) + cos(3π/2)(8) + cos(9π/2)(4) = 8+0-4 = 4
        test_input_real[7] = 8'd14;  // DC(8) + cos(7π/4)(8) + cos(21π/4)(4) ≈ 8+6+3 ≈ 17
        
        test_input_imag[0] = 8'd2;   // sin(0) + sin(0) = 0, plus small DC offset
        test_input_imag[1] = 8'd9;   // sin(π/4) + sin(3π/4) ≈ 6+3 = 9
        test_input_imag[2] = 8'd12;  // sin(π/2) + sin(3π/2) = 8-4 = 4
        test_input_imag[3] = 8'd9;   // sin(3π/4) + sin(9π/4) ≈ 6+3 = 9
        test_input_imag[4] = 8'd2;   // sin(π) + sin(3π) = 0
        test_input_imag[5] = -8'd5;  // sin(5π/4) + sin(15π/4) ≈ -6-3 = -9
        test_input_imag[6] = -8'd12; // sin(3π/2) + sin(9π/2) = -8+4 = -4
        test_input_imag[7] = -8'd5;  // sin(7π/4) + sin(21π/4) ≈ -6-3 = -9
        run_fft_test("Three-Tone Complex");
        
        // Test Case 5: Random-looking but structured data
        $display("\n=== Test Case 5: Structured 'Random' ===");
        test_input_real[0] = 8'd25;
        test_input_real[1] = -8'd12;
        test_input_real[2] = 8'd31;
        test_input_real[3] = 8'd7;
        test_input_real[4] = -8'd18;
        test_input_real[5] = 8'd44;
        test_input_real[6] = -8'd6;
        test_input_real[7] = 8'd15;
        
        test_input_imag[0] = 8'd8;
        test_input_imag[1] = 8'd22;
        test_input_imag[2] = -8'd14;
        test_input_imag[3] = 8'd33;
        test_input_imag[4] = 8'd11;
        test_input_imag[5] = -8'd27;
        test_input_imag[6] = 8'd19;
        test_input_imag[7] = -8'd9;
        run_fft_test("Structured Random");
        
        $display("\n=== All Tests Complete ===");
        $finish;
    end
    
    // Task to run FFT test
    task run_fft_test;
        input [127:0] test_name;
        integer timeout_count;
        begin
            $display("Running test: %s", test_name);
            
            // Print input
            $display("Input Real: [%d,%d,%d,%d,%d,%d,%d,%d]", 
                test_input_real[0], test_input_real[1], test_input_real[2], test_input_real[3],
                test_input_real[4], test_input_real[5], test_input_real[6], test_input_real[7]);
            $display("Input Imag: [%d,%d,%d,%d,%d,%d,%d,%d]", 
                test_input_imag[0], test_input_imag[1], test_input_imag[2], test_input_imag[3],
                test_input_imag[4], test_input_imag[5], test_input_imag[6], test_input_imag[7]);
            
            // Start FFT
            @(posedge clk);
            data_in_valid = 1;
            @(posedge clk);
            data_in_valid = 0;
            
            // Wait for completion with timeout
            timeout_count = 0;
            while (!output_ready_flag && timeout_count < 1000) begin
                @(posedge clk);
                timeout_count = timeout_count + 1;
            end
            
            if (timeout_count >= 1000) begin
                $display("ERROR: Test timed out!");
            end else begin
                $display("FFT completed in %d clock cycles", timeout_count);
                
                // Print output
                $display("Output Real: [%d,%d,%d,%d,%d,%d,%d,%d]", 
                    test_output_real[0], test_output_real[1], test_output_real[2], test_output_real[3],
                    test_output_real[4], test_output_real[5], test_output_real[6], test_output_real[7]);
                $display("Output Imag: [%d,%d,%d,%d,%d,%d,%d,%d]", 
                    test_output_imag[0], test_output_imag[1], test_output_imag[2], test_output_imag[3],
                    test_output_imag[4], test_output_imag[5], test_output_imag[6], test_output_imag[7]);
                
                // Calculate and display magnitudes
                $display("Magnitudes: [%d,%d,%d,%d,%d,%d,%d,%d]",
                    magnitude(test_output_real[0], test_output_imag[0]),
                    magnitude(test_output_real[1], test_output_imag[1]),
                    magnitude(test_output_real[2], test_output_imag[2]),
                    magnitude(test_output_real[3], test_output_imag[3]),
                    magnitude(test_output_real[4], test_output_imag[4]),
                    magnitude(test_output_real[5], test_output_imag[5]),
                    magnitude(test_output_real[6], test_output_imag[6]),
                    magnitude(test_output_real[7], test_output_imag[7]));
            end
            
            // Wait for output_ready_flag to go low
            while (output_ready_flag) begin
                @(posedge clk);
            end
            
            #100; // Gap between tests
        end
    endtask
    
    // Function to calculate rough magnitude |a + jb| ≈ max(|a|,|b|) + 0.5*min(|a|,|b|)
    function integer magnitude;
        input signed [OUTPUT_WIDTH-1:0] real_part;
        input signed [OUTPUT_WIDTH-1:0] imag_part;
        integer abs_real, abs_imag, max_val, min_val;
        begin
            abs_real = (real_part < 0) ? -real_part : real_part;
            abs_imag = (imag_part < 0) ? -imag_part : imag_part;
            max_val = (abs_real > abs_imag) ? abs_real : abs_imag;
            min_val = (abs_real < abs_imag) ? abs_real : abs_imag;
            magnitude = max_val + (min_val >> 1);  // Approximation
        end
    endfunction
    

    
    // Monitor for debugging
    initial begin
        $monitor("Time: %t, State: %d, Stage: %d, Ready: %b", 
                 $time, dut.fft_state, dut.fft_stage, output_ready_flag);
    end

endmodule
