`default_nettype none

module reg_file_32 (
  input wire         clk,
  input wire         reset,
  input wire [4:0]   raddr_a,
  input wire [4:0]   raddr_b,
  input wire [4:0]   waddr,
  input wire [31:0]  wdata,
  input wire         we,
  output reg [31:0] rdata_a,
  output reg [31:0] rdata_b
  );

  // x0 is always 0, so it's not stored.
  reg [31:0]         reg_store [31:1];

  always @ (posedge clk) begin
    if (reset) begin
      // I'm not sure whether this would generate a
      // good circuit...
      integer i;
      for (i = 1; i <= 31; i = i + 1) begin
        reg_store[i] <= 0;
      end
    end else begin
      if (we && waddr != 5'd0) begin
        reg_store[waddr] <= wdata;
      end
    end
  end // always @ (posedge clk)

  assign rdata_a = raddr_a == 5'd0 ? 32'd0 : reg_store[raddr_a];
  assign rdata_b = raddr_b == 5'd0 ? 32'd0 : reg_store[raddr_b];

endmodule // reg_file_32
