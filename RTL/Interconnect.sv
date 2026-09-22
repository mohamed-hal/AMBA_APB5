module Interconnect #(
    parameter int ADDR_WIDTH        = 32,
    parameter int DATA_WIDTH        = 32,
    parameter int USER_DATA_WIDTH   = 1,
    parameter int USER_RESP_WIDTH   = 1,
    parameter bit Check_Type        = 0,
    parameter int NUM_of_Completers = 2
)
(
    ///////////////////////////////////////////////////////
    //////////////// INTERCONNECT --> COMPLETERS ///////////
    ///////////////////////////////////////////////////////

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
    //////////////// INTERCONNECT <--> REQUESTER //////////
    ///////////////////////////////////////////////////////

    input logic  [ADDR_WIDTH - 1 : 0]               PADDR,
    input logic                                     PSEL,
    input logic                                     PENABLE,
    input logic                                     PWRITE,

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

    output logic                                    o_hop1_parity_err
);

    localparam int SEL_BITS = (NUM_of_Completers > 1) ? $clog2(NUM_of_Completers) : 1;

    logic [SEL_BITS - 1 : 0] sel_index;
    assign sel_index = PADDR[ADDR_WIDTH - 1 : ADDR_WIDTH - SEL_BITS];

    always_comb begin
        PSELx = '0;
        if (PSEL) begin
            PSELx[sel_index] = 1'b1;
        end
    end

    ///////////////////////////////////////////////////////
    ///////////// RESPONSE MUX (Completer -> Requester) ///
    ///////////////////////////////////////////////////////
    always_comb begin
        if (PSEL) begin
            PRDATA  = i_PRDATA  [sel_index];
            PREADY  = i_PREADY  [sel_index];
            PSLVERR = i_PSLVERR [sel_index];
            PBUSER  = i_PBUSER  [sel_index];
            PRUSER  = i_PRUSER  [sel_index];
        end else begin
            PRDATA  = '0;
            PREADY  = 1'b1;
            PSLVERR = 1'b0;
            PBUSER  = '0;
            PRUSER  = '0;
        end
    end

    ///////////////////////////////////////////////////////
    ///////////// INTERFACE PARITY PROTECTION /////////////
    ///////////////////////////////////////////////////////

    generate
        if (Check_Type) begin : g_parity_enabled

            for (genvar i = 0; i < NUM_of_Completers; i++) begin : g_selx_chk
                APB_parity_gen #(.WIDTH(1), .GRAN(1)) u_selx_chk (
                    .payload (PSELx[i]),
                    .chk     (PSELxCHK[i])
                );
            end

            logic [NUM_of_Completers - 1 : 0] hop1_err_per_completer;

            for (genvar c = 0; c < NUM_of_Completers; c++) begin : g_hop1_c
                logic ready_e, rdata_e, slverr_e, ruser_e, buser_e;

                APB_parity_check #(.WIDTH(1), .GRAN(1)) u_ready_chk (
                    .payload      (i_PREADY[c]),
                    .sent_check   (i_PREADYCHK[c]),
                    .Check_Enable (PSELx[c] & PENABLE),
                    .error        (ready_e)
                );

                APB_parity_check #(.WIDTH(DATA_WIDTH), .GRAN(8)) u_rdata_chk (
                    .payload      (i_PRDATA[c]),
                    .sent_check   (i_PRDATACHK[c]),
                    .Check_Enable (PSELx[c] & PENABLE & i_PREADY[c] & !PWRITE),
                    .error        (rdata_e)
                );

                APB_parity_check #(.WIDTH(1), .GRAN(1)) u_slverr_chk (
                    .payload      (i_PSLVERR[c]),
                    .sent_check   (i_PSLVERRCHK[c]),
                    .Check_Enable (PSELx[c] & PENABLE & i_PREADY[c]),
                    .error        (slverr_e)
                );

                APB_parity_check #(.WIDTH(USER_DATA_WIDTH), .GRAN(8)) u_ruser_chk (
                    .payload      (i_PRUSER[c]),
                    .sent_check   (i_PRUSERCHK[c]),
                    .Check_Enable (PSELx[c] & PENABLE & i_PREADY[c] & !PWRITE),
                    .error        (ruser_e)
                );

                APB_parity_check #(.WIDTH(USER_RESP_WIDTH), .GRAN(8)) u_buser_chk (
                    .payload      (i_PBUSER[c]),
                    .sent_check   (i_PBUSERCHK[c]),
                    .Check_Enable (PSELx[c] & PENABLE & i_PREADY[c]),
                    .error        (buser_e)
                );

                assign hop1_err_per_completer[c] = ready_e | rdata_e | slverr_e | ruser_e | buser_e;
            end

            assign o_hop1_parity_err = |hop1_err_per_completer;

            APB_parity_gen #(.WIDTH(1), .GRAN(1)) u_pready_gen (
                .payload (PREADY), .chk (PREADYCHK));
            APB_parity_gen #(.WIDTH(DATA_WIDTH), .GRAN(8)) u_prdata_gen (
                .payload (PRDATA), .chk (PRDATACHK));
            APB_parity_gen #(.WIDTH(1), .GRAN(1)) u_pslverr_gen (
                .payload (PSLVERR), .chk (PSLVERRCHK));
            APB_parity_gen #(.WIDTH(USER_DATA_WIDTH), .GRAN(8)) u_pruser_gen (
                .payload (PRUSER), .chk (PRUSERCHK));
            APB_parity_gen #(.WIDTH(USER_RESP_WIDTH), .GRAN(8)) u_pbuser_gen (
                .payload (PBUSER), .chk (PBUSERCHK));

        end else begin : g_parity_disabled
            assign PSELxCHK          = '0;
            assign o_hop1_parity_err = 1'b0;
            assign PREADYCHK         = 1'b0;
            assign PRDATACHK         = '0;
            assign PSLVERRCHK        = 1'b0;
            assign PRUSERCHK         = '0;
            assign PBUSERCHK         = '0;
        end
    endgenerate

endmodule