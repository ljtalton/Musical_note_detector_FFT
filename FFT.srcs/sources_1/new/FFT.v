`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/27/2025 10:52:45 AM
// Design Name: 
// Module Name: FFT
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module FFT #(
    parameter N_POINTS = 1024,
    parameter HALF_POINTS = N_POINTS >> 1,
    parameter DATA_WIDTH = 24,
    parameter DATA_FRAC_BITS = 8,
    parameter INPUT_WIDTH = 8,
    parameter OUTPUT_WIDTH = DATA_WIDTH-DATA_FRAC_BITS,
    parameter TWIDDLE_WIDTH = 16,
    parameter PIPELINE_STAGES = $clog2(N_POINTS),
    parameter FIXED_POINT_FRAC = 15
)(
    input wire clk,
    input wire rst,
    //input wire en,
    
    //input wire start,
    //input wire inverse,
    //input wire busy,
    //input wire valid,
    //input wire done,
    
    input wire data_in_valid,
    input wire [INPUT_WIDTH-1:0] data_in_real,
    input wire [INPUT_WIDTH-1:0] data_in_imag,
    output reg [INPUT_WIDTH-1:0] data_out_real,
    output reg [INPUT_WIDTH-1:0] data_out_imag,
    output reg output_ready_flag,
    output reg output_start
    );
    
    //wire signed [DATA_WIDTH-1:0] data_real_array [0:N_POINTS-1];
    //wire signed [DATA_WIDTH-1:0] data_imag_array [0:N_POINTS-1];
    //reg signed [OUTPUT_WIDTH-1:0] result_real_array [0:N_POINTS-1];
    //reg signed [OUTPUT_WIDTH-1:0] result_imag_array [0:N_POINTS-1];
    //wire signed [TWIDDLE_WIDTH-1:0] twiddle_real_array [0:HALF_POINTS-1];
    //wire signed [TWIDDLE_WIDTH-1:0] twiddle_imag_array [0:HALF_POINTS-1];
    
    wire [TWIDDLE_WIDTH-1:0] twiddle_real;
    wire [TWIDDLE_WIDTH-1:0] twiddle_imag;
    wire [(TWIDDLE_WIDTH<<1)-1:0] complex_pair;
    
    //wire [PIPELINE_STAGES-1:0] reverse [0:N_POINTS-1];
    wire [PIPELINE_STAGES-1:0] reverse;
    
    localparam NUM_HIGH_BITS = DATA_WIDTH - INPUT_WIDTH - DATA_FRAC_BITS;
    
    /*
    // convert flat arrays into arrays
    genvar i;
    generate
        for (i = 0; i < N_POINTS; i = i + 1) begin : input_unflatten
            assign data_real_array[i] = {{NUM_HIGH_BITS{data_in_real[(i+1)*INPUT_WIDTH-1]}}, data_in_real[(i+1)*INPUT_WIDTH-1 : i*INPUT_WIDTH], {DATA_FRAC_BITS{1'b0}}};
            assign data_imag_array[i] = {{NUM_HIGH_BITS{data_in_imag[(i+1)*INPUT_WIDTH-1]}}, data_in_imag[(i+1)*INPUT_WIDTH-1 : i*INPUT_WIDTH], {DATA_FRAC_BITS{1'b0}}};
        end
        
        for (i = 0; i < N_POINTS; i = i + 1) begin : output_flatten
            assign data_out_real[(i+1)*OUTPUT_WIDTH-1 : i*OUTPUT_WIDTH] = result_real_array[i];
            assign data_out_imag[(i+1)*OUTPUT_WIDTH-1 : i*OUTPUT_WIDTH] = result_imag_array[i];
        end
    endgenerate
    */
    
    // generate all pipeline stages
    //reg signed [DATA_WIDTH-1:0] buffer_a_real [0:N_POINTS-1];
    //reg signed [DATA_WIDTH-1:0] buffer_a_imag [0:N_POINTS-1];
    //reg signed [DATA_WIDTH-1:0] buffer_b_real [0:N_POINTS-1];
    //reg signed [DATA_WIDTH-1:0] buffer_b_imag [0:N_POINTS-1];
    
    
    // new code
    reg [2:0] fft_state = 0, fft_next_state;
    reg [$clog2(PIPELINE_STAGES):0] fft_stage = 1;
    reg [PIPELINE_STAGES-1:0] index, prev_index, prev_index_1;
    reg [PIPELINE_STAGES-1:0] buffer_index_a, buffer_index_b, prev_buffer_index;
    reg [PIPELINE_STAGES-1:0] butterfly_count;
    reg [PIPELINE_STAGES-1:0] nodes_count; // counts to set number of nodes per stage
    reg [PIPELINE_STAGES-1:0] init_counter;
    reg [$clog2(N_POINTS)-1:0] fill_counter;
    wire [DATA_WIDTH-1:0] cos_out, sin_out;
    wire [DATA_WIDTH-1:0] ext_in_real, ext_in_imag;
    wire [$clog2(HALF_POINTS)-1:0] twiddle_index = butterfly_count*(HALF_POINTS>>(fft_stage-1));
    wire [PIPELINE_STAGES-1:0] exp_fft_stage;
    wire use_buffer_a = (fft_stage[0] == 1); // Ping-pong between buffers each stage
    wire final_buffer_a = (PIPELINE_STAGES[0] == 1);  // Odd stages end in buffer_a
    // Select input buffer
    //wire signed [DATA_WIDTH-1:0] input_data_real = use_buffer_a ? 
    //buffer_a_real[index+exp_fft_stage] : buffer_b_real[index+exp_fft_stage];
    //wire signed [DATA_WIDTH-1:0] input_data_imag = use_buffer_a ? 
    //buffer_a_imag[index+exp_fft_stage] : buffer_b_imag[index+exp_fft_stage];
    wire signed [DATA_WIDTH-1:0] input_data_real, input_data_imag;
    wire [(DATA_WIDTH<<1)-1:0] initial_in;
    wire [(DATA_WIDTH<<1)-1:0] complex_a, complex_b;
    reg [(DATA_WIDTH<<1)-1:0] calc_2;
    reg [(DATA_WIDTH<<1)-1:0] complex_1_reg [0:2];
    wire buffer_a_wea, buffer_b_wea;
    wire wea;
    reg butt_state, init_state, out_state;
    wire [(DATA_WIDTH<<1)-1:0] buffer_din, calc_1;
    
    
    assign exp_fft_stage = (1<<(fft_stage-1));
    assign twiddle_real = complex_pair[31:16];
    assign twiddle_imag = complex_pair[15:0];
    assign ext_in_real = {{NUM_HIGH_BITS{data_in_real[INPUT_WIDTH-1]}}, data_in_real, {DATA_FRAC_BITS{1'b0}}};
    assign ext_in_imag = {{NUM_HIGH_BITS{data_in_imag[INPUT_WIDTH-1]}}, data_in_imag, {DATA_FRAC_BITS{1'b0}}};
    //assign initial_in = {data_real_array[reverse], data_imag_array[reverse]};
    assign initial_in = {ext_in_real, ext_in_imag};
    assign calc_1 = {complex_1_reg[2][(DATA_WIDTH<<1)-1:DATA_WIDTH]+cos_out, complex_1_reg[2][DATA_WIDTH-1:0]+sin_out};
    assign buffer_a_wea = (fft_state == 1) ? (init_state == 1) : (wea && !use_buffer_a);
    assign buffer_b_wea = (fft_state == 1) ? 1'b0 : (wea && use_buffer_a);
    assign buffer_din = (fft_state == 1) ? initial_in : (butt_state ? calc_2 : calc_1);
    assign wea = (fft_state == 2);
    assign input_data_real = use_buffer_a ? complex_a[(DATA_WIDTH<<1)-1:DATA_WIDTH] : complex_b[(DATA_WIDTH<<1)-1:DATA_WIDTH];
    assign input_data_imag = use_buffer_a ? complex_a[DATA_WIDTH-1:0] : complex_b[DATA_WIDTH-1:0];
    
    complex_mult #(
        .DATA_WIDTH(DATA_WIDTH),
        .TWIDDLE_WIDTH(TWIDDLE_WIDTH),
        .MULTI_OUTPUT_WIDTH(DATA_WIDTH)
        ) m0 (
        .clk(clk),
        .data_real(input_data_real),
        .data_imag(input_data_imag),
        .twiddle_cos(twiddle_real),
        .twiddle_sin(twiddle_imag),
        .result_real(cos_out),
        .result_imag(sin_out)
        //.valid_out(
    );
    
    twiddle_bits twiddle_block(
        .addra(twiddle_index), // {6'b0, twiddle_index}
        .clka(clk),
        .dina(32'b0),
        .douta(complex_pair),
        .wea(1'b0)
    );
    
    data_buffer data_buffer_a(
        .addra(buffer_index_a), // {6'b0, buffer_index_a}
        .clka(clk),
        .dina(buffer_din), // need variable
        .douta(complex_a),
        .wea(buffer_a_wea) // need variable
    );
    
    data_buffer data_buffer_b(
        .addra(buffer_index_b), 
        .clka(clk),
        .dina(buffer_din), // need variable
        .douta(complex_b),
        .wea(buffer_b_wea) // need variable
    );
    
    integer j;
    always@(posedge clk) begin
    
        complex_1_reg[2] <= complex_1_reg[1];
        complex_1_reg[1] <= complex_1_reg[0];
    
        if (rst) begin
            fft_state <= 0;
            fft_stage <= 1;
            index <= 0;
            butterfly_count <= 0;
            nodes_count <= 0;
        end else case(fft_state) 
            0: begin
                fft_state <= 1;
                fft_stage <= 1; // starts at 1
                index <= 0;
                prev_index <= 0;
                prev_index_1 <= 0;
                buffer_index_a <= 0;
                buffer_index_b <= 0;
                butterfly_count <= 0;
                nodes_count <= 0;
                output_ready_flag <= 0;
                fill_counter <= 0;
                butt_state <= 0;
                init_counter <= 0;
                init_state <= 0;
            end
            1: begin // fill buffers
                /*buffer_a_real[fill_counter] <= data_real_array[reverse];
                buffer_a_imag[fill_counter] <= data_imag_array[reverse];
                
                if (fill_counter < N_POINTS-1) begin
                    fill_counter <= fill_counter + 1;
                end else begin
                    fill_counter <= 0;
                    fft_state <= 2;
                end*/
                //initial_in <= {data_real_array[reverse], data_imag_array[reverse]};
                
                /*
                if (buffer_index_a < N_POINTS-1) begin
                    buffer_index_a <= buffer_index_a + 1;
                end
                else begin
                    buffer_index_a <= 0;
                    init_counter <= 0;
                    init_state <= 0;
                    fft_state <= 2;
                end */
                
                case (init_state) 
                    0: begin
                        if (data_in_valid) begin
                            buffer_index_a <= reverse_bits(init_counter);
                            init_state <= 1;
                        end
                    end
                    1: begin
                        if (!data_in_valid) begin
                            if (init_counter < N_POINTS-1) begin
                                init_counter <= init_counter + 1;
                            end
                            else begin
                                buffer_index_a <= 0;
                                init_counter <= 0;
                                fft_state <= 2;
                            end
                            
                            init_state <= 0;
                        end
                    end
                    default: begin
                        init_state <= 0;
                    end
                endcase
            end
            2: begin // butterfly
                case (butt_state)
                    0: begin
                        calc_2 <= {complex_1_reg[2][(DATA_WIDTH<<1)-1:DATA_WIDTH]-cos_out, complex_1_reg[2][DATA_WIDTH-1:0]-sin_out};
                        butt_state <= 1;
                        
                        if (use_buffer_a) begin
                            buffer_index_a <= index + exp_fft_stage;
                            buffer_index_b <= prev_index_1 + exp_fft_stage;
                        end else begin
                            buffer_index_b <= index + exp_fft_stage;
                            buffer_index_a <= prev_index_1 + exp_fft_stage;
                        end
                    end
                    1: begin
                        complex_1_reg[0] <= use_buffer_a ? complex_a : complex_b;
                        butt_state <= 0;
                        
                        // Next index
                        if (nodes_count == HALF_POINTS + 1) begin // maybe HALF_POINTS-1
                            if (fft_stage == PIPELINE_STAGES) begin // maybe +1
                                fft_state <= 3;
                                fft_next_state <= 3;
                                fill_counter <= 0;
                                prev_buffer_index <= 0;
                                out_state <= 0;
                                output_start <= 1;
                            end else begin
                                nodes_count <= 0;
                                butterfly_count <= 0;
                                index <= 0;
                                fft_stage <= fft_stage + 1;
                            end
                            
                            buffer_index_a <= 0;
                            buffer_index_b <= 0;
                        end else begin
                            if (butterfly_count < exp_fft_stage - 1) begin
                                butterfly_count <= butterfly_count + 1;
                                index <= index + 1;
                                if (use_buffer_a) buffer_index_a <= index + 1;
                                else buffer_index_b <= index + 1;
                            end
                            else begin
                                butterfly_count <= 0;
                                index <= index + exp_fft_stage + 1;
                                if (use_buffer_a) buffer_index_a <= index + exp_fft_stage + 1;
                                else buffer_index_b <= index + exp_fft_stage + 1;
                            end
                            
                            nodes_count <= nodes_count + 1;
                            if (use_buffer_a) buffer_index_b <= prev_index;
                            else buffer_index_a <= prev_index;
                        end 
                        
                        prev_index <= index;
                        prev_index_1 <= prev_index;
                    end
                    default: butt_state <= 0;
                endcase                  
            end
            3: begin
                case (final_buffer_a)
                    0: begin
                        case (out_state)
                            0: begin
                                if (prev_buffer_index < N_POINTS-1) begin
                                    buffer_index_a <= buffer_index_a + 1;
                                end else begin
                                    buffer_index_a <= 0;
                                    fft_next_state <= 4;
                                end
                                out_state <= 1;
                                output_ready_flag <= 1;
                                prev_buffer_index <= buffer_index_a;
                                data_out_real <= complex_a[(DATA_WIDTH<<1)-1:DATA_WIDTH] >> (DATA_WIDTH-OUTPUT_WIDTH);
                                data_out_imag <= complex_a[DATA_WIDTH-1:0] >> (DATA_WIDTH-OUTPUT_WIDTH);
                            end
                            1: begin
                                out_state <= 0;
                                output_ready_flag <= 0;
                            end
                            default: out_state <= 0;
                        endcase
                        
                        //result_real_array[prev_buffer_index] <= complex_a[(DATA_WIDTH<<1)-1:DATA_WIDTH] >> (DATA_WIDTH-OUTPUT_WIDTH);
                        //result_imag_array[prev_buffer_index] <= complex_a[DATA_WIDTH-1:0] >> (DATA_WIDTH-OUTPUT_WIDTH);
                    end
                    1: begin
                        case (out_state)
                            0: begin
                                out_state <= 1;
                                output_ready_flag <= 0;
                            end
                            1: begin
                                if (prev_buffer_index < N_POINTS-1) begin
                                    buffer_index_b <= buffer_index_b + 1;
                                end else begin
                                    buffer_index_b <= 0;
                                    fft_next_state <= 4;
                                end
                                out_state <= 0;
                                output_ready_flag <= 1;
                                prev_buffer_index <= buffer_index_b;
                                data_out_real <= complex_b[(DATA_WIDTH<<1)-1:DATA_WIDTH] >> (DATA_WIDTH-OUTPUT_WIDTH);
                                data_out_imag <= complex_b[DATA_WIDTH-1:0] >> (DATA_WIDTH-OUTPUT_WIDTH);
                            end
                            default: out_state <= 0;
                        endcase
                    end
                    default: begin
                        case (out_state)
                            0: begin
                                if (prev_buffer_index < N_POINTS-1) begin
                                    buffer_index_a <= buffer_index_a + 1;
                                end else begin
                                    buffer_index_a <= 0;
                                    fft_next_state <= 4;
                                end
                                out_state <= 1;
                                output_ready_flag <= 1;
                                prev_buffer_index <= buffer_index_a;
                                data_out_real <= 0;
                                data_out_imag <= 0;
                            end
                            1: begin
                                out_state <= 0;
                                output_ready_flag <= 0;
                            end
                            default: out_state <= 0;
                        endcase
                    end
                endcase
                
                output_start <= 0;
                fft_state <= fft_next_state;
                
            end
            4: begin
                if (~data_in_valid) begin
                    fft_state <= 0;
                end
                output_ready_flag <= 0;
            end
            default: fft_state <= 0;
        endcase
    end
    
    function [PIPELINE_STAGES-1:0] reverse_bits;
        input [PIPELINE_STAGES-1:0] data;
        integer i;
        begin
            for (i = 0; i < PIPELINE_STAGES; i = i + 1) begin
                reverse_bits[i] = data[PIPELINE_STAGES-1-i];
            end
        end
    endfunction
endmodule



module complex_mult #(
    parameter DATA_WIDTH = 24,
    parameter DATA_FRAC_BITS = 8,
    
    parameter TWIDDLE_WIDTH = 16,
    parameter TWIDDLE_FRAC_BITS = TWIDDLE_WIDTH - 1,

    parameter MULTI_OUTPUT_WIDTH = 24,
    parameter OUTPUT_FRAC_BITS = 8
)(
    input wire clk,
    //input wire rst,
    //input wire enable,
    
    input wire signed [DATA_WIDTH-1:0] data_real,
    input wire signed [DATA_WIDTH-1:0] data_imag,
    
    input wire signed [TWIDDLE_WIDTH-1:0] twiddle_cos,
    input wire signed [TWIDDLE_WIDTH-1:0] twiddle_sin,
    
    output reg signed [MULTI_OUTPUT_WIDTH-1:0] result_real,
    output reg signed [MULTI_OUTPUT_WIDTH-1:0] result_imag
    
    //output wire valid_out    
);

    localparam MULTI_WIDTH = DATA_WIDTH + TWIDDLE_WIDTH;
    localparam EXTENDED_WIDTH = MULTI_WIDTH + 1; // additional for addition/subtraction
    
    localparam TOTAL_FRAC_BITS = DATA_FRAC_BITS + TWIDDLE_FRAC_BITS;
    localparam SCALE_SHIFT = TOTAL_FRAC_BITS - OUTPUT_FRAC_BITS;
    
    initial begin
        if (SCALE_SHIFT < 0) begin
            $error("Invalid scaling: output has more fractional bits than input pfoducts");
        end
        if (MULTI_OUTPUT_WIDTH < DATA_WIDTH + $clog2(2)) begin
            $warning("Output width may be too small - risk of overflow");
        end
    end
    
    
    reg signed [MULTI_WIDTH-1:0] ac, bd, ad, bc;
    wire signed [EXTENDED_WIDTH-1:0] ac_ext, bd_ext, ad_ext, bc_ext;
    wire signed [EXTENDED_WIDTH-1:0] real_unscaled, imag_unscaled;
    wire signed [MULTI_OUTPUT_WIDTH-1:0] real_scaled, imag_scaled;
    
    assign ac_ext = {{1{ac[MULTI_WIDTH-1]}}, ac};
    assign bd_ext = {{1{bd[MULTI_WIDTH-1]}}, bd};
    assign ad_ext = {{1{ad[MULTI_WIDTH-1]}}, ad};
    assign bc_ext = {{1{bc[MULTI_WIDTH-1]}}, bc};
    
    assign real_unscaled = ac_ext - bd_ext;
    assign imag_unscaled = ad_ext + bc_ext;
    
    // truncated
    assign real_scaled = real_unscaled >>> SCALE_SHIFT;
    assign imag_scaled = imag_unscaled >>> SCALE_SHIFT;
    
    always@(posedge clk) begin
        ac <= data_real * twiddle_cos;
        bd <= data_imag * twiddle_sin;
        ad <= data_real * twiddle_sin;
        bc <= data_imag * twiddle_cos;
        
        result_real <= real_scaled;
        result_imag <= imag_scaled;
    end
    
endmodule