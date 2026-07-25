module uart_tx (
  input wire clk,
  input wire reset,
  input wire [7:0] data_in,
  input wire tx_start,
  output reg tx,
  output reg tx_done
);

  localparam IDLE = 0, START = 1, DATA = 2, STOP = 3, DONE = 4;
  localparam CLK_PER_BIT = 16'd20;

  reg [2:0] state;
  reg [7:0] shift_reg;
  reg [2:0] bit_counter;
  reg [15:0] clk_counter;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      state <= IDLE;
      tx <= 1;
      tx_done <= 0;
      shift_reg <= 0;
      bit_counter <= 0;
      clk_counter <= 0;
    end else begin

      tx_done <= 0;

      case (state)

        IDLE: begin
          tx <= 1;
          clk_counter <= 0;
          bit_counter <= 0;

          if (tx_start) begin
            shift_reg <= data_in;
            state <= START;
          end
        end

        START: begin
          tx <= 0;

          if (clk_counter == CLK_PER_BIT - 1) begin
            clk_counter <= 0;
            state <= DATA;
          end else
            clk_counter <= clk_counter + 1;
        end

        DATA: begin
          tx <= shift_reg[bit_counter];

          if (clk_counter == CLK_PER_BIT - 1) begin
            clk_counter <= 0;

            if (bit_counter == 7)
              state <= STOP;
            else
              bit_counter <= bit_counter + 1;
          end else
            clk_counter <= clk_counter + 1;
        end

        STOP: begin
          tx <= 1;

          if (clk_counter == CLK_PER_BIT - 1) begin
            clk_counter <= 0;
            state <= DONE;
          end else
            clk_counter <= clk_counter + 1;
        end

        DONE: begin
          tx_done <= 1;
          state <= IDLE;
        end

      endcase
    end
  end

endmodule