module APB_parity_check #(parameter WIDTH = 32 , GRAN = 8) (
    input   wire [WIDTH - 1 : 0]               payload,
    input   wire [((WIDTH+GRAN-1)/GRAN)-1:0]   sent_check,
    input   wire                               Check_Enable,
    output  wire                               error
    );

    wire [((WIDTH+GRAN-1)/GRAN)-1:0] generated_check;

    APB_parity_gen #(.WIDTH(WIDTH) , .GRAN(GRAN)) u_check (
        .payload(payload),
        .chk(generated_check)
    );

    assign error = Check_Enable ? (!(generated_check == sent_check)) : 0;
endmodule
