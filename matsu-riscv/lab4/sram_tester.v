module sram_tester #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,

    parameter ADDR_BASE   = 32'h8000_0000,
    parameter ADDR_MASK   = 32'h007F_FFFF,
    parameter TEST_ROUNDS = 1000
) (
    input wire clk_i,
    input wire rst_i,

    input wire start,
    input wire [31:0] random_seed,

    // wishbone master
    output reg wb_cyc_o,
    output reg wb_stb_o,
    input wire wb_ack_i,
    output reg [ADDR_WIDTH-1:0] wb_adr_o,
    output reg [DATA_WIDTH-1:0] wb_dat_o,
    input wire [DATA_WIDTH-1:0] wb_dat_i,
    output reg [DATA_WIDTH/8-1:0] wb_sel_o,
    output reg wb_we_o,

    // status signals
    output reg done,
    output reg error,
    output reg [31:0] error_round,
    output reg [ADDR_WIDTH-1:0] error_addr,
    output reg [DATA_WIDTH-1:0] error_read_data,
    output reg [DATA_WIDTH-1:0] error_expected_data
);

  // Calculate RAM_ADDR_WIDTH manually (ceil(log2(ADDR_MASK)))
  // For ADDR_MASK = 32'h007F_FFFF, log2 = ~22.9, so RAM_ADDR_WIDTH = 23
  localparam RAM_ADDR_WIDTH = 23; // ceil to correct bits
  localparam ADDR_ZEROS = ADDR_WIDTH - RAM_ADDR_WIDTH;

  parameter ST_IDLE = 4'd0;
  parameter ST_WRITE = 4'd1;
  parameter ST_WRITE_ACTION = 4'd2;
  parameter ST_READ = 4'd3;
  parameter ST_READ_ACTION = 4'd4;
  parameter ST_ERROR = 4'd5;
  parameter ST_DONE = 4'd6;

  reg [31:0] count;
  reg [DATA_WIDTH-1:0] data_expected;
  wire [DATA_WIDTH-1:0] data_mask;  // mask out rng for write
  wire [DATA_WIDTH/8-1:0] read_compare;  // byte read compare result

  reg [3:0] state, state_n;

  always @(*) begin
    state_n = state;
    case (state)
      ST_IDLE: begin
        // start test sequence
        if (start) state_n = ST_WRITE;
      end

      ST_WRITE: begin
        if (count == TEST_ROUNDS) state_n = ST_READ;
        else state_n = ST_WRITE_ACTION;
      end

      ST_WRITE_ACTION: begin
        // wait for ack
        if (wb_ack_i) state_n = ST_WRITE;
      end

      ST_READ: begin
        if (count == TEST_ROUNDS) state_n = ST_DONE;
        else state_n = ST_READ_ACTION;
      end

      ST_READ_ACTION: begin
        if (wb_ack_i) begin
          if (!(&read_compare)) state_n = ST_ERROR;
          else state_n = ST_READ;
        end
      end

      ST_ERROR: begin
        state_n = ST_ERROR;
      end

      ST_DONE: begin
        state_n = ST_DONE;
      end

      default: begin
        state_n = ST_IDLE;
      end
    endcase
  end

  always @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      state <= ST_IDLE;
    end else begin
      state <= state_n;
    end
  end

  // test cycle counting
  always @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      count <= 32'b0;
    end else if (state == ST_WRITE || state == ST_READ) begin
      count <= count + 32'd1;
      if (count == TEST_ROUNDS) begin
        count <= 32'b0;
      end
    end
  end

  // rng control
  reg rng_load;
  always @(*) begin
    rng_load = 0;
    case (state)
      ST_IDLE: begin
        if (start) rng_load = 1;
      end

      ST_WRITE: begin
        if (count == TEST_ROUNDS) rng_load = 1;
      end

      default: rng_load = 0;
    endcase
  end

  wire rng_enable;
  assign rng_enable = (state == ST_WRITE) || (state == ST_READ);

  // address prng
  wire [RAM_ADDR_WIDTH-1:0] rng_addr;
  lfsr_prng #(
      .DATA_WIDTH(RAM_ADDR_WIDTH),
      .INVERT    (0)
  ) u_prng_addr (
      .clk (clk_i),
      .load(rng_load),
      .seed(random_seed | 32'h1),

      .enable  (rng_enable),
      .data_out(rng_addr)
  );

  // data prng
  wire [DATA_WIDTH-1:0] rng_data;
  lfsr_prng #(
      .DATA_WIDTH(DATA_WIDTH),
      .INVERT    (0)
  ) u_prng_data (
      .clk (clk_i),
      .load(rng_load),
      .seed(random_seed | 32'h1),

      .enable  (rng_enable),
      .data_out(rng_data)
  );

  // address and data output
  always @(*) begin
    wb_adr_o = 32'b0;
    wb_dat_o = 32'b0;
    data_expected = 32'b0;

    case (state)
      ST_WRITE, ST_WRITE_ACTION: begin
        wb_adr_o = ADDR_BASE | {{ADDR_ZEROS{1'b0}}, rng_addr};
        wb_dat_o = rng_data & data_mask;
      end

      ST_READ, ST_READ_ACTION: begin
        wb_adr_o = ADDR_BASE | {{ADDR_ZEROS{1'b0}}, rng_addr};
        data_expected = rng_data & data_mask;
      end

      default: begin
        wb_adr_o = 32'b0;
        wb_dat_o = 32'b0;
        data_expected = 32'b0;
      end
    endcase
  end

  // data mask
  genvar i;
  for (i = 0; i < DATA_WIDTH / 8; i = i + 1) begin : gen_compare
    assign data_mask[i*8+:8] = wb_sel_o[i] ? 8'hFF : 8'h00;
    assign read_compare[i] = ~wb_sel_o[i] ? 1'b1 : (wb_dat_i[i*8+:8] == data_expected[i*8+:8]);
  end

  // wishbone bus
  assign wb_cyc_o = wb_stb_o;

  always @(*) begin
    wb_we_o = (state == ST_WRITE_ACTION);
    wb_stb_o = (state == ST_READ_ACTION || state == ST_WRITE_ACTION);
  end

  always @(*) begin
    case (wb_adr_o[1:0])
      2'b00: wb_sel_o = 4'b1111;  // full word
      2'b10: wb_sel_o = 4'b1100;  // half word
      2'b01: wb_sel_o = 4'b0010;  // byte
      2'b11: wb_sel_o = 4'b1000;  // byte
    endcase
  end

  // status output
  always @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      done <= 1'b0;
      error <= 1'b0;

      error_round <= 32'b0;
      error_addr <= 32'b0;
      error_read_data <= 32'b0;
      error_expected_data <= 32'b0;
    end else begin
      case (state)
        ST_DONE: begin
          done  <= 1'b1;
          error <= 1'b0;
        end

        ST_ERROR: begin
          done <= 1'b0;
          error <= 1'b1;

          error_round <= count;
          error_addr <= wb_adr_o;
          error_read_data <= wb_dat_i;
          error_expected_data <= data_expected;
        end

        default: begin
          done  <= 1'b0;
          error <= 1'b0;
        end
      endcase
    end
  end

endmodule
