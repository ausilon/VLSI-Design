// Two-entry elastic FIFO with no combinational ready path from sink to source.
// A full FIFO inserts one recovery cycle after backpressure; the steady-state
// throughput remains one transfer per clock.
module elastic_fifo2 #(
    parameter WIDTH = 32
) (
    input  wire             clk,
    input  wire             resetn,
    input  wire [WIDTH-1:0] s_data,
    input  wire             s_valid,
    output wire             s_ready,
    output wire [WIDTH-1:0] m_data,
    output wire             m_valid,
    input  wire             m_ready
);
    reg [WIDTH-1:0] storage [0:1];
    reg             write_ptr;
    reg             read_ptr;
    reg [1:0]       count;

    wire push = s_valid && s_ready;
    wire pop  = m_valid && m_ready;

    assign s_ready = (count != 2);
    assign m_valid = (count != 0);
    assign m_data  = storage[read_ptr];

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            write_ptr <= 1'b0;
            read_ptr  <= 1'b0;
            count     <= 2'd0;
        end else begin
            case ({push, pop})
                2'b10: begin
                    storage[write_ptr] <= s_data;
                    write_ptr         <= ~write_ptr;
                    count             <= count + 1'b1;
                end
                2'b01: begin
                    read_ptr <= ~read_ptr;
                    count    <= count - 1'b1;
                end
                2'b11: begin
                    storage[write_ptr] <= s_data;
                    write_ptr         <= ~write_ptr;
                    read_ptr          <= ~read_ptr;
                end
                default: begin
                end
            endcase
        end
    end
endmodule
