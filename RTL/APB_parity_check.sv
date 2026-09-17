module APB_parity_check #(
    parameter int WIDTH = 32,
    parameter int GRAN  = 8
) (
    input  logic [WIDTH - 1 : 0]               payload,
    input  logic [((WIDTH+GRAN-1)/GRAN)-1:0]   sent_check,
    input  logic                               Check_Enable,
    output logic                               error
);

    logic [((WIDTH+GRAN-1)/GRAN)-1:0] generated_check;

    APB_parity_gen #(.WIDTH(WIDTH), .GRAN(GRAN)) u_check (
        .payload (payload),
        .chk     (generated_check)
    );

    assign error = Check_Enable ? (generated_check != sent_check) : 1'b0;

endmodule
