module sky130_sram_2kbyte_1rw1r_32x512_8 (
    input wire clk0, input wire csb0, input wire web0,
    input wire [3:0] wmask0, input wire [8:0] addr0,
    input wire [31:0] din0, output reg [31:0] dout0,
    input wire clk1, input wire csb1, input wire [8:0] addr1,
    output reg [31:0] dout1
);
    reg [31:0] mem [0:511];
    integer byte_idx;

    always @(posedge clk0) begin
        if (!csb0) begin
            if (!web0) begin
                for (byte_idx = 0; byte_idx < 4; byte_idx = byte_idx + 1)
                    if (wmask0[byte_idx])
                        mem[addr0][8*byte_idx +: 8] <= din0[8*byte_idx +: 8];
            end else begin
                dout0 <= mem[addr0];
            end
        end
    end

    always @(posedge clk1)
        if (!csb1)
            dout1 <= mem[addr1];
endmodule
