module APB_parity_gen #(
    parameter int WIDTH = 32,  // payload width in bits
    parameter int GRAN  = 8    // bits covered by each check bit
) (
    input  logic [WIDTH-1:0]                 payload,
    output logic [((WIDTH+GRAN-1)/GRAN)-1:0] chk
);

    localparam int CHK_W = (WIDTH + GRAN - 1) / GRAN;

    generate
        for (genvar i = 0; i < CHK_W; i++) begin : g_chk
            localparam int LSB = i * GRAN;
            localparam int MSB = ((LSB + GRAN) > WIDTH) ? (WIDTH - 1) : (LSB + GRAN - 1);
            assign chk[i] = ~(^payload[MSB:LSB]);
        end
    endgenerate

endmodule
