module Interconnect #(
    parameter int ADDR_WIDTH        = 32,
    parameter int DATA_WIDTH        = 32,
    parameter int USER_DATA_WIDTH   = 1,
    parameter int USER_RESP_WIDTH   = 1,
    parameter bit Check_Type        = 1,
    parameter int NUM_of_Completers = 2
)
(
    ///////////////////////////////////////////////////////
    //////////////// INTERCONNECT --> COMPLETERS ///////////
    ///////////////////////////////////////////////////////
    output logic [ADDR_WIDTH - 1 : 0]        o_PADDR,
    output logic                             o_PADDRCHK,
   
    output logic [NUM_of_Completers - 1 : 0] PSELx,
    output logic [NUM_of_Completers - 1 : 0] PSELxCHK,


    ///////////////////////////////////////////////////////
    //////////////// COMPLETERS --> INTERCONNECT ///////////
    ///////////////////////////////////////////////////////
    input  logic [NUM_of_Completers - 1 : 0] [DATA_WIDTH - 1 : 0]        i_PRDATA,
    input  logic [NUM_of_Completers - 1 : 0]                             i_PREADY,
    input  logic [NUM_of_Completers - 1 : 0]                             i_PSLVERR,
    input  logic [NUM_of_Completers - 1 : 0] [USER_RESP_WIDTH - 1 : 0]   i_PBUSER,
    input  logic [NUM_of_Completers - 1 : 0] [USER_DATA_WIDTH - 1 : 0]   i_PRUSER,

    input  logic [NUM_of_Completers - 1 : 0]                             i_PREADYCHK,
    input  logic [NUM_of_Completers - 1 : 0] [(DATA_WIDTH + 7)/8 - 1:0]  i_PRDATACHK,
    input  logic [NUM_of_Completers - 1 : 0]                             i_PSLVERRCHK,
    input  logic [NUM_of_Completers - 1 : 0] [(USER_DATA_WIDTH+7)/8-1:0] i_PRUSERCHK,
    input  logic [NUM_of_Completers - 1 : 0] [(USER_RESP_WIDTH+7)/8-1:0] i_PBUSERCHK,

    ///////////////////////////////////////////////////////
    //////////////// INTERCONNECT <--> REQUESTER ////////////
    ///////////////////////////////////////////////////////

    input logic  [ADDR_WIDTH - 1 : 0]               PADDR,
    input logic                                     PSEL,

    output logic [DATA_WIDTH - 1 : 0]               PRDATA,
    output logic                                    PREADY,
    output logic                                    PSLVERR,
    output logic [USER_RESP_WIDTH - 1 : 0]          PBUSER,
    output logic [USER_DATA_WIDTH - 1 : 0]          PRUSER,

    output logic                                    PREADYCHK,
    output logic [(DATA_WIDTH + 7)/8 - 1 : 0]       PRDATACHK,
    output logic                                    PSLVERRCHK,
    output logic [(USER_DATA_WIDTH + 7)/8 - 1 : 0]  PRUSERCHK,
    output logic [(USER_RESP_WIDTH + 7)/8 - 1 : 0]  PBUSERCHK,

    output logic                                    o_parity_err
);


    localparam int SEL_BITS = (NUM_of_Completers > 1) ? $clog2(NUM_of_Completers) : 1;

    ///////////////////////////////////////////////////////
    ///////////// ADDRESS DECODE / PSELx GENERATION ////////
    ///////////////////////////////////////////////////////
    logic [SEL_BITS - 1 : 0] sel_index;
    assign sel_index = PADDR[ADDR_WIDTH - 1 : ADDR_WIDTH - SEL_BITS];

    always_comb begin
        PSELx = '0;
        if (PSEL) begin
            PSELx[sel_index] = 1'b1;
        end
    end

    ///////////////////////////////////////////////////////
    ///////////// RESPONSE MUX (Completer -> Requester) ////
    ///////////////////////////////////////////////////////
    always_comb begin
        if (PSEL) begin
            PRDATA     = i_PRDATA     [sel_index];
            PREADY     = i_PREADY     [sel_index];
            PSLVERR    = i_PSLVERR    [sel_index];
            PBUSER     = i_PBUSER     [sel_index];
            PRUSER     = i_PRUSER     [sel_index];
            PREADYCHK  = i_PREADYCHK  [sel_index];
            PRDATACHK  = i_PRDATACHK  [sel_index];
            PSLVERRCHK = i_PSLVERRCHK [sel_index];
            PRUSERCHK  = i_PRUSERCHK  [sel_index];
            PBUSERCHK  = i_PBUSERCHK  [sel_index];
        end else begin
            PRDATA     = '0;
            PREADY     = 1'b1;
            PSLVERR    = 1'b0;
            PBUSER     = '0;
            PRUSER     = '0;
            PREADYCHK  = 1'b0;
            PRDATACHK  = '0;
            PSLVERRCHK = 1'b0;
            PRUSERCHK  = '0;
            PBUSERCHK  = '0;
        end
    end

    ///////////////////////////////////////////////////////
    ///////////// INTERFACE PARITY PROTECTION //////////////
    ///////////////////////////////////////////////////////
    logic [4:0] resp_check_errors; 

    generate
        if (Check_Type) begin : g_parity_enabled

            for (genvar i = 0; i < NUM_of_Completers; i++) begin : g_selx_chk
                APB_parity_gen #(.WIDTH(1), .GRAN(1)) u_selx_chk (
                    .payload (PSELx[i]),
                    .chk     (PSELxCHK[i])
                );
            end


            APB_parity_check #(.WIDTH(1), .GRAN(1)) u_pready_chk (
                .payload      (PREADY),
                .sent_check   (PREADYCHK),
                .Check_Enable (PSEL & PENABLE),
                .error        (resp_check_errors[0])
            );

            APB_parity_check #(.WIDTH(DATA_WIDTH), .GRAN(8)) u_rdata_chk (
                .payload      (PRDATA),
                .sent_check   (PRDATACHK),
                .Check_Enable (PSEL & PENABLE & PREADY & !PWRITE),
                .error        (resp_check_errors[1])
            );

            APB_parity_check #(.WIDTH(1), .GRAN(1)) u_slverr_chk (
                .payload      (PSLVERR),
                .sent_check   (PSLVERRCHK),
                .Check_Enable (PSEL & PENABLE & PREADY),
                .error        (resp_check_errors[2])
            );

            APB_parity_check #(.WIDTH(USER_DATA_WIDTH), .GRAN(8)) u_ruser_chk (
                .payload      (PRUSER),
                .sent_check   (PRUSERCHK),
                .Check_Enable (PSEL & PENABLE & PREADY & !PWRITE),
                .error        (resp_check_errors[3])
            );

            APB_parity_check #(.WIDTH(USER_RESP_WIDTH), .GRAN(8)) u_buser_chk (
                .payload      (PBUSER),
                .sent_check   (PBUSERCHK),
                .Check_Enable (PSEL & PENABLE & PREADY),
                .error        (resp_check_errors[4])
            );

            assign o_parity_err = |resp_check_errors;

        end else begin : g_parity_disabled
            assign PSELxCHK          = '0;
            assign resp_check_errors = '0;
            assign o_parity_err      = 1'b0;
        end
    endgenerate    

endmodule
