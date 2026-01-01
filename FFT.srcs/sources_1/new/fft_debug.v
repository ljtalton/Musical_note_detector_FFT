// Debug Stage 4: Test PDM to PCM conversion
module debug_stage4 (
    input wire clk_100mhz,
    input wire CPU_RESETN,
    output wire mic_clk,
    output wire mic_lr_sel,
    input wire mic_data,
    output wire [7:0] LED
);
    
    wire rst = ~CPU_RESETN;
    
    // Clock generation
    reg [5:0] clk_div_counter;
    reg mic_clk_reg;
    
    always @(posedge clk_100mhz or posedge rst) begin
        if (rst) begin
            clk_div_counter <= 0;
            mic_clk_reg <= 0;
        end else begin
            if (clk_div_counter >= 23) begin
                clk_div_counter <= 0;
                mic_clk_reg <= ~mic_clk_reg;
            end else begin
                clk_div_counter <= clk_div_counter + 1;
            end
        end
    end
    
    assign mic_clk = mic_clk_reg;
    assign mic_lr_sel = 1'b0;
    
    // PDM to PCM conversion with small decimation for testing
    localparam DECIMATION_FACTOR = 256;  // Small for quick response
    
    reg [8:0] pdm_counter;
    reg [$clog2(DECIMATION_FACTOR)-1:0] decimation_counter;
    reg signed [7:0] pcm_sample;
    reg pcm_valid;
    
    always @(posedge mic_clk_reg or posedge rst) begin
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
                pcm_sample <= pdm_counter - 9'd128;  // Center around zero
                pdm_counter <= 0;
                pcm_valid <= 1;
            end else begin
                pcm_valid <= 0;
            end
        end
    end
    
    // Cross to 100MHz domain
    reg signed [7:0] pcm_sample_sync1, pcm_sample_sync2;
    reg pcm_valid_sync1, pcm_valid_sync2;
    
    always @(posedge clk_100mhz or posedge rst) begin
        if (rst) begin
            pcm_sample_sync1 <= 0;
            pcm_sample_sync2 <= 0;
            pcm_valid_sync1 <= 0;
            pcm_valid_sync2 <= 0;
        end else begin
            pcm_sample_sync1 <= pcm_sample;
            pcm_sample_sync2 <= pcm_sample_sync1;
            pcm_valid_sync1 <= pcm_valid;
            pcm_valid_sync2 <= pcm_valid_sync1;
        end
    end
    
    // Display PCM value (should change with sound)
    assign LED[7:0] = pcm_sample_sync2;
    
endmodule