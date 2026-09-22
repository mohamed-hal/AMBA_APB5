module Completer #(
    parameter int ADDR_WIDTH      = 32,
    parameter int DATA_WIDTH      = 32,
    parameter bit Wakeup_Signal   = 1,
    parameter int USER_REQ_WIDTH  = 1,
    parameter int USER_DATA_WIDTH = 1,
    parameter int USER_RESP_WIDTH = 1,
    parameter bit Check_Type      = 0,
    parameter int WAIT_STATES_NUM = 2
) 
(
    input  logic                                     PCLK,
    input  logic                                     PRESETn,

    ///////////////////////////////////////////////////////
    //////////////// INTERCONNECT --> COMPLETER ///////////
    ///////////////////////////////////////////////////////
    input logic [ADDR_WIDTH - 1 : 0]                 i_PADDR,
    input logic [(ADDR_WIDTH + 7)/8 - 1 : 0]         i_PADDRCHK,
   
    input logic                                      PSELx,
    input logic                                      PSELxCHK,

    ///////////////////////////////////////////////////////
    //////////////// COMPLETER --> INTERCONNECT ///////////
    ///////////////////////////////////////////////////////
    output  logic [DATA_WIDTH - 1 : 0]               PRDATA,
    output  logic                                    PREADY,
    output  logic                                    PSLVERR,
    output  logic [USER_RESP_WIDTH - 1 : 0]          PBUSER,
    output  logic [USER_DATA_WIDTH - 1 : 0]          PRUSER,

    output  logic                                    PREADYCHK,
    output  logic [(DATA_WIDTH + 7)/8 - 1:0]         PRDATACHK,
    output  logic                                    PSLVERRCHK,
    output  logic [(USER_DATA_WIDTH+7)/8-1:0]        PRUSERCHK,
    output  logic [(USER_RESP_WIDTH+7)/8-1:0]        PBUSERCHK, 
                                                     
    ///////////////////////////////////////////////////////
    //////////////// REQUESTER --> COMPLETER //////////////
    ///////////////////////////////////////////////////////
    input   logic                                    PWAKEUP,
    input   logic [DATA_WIDTH/8 - 1 : 0]             PSTRB,
    input   logic                                    PENABLE,
    input   logic                                    PWAKEUPCHK,
    input   logic                                    PSTRBCHK,
    input   logic                                    PENABLECHK,

    input   logic [2:0]                              i_PPROT,       
    input   logic                                    i_PWRITE,
    input   logic [DATA_WIDTH - 1 : 0]               i_PWDATA,
    input   logic [USER_REQ_WIDTH - 1 : 0]           i_PAUSER,
    input   logic [USER_DATA_WIDTH - 1 : 0]          i_PWUSER,


    input   logic [(DATA_WIDTH + 7)/8 - 1 : 0]       i_PWDATACHK,
    input   logic [(USER_REQ_WIDTH + 7)/8 - 1 : 0]   i_PAUSERCHK,
    input   logic [(USER_DATA_WIDTH + 7)/8 - 1 : 0]  i_PWUSERCHK,
    input   logic                                    i_PCTRLCHK,

    ///////////////////////////////////////////////////////
    //////////////// COMPLETER <--> PERIPHERAL ////////////
    ///////////////////////////////////////////////////////
    input  logic [USER_RESP_WIDTH - 1 : 0]           i_PBUSER,
    input  logic [USER_DATA_WIDTH - 1 : 0]           i_PRUSER,
    input  logic [DATA_WIDTH - 1 : 0]                i_PRDATA,
    input  logic                                     i_PSLVERR,  //It depends on each peripheral archeticture

    output logic [2:0]                               PPROT,       
    output logic [DATA_WIDTH - 1 : 0]                PWDATA,
    output logic [USER_REQ_WIDTH - 1 : 0]            PAUSER,
    output logic [USER_DATA_WIDTH - 1 : 0]           PWUSER,
    output logic [ADDR_WIDTH - 1 : 0]                PADDR,
    output logic                                     o_parity_err
);

localparam int wait_signal_width = (WAIT_STATES_NUM > 1) ? $clog2(WAIT_STATES_NUM) : 1;

logic GATED_CLK;
logic [wait_signal_width - 1 : 0] wait_cnt;
logic PENABLE_PREV;
logic first_access_cycle;
logic [DATA_WIDTH - 1 : 0] MASKED_PWDATA;
logic [DATA_WIDTH - 1 : 0] MASK;

///////////////////////////////////////////////////////
//////////////// WAIT STATES GENERATOR ////////////////
///////////////////////////////////////////////////////
assign first_access_cycle = PENABLE && !PENABLE_PREV;

always_ff @(posedge GATED_CLK or negedge PRESETn) begin
    if (!PRESETn) begin
        PENABLE_PREV <= '0;
    end else begin
        PENABLE_PREV <= PENABLE;
    end
end

always_ff @(posedge GATED_CLK or negedge PRESETn) begin
    if (!PRESETn) begin
        wait_cnt <= '0;
    end
    else if (first_access_cycle) begin
        wait_cnt <= WAIT_STATES_NUM;
    end
    else if (wait_cnt != '0 && PSELx && PENABLE) begin
        wait_cnt <= wait_cnt - 1;
    end
end

///////////////////////////////////////////////////////
//////////////// PSTRB DECODING ///////////////////////
///////////////////////////////////////////////////////
genvar i;
generate
    for (i = 0 ; i < DATA_WIDTH/8 ; i++ ) begin : Gen_Mask
        assign MASK[(8*i+7) : 8*i] = {8 {PSTRB[i]}};
    end
endgenerate

assign MASKED_PWDATA = i_PWDATA & MASK;

///////////////////////////////////////////////////////
//////////////// TRANSFERRED DATA /////////////////////
///////////////////////////////////////////////////////

assign PREADY  = (wait_cnt == '0) || !(PSELx && PENABLE);
assign PRDATA  = i_PRDATA;
assign PSLVERR = i_PSLVERR;
assign PBUSER  = i_PBUSER;
assign PRUSER  = i_PRUSER;
assign PPROT   = i_PPROT;
assign PWDATA  = i_PWDATA;
assign PAUSER  = i_PAUSER;
assign PWUSER  = i_PWUSER;
assign PADDR   = i_PADDR;  

///////////////////////////////////////////////////////
///////////// INTERFACE PARITY PROTECTION /////////////
///////////////////////////////////////////////////////

generate
    if (Check_Type) begin : g_parity_enabled

        APB_parity_gen #(.WIDTH(1), .GRAN(1)) u_pready_chk (
            .payload (PREADY),
            .chk     (PREADYCHK)
        );

        APB_parity_gen #(.WIDTH(DATA_WIDTH), .GRAN(8)) u_prdata_chk (
            .payload (PRDATA),
            .chk     (PRDATACHK)
        );

        APB_parity_gen #(.WIDTH(1), .GRAN(1)) u_pslverr_chk (
            .payload (PSLVERR),
            .chk     (PSLVERRCHK)
        );

        APB_parity_gen #(.WIDTH(USER_DATA_WIDTH), .GRAN(8)) u_pruser_chk (
            .payload (PRUSER),
            .chk     (PRUSERCHK)
        );

        APB_parity_gen #(.WIDTH(USER_RESP_WIDTH), .GRAN(8)) u_pbuser_chk (
            .payload (PBUSER),
            .chk     (PBUSERCHK)
        );

        logic [8:0] req_check_errors;
        logic [3:0] ctrl_payload;
        assign ctrl_payload = {i_PWRITE, i_PPROT};

        APB_parity_check #(.WIDTH(ADDR_WIDTH), .GRAN(8)) u_addr_chk (
            .payload      (i_PADDR),
            .sent_check   (i_PADDRCHK),
            .Check_Enable (PSELx),
            .error        (req_check_errors[0])
        );

        APB_parity_check #(.WIDTH(4), .GRAN(4)) u_ctrl_chk (
            .payload      (ctrl_payload),
            .sent_check   (i_PCTRLCHK),
            .Check_Enable (PSELx),
            .error        (req_check_errors[1])
        );

        APB_parity_check #(.WIDTH(1), .GRAN(1)) u_selx_chk (
            .payload      (PSELx),
            .sent_check   (PSELxCHK),
            .Check_Enable (PRESETn),
            .error        (req_check_errors[2])
        );

        APB_parity_check #(.WIDTH(1), .GRAN(1)) u_enable_chk (
            .payload      (PENABLE),
            .sent_check   (PENABLECHK),
            .Check_Enable (PSELx),
            .error        (req_check_errors[3])
        );

        APB_parity_check #(.WIDTH(DATA_WIDTH), .GRAN(8)) u_wdata_chk (
            .payload      (i_PWDATA),
            .sent_check   (i_PWDATACHK),
            .Check_Enable (PSELx & i_PWRITE),
            .error        (req_check_errors[4])
        );

        APB_parity_check #(.WIDTH(DATA_WIDTH/8), .GRAN(DATA_WIDTH/8)) u_strb_chk (
            .payload      (PSTRB),
            .sent_check   (PSTRBCHK),
            .Check_Enable (PSELx & i_PWRITE),
            .error        (req_check_errors[5])
        );

        APB_parity_check #(.WIDTH(1), .GRAN(1)) u_wakeup_chk (
            .payload      (PWAKEUP),
            .sent_check   (PWAKEUPCHK),
            .Check_Enable (PRESETn),
            .error        (req_check_errors[6])
        );

        APB_parity_check #(.WIDTH(USER_REQ_WIDTH), .GRAN(8)) u_auser_chk (
            .payload      (i_PAUSER),
            .sent_check   (i_PAUSERCHK),
            .Check_Enable (PSELx),
            .error        (req_check_errors[7])
        );

        APB_parity_check #(.WIDTH(USER_DATA_WIDTH), .GRAN(8)) u_wuser_chk (
            .payload      (i_PWUSER),
            .sent_check   (i_PWUSERCHK),
            .Check_Enable (PSELx & i_PWRITE),
            .error        (req_check_errors[8])
        );

        assign o_parity_err = |req_check_errors;

    end else begin : g_parity_disabled
        assign PREADYCHK    = '0;
        assign PRDATACHK    = '0;
        assign PSLVERRCHK   = '0; 
        assign PRUSERCHK    = '0;
        assign PBUSERCHK    = '0;
        assign o_parity_err = '0;
    end
endgenerate
    

//CLOCK GATING
generate
    if (Wakeup_Signal) begin
        CLK_GATE u0(
           .CLK_EN (PWAKEUP),
           .CLK (PCLK),
           .GATED_CLK (GATED_CLK)
        );
    end else begin
        assign GATED_CLK = PCLK;
    end
endgenerate

endmodule
