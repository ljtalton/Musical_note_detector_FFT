`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/13/2024 11:15:28 AM
// Design Name: 
// Module Name: SevSegTest
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


module SevSegConvert(
    input clk,
    input [15:0] SW,
    output CA,
    output CB,
    output CC,
    output CD,
    output CE,
    output CF,
    output CG,
    output [7:0] AN
    );
    
    wire [6:0] Cout;     
    wire [31:0] BCDnum;
    
    assign CA = Cout[0];
    assign CB = Cout[1];
    assign CC = Cout[2];
    assign CD = Cout[3];
    assign CE = Cout[4];
    assign CF = Cout[5];
    assign CG = Cout[6];
    
    //bin2BCD(clk, SW | 26'b0, BCDnum);
    printScreen(clk, SW, AN, Cout);
    
endmodule

module bin2BCD(
    input clk,
    input [25:0] binIn,
    output reg [31:0] BCDout
    );
    
    reg [31:0] temp_bcd;
    reg [25:0] num1, binInCopy;
    reg [4:0] count;
    reg data_changed;
    
    always@(posedge clk) begin 
    data_changed <= (binIn != binInCopy);

    if (data_changed) begin
        num1 <= binIn;
        BCDout <= 32'b0;
        count <= 5'b0;
        binInCopy <= binIn;
    end
    else if(count < 26) begin
        // Create temporary value for digit adjustments
        temp_bcd = BCDout;  // Use blocking for immediate update
        
        // Adjust digits
        if (temp_bcd[31:28] >= 5) temp_bcd[31:28] = temp_bcd[31:28] + 3;
        if (temp_bcd[27:24] >= 5) temp_bcd[27:24] = temp_bcd[27:24] + 3;
        if (temp_bcd[23:20] >= 5) temp_bcd[23:20] = temp_bcd[23:20] + 3;
        if (temp_bcd[19:16] >= 5) temp_bcd[19:16] = temp_bcd[19:16] + 3;
        if (temp_bcd[15:12] >= 5) temp_bcd[15:12] = temp_bcd[15:12] + 3;
        if (temp_bcd[11:8] >= 5) temp_bcd[11:8] = temp_bcd[11:8] + 3;
        if (temp_bcd[7:4] >= 5) temp_bcd[7:4] = temp_bcd[7:4] + 3;
        if (temp_bcd[3:0] >= 5) temp_bcd[3:0] = temp_bcd[3:0] + 3;
        
        // Single assignment to BCDout with shift
        BCDout <= {temp_bcd[30:0], num1[25]};
        num1 <= {num1[24:0], 1'b0};
        count <= count + 1;
    end
end
endmodule

module printScreen(
    // Takes 8 hex values and displays them
    input clk,
    input [15:0] in16,
    output reg [7:0] A,
    output [6:0] Cout
    );
    
    reg [16:0] count;
    reg [3:0] Iout;
    
    assign Cout = ~BCDmatch(Iout);
    
    always@ (posedge clk) begin
        // cycle through 8 displays quickly and display number for each
        count <= count + 1;
        case (count[16:14])
            0: begin A <= 8'b11111110; Iout <= in16[3:0]; end
            1: begin A <= 8'b11111101; end //Iout <= in32[7:4]; end
            2: begin A <= 8'b11111011; Iout <= in16[7:4]; end
            3: begin A <= 8'b11110111; end //Iout <= in32[15:12]; end
            4: begin A <= 8'b11101111; Iout <= in16[11:8]; end
            5: begin A <= 8'b11011111; end //Iout <= in32[23:20]; end
            6: begin A <= 8'b10111111; Iout <= in16[15:12]; end
            7: begin A <= 8'b01111111; end //Iout <= in32[31:28]; end
            default: begin end
        endcase
    end
    
    function [6:0] BCDmatch;
        // Matches hex numbers to seven segment LED outputs
        input [3:0] BCD1;
        
        if (!count[14]) begin
            case (BCD1)
                0: BCDmatch = 7'b0001000;
                1: BCDmatch = 7'b0001000;
                2: BCDmatch = 7'b1110110;
                3: BCDmatch = 7'b0001000;
                4: BCDmatch = 7'b1110110;
                5: BCDmatch = 7'b0001000;
                6: BCDmatch = 7'b0001000;
                7: BCDmatch = 7'b1110110;
                8: BCDmatch = 7'b0001000;
                9: BCDmatch = 7'b1110110;
                10: BCDmatch = 7'b0001000;
                11: BCDmatch = 7'b1110110;
                12: BCDmatch = 7'b0001000;
                default: BCDmatch = 7'b0000000;
            endcase
        end
        else begin
            case (BCD1)
                0: BCDmatch = 7'b0001000; // nothing
                1: BCDmatch = 7'b0111001; // c
                2: BCDmatch = 7'b0111001; // c
                3: BCDmatch = 7'b1011110; // d
                4: BCDmatch = 7'b1011110; // d
                5: BCDmatch = 7'b1111001; // e
                6: BCDmatch = 7'b1110001; // f
                7: BCDmatch = 7'b1110001; // f
                8: BCDmatch = 7'b0111101; // g
                9: BCDmatch = 7'b0111101; // g
                10: BCDmatch = 7'b1110111; // a
                11: BCDmatch = 7'b1110111; // a
                12: BCDmatch = 7'b1111100; // b
                default: BCDmatch = 7'b0001000;         
            endcase
        end
    endfunction
    
endmodule