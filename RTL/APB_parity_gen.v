module APB_parity_gen #(
  parameter WIDTH = 32,   // payload width in bits
  parameter GRAN  = 8     // bits covered by each check bit
) (
  input  wire [WIDTH-1:0]                   payload,
  output wire [((WIDTH+GRAN-1)/GRAN)-1:0]   chk
);

  localparam CHK_W = (WIDTH + GRAN - 1) / GRAN;

  genvar i;
  generate
    for (i = 0; i < CHK_W; i = i + 1) begin : g_chk
      localparam LSB = i * GRAN;
      localparam MSB = ((LSB + GRAN) > WIDTH) ? (WIDTH - 1) : (LSB + GRAN - 1);
      assign chk[i] = ~(^payload[MSB:LSB]);
    end
  endgenerate

endmodule